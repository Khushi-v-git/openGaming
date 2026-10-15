extends GutTest
## The lobby's papercut layout: empty seats, the guest's "you" line and rules list, the segmented
## "Host with" control, the big room code, and the card colours. (Behaviour has its own tests in
## test_lobby_scene.gd and test_lobby_scene_settings.gd; this checks what is drawn.)

const TEST_SETTINGS: String = "user://test_lobby_look.cfg"
const GAME: String = "climb_and_slither"

var hub: LoopbackHub
var registry: GameRegistry
var _saved_path: String


func before_each() -> void:
	hub = LoopbackHub.new()
	MessageLog.enabled = false
	registry = GameRegistry.new()
	registry.load_from("res://games")
	_saved_path = AppSettings.path
	AppSettings.path = TEST_SETTINGS
	DirAccess.remove_absolute(TEST_SETTINGS)


func after_each() -> void:
	await get_tree().process_frame
	DirAccess.remove_absolute(TEST_SETTINGS)
	AppSettings.path = _saved_path


func _scene(player_name: String, transport: Dictionary = {}) -> LobbyScene:
	var scene: LobbyScene = LobbyScene.new()
	scene.setup({
		"game_id": GAME, "game_title": "Climb", "app_version": "1.0.0", "game_registry": registry,
		"transport": transport if not transport.is_empty() else {"transport": "loopback", "hub": hub},
		"player_name": player_name,
	})
	add_child_autofree(scene)
	return scene


func _until(condition: Callable, max_frames: int = 600) -> bool:
	for _i: int in max_frames:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _host_and_guest() -> Array[LobbyScene]:
	var host: LobbyScene = _scene("Hosty")
	host.host_button.pressed.emit()
	await _until(func() -> bool: return host.lobby_view.visible and host.shared_address != "")
	var guest: LobbyScene = _scene("Asha")
	guest.address_edit.text = host.shared_address
	guest.join_button.pressed.emit()
	await _until(func() -> bool: return host.players_box.get_child_count() == 2 and guest.players_box.get_child_count() == 2)
	return [host, guest]


func _back_color(scene: LobbyScene) -> Color:
	return (scene.panel as PaperCard).back_color


# --- the players and the empty seats ------------------------------------------------------------------------

func test_free_seats_are_dashed_rows_outside_the_player_list() -> void:
	var pair: Array[LobbyScene] = await _host_and_guest()
	var host: LobbyScene = pair[0]
	assert_eq(host.players_box.get_child_count(), 2, "only real players are in the list")
	assert_eq(host.empty_seats_box.get_child_count(), 2, "Climb seats 4: two seats are still free (two are shown)")
	for seat: Node in host.empty_seats_box.get_children():
		assert_true(seat is PaperEmptySeat)


func test_a_full_table_has_no_empty_seats_and_the_lobby_rooms_follow_the_game_limits() -> void:
	var pair: Array[LobbyScene] = await _host_and_guest()
	var host: LobbyScene = pair[0]
	var third: LobbyScene = _scene("Bo")
	third.address_edit.text = host.shared_address
	third.join_button.pressed.emit()
	var fourth: LobbyScene = _scene("Cy")
	fourth.address_edit.text = host.shared_address
	fourth.join_button.pressed.emit()
	assert_true(await _until(func() -> bool: return host.players_box.get_child_count() == 4))
	assert_eq(host.empty_seats_box.get_child_count(), 0)


func test_rows_are_pills_with_a_pawn_a_crown_for_the_host_and_a_check_when_ready() -> void:
	var pair: Array[LobbyScene] = await _host_and_guest()
	var host: LobbyScene = pair[0]
	var host_row: PaperRow = host.players_box.get_child(0)
	var name_label: Label = host_row.get_child(0)
	assert_eq(name_label.get_child_count(), 2, "the host's pawn and crown")
	assert_gte(host_row.custom_minimum_size.y, 52.0)
	var status: Label = host_row.get_child(1)
	assert_eq(status.text, "Ready")
	assert_eq(status.get_child_count(), 1, "a dot before Ready")
	assert_true((status.get_child(0) as ChipDot).ready_mark, "with a check in it")
	var guest_row: PaperRow = host.players_box.get_child(1)
	assert_eq((guest_row.get_child(0) as Label).get_child_count(), 1, "a pawn, no crown")
	assert_eq((guest_row.get_child(1) as Label).text, "Not ready")
	assert_false(((guest_row.get_child(1) as Label).get_child(0) as ChipDot).ready_mark, "an empty dot, no check, until ready")


