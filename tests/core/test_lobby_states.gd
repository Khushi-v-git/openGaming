extends GutTest
## The lobby's less common states: a short window with an error and a Rejoin button, the error mark
## on the join field, Back beside the title, a long address that is not a room code, and what a host
## sees once the game has started. (Screens: games/climb_and_slither/tools/render_lobby_states.gd.)

const TEST_SETTINGS: String = "user://test_lobby_states.cfg"
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
	AppSettings.set_host_via("direct")


func after_each() -> void:
	await get_tree().process_frame
	DirAccess.remove_absolute(TEST_SETTINGS)
	AppSettings.path = _saved_path


func _scene(player_name: String, window: Vector2i = Vector2i(1280, 720)) -> LobbyScene:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = window
	add_child_autofree(viewport)
	var scene: LobbyScene = LobbyScene.new()
	scene.setup({
		"game_id": GAME, "game_title": "Climb", "app_version": "1.0.0", "game_registry": registry,
		"transport": {"transport": "loopback", "hub": hub, "connection_ui": true, "port": 24680}, "player_name": player_name,
	})
	viewport.add_child(scene)
	return scene


func _until(condition: Callable, max_frames: int = 600) -> bool:
	for _i: int in max_frames:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


## True when the field carries the rose "something is wrong" edge.
func _marked(field: LineEdit) -> bool:
	return (field.get_theme_stylebox("normal") as StyleBoxFlat).border_color == Tokens.ROSE


# --- the start screen on a short window -----------------------------------------------------------------

func test_the_start_screen_with_an_error_and_a_rejoin_button_stays_inside_a_720p_window() -> void:
	var scene: LobbyScene = _scene("Asha")
	await get_tree().process_frame
	scene._resume = {"address": "x", "name": "Asha", "identity": {}}
	scene._show_start_view("Left the session: Lost connection to the host.")
	await get_tree().process_frame
	await get_tree().process_frame
	var card: Rect2 = scene.panel.get_global_rect()
	assert_gte(card.position.y, 0.0, "the card is not cut off at the top")
	assert_lte(card.end.y, 720.0, "nor at the bottom")
	assert_true(scene.rejoin_button.visible)
	assert_true(scene.status_label.visible)


func test_the_plain_start_screen_does_not_need_to_scroll_at_720p() -> void:
	var scene: LobbyScene = _scene("Asha")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_lte(scene.start_scroll.custom_minimum_size.y, scene.start_view.get_combined_minimum_size().y + 0.5)
	assert_false(scene.start_scroll.get_v_scroll_bar().visible, "everything fits without a scroll bar")


func test_back_sits_beside_the_title_on_the_start_screen_only() -> void:
	var scene: LobbyScene = _scene("Asha")
	await get_tree().process_frame
	assert_true(scene.back_button.visible)
	assert_eq(scene.back_button.get_parent(), scene.title_label.get_parent(), "in the title row")
	scene.host_session()
	assert_false(scene.back_button.visible, "not while connecting or in the lobby")


# --- a join that failed ------------------------------------------------------------------------------------

func test_a_failed_join_marks_the_address_field_and_typing_clears_the_mark() -> void:
	var scene: LobbyScene = _scene("Asha")
	await get_tree().process_frame
	assert_false(_marked(scene.address_edit))
	scene._on_join_failed(ErrorCodes.ROOM_FULL, "This room is full.", {})
	assert_true(_marked(scene.address_edit), "a rose edge")
	assert_string_contains(scene.status_label.text, "This room is full.")
	scene.address_edit.text_changed.emit("x")
	assert_false(_marked(scene.address_edit))


func test_starting_a_new_join_clears_an_old_error_mark() -> void:
	var scene: LobbyScene = _scene("Asha")
	await get_tree().process_frame
	scene._on_join_failed(ErrorCodes.ROOM_FULL, "This room is full.", {})
	scene.address_edit.text = "loopback:99"
	scene.name_edit.text = "Asha"
	scene.join_session()
	assert_false(_marked(scene.address_edit))


# --- the share field --------------------------------------------------------------------------------------

func test_a_room_code_is_shown_big_and_a_long_address_is_shown_in_a_readable_size() -> void:
	var scene: LobbyScene = _scene("Asha")
	await get_tree().process_frame
	scene.name_edit.text = "Asha"
	scene.host_session()
	assert_true(await _until(func() -> bool: return scene.shared_address != ""))
	scene._address_editable = false
	scene.shared_address = "K4M9XQ"
	scene._style_share_field()
	assert_eq(scene.public_address_edit.get_theme_font_size("font_size"), 40)
	scene.shared_address = "192.168.100.100:24680"
	scene._style_share_field()
	assert_eq(scene.public_address_edit.get_theme_font_size("font_size"), 22, "a long address does not get the big spaced style")
	assert_eq(scene.public_address_edit.get_theme_color("font_uneditable_color"), Tokens.INK, "and it is readable")


# --- a host once the game has started -------------------------------------------------------------------------

func test_a_host_whose_game_has_started_sees_the_rules_summary_not_an_empty_card() -> void:
	var host: LobbyScene = _scene("Asha")
	await get_tree().process_frame
	host.name_edit.text = "Asha"
	host.host_session()
	assert_true(await _until(func() -> bool: return host.shared_address != ""))
	var guest: LobbyScene = _scene("Ben")
	await get_tree().process_frame
	guest.name_edit.text = "Ben"
	guest.address_edit.text = host.shared_address
	guest.join_session()
	assert_true(await _until(func() -> bool: return host.players_box.get_child_count() == 2))
	assert_true(host.settings_box.visible, "while the lobby is open the host has the interactive panel")
	guest.ready_button.button_pressed = true
	assert_true(await _until(func() -> bool: return not host.start_button.disabled))
	host.start_button.pressed.emit()
	assert_true(await _until(func() -> bool: return host.lobby_host().state["phase"] == LobbyLogic.PHASE_IN_GAME))
	await get_tree().process_frame
	assert_false(host.settings_box.visible, "no toggles once the game runs")
	assert_true(host.house_rules_box.visible, "a read-only summary instead")
	assert_gt(host.house_rules_box.get_child_count(), 0)
