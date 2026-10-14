extends GutTest
## The game screen driven by the hot-seat controller, in a SubViewport at both target sizes.
## It checks what the screen shows and allows, never how a roll turns out.

var _rules: ClimbAndSlitherRules


func before_each() -> void:
	_rules = ClimbAndSlitherRules.new()


func _screen(window: Vector2i = Vector2i(1280, 720), players: Array = ["p1", "p2"], settings: Dictionary = {}, seed_value: int = 11, speed_label: String = "Instant") -> Array:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = window
	add_child_autofree(viewport)
	var screen: ClimbGameScreen = load("res://games/climb_and_slither/ui/climb_game_screen.tscn").instantiate()
	viewport.add_child(screen)
	var controller: LocalGameController = LocalGameController.new(_rules, players, ClimbRig.classic(), settings, seed_value)
	var named: Array = []
	for id: String in players:
		named.append({"player_id": id, "name": "Name %s" % id})
	screen.setup(controller, named)
	screen.set_speed_by_label(speed_label)
	controller.start()
	await get_tree().process_frame
	await get_tree().process_frame
	return [screen, controller, viewport]


func _roll(screen: ClimbGameScreen) -> void:
	screen.roll_button.pressed.emit()


func _wait_idle(screen: ClimbGameScreen, frames: int = 600) -> void:
	for _i: int in frames:
		if not screen.timeline.is_busy():
			return
		await get_tree().process_frame


# --- the opening picture --------------------------------------------------------------------------------

func test_the_screen_shows_the_players_the_board_and_whose_turn_it_is() -> void:
	var made: Array = await _screen()
	var screen: ClimbGameScreen = made[0]
	assert_eq(screen.player_rows.size(), 2)
	assert_eq(screen.board_view.number_labels.size(), 100)
	assert_eq(screen.board_view.pawn_sprites.size(), 2)
	assert_eq(screen.roll_button.text, "Roll for Name p1")
	assert_false(screen.roll_button.disabled)
	assert_false(screen.overlay.visible)
	assert_false(screen.skip_button.visible)
	assert_eq((screen.player_rows["p1"]["square"] as Label).text, "Start")


func test_the_screen_fits_at_both_target_window_sizes() -> void:
	for window: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var made: Array = await _screen(window, ["p1", "p2", "p3", "p4"])
		var screen: ClimbGameScreen = made[0]
		assert_eq(screen.size, Vector2(window))
		var board_rect: Rect2 = Rect2(screen.board_view.global_position, screen.board_view.size)
		assert_true(Rect2(Vector2.ZERO, Vector2(window)).encloses(board_rect), "%s board inside window" % str(window))
		assert_gt(screen.board_view.cell, 40.0, "%s cells readable" % str(window))
		var panel_bottom: float = screen.roll_button.global_position.y + screen.roll_button.size.y
		assert_lt(panel_bottom, float(window.y), "%s roll button on screen" % str(window))
		assert_eq(screen.player_rows.size(), 4)


# --- playing -----------------------------------------------------------------------------------------------

func test_rolling_moves_the_turn_and_shows_the_dice() -> void:
	var made: Array = await _screen()
	var screen: ClimbGameScreen = made[0]
	_roll(screen)
	await _wait_idle(screen)
	assert_eq(screen.dice_view.values().size(), 1)
	assert_between(screen.dice_view.values()[0], 1, 6)
	assert_eq(screen.roll_button.text, "Roll for Name p2")
	var rolled: int = screen.dice_view.values()[0]
	assert_eq(screen.board_view.square_of("p1"), screen.current_view()["positions"]["p1"], "the pawn is where the true state says")
	assert_gte(rolled, 1)


func test_the_roll_button_is_off_while_animations_play_and_back_after() -> void:
	var made: Array = await _screen(Vector2i(1280, 720), ["p1", "p2"], {}, 11, "2x")
	var screen: ClimbGameScreen = made[0]
	_roll(screen)
	assert_true(screen.roll_button.disabled, "busy: no second roll while animating")
	assert_true(screen.skip_button.visible)
	var before: int = screen.timeline.pending_count()
	_roll(screen)  # pressing a disabled button does nothing: still one batch
	assert_eq(screen.timeline.pending_count(), before)
	await _wait_idle(screen)
	assert_false(screen.roll_button.disabled)
	assert_false(screen.skip_button.visible)


func test_skip_ends_the_animation_on_the_true_state() -> void:
	var made: Array = await _screen(Vector2i(1280, 720), ["p1", "p2"], {}, 11, "0.5x")
	var screen: ClimbGameScreen = made[0]
	_roll(screen)
	assert_true(screen.timeline.is_busy())
	screen.skip_button.pressed.emit()
	assert_false(screen.timeline.is_busy())
	assert_false(screen.roll_button.disabled)
	var view: Dictionary = screen.current_view()
	for id: String in ["p1", "p2"]:
		assert_eq(screen.board_view.square_of(id), view["positions"][id])
	assert_false(screen.board_view.is_animating())