# --- the guest's side ------------------------------------------------------------------------------------------------

func test_a_guest_sees_who_they_are_and_a_list_of_the_house_rules() -> void:
	var pair: Array[LobbyScene] = await _host_and_guest()
	var guest: LobbyScene = pair[1]
	assert_true(guest.you_row.visible)
	assert_eq(guest.you_label.text, "You are playing as Asha")
	assert_true(guest.you_icon.visible)
	assert_false(guest.share_box.visible, "guests have nothing to share")
	assert_true(guest.house_rules_box.visible)
	assert_eq(guest.house_rules_box.get_child_count(), 1)
	assert_eq(guest.bottom_caption.text, "Waiting for the host to start...")
	assert_true(guest.bottom_caption.visible)
	assert_true(guest.ready_card.visible)
	assert_false(guest.start_button.visible)


func test_the_host_does_not_see_the_guest_widgets() -> void:
	var pair: Array[LobbyScene] = await _host_and_guest()
	var host: LobbyScene = pair[0]
	assert_false(host.you_row.visible)
	assert_false(host.ready_card.visible)
	assert_true(host.share_box.visible)
	assert_true(host.settings_box.visible, "the host edits the house rules")
	assert_false(host.house_rules_box.visible)


func test_the_host_is_told_what_is_missing_before_start() -> void:
	var pair: Array[LobbyScene] = await _host_and_guest()
	var host: LobbyScene = pair[0]
	assert_true(host.start_button.disabled)
	assert_true(host.bottom_caption.visible)
	assert_eq(host.bottom_caption.text, "Everyone must be ready")
	pair[1].ready_button.button_pressed = true
	assert_true(await _until(func() -> bool: return not host.start_button.disabled))
	assert_false(host.bottom_caption.visible, "nothing is missing any more")


# --- the room code ---------------------------------------------------------------------------------------------------------

func test_a_relay_room_code_is_big_spaced_out_and_cannot_be_edited() -> void:
	var host: LobbyScene = _scene("Hosty")
	host.host_button.pressed.emit()
	await _until(func() -> bool: return host.lobby_view.visible and host.shared_address != "")
	host.shared_address = "K4M9XQ"
	host.share_label = "room code"
	host._address_editable = false
	host._render()
	assert_eq(host.public_address_edit.text, "K4M9XQ", "the text itself is just the code, so Copy copies it")
	assert_false(host.public_address_edit.editable)
	assert_gte(host.public_address_edit.get_theme_font_size("font_size"), 36)
	var font: Font = host.public_address_edit.get_theme_font("font")
	assert_true(font is FontVariation)
	assert_gt((font as FontVariation).spacing_glyph, 0, "letters are spaced out")
	assert_eq(host.address_caption.text, "Share this room code")
	assert_true(host.share_help_label.visible)


func test_a_direct_address_is_a_normal_editable_field_without_the_code_help() -> void:
	var host: LobbyScene = _scene("Hosty")
	host.host_button.pressed.emit()
	await _until(func() -> bool: return host.lobby_view.visible and host.shared_address != "")
	host.share_label = "address"
	host._address_editable = true
	host._render()
	assert_true(host.public_address_edit.editable)
	assert_false(host.share_help_label.visible)
	assert_lt(host.public_address_edit.get_theme_font_size("font_size"), 30)


# --- the start screen's connection box --------------------------------------------------------------------------------------

