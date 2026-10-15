extends GutTest
## Host and Join through the home screen, end to end: two MainMenu instances (one per player) on
## the same in-memory network. Lobby, ready, start, the game screen on both sides, back to the
## lobby, leaving.

const GAME: String = "climb_and_slither"

var hub: LoopbackHub
var host_menu: MainMenu
var guest_menu: MainMenu
var _saved_path: String


func before_each() -> void:
	hub = LoopbackHub.new()
	_saved_path = AppSettings.path
	AppSettings.path = "user://test_main_flows_settings.cfg"
	DirAccess.remove_absolute(AppSettings.path)


func after_each() -> void:
	await get_tree().process_frame  # rows queued for freeing are gone before the orphan check
	DirAccess.remove_absolute(AppSettings.path)
	for leftover: String in ["Hosty", "Asha"]:  # settings files the auto-launch tests isolated into
		DirAccess.remove_absolute("user://settings_%s.cfg" % leftover)
	AppSettings.path = _saved_path


func _menu() -> MainMenu:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child_autofree(viewport)
	var menu: MainMenu = MainMenu.new()
	menu.use_command_line = false
	menu.network_config = {"transport": "loopback", "hub": hub}
	viewport.add_child(menu)
	await get_tree().process_frame
	return menu


func _until(condition: Callable, max_frames: int = 600) -> bool:
	for _i: int in max_frames:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


## Both players are in the lobby, the guest is ready. The host has not pressed Start.
func _lobby_with_a_ready_guest() -> void:
	host_menu = await _menu()
	guest_menu = await _menu()
	var host_lobby: LobbyScene = host_menu.open_host_lobby(GAME)
	host_lobby.name_edit.text = "Hosty"
	host_lobby.host_session()
	assert_true(await _until(func() -> bool: return host_lobby.shared_address != ""), "hosting never went live")
	var guest_lobby: LobbyScene = guest_menu.open_join_lobby()
	guest_lobby.name_edit.text = "Asha"
	guest_lobby.address_edit.text = host_lobby.shared_address
	guest_lobby.join_session()
	assert_true(await _until(func() -> bool: return guest_lobby.lobby_view.visible and host_lobby.players_box.get_child_count() == 2), "the guest never joined")
	guest_lobby.ready_button.button_pressed = true
	assert_true(await _until(func() -> bool: return not host_lobby.start_button.disabled), "the host's Start never enabled")


func _start_the_game() -> void:
	await _lobby_with_a_ready_guest()
	host_menu.lobby().start_button.pressed.emit()
	assert_true(await _until(func() -> bool: return host_menu.in_network_game() and guest_menu.in_network_game()), "the game screens never appeared")
	(host_menu.network_screen() as ClimbGameScreen).set_speed_by_label("Instant")
	(guest_menu.network_screen() as ClimbGameScreen).set_speed_by_label("Instant")


# --- the lobby ---------------------------------------------------------------------------------------------

func test_hosting_opens_the_lobby_and_back_returns_to_the_home_list() -> void:
	host_menu = await _menu()
	var lobby: LobbyScene = host_menu.open_host_lobby(GAME)
	assert_not_null(lobby)
	assert_false(host_menu.game_list.is_visible_in_tree(), "the home list is hidden behind the lobby")
	lobby.back_requested.emit()
	assert_null(host_menu.lobby())
	assert_true(host_menu.game_list.is_visible_in_tree())


func test_a_game_this_app_does_not_have_cannot_be_hosted() -> void:
	host_menu = await _menu()
	assert_null(host_menu.open_host_lobby("no_such_game"))
	assert_null(host_menu.lobby())


func test_the_players_name_is_remembered_for_next_time() -> void:
	host_menu = await _menu()
	var lobby: LobbyScene = host_menu.open_host_lobby(GAME)
	lobby.name_edit.text = "Mira"
	lobby.host_session()
	assert_eq(AppSettings.player_name(), "Mira")
	var again: MainMenu = await _menu()
	assert_eq(again.open_join_lobby().name_edit.text, "Mira")


# --- the game on both screens ----------------------------------------------------------------------------------------

func test_pressing_start_puts_a_started_game_on_both_screens() -> void:
	await _start_the_game()
	for menu: MainMenu in [host_menu, guest_menu]:
		var screen: ClimbGameScreen = menu.network_screen()
		assert_not_null(screen)
		var view: Dictionary = screen.current_view()
		assert_false(view.is_empty(), "the first batch was not missed")
		for position: Variant in (view["positions"] as Dictionary).values():
			assert_eq(position, 0)
		assert_eq(screen.player_rows.size(), 2)
	var host_screen: ClimbGameScreen = host_menu.network_screen()
	var guest_screen: ClimbGameScreen = guest_menu.network_screen()
	assert_false(host_screen.roll_button.disabled, "the host sits in seat 0 and rolls first")
	assert_true(guest_screen.roll_button.disabled, "the guest waits for their turn")
	assert_eq(guest_screen.current_view()["you"], guest_menu.lobby().lobby_client().player_id)


func test_a_roll_by_the_host_shows_up_on_the_guests_screen() -> void:
	await _start_the_game()
	var host_screen: ClimbGameScreen = host_menu.network_screen()
	var guest_screen: ClimbGameScreen = guest_menu.network_screen()
	host_screen.roll_button.pressed.emit()
	assert_true(await _until(func() -> bool: return int(guest_screen.current_view().get("rolls", 0)) == 1 and not guest_screen.timeline.is_busy()))
	assert_eq(guest_screen.current_view()["last_roll"]["dice"], host_screen.current_view()["last_roll"]["dice"])
	assert_eq(guest_screen.current_view()["positions"], host_screen.current_view()["positions"])
	assert_false(guest_screen.roll_button.disabled, "now it is the guest's turn")
	guest_screen.roll_button.pressed.emit()
	assert_true(await _until(func() -> bool: return int(host_screen.current_view().get("rolls", 0)) == 2 and not host_screen.timeline.is_busy()))


