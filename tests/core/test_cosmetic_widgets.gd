extends GutTest
## The small drawn widgets behind the home screen and the cards: deterministic and cheap.


func _in_viewport(node: Control, window: Vector2i = Vector2i(800, 600)) -> Control:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = window
	add_child_autofree(viewport)
	viewport.add_child(node)
	return node


# --- confetti ---------------------------------------------------------------------------------------

func test_confetti_is_the_same_every_time_for_the_same_seed() -> void:
	var a: Confetti = Confetti.new()
	var b: Confetti = Confetti.new()
	assert_eq(a.pieces, b.pieces)
	assert_eq(a.pieces.size(), a.count)
	b.reseed(99)
	assert_ne(a.pieces, b.pieces, "another seed gives another scatter")
	a.free()
	b.free()


func test_confetti_pieces_stay_inside_the_rect_and_use_the_palette() -> void:
	var confetti: Confetti = Confetti.new()
	for piece: Dictionary in confetti.pieces:
		assert_between(float(piece["x"]), 0.0, 1.0)
		assert_between(float(piece["y"]), 0.0, 1.0)
		assert_true(Confetti.COLORS.has(piece["color"]))
		assert_between(float(piece["size"]), 10.0, 22.0)
	confetti.free()


func test_confetti_never_catches_the_mouse() -> void:
	var confetti: Confetti = Confetti.new()
	assert_eq(confetti.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	confetti.free()


# --- the winner's medallion -----------------------------------------------------------------------------

func test_the_medallion_takes_the_players_colour_and_has_room_for_its_crown() -> void:
	var medallion: PawnMedallion = PawnMedallion.new()
	medallion.color = Tokens.PLAYER_BLUE
	assert_eq(medallion.color, Tokens.PLAYER_BLUE)
	assert_gte(medallion.custom_minimum_size.x, 164.0)
	assert_gte(medallion.custom_minimum_size.y, 170.0 + 20.0, "disc plus the crown above it")
	medallion.free()


# --- bouncing dots -----------------------------------------------------------------------------------------

func test_the_dots_only_animate_while_they_can_be_seen() -> void:
	var dots: BouncingDots = BouncingDots.new()
	_in_viewport(dots)
	await get_tree().process_frame
	assert_true(dots.is_animating())
	dots.visible = false
	assert_false(dots.is_animating(), "a hidden card costs nothing")
	dots.visible = true
	assert_true(dots.is_animating())


func test_the_dots_bounce_up_never_below_the_baseline_and_in_a_wave() -> void:
	var lowest: float = 0.0
	var highest: float = -100.0
	for step: int in 200:
		for i: int in 5:
			var offset: float = BouncingDots.bounce(i, float(step) * 0.05)
			lowest = minf(lowest, offset)
			highest = maxf(highest, offset)
	assert_lte(highest, 0.0)
	assert_gte(lowest, -9.0)
	assert_ne(BouncingDots.bounce(0, 0.4), BouncingDots.bounce(3, 0.4), "neighbours are out of step")


# --- the game badge ---------------------------------------------------------------------------------------------

func test_each_game_gets_its_own_badge_colours_and_they_cycle() -> void:
	assert_ne(GameBadge.colors_for(0), GameBadge.colors_for(1))
	assert_eq(GameBadge.colors_for(0), GameBadge.colors_for(GameBadge.PALETTES.size()))
	var badge: GameBadge = GameBadge.new()
	badge.use_palette(1)
	assert_eq(badge.disc, GameBadge.colors_for(1)[0])
	badge.free()
