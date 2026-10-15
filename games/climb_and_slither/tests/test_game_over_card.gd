extends GutTest
## The game-over card: the winner's colour on the medallion, confetti behind it, and the pause and
## disconnect cards' extra decoration.


func _finished_screen() -> ClimbGameScreen:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child_autofree(viewport)
	var screen: ClimbGameScreen = load("res://games/climb_and_slither/ui/climb_game_screen.tscn").instantiate()
	viewport.add_child(screen)
	var rules: ClimbAndSlitherRules = ClimbAndSlitherRules.new()
	var controller: LocalGameController = LocalGameController.new(rules, ["p1", "p2", "p3"], ClimbRig.classic(), {}, 4)
	screen.setup(controller, [{"player_id": "p1", "name": "Asha"}, {"player_id": "p2", "name": "Ben"}, {"player_id": "p3", "name": "Chandra"}])
	screen.set_speed_by_label("Instant")
	controller.start()
	var guard: int = 0
	while not screen.overlay.visible and guard < 3000:
		if not screen.roll_button.disabled:
			screen.roll_button.pressed.emit()
		await get_tree().process_frame
		guard += 1
	return screen


func test_the_medallion_is_in_the_winners_colour_and_the_title_names_them() -> void:
	var screen: ClimbGameScreen = await _finished_screen()
	assert_true(screen.overlay.visible)
	var rules: ClimbAndSlitherRules = ClimbAndSlitherRules.new()
	var winner: String = rules.winner(screen.current_view())
	var expected: Color = ClimbGameScreen._tint_of(screen.current_view(), winner)
	assert_eq(screen.medallion.color, expected)
	assert_ne(expected, Tokens.SAFFRON, "a real player colour, not the fallback")
	assert_string_contains(screen.overlay_title.text, "wins!")


func test_the_confetti_is_behind_the_card_and_does_not_block_the_buttons() -> void:
	var screen: ClimbGameScreen = await _finished_screen()
	assert_not_null(screen.confetti)
	assert_eq(screen.confetti.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var order: Array = screen.overlay.get_children()
	assert_lt(order.find(screen.confetti), order.size() - 1, "the card is drawn after (above) the confetti")


func test_the_tint_falls_back_to_saffron_for_an_unknown_player() -> void:
	assert_eq(ClimbGameScreen._tint_of({"players": []}, "nobody"), Tokens.SAFFRON)
	var view: Dictionary = {"players": [{"player_id": "a", "color": "green"}]}
	assert_eq(ClimbGameScreen._tint_of(view, "a"), Tokens.PLAYER_GREEN)


func test_the_disconnected_card_has_its_round_badge_and_the_pause_card_its_dots() -> void:
	var overlay: PresenceOverlay = PresenceOverlay.new()
	add_child_autofree(overlay)
	assert_eq(overlay.lost_badge.text, "!")
	assert_not_null(overlay.pause_dots)
	assert_not_null(overlay.link_dots)