func _app_scene() -> LobbyScene:
	var scene: LobbyScene = _scene("Asha", {"transport": "auto", "host_via": "relay", "relay_url": "", "port": 24999, "bind_address": "127.0.0.1", "connection_ui": true})
	return scene


func test_host_with_is_two_pills_that_drive_the_real_choice() -> void:
	var scene: LobbyScene = _app_scene()
	await get_tree().process_frame
	var panel: ConnectionPanel = scene.connection_panel
	assert_eq(panel._segments.size(), 2)
	assert_false(panel.via_picker.visible, "the OptionButton only holds the choice")
	assert_true(panel.uses_relay())
	panel._segments[1].pressed.emit()
	assert_eq(panel.host_via(), "direct")
	assert_eq(AppSettings.host_via(), "direct")
	assert_true(scene.port_spin.visible, "direct hosting needs the port")
	panel._segments[0].pressed.emit()
	assert_true(panel.uses_relay())
	assert_false(scene.port_spin.visible)


func test_choosing_through_the_picker_moves_the_pills_too() -> void:
	var scene: LobbyScene = _app_scene()
	await get_tree().process_frame
	var panel: ConnectionPanel = scene.connection_panel
	panel.via_picker.select(1)
	panel.via_picker.item_selected.emit(1)
	var selected_style: StyleBoxFlat = panel._segments[1].get_theme_stylebox("normal") as StyleBoxFlat
	var other_style: StyleBoxFlat = panel._segments[0].get_theme_stylebox("normal") as StyleBoxFlat
	assert_eq(selected_style.bg_color, Tokens.DEEP_TEAL)
	assert_eq(other_style.bg_color.a, 0.0, "the other pill is flat")


func test_the_result_line_shows_a_mark_only_when_it_has_something_to_say() -> void:
	var scene: LobbyScene = _app_scene()
	await get_tree().process_frame
	var panel: ConnectionPanel = scene.connection_panel
	assert_false(panel.result_label.visible)
	assert_false(panel._result_row.visible)
	panel.url_edit.text = ""
	panel.test_relay()
	assert_true(panel._result_row.visible)
	assert_eq(panel._result_icon.kind, ConnectionPanel.ResultIcon.ERROR)
	assert_true(panel._result_icon.visible)


# --- the card behind the card -------------------------------------------------------------------------------------------------

func test_the_card_behind_changes_colour_with_the_view() -> void:
	var scene: LobbyScene = _scene("Hosty")
	await get_tree().process_frame
	assert_eq(_back_color(scene), Tokens.DEEP_TEAL, "start screen")
	scene.host_button.pressed.emit()
	assert_true(scene.connecting_view.visible or scene.lobby_view.visible)
	await _until(func() -> bool: return scene.lobby_view.visible)
	assert_eq(_back_color(scene), Tokens.ROSE, "lobby")
	scene._show_connecting("Starting your game...")
	assert_eq(_back_color(scene), Tokens.SAFFRON, "starting")
	assert_false(scene.title_label.visible, "the waiting cards have no title")
	scene._show_connecting("Waiting for the host to let you back in...")
	assert_eq(_back_color(scene), Tokens.INDIGO, "waiting for the host")
	scene._show_start_view("No game was found with that room code.")
	assert_eq(_back_color(scene), Tokens.ROSE, "an error on the start screen")
	assert_true(scene.title_label.visible)


func test_the_card_is_wide_in_the_lobby_and_narrower_elsewhere() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	add_child_autofree(viewport)
	var scene: LobbyScene = LobbyScene.new()
	scene.setup({"game_id": GAME, "game_title": "Climb", "app_version": "1.0.0", "game_registry": registry, "transport": {"transport": "loopback", "hub": hub}, "player_name": "Hosty"})
	viewport.add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var start_width: float = scene.panel.size.x
	assert_lte(start_width, 1000.0 + 2.0)
	scene.host_button.pressed.emit()
	assert_true(await _until(func() -> bool: return scene.lobby_view.visible))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(scene.panel.size.x, start_width, "the lobby card is the wide one")
	assert_lte(scene.panel.size.x, 1400.0 + 2.0)