func test_a_whole_game_plays_to_the_game_over_overlay() -> void:
	var made: Array = await _screen(Vector2i(1280, 720), ["p1", "p2", "p3"], {}, 4)
	var screen: ClimbGameScreen = made[0]
	var guard: int = 0
	while not screen.overlay.visible and guard < 3000:
		if not screen.roll_button.disabled:
			_roll(screen)
		await get_tree().process_frame
		guard += 1
	assert_true(screen.overlay.visible, "the game over overlay appeared")
	var winner: String = _rules.winner(screen.current_view())
	assert_string_contains(screen.overlay_title.text, "Name %s" % winner)
	assert_true(screen.roll_button.disabled, "no rolling once it is over")
	assert_true(screen.rematch_button.visible, "hot-seat can play again")


func test_the_overlay_waits_for_the_animation_to_finish() -> void:
	var made: Array = await _screen(Vector2i(1280, 720), ["p1", "p2"], {}, 4)
	var screen: ClimbGameScreen = made[0]
	var guard: int = 0
	screen.set_speed_by_label("0.5x")
	while not _rules.is_finished(screen.timeline.latest) and guard < 6000:
		if not screen.roll_button.disabled:
			_roll(screen)
			if _rules.is_finished(screen.timeline.latest):
				break
			screen.skip()
		await get_tree().process_frame
		guard += 1
	assert_true(_rules.is_finished(screen.timeline.latest), "the game is over in the true state")
	assert_true(screen.timeline.is_busy(), "but the final animation is still playing")
	assert_false(screen.overlay.visible, "so the overlay is not up yet")
	screen.skip()
	assert_true(screen.overlay.visible, "skipping reaches the end and shows it")


func test_a_rematch_clears_the_overlay_and_starts_fresh() -> void:
	var made: Array = await _screen(Vector2i(1280, 720), ["p1", "p2"], {}, 4)
	var screen: ClimbGameScreen = made[0]
	var guard: int = 0
	while not screen.overlay.visible and guard < 3000:
		if not screen.roll_button.disabled:
			_roll(screen)
		await get_tree().process_frame
		guard += 1
	assert_true(screen.overlay.visible)
	screen.rematch_button.pressed.emit()
	assert_false(screen.overlay.visible)
	assert_false(_rules.is_finished(screen.current_view()))
	assert_eq(screen.board_view.square_of("p1"), 0)
	assert_eq(screen.dice_view.values().size(), 0, "no dice from the last game")
	assert_false(screen.roll_button.disabled)


# --- convergence: a snapshot of a finished game still shows the overlay --------------------------------

func test_a_snapshot_of_a_finished_game_shows_the_overlay() -> void:
	var made: Array = await _screen()
	var screen: ClimbGameScreen = made[0]
	var state: Dictionary = _rules.new_game(["p1", "p2"], ClimbRig.classic(), {}, 1)["state"]
	state["phase"] = "finished"
	state["winner"] = "p2"
	state["positions"]["p2"] = 100
	state["positions"]["p1"] = 41
	state["last_roll"] = {"player_id": "p2", "dice": [4], "total": 4}
	# a rejoin: one snapshot, no events at all
	var batch: Dictionary = {"seq": 50, "reason": "rejoin", "events": [], "view": _rules.view_for(state, "p1")}
	screen.timeline.push(batch)
	assert_true(screen.overlay.visible)
	assert_string_contains(screen.overlay_title.text, "Name p2")
	assert_eq(screen.board_view.square_of("p2"), 100)
	assert_eq(screen.dice_view.values(), [4])


func test_a_gap_in_the_batches_snaps_to_a_finished_game_too() -> void:
	var made: Array = await _screen()
	var screen: ClimbGameScreen = made[0]
	var state: Dictionary = _rules.new_game(["p1", "p2"], ClimbRig.classic(), {}, 1)["state"]
	state["phase"] = "finished"
	state["winner"] = "p1"
	state["positions"]["p1"] = 100
	screen.timeline.push({"seq": 9, "reason": "action", "events": [{"type": "won", "player_id": "p1"}], "view": _rules.view_for(state, "p1")})
	assert_true(screen.overlay.visible, "a missed batch is a snap, and the winner is shown")


func test_a_snapshot_mid_animation_drops_it_and_the_late_callbacks_do_nothing() -> void:
	var made: Array = await _screen(Vector2i(1280, 720), ["p1", "p2"], {}, 11, "0.5x")
	var screen: ClimbGameScreen = made[0]
	_roll(screen)
	assert_true(screen.timeline.is_busy())
	var state: Dictionary = _rules.new_game(["p1", "p2"], ClimbRig.classic(), {}, 1)["state"]
	state["positions"]["p1"] = 60
	screen.timeline.push({"seq": 40, "reason": "resync", "events": [], "view": _rules.view_for(state, "p1")})
	assert_false(screen.timeline.is_busy())
	assert_eq(screen.board_view.square_of("p1"), 60)
	for _i: int in 90:
		await get_tree().process_frame
	assert_eq(screen.board_view.square_of("p1"), 60, "nothing from the dropped animation moved it")
	assert_false(screen.banner.visible)


