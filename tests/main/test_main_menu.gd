extends GutTest
## The home screen is built from the registry and starts a hot-seat game without knowing which.


func after_each() -> void:
	await get_tree().process_frame  # rows the menu queued for freeing are gone before the orphan check


func _menu() -> MainMenu:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child_autofree(viewport)
	var menu: MainMenu = MainMenu.new()
	menu.use_command_line = false
	viewport.add_child(menu)
	await get_tree().process_frame
	return menu


func test_the_game_list_comes_from_the_registry() -> void:
	var menu: MainMenu = await _menu()
	var ids: Array = []
	for card: Node in menu.game_list.get_children():
		ids.append(card.get_meta("game_id"))
	assert_true(ids.has("climb_and_slither"))
	assert_eq(ids.size(), menu.registry.playable().size())
	assert_eq((menu.game_list.get_child(0).find_child("Title", true, false) as Label).text, "Climb and Slither")


func test_each_game_card_offers_host_join_and_hot_seat() -> void:
	var menu: MainMenu = await _menu()
	var card: Node = menu.game_list.get_child(0)
	assert_eq((card.find_child("HostButton", true, false) as Button).text, "Host game")
	assert_eq((card.find_child("JoinGameButton", true, false) as Button).text, "Join game")
	assert_eq((card.find_child("HotseatButton", true, false) as Button).text, "Play on this computer")
	assert_eq(menu.join_button.text, "Join with a room code", "and a top-level Join that works whichever game the host runs")


func test_choosing_a_game_shows_its_player_count_names_and_settings() -> void:
	var menu: MainMenu = await _menu()
	menu.choose_game("climb_and_slither")
	assert_true(menu.setup_panel.visible)
	assert_false(menu.game_list.visible)
	assert_eq(menu.player_names(), ["Player 1", "Player 2"])
	menu.set_player_count(4)
	assert_eq(menu.player_names().size(), 4)
	assert_eq(menu.player_names()[3], "Player 4")
	assert_not_null(menu._settings_node, "the game's own settings panel is shown")
	assert_true(menu._settings_node is ClimbSettingsPanel)


func test_changing_the_count_keeps_the_names_already_typed() -> void:
	var menu: MainMenu = await _menu()
	menu.choose_game("climb_and_slither")
	menu._name_fields[0].text = "Asha"
	menu.set_player_count(3)
	assert_eq(menu.player_names()[0], "Asha")
	menu.set_player_count(2)
	assert_eq(menu.player_names(), ["Asha", "Player 2"])


func test_a_game_without_a_ui_cannot_be_chosen() -> void:
	var menu: MainMenu = await _menu()
	menu.choose_game("no_such_game")
	assert_eq(menu.selected_game(), "")
	assert_false(menu.setup_panel.visible)


func test_empty_and_duplicate_names_are_refused_with_a_message() -> void:
	var menu: MainMenu = await _menu()
	menu.choose_game("climb_and_slither")
	menu._name_fields[0].text = "   "
	menu.start_hotseat()
	assert_true(menu.error_label.visible)
	assert_false(menu.in_game())
	menu._name_fields[0].text = "Mira"
	menu._name_fields[1].text = "mira"
	menu.start_hotseat()
	assert_string_contains(menu.error_label.text, "different")
	assert_false(menu.in_game())


func test_starting_a_game_opens_the_game_screen_ready_to_roll() -> void:
	var menu: MainMenu = await _menu()
	var started: Array = []
	menu.game_started.connect(func(id: String) -> void: started.append(id))
	menu.choose_game("climb_and_slither")
	menu._name_fields[0].text = "Asha"
	menu._name_fields[1].text = "Ben"
	menu.start_hotseat()
	assert_true(menu.in_game())
	assert_eq(started, ["climb_and_slither"])
	var screen: ClimbGameScreen = menu._game_node
	await get_tree().process_frame
	assert_eq(screen.roll_button.text, "Roll for Asha")
	assert_false(menu._menu_root.visible)
	screen.set_speed_by_label("Instant")
	screen.roll_button.pressed.emit()
	assert_eq(screen.roll_button.text, "Roll for Ben")


func test_the_chosen_house_rules_reach_the_game() -> void:
	var menu: MainMenu = await _menu()
	menu.choose_game("climb_and_slither")
	var panel: ClimbSettingsPanel = menu._settings_node
	(panel.get_child(0) as CheckButton).button_pressed = true  # exact finish
	(panel.get_child(1) as CheckButton).button_pressed = true  # extra turn on a six
	menu.start_hotseat()
	var settings: Dictionary = (menu._game_node as ClimbGameScreen).current_view()["settings"]
	assert_true(settings["exact_finish"])
	assert_true(settings["extra_turn_on_six"])
	assert_eq(settings["dice_count"], 1)


