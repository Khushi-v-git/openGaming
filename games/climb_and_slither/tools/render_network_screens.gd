extends SceneTree
## Developer tool, not part of the game: runs a host and a guest in ONE process over direct
## WebSocket on localhost, drives them through Host, Join, ready and Start, plays some turns, and
## saves screenshots of the lobby (host and guest) and of the networked game (host and guest).
## Needs a real renderer (not --headless):
##   godot --rendering-driver opengl3 --resolution 1280x720 -s games/climb_and_slither/tools/render_network_screens.gd -- <out_dir>
## The host is drawn on the main window, the guest in an off-screen viewport of the same size.

const GAME: String = "climb_and_slither"
const PORT: int = 24987

var _out: String = "."
var _host_menu: MainMenu
var _guest_menu: MainMenu
var _guest_viewport: SubViewport


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	AppSettings.path = "user://render_network_settings.cfg"
	DirAccess.remove_absolute(AppSettings.path)
	await _run()
	DirAccess.remove_absolute(AppSettings.path)
	quit()


func _frames(count: int = 4) -> void:
	for _i: int in count:
		await process_frame


func _until(condition: Callable, max_frames: int = 900) -> bool:
	for _i: int in max_frames:
		if condition.call():
			return true
		await process_frame
	return false


func _size_tag() -> String:
	return "%dx%d" % [get_root().size.x, get_root().size.y]


func _save_host(name: String) -> void:
	await _frames()
	get_root().get_texture().get_image().save_png("%s/%s-host-%s.png" % [_out, name, _size_tag()])


func _save_guest(name: String) -> void:
	await _frames()
	_guest_viewport.get_texture().get_image().save_png("%s/%s-guest-%s.png" % [_out, name, _size_tag()])


func _config() -> Dictionary:
	return {
		"transport": "auto", "host_via": "direct", "relay_url": "wss://my-relay.example.workers.dev",
		"port": PORT, "bind_address": "127.0.0.1", "connection_ui": true,
	}


func _make_menu(parent: Node) -> MainMenu:
	var menu: MainMenu = MainMenu.new()
	menu.use_command_line = false
	menu.network_config = _config()
	parent.add_child(menu)
	return menu


func _run() -> void:
	await _frames()  # the window has its real size only after the first frame
	AppSettings.set_host_via("direct")
	_host_menu = _make_menu(get_root())
	_guest_viewport = SubViewport.new()
	_guest_viewport.size = get_root().size
	_guest_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(_guest_viewport)
	_guest_menu = _make_menu(_guest_viewport)
	await _frames()

	var host_lobby: LobbyScene = _host_menu.open_host_lobby(GAME)
	host_lobby.name_edit.text = "Asha"
	await _save_host("lobby-1-start")

	host_lobby.host_session()
	if not await _until(func() -> bool: return host_lobby.shared_address != ""):
		push_error("hosting never went live")
		return
	var guest_lobby: LobbyScene = _guest_menu.open_join_lobby()
	guest_lobby.name_edit.text = "Ben"
	guest_lobby.address_edit.text = host_lobby.shared_address
	guest_lobby.join_session()
	if not await _until(func() -> bool: return guest_lobby.lobby_view.visible and host_lobby.players_box.get_child_count() == 2):
		push_error("the guest never joined")
		return
	guest_lobby.ready_button.button_pressed = true
	await _until(func() -> bool: return not host_lobby.start_button.disabled)
	await _save_host("lobby-2-waiting")
	await _save_guest("lobby-2-waiting")

	host_lobby.start_button.pressed.emit()
	if not await _until(func() -> bool: return _host_menu.in_network_game() and _guest_menu.in_network_game()):
		push_error("the game never started")
		return
	var host_screen: ClimbGameScreen = _host_menu.network_screen()
	var guest_screen: ClimbGameScreen = _guest_menu.network_screen()
	host_screen.set_speed_by_label("Instant")
	guest_screen.set_speed_by_label("Instant")
	await _save_host("game-1-start")

	var rolls: int = 0
	while rolls < 16:
		for screen: ClimbGameScreen in [host_screen, guest_screen]:
			if screen.can_roll():
				screen.roll_button.pressed.emit()
				rolls += 1
		await _frames(3)
	await _frames(20)
	await _save_host("game-2-playing")
	await _save_guest("game-2-playing")