# --- leaving ----------------------------------------------------------------------------------------------------

func test_leaving_a_running_game_asks_first_and_a_finished_one_does_not() -> void:
	var made: Array = await _screen()
	var screen: ClimbGameScreen = made[0]
	var left: Array = [0]
	screen.leave_requested.connect(func() -> void: left[0] += 1)
	screen.menu_button.pressed.emit()
	assert_eq(left[0], 0, "a confirmation comes first")
	assert_true(screen._leave_dialog.visible)
	screen._leave_dialog.confirmed.emit()
	assert_eq(left[0], 1)
	screen.overlay_menu_button.pressed.emit()
	assert_eq(left[0], 2)


# --- the settings panel ----------------------------------------------------------------------------------------

func _panel() -> ClimbSettingsPanel:
	var panel: ClimbSettingsPanel = load("res://games/climb_and_slither/ui/settings_panel.tscn").instantiate()
	add_child_autofree(panel)
	return panel


func test_the_settings_panel_starts_with_the_default_rules() -> void:
	var panel: ClimbSettingsPanel = _panel()
	assert_eq(panel.settings(), ClimbSettings.defaults())
	assert_eq(panel.get_child_count(), 3)


func test_choosing_exact_finish_greys_out_two_dice_with_the_rules_tooltip_and_back() -> void:
	var panel: ClimbSettingsPanel = _panel()
	var buttons: Array = panel.get_children()
	var exact: CheckButton = buttons[0]
	var two: CheckButton = buttons[2]
	exact.button_pressed = true
	assert_true(panel.settings()["exact_finish"])
	assert_true(two.disabled)
	assert_eq(two.tooltip_text, ClimbSettings.TWO_DICE_NEEDS_NO_EXACT_FINISH)
	assert_false(exact.disabled, "a chosen option can always be switched off")
	exact.button_pressed = false
	assert_false(two.disabled)


func test_choosing_two_dice_greys_out_exact_finish() -> void:
	var panel: ClimbSettingsPanel = _panel()
	var buttons: Array = panel.get_children()
	(buttons[2] as CheckButton).button_pressed = true
	assert_eq(panel.settings()["dice_count"], 2)
	assert_true((buttons[0] as CheckButton).disabled)
	assert_eq((buttons[0] as CheckButton).tooltip_text, ClimbSettings.EXACT_FINISH_NEEDS_ONE_DIE)
	(buttons[1] as CheckButton).button_pressed = true
	assert_true(panel.settings()["extra_turn_on_six"])


func test_the_panel_only_ever_produces_settings_the_rules_accept() -> void:
	var panel: ClimbSettingsPanel = _panel()
	var buttons: Array = panel.get_children()
	for pattern: Array in [[true, false, false], [false, true, true], [true, true, false], [false, false, true]]:
		for i: int in 3:
			(buttons[i] as CheckButton).button_pressed = pattern[i]
		assert_true(CoreResult.is_ok(ClimbSettings.normalize(panel.settings())), str(pattern))


func test_set_settings_shows_them_and_refuses_nonsense() -> void:
	var panel: ClimbSettingsPanel = _panel()
	panel.set_settings({"exact_finish": true, "extra_turn_on_six": true})
	assert_true((panel.get_child(0) as CheckButton).button_pressed)
	assert_true((panel.get_child(2) as CheckButton).disabled)
	panel.set_settings({"exact_finish": true, "dice_count": 2})
	assert_eq(panel.settings(), ClimbSettings.defaults(), "a refused combination falls back to the defaults")


# --- dice view ----------------------------------------------------------------------------------------------------

func test_dice_show_and_tumble_to_the_real_faces() -> void:
	var viewport: SubViewport = SubViewport.new()
	add_child_autofree(viewport)
	var dice: ClimbDiceView = ClimbDiceView.new()
	viewport.add_child(dice)
	await get_tree().process_frame
	dice.show_faces([3, 6])
	assert_eq(dice.values(), [3, 6])
	var done: Array = [false]
	dice.tumble([2, 5], 0.2, func() -> void: done[0] = true)
	assert_true(dice.is_tumbling())
	for _i: int in 120:
		if done[0]:
			break
		await get_tree().process_frame
	assert_true(done[0])
	assert_false(dice.is_tumbling())
	assert_eq(dice.values(), [2, 5], "it lands on the real values, not the random faces")
	var instant: Array = [false]
	dice.tumble([1], 0.0, func() -> void: instant[0] = true)
	assert_true(instant[0])
	assert_eq(dice.values(), [1])