func test_leaving_the_game_returns_to_the_list() -> void:
	var menu: MainMenu = await _menu()
	menu.choose_game("climb_and_slither")
	menu.start_hotseat()
	(menu._game_node as ClimbGameScreen).leave_requested.emit()
	await get_tree().process_frame
	assert_false(menu.in_game())
	assert_true(menu._menu_root.visible)
	assert_true(menu.game_list.visible)
	assert_false(menu.setup_panel.visible)


func test_the_project_opens_the_main_scene_at_1280_by_720() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://main/main.tscn")
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_width"), 1280)
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 720)
	assert_not_null(load("res://main/main.tscn"))


# --- the home screen's look ---------------------------------------------------------------------------------

func test_each_game_card_has_a_badge_a_name_and_a_player_count() -> void:
	var menu: MainMenu = await _menu()
	var card: Node = menu.game_list.get_child(0)
	assert_true(card is PaperCard, "a cream card with a coloured card behind it")
	assert_not_null(card.find_child("Badge", true, false) as GameBadge)
	assert_eq((card.find_child("Players", true, false) as Label).text, "2-4 players")


func test_the_player_count_line_reads_naturally() -> void:
	assert_eq(MainMenu._players_text(2, 4), "2-4 players")
	assert_eq(MainMenu._players_text(2, 2), "2 players")
	assert_eq(MainMenu._players_text(1, 1), "1 player")


func test_the_title_has_its_shadow_copy_and_hides_with_the_menu_while_setting_up() -> void:
	var menu: MainMenu = await _menu()
	assert_true(menu._title_block.visible)
	var labels: Array = menu._title_block.find_children("*", "Label", true, false)
	assert_eq(labels.size(), 2, "a saffron shadow copy behind the indigo title")
	menu.choose_game("climb_and_slither")
	assert_false(menu._title_block.visible, "the setup card needs the room")
	assert_false(menu._bottom_row.visible)
	menu.show_game_list()
	assert_true(menu._title_block.visible)
	assert_true(menu._bottom_row.visible)


func test_the_setup_panel_is_a_paper_card() -> void:
	var menu: MainMenu = await _menu()
	assert_true(menu.setup_panel is PaperCard)


func test_quit_asks_to_quit_without_closing_the_test_run() -> void:
	var menu: MainMenu = await _menu()
	menu.quit_on_request = false
	var asked: Array = [0]
	menu.quit_requested.connect(func() -> void: asked[0] += 1)
	menu.quit_button.pressed.emit()
	assert_eq(asked[0], 1)
	assert_true(is_instance_valid(menu))


func test_the_home_screen_fits_a_1280_by_720_window() -> void:
	var menu: MainMenu = await _menu()
	await get_tree().process_frame
	var column: Control = menu._title_block.get_parent()
	assert_lte(column.size.y, 720.0, "the home column fits the window height")
	assert_gte(column.global_position.y, 0.0)
	menu.choose_game("climb_and_slither")
	menu.set_player_count(4)
	await get_tree().process_frame
	await get_tree().process_frame
	var card: Control = menu.setup_panel
	assert_lte(card.size.y, 720.0, "the hot-seat setup with four players fits too")


# --- the home screen's wording -------------------------------------------------------------------------------

func test_the_card_says_the_player_count_once_and_the_bottom_join_says_what_it_is_for() -> void:
	var menu: MainMenu = await _menu()
	var card: Node = menu.game_list.get_child(0)
	var description: Label = card.find_child("Description", true, false) as Label
	assert_not_null(description)
	assert_false(description.text.contains("players"), "the player count is on the card's own line")
	assert_eq(menu.join_button.text, "Join with a room code")
	assert_string_contains(menu.join_button.tooltip_text, "room code")


func test_the_home_screen_buttons_fit_inside_a_720p_window() -> void:
	var menu: MainMenu = await _menu()
	await get_tree().process_frame
	var window: Rect2 = Rect2(Vector2.ZERO, Vector2(1280, 720))
	for button: Button in [menu.join_button, menu.quit_button]:
		assert_true(window.encloses(button.get_global_rect()), "%s is inside the window" % button.text)
