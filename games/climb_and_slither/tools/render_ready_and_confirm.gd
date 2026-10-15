extends SceneTree
## Developer tool, not part of the game: screenshots of the ready pill (guest lobby not ready and
## ready), the Start game pill (host lobby disabled and enabled), and every "are you sure?" card
## over its screen (design sections 13 and 14). Each screen lives in its own off-screen viewport
## the size of the window, all in one process on a loopback hub. Needs a real renderer:
##   godot --rendering-driver opengl3 --resolution 1280x720 -s games/climb_and_slither/tools/render_ready_and_confirm.gd -- <out_dir>

const GAME: String = "climb_and_slither"

var _out: String = "."
var _failed: bool = false
var _hub: LoopbackHub = LoopbackHub.new()
var _registry: GameRegistry = GameRegistry.new()


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	AppSettings.path = "user://render_ready_settings.cfg"
	DirAccess.remove_absolute(AppSettings.path)
	await _run()
	DirAccess.remove_absolute(AppSettings.path)
	quit(1 if _failed else 0)


func _frames(count: int = 4) -> void:
	for _i: int in count:
		await process_frame


func _until(condition: Callable, what: String, max_frames: int = 600) -> bool:
	for _i: int in max_frames:
		if condition.call():
			return true
		await process_frame
	push_error("never happened: %s" % what)
	_failed = true
	return false


func _tag() -> String:
	return "%dx%d" % [get_root().size.x, get_root().size.y]


func _holder() -> SubViewport:
	var holder: SubViewport = SubViewport.new()
	holder.size = get_root().size
	holder.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(holder)
	return holder


func _shot(node: Node, name: String) -> void:
	await _frames(6)
	var holder: SubViewport = node as SubViewport
	if holder == null:
		holder = node.get_viewport() as SubViewport
	holder.get_texture().get_image().save_png("%s/%s-%s.png" % [_out, name, _tag()])


func _lobby(player_name: String, address: String = "") -> LobbyScene:
	var scene: LobbyScene = LobbyScene.new()
	scene.setup({
		"app_version": "1.0.0", "game_id": GAME if address.is_empty() else "", "game_registry": _registry,
		"min_players": 2, "max_players": 4, "min_active_players": 2,
		"transport": {"transport": "loopback", "hub": _hub, "connection_ui": false}, "player_name": player_name,
	})
	_holder().add_child(scene)
	await _frames()
	scene.name_edit.text = player_name
	if address.is_empty():
		scene.host_session()
		await _until(func() -> bool: return scene.shared_address != "", "hosting went live")
	else:
		scene.address_edit.text = address
		scene.join_session()
	return scene


func _game_screen() -> ClimbGameScreen:
	var screen: ClimbGameScreen = load("res://games/climb_and_slither/ui/climb_game_screen.tscn").instantiate()
	_holder().add_child(screen)
	var rules: ClimbAndSlitherRules = ClimbAndSlitherRules.new()
	var controller: LocalGameController = LocalGameController.new(rules, ["p1", "p2", "p3"], rules.default_setup(), {}, 7)
	screen.setup(controller, [{"player_id": "p1", "name": "Asha"}, {"player_id": "p2", "name": "Ben"}, {"player_id": "p3", "name": "Chandra"}])
	controller.start()
	screen.set_speed_by_label("Instant")
	for _i: int in 6:
		if screen.can_roll():
			screen.roll_button.pressed.emit()
		await _frames(2)
	return screen


## Shows `config` as a question over `screen` and saves it, then dismisses it with its first button.
func _question(screen: Node, config: Dictionary, name: String) -> void:
	var dialog: ConfirmDialog = ConfirmDialog.ask(screen, config)
	await _shot(screen, name)
	if dialog != null:
		dialog.buttons[0].pressed.emit()
	await _frames()


func _run() -> void:
	await _frames()
	_registry.load_from()
	AppSettings.set_host_via("direct")

	var host: LobbyScene = await _lobby("Asha")
	var guest: LobbyScene = await _lobby("Ben", host.shared_address)
	if not await _until(func() -> bool: return guest.lobby_view.visible and host.players_box.get_child_count() == 2, "the guest joined"):
		return
	await _shot(host, "ready-1-host-start-disabled")
	await _shot(guest, "ready-2-guest-not-ready")
	guest.ready_button.button_pressed = true
	await _until(func() -> bool: return not host.start_button.disabled, "the host's Start enabled")
	await _shot(guest, "ready-3-guest-ready")
	await _shot(host, "ready-4-host-start-enabled")

	# 13a / 13b / 13f: asked in the lobby
	guest.leave_button.pressed.emit()
	await _shot(guest, "confirm-13a-guest-leaves-lobby")
	(guest.get_children().filter(func(n: Node) -> bool: return n is ConfirmDialog)[0] as ConfirmDialog).buttons[0].pressed.emit()
	host.leave_button.pressed.emit()
	await _shot(host, "confirm-13b-host-closes-room")
	(host.get_children().filter(func(n: Node) -> bool: return n is ConfirmDialog)[0] as ConfirmDialog).buttons[0].pressed.emit()
	((host.players_box.get_child(1) as HBoxContainer).get_child(2) as Button).pressed.emit()
	await _shot(host, "confirm-13f-remove-player")
	(host.get_children().filter(func(n: Node) -> bool: return n is ConfirmDialog)[0] as ConfirmDialog).buttons[0].pressed.emit()

	# 13c / 13d / 13e: asked over a game
	var screen: ClimbGameScreen = await _game_screen()
	await _question(screen, ConfirmDialog.leave_game(), "confirm-13c-guest-leaves-game")
	await _question(screen, ConfirmDialog.end_game_for_all(), "confirm-13d-host-ends-game")
	await _question(screen, ConfirmDialog.leave_hotseat(), "confirm-13e-hotseat-leaves")
