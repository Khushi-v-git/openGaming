extends GutTest
## The "are you sure?" card: its buttons, the keyboard rules (the first, safe button has focus;
## Escape chooses it; Enter chooses the focused one), every variant from the design, and that it
## scales to a small window and frees itself.

var viewport: SubViewport
var host: Control


func before_each() -> void:
	ConfirmDialog.auto_confirm = false
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child_autofree(viewport)
	host = Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(host)


func after_each() -> void:
	await get_tree().process_frame
	ConfirmDialog.auto_confirm = false


func _ask(config: Dictionary) -> Array:
	var chosen: Array = []
	var dialog: ConfirmDialog = ConfirmDialog.ask(host, config, func(id: String) -> void: chosen.append(id))
	await get_tree().process_frame
	await get_tree().process_frame
	return [dialog, chosen]


func _key(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event


# --- the questions ---------------------------------------------------------------------------------------

func test_every_question_from_the_design_has_its_words_and_buttons() -> void:
	var expected: Array = [
		[ConfirmDialog.leave_lobby(), "Leave this lobby?", "You can join again with the room code.", ["Stay", "Leave"], "door"],
		[ConfirmDialog.close_room(), "Close the room for everyone?", "Everyone is sent back to the home screen.", ["Keep hosting", "Close room"], "bang"],
		[ConfirmDialog.leave_game(), "Leave this game?", "Your seat is kept for a while, so you can rejoin.", ["Stay", "Leave game"], "door"],
		[ConfirmDialog.end_game_for_all(), "End the game for everyone?", "Players will go back to the lobby.", ["Keep playing", "Back to lobby", "Close room"], "bang"],
		[ConfirmDialog.leave_hotseat(), "Leave this game?", "Its progress will be lost.", ["Stay", "Leave"], "door"],
		[ConfirmDialog.remove_player("Ben", "blue"), "Remove Ben for good?", "They can't come back to this game.", ["Keep", "Remove"], "pawn"],
	]
	for entry: Array in expected:
		var made: Array = await _ask(entry[0])
		var dialog: ConfirmDialog = made[0]
		assert_eq(dialog.title_label.text, entry[1])
		assert_eq(dialog.body_label.text, entry[2])
		assert_eq(dialog.buttons.map(func(b: Button) -> String: return b.text), entry[3])
		assert_eq(dialog.config["badge"], entry[4])
		dialog.buttons[0].pressed.emit()
	assert_true(true)


func test_the_first_button_is_the_safe_one_and_the_last_is_the_destructive_one() -> void:
	for config: Dictionary in [ConfirmDialog.leave_lobby(), ConfirmDialog.close_room(), ConfirmDialog.end_game_for_all(), ConfirmDialog.remove_player("A", "red")]:
		assert_eq(config["buttons"][0]["kind"], "cream", "the first button is the quiet one")
		assert_eq(config["buttons"][0]["id"], "stay")
		assert_eq(config["buttons"][config["buttons"].size() - 1]["kind"], "terracotta")


# --- choosing ------------------------------------------------------------------------------------------------

func test_pressing_a_button_chooses_it_and_frees_the_card() -> void:
	var made: Array = await _ask(ConfirmDialog.leave_lobby())
	var dialog: ConfirmDialog = made[0]
	dialog.buttons[1].pressed.emit()
	assert_eq(made[1], ["leave"])
	assert_true(dialog.is_queued_for_deletion())
	dialog.buttons[0].pressed.emit()
	assert_eq(made[1], ["leave"], "a card answers once")


func test_escape_chooses_the_first_button() -> void:
	var made: Array = await _ask(ConfirmDialog.close_room())
	(made[0] as ConfirmDialog)._input(_key(KEY_ESCAPE))
	assert_eq(made[1], ["stay"])


func test_the_first_button_starts_with_the_focus_and_enter_chooses_it() -> void:
	var made: Array = await _ask(ConfirmDialog.leave_game())
	var dialog: ConfirmDialog = made[0]
	assert_eq(viewport.gui_get_focus_owner(), dialog.buttons[0], "focus starts on the safe button")
	dialog._input(_key(KEY_ENTER))
	assert_eq(made[1], ["stay"])


func test_enter_chooses_whichever_button_has_the_focus() -> void:
	var made: Array = await _ask(ConfirmDialog.leave_game())
	var dialog: ConfirmDialog = made[0]
	dialog.buttons[1].grab_focus()
	dialog._input(_key(KEY_ENTER))
	assert_eq(made[1], ["leave"])


func test_auto_confirm_answers_with_the_last_button_and_shows_nothing() -> void:
	ConfirmDialog.auto_confirm = true
	var chosen: Array = []
	var dialog: ConfirmDialog = ConfirmDialog.ask(host, ConfirmDialog.end_game_for_all(), func(id: String) -> void: chosen.append(id))
	assert_null(dialog)
	assert_eq(chosen, ["close"])
	assert_eq(host.get_child_count(), 0)


# --- looks -----------------------------------------------------------------------------------------------------

func test_the_card_is_centred_wide_enough_and_stacks_three_buttons() -> void:
	var made: Array = await _ask(ConfirmDialog.end_game_for_all())
	var dialog: ConfirmDialog = made[0]
	assert_eq(dialog.size, Vector2(1280, 720))
	assert_almost_eq(dialog.card.size.x, ConfirmDialog.CARD_WIDTH_STACKED, 1.0)
	var column: Control = dialog.buttons[0].get_parent()
	assert_true(column is VBoxContainer, "stacked")
	assert_lt(dialog.buttons[0].global_position.y, dialog.buttons[1].global_position.y)
	assert_almost_eq(dialog.buttons[0].global_position.x, dialog.buttons[2].global_position.x, 1.0)
	var center: float = dialog.card.global_position.x + dialog.card.size.x / 2.0
	assert_almost_eq(center, 640.0, 6.0)
	var two: Array = await _ask(ConfirmDialog.leave_lobby())
	var row: Control = (two[0] as ConfirmDialog).buttons[0].get_parent()
	assert_true(row is HBoxContainer, "side by side")


func test_it_scales_down_for_a_small_window_and_stays_on_screen() -> void:
	viewport.size = Vector2i(480, 360)
	await get_tree().process_frame
	var made: Array = await _ask(ConfirmDialog.close_room())
	var dialog: ConfirmDialog = made[0]
	assert_lte(dialog.card.size.x, 480.0 - 32.0 + 1.0)
	assert_gte(dialog.card.global_position.x, 0.0)
	assert_lte(dialog.card.global_position.x + dialog.card.size.x, 480.0)


func test_the_dim_layer_blocks_the_screen_behind() -> void:
	var made: Array = await _ask(ConfirmDialog.leave_lobby())
	var dialog: ConfirmDialog = made[0]
	assert_eq(dialog.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_eq((dialog.get_child(0) as ColorRect).mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_almost_eq((dialog.get_child(0) as ColorRect).color.a, 0.5, 0.01)


func test_the_focus_mark_is_a_saffron_ring_outside_the_button() -> void:
	var made: Array = await _ask(ConfirmDialog.leave_lobby())
	var ring: StyleBoxFlat = (made[0] as ConfirmDialog).buttons[0].get_theme_stylebox("focus") as StyleBoxFlat
	assert_not_null(ring)
	assert_false(ring.draw_center)
	assert_eq(ring.border_color, Tokens.SAFFRON)
	assert_eq(ring.border_width_left, 4)
	assert_eq(ring.expand_margin_left, 4.0)


func test_the_card_goes_away_with_the_screen_it_was_asked_on() -> void:
	var made: Array = await _ask(ConfirmDialog.leave_lobby())
	host.visible = false
	assert_true((made[0] as ConfirmDialog).is_queued_for_deletion())
	assert_eq(made[1], [], "nothing was chosen")


func test_a_removed_players_card_takes_their_colour_and_pawn() -> void:
	for color: String in ["red", "blue", "green", "yellow"]:
		var config: Dictionary = ConfirmDialog.remove_player("X", color)
		assert_eq(config["back"], ConfirmDialog.PAWN_COLORS[color])
	var unknown: Dictionary = ConfirmDialog.remove_player("X", "")
	assert_eq(unknown["back"], Tokens.DEEP_TEAL)