func test_the_host_can_send_everyone_back_to_the_lobby_and_start_again() -> void:
	await _start_the_game()
	(host_menu.network_screen() as ClimbGameScreen).lobby_button.pressed.emit()
	assert_true(await _until(func() -> bool: return not host_menu.in_network_game() and not guest_menu.in_network_game()))
	assert_true(host_menu.lobby().visible and host_menu.lobby().lobby_view.visible)
	assert_true(guest_menu.lobby().visible and guest_menu.lobby().lobby_view.visible)
	assert_eq(guest_menu.lobby().lobby_client().state["phase"], LobbyLogic.PHASE_OPEN)
	# the same session plays again: ready up, start, a fresh game on both screens
	guest_menu.lobby().ready_button.button_pressed = true
	assert_true(await _until(func() -> bool: return not host_menu.lobby().start_button.disabled))
	host_menu.lobby().start_button.pressed.emit()
	assert_true(await _until(func() -> bool: return host_menu.in_network_game() and guest_menu.in_network_game()))
	assert_eq(int(host_menu.network_screen().current_view()["rolls"]), 0)
	assert_false((guest_menu.network_screen() as ClimbGameScreen).current_view().is_empty())


# --- leaving -------------------------------------------------------------------------------------------------------------

func test_a_guest_who_leaves_goes_home_and_the_host_keeps_playing() -> void:
	await _start_the_game()
	(guest_menu.network_screen() as ClimbGameScreen).leave_requested.emit()
	assert_true(await _until(func() -> bool: return guest_menu.lobby() == null and guest_menu.game_list.is_visible_in_tree()))
	assert_true(host_menu.in_network_game(), "the host's game goes on (paused, waiting)")


func test_when_the_host_leaves_everybody_goes_home() -> void:
	await _start_the_game()
	(host_menu.network_screen() as ClimbGameScreen).leave_requested.emit()
	assert_true(await _until(func() -> bool: return host_menu.lobby() == null and guest_menu.lobby() == null, 900))
	assert_true(host_menu.game_list.is_visible_in_tree())
	assert_true(guest_menu.game_list.is_visible_in_tree())
	assert_false(guest_menu.in_network_game())
	assert_true(guest_menu.error_label.visible, "the guest is told why")


func test_a_guest_without_the_game_is_told_so_not_dropped_silently() -> void:
	host_menu = await _menu()
	var host_lobby: LobbyScene = host_menu.open_host_lobby(GAME)
	host_lobby.name_edit.text = "Hosty"
	host_lobby.host_session()
	await _until(func() -> bool: return host_lobby.shared_address != "")
	guest_menu = await _menu()
	guest_menu.registry = GameRegistry.new()  # an app that has no games
	var guest_lobby: LobbyScene = guest_menu.open_join_lobby()
	guest_lobby.name_edit.text = "Asha"
	guest_lobby.address_edit.text = host_lobby.shared_address
	guest_lobby.join_session()
	assert_true(await _until(func() -> bool: return guest_lobby.start_view.visible and guest_lobby.status_label.text.contains("Could not join")))
	assert_false(guest_menu.in_network_game())


# --- the command line --------------------------------------------------------------------------------------------------------

func test_auto_host_opens_the_host_lobby_and_writes_the_room_code_to_the_share_file() -> void:
	var share: String = "user://test_share_%d.txt" % randi()
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child_autofree(viewport)
	var menu: MainMenu = MainMenu.new()
	menu.use_command_line = false
	menu.network_config = {"transport": "loopback", "hub": hub}
	menu.launch_options = {"auto": "host", "name": "Hosty", "share_file": share}
	viewport.add_child(menu)
	assert_true(await _until(func() -> bool: return FileAccess.file_exists(share)))
	var written: String = FileAccess.get_file_as_string(share)
	assert_eq(written, menu.lobby().shared_address)
	assert_ne(written, "")
	# a second instance reads the same file, joins and ticks ready by itself
	var guest_viewport: SubViewport = SubViewport.new()
	guest_viewport.size = Vector2i(1280, 720)
	add_child_autofree(guest_viewport)
	var guest: MainMenu = MainMenu.new()
	guest.use_command_line = false
	guest.network_config = {"transport": "loopback", "hub": hub}
	guest.launch_options = {"auto": "join", "name": "Asha", "join_from_file": share, "auto_ready": true}
	guest_viewport.add_child(guest)
	assert_true(await _until(func() -> bool: return not menu.lobby().start_button.disabled), "the guest joined and readied up on its own")
	DirAccess.remove_absolute(share)
	AppSettings.path = "user://test_main_flows_settings.cfg"


func test_auto_join_by_code_joins_without_a_click() -> void:
	host_menu = await _menu()
	var host_lobby: LobbyScene = host_menu.open_host_lobby(GAME)
	host_lobby.name_edit.text = "Hosty"
	host_lobby.host_session()
	await _until(func() -> bool: return host_lobby.shared_address != "")
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child_autofree(viewport)
	var guest: MainMenu = MainMenu.new()
	guest.use_command_line = false
	guest.network_config = {"transport": "loopback", "hub": hub}
	guest.launch_options = {"auto": "join", "name": "Asha", "join": host_lobby.shared_address}
	viewport.add_child(guest)
	assert_true(await _until(func() -> bool: return host_lobby.players_box.get_child_count() == 2))
	AppSettings.path = "user://test_main_flows_settings.cfg"
