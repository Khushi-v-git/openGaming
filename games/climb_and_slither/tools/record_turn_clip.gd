extends SceneTree
## Developer tool, not part of the game: records a short clip of the lobby and a few turns for the
## README and posts. A host (Asha, drawn on the main window) and a guest (Ben, in an off-screen
## viewport) play over the in-process FakeRelay, so the lobby shows a room code and no real relay
## URL is ever on screen. A drawn pointer moves to each button the host presses.
## Run with Movie Maker mode so every frame is written at a fixed rate, whatever the machine speed:
##   godot --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 \
##     --write-movie <out_dir>/frame.png -s games/climb_and_slither/tools/record_turn_clip.gd
## Keep the window visible while it records: Godot does not draw a minimized window, and the
## clip then freezes even though the script carries on.
## Then turn the frames into a GIF and an MP4 with ffmpeg, e.g.
##   ffmpeg -framerate 30 -i <out_dir>/frame%08d.png -vf "fps=20,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" turn.gif

const GAME: String = "climb_and_slither"
const ROOM_CODE: String = "K7QF2M"
const LADDER_FOOT: int = 9  # classic board: 9 climbs to 49
const FPS: float = 30.0

var _failed: bool = false
var _relay: FakeRelay = FakeRelay.new()
var _host_menu: MainMenu
var _guest_menu: MainMenu
var _guest_viewport: SubViewport
var _pointer: Node2D


func _initialize() -> void:
	AppSettings.path = "user://record_clip_settings.cfg"
	DirAccess.remove_absolute(AppSettings.path)
	await _run()
	DirAccess.remove_absolute(AppSettings.path)
	quit(1 if _failed else 0)


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame


func _hold(seconds: float) -> void:
	await _frames(int(seconds * FPS))


func _until(condition: Callable, max_frames: int = 900) -> bool:
	for _i: int in max_frames:
		if condition.call():
			return true
		await process_frame
	return false


func _fail(message: String) -> void:
	push_error(message)
	_failed = true


func _config() -> Dictionary:
	return {"transport": "fake_relay", "relay": _relay, "room_code": ROOM_CODE}


func _make_menu(parent: Node) -> MainMenu:
	var menu: MainMenu = MainMenu.new()
	menu.use_command_line = false
	menu.network_config = _config()
	parent.add_child(menu)
	return menu


## A plain arrow pointer drawn above everything, so viewers can follow the host's clicks.
func _make_pointer() -> Node2D:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 100
	get_root().add_child(layer)
	var arrow: Node2D = Node2D.new()
	var shape: PackedVector2Array = PackedVector2Array([
		Vector2(0, 0), Vector2(0, 30), Vector2(8, 23), Vector2(14, 36), Vector2(20, 33), Vector2(14, 21), Vector2(24, 21),
	])
	var border: Polygon2D = Polygon2D.new()
	border.polygon = shape
	border.color = Color("#2B2A33")
	border.scale = Vector2(1.18, 1.18)
	border.position = Vector2(-1.5, -2)
	arrow.add_child(border)
	var fill: Polygon2D = Polygon2D.new()
	fill.polygon = shape
	fill.color = Color("#FFFFFF")
	arrow.add_child(fill)
	arrow.position = Vector2(1100, 650)
	layer.add_child(arrow)
	return arrow


## Glides the pointer to the middle of a control, gives a small click pulse, then presses it.
func _click(button: BaseButton) -> void:
	var target: Vector2 = button.get_global_rect().get_center() + Vector2(-4, -2)
	var tween: Tween = _pointer.create_tween()
	tween.tween_property(_pointer, "position", target, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	var pulse: Tween = _pointer.create_tween()
	pulse.tween_property(_pointer, "scale", Vector2(0.82, 0.82), 0.07)
	pulse.tween_property(_pointer, "scale", Vector2.ONE, 0.09)
	await pulse.finished
	button.pressed.emit()


## Moves the pointer off whatever it just pressed, so the button's new text stays readable.
func _step_aside() -> void:
	var tween: Tween = _pointer.create_tween()
	tween.tween_property(_pointer, "position", _pointer.position + Vector2(150, 30), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## A global seed for which the host's second roll lands on the ladder foot (MainMenu seeds the
## game with randi()), so the clip shows a climb.
func _ladder_seed() -> int:
	for n: int in 5000:
		seed(n)
		var prng: Prng = Prng.new(randi())
		var first: int = prng.range_int(1, 6)
		var _guest_roll: int = prng.range_int(1, 6)
		var second: int = prng.range_int(1, 6)
		if first >= 3 and first + second == LADDER_FOOT:
			return n
	return 0


func _run() -> void:
	await _frames(2)  # the window has its real size only after the first frame
	_host_menu = _make_menu(get_root())
	_guest_viewport = SubViewport.new()
	_guest_viewport.size = get_root().size
	_guest_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(_guest_viewport)
	_guest_menu = _make_menu(_guest_viewport)
	_pointer = _make_pointer()
	var lucky_seed: int = _ladder_seed()

	var host_lobby: LobbyScene = _host_menu.open_host_lobby(GAME)
	host_lobby.name_edit.text = "Asha"
	host_lobby.host_session()
	if not await _until(func() -> bool: return host_lobby.shared_address != ""):
		_fail("hosting never went live")
		return
	await _hold(1.0)

	var guest_lobby: LobbyScene = _guest_menu.open_join_lobby()
	guest_lobby.name_edit.text = "Ben"
	guest_lobby.address_edit.text = ROOM_CODE
	guest_lobby.join_session()
	if not await _until(func() -> bool: return host_lobby.players_box.get_child_count() == 2 and guest_lobby.lobby_view.visible):
		_fail("the guest never joined")
		return
	await _hold(0.7)
	guest_lobby.ready_button.button_pressed = true
	await _until(func() -> bool: return not host_lobby.start_button.disabled)
	await _hold(0.4)

	seed(lucky_seed)
	await _click(host_lobby.start_button)
	if not await _until(func() -> bool: return _host_menu.in_network_game() and _guest_menu.in_network_game()):
		_fail("the game never started")
		return
	var host_screen: ClimbGameScreen = _host_menu.network_screen()
	var guest_screen: ClimbGameScreen = _guest_menu.network_screen()
	guest_screen.set_speed_by_label("Instant")  # off screen; only the host's board is recorded
	await _until(host_screen.can_roll)
	await _hold(0.4)

	await _click(host_screen.roll_button)  # Asha
	_step_aside()
	if not await _until(guest_screen.can_roll):
		_fail("Ben never got the turn")
		return
	await _until(func() -> bool: return not host_screen.timeline.is_busy())
	await _hold(0.3)
	guest_screen.roll_button.pressed.emit()  # Ben, on his own computer
	if not await _until(host_screen.can_roll):
		_fail("Asha never got the turn back")
		return
	await _hold(0.3)
	await _click(host_screen.roll_button)  # Asha again: up the ladder
	_step_aside()
	await _frames(3)
	await _until(func() -> bool: return not host_screen.timeline.is_busy())
	await _hold(1.6)
