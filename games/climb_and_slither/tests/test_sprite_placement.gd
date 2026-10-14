extends GutTest

const CELL: float = 72.0


func _catalog() -> Dictionary:
	var loaded: Dictionary = ClimbArt.load_catalog()
	assert_true(CoreResult.is_ok(loaded), str(loaded))
	return loaded["catalog"]


func _near(a: Vector2, b: Vector2, label: String = "") -> void:
	assert_lt(a.distance_to(b), 0.01, "%s: %s should be %s" % [label, str(a), str(b)])


# --- snakes: the anchors land exactly on the two squares ---------------------------------------------

func test_a_snake_puts_its_head_and_tail_exactly_on_the_two_squares() -> void:
	var prng: Prng = Prng.new(12)
	for art: Dictionary in _catalog()["snakes"]:
		for _i: int in 60:
			var head: Vector2 = Vector2(prng.range_int(0, 800), prng.range_int(0, 800))
			var tail: Vector2 = Vector2(prng.range_int(0, 800), prng.range_int(0, 800))
			if head.distance_to(tail) < 20.0:
				continue
			var placed: Dictionary = ClimbSpritePlacement.snake_transform(art, head, tail, CELL)
			var t: Transform2D = placed["transform"]
			_near(t * (art["head"] as Vector2), head, "%s head" % art["name"])
			_near(t * (art["tail"] as Vector2), tail, "%s tail" % art["name"])


func test_a_snake_pointing_right_is_not_mirrored_and_one_pointing_left_is() -> void:
	var art: Dictionary = _catalog()["snakes"][0]
	var right: Dictionary = ClimbSpritePlacement.snake_transform(art, Vector2(400, 100), Vector2(100, 100), CELL)
	var left: Dictionary = ClimbSpritePlacement.snake_transform(art, Vector2(100, 100), Vector2(400, 100), CELL)
	assert_false(right["flipped"])
	assert_true(left["flipped"])
	assert_gt((right["transform"] as Transform2D).determinant(), 0.0, "an unmirrored sprite keeps its handedness")
	assert_lt((left["transform"] as Transform2D).determinant(), 0.0, "a snake heading left is mirrored so it is not upside down")


func test_a_vertical_snake_is_not_flipped() -> void:
	var art: Dictionary = _catalog()["snakes"][0]
	assert_false(ClimbSpritePlacement.snake_transform(art, Vector2(100, 400), Vector2(100, 100), CELL)["flipped"])
	assert_false(ClimbSpritePlacement.snake_transform(art, Vector2(100, 100), Vector2(100, 400), CELL)["flipped"])


func test_a_snake_heading_left_stays_the_right_way_up_on_screen() -> void:
	# the sprite's "up" (negative y) must still point up the screen for a mirrored placement
	var art: Dictionary = _catalog()["snakes"][0]
	var placed: Dictionary = ClimbSpritePlacement.snake_transform(art, Vector2(100, 300), Vector2(400, 300), CELL)
	var t: Transform2D = placed["transform"]
	var origin: Vector2 = t * (art["tail"] as Vector2)
	var up: Vector2 = (t * ((art["tail"] as Vector2) + Vector2(0, -50))) - origin
	assert_lt(up.y, 0.0, "up stays up")


func test_snake_thickness_follows_the_stretch_gently_and_within_limits() -> void:
	var art: Dictionary = _catalog()["snakes"][0]
	var reference: float = ClimbSpritePlacement.SNAKE_BODY_CELLS * CELL / float(art["body_width"])
	var natural_px: float = ClimbSpritePlacement.snake_natural_cells(art) * CELL
	for factor: float in [0.3, 0.6, 1.0, 2.0, 5.0, 20.0]:
		var placed: Dictionary = ClimbSpritePlacement.snake_transform(art, Vector2(natural_px * factor, 0), Vector2.ZERO, CELL)
		assert_almost_eq(placed["stretch"], factor, 0.001)
		var ratio: float = placed["thickness"] / reference
		assert_between(ratio, ClimbSpritePlacement.SNAKE_THICKNESS_MIN - 0.0001, ClimbSpritePlacement.SNAKE_THICKNESS_MAX + 0.0001, "factor %f" % factor)
	var natural: Dictionary = ClimbSpritePlacement.snake_transform(art, Vector2(natural_px, 0), Vector2.ZERO, CELL)
	assert_almost_eq(natural["thickness"], reference, 0.0001, "at its natural length the body is exactly the standard width")


func test_the_snake_body_ends_up_about_the_standard_width_in_cells() -> void:
	var art: Dictionary = _catalog()["snakes"][0]
	var natural_px: float = ClimbSpritePlacement.snake_natural_cells(art) * CELL
	var placed: Dictionary = ClimbSpritePlacement.snake_transform(art, Vector2(natural_px, 0), Vector2.ZERO, CELL)
	var body_px: float = float(art["body_width"]) * placed["thickness"]
	assert_almost_eq(body_px / CELL, ClimbSpritePlacement.SNAKE_BODY_CELLS, 0.001)


# --- choosing snake art ----------------------------------------------------------------------------------

func test_the_snake_that_needs_the_least_stretching_is_chosen() -> void:
	var arts: Array = _catalog()["snakes"]
	for art_index: int in arts.size():
		var natural: float = ClimbSpritePlacement.snake_natural_cells(arts[art_index])
		var chosen: Array[int] = ClimbSpritePlacement.choose_snake_arts([natural], arts)
		assert_eq(arts[chosen[0]]["name"], arts[art_index]["name"] if _is_unique_length(arts, art_index) else arts[chosen[0]]["name"], "a snake exactly as long as %s picks a sprite of that length" % arts[art_index]["name"])
		assert_almost_eq(ClimbSpritePlacement.snake_natural_cells(arts[chosen[0]]), natural, 0.0001)


func _is_unique_length(arts: Array, index: int) -> bool:
	var length: float = ClimbSpritePlacement.snake_natural_cells(arts[index])
	for other: int in arts.size():
		if other != index and absf(ClimbSpritePlacement.snake_natural_cells(arts[other]) - length) < 0.0001:
			return false
	return true


func test_equal_snakes_get_varied_art() -> void:
	var arts: Array = _catalog()["snakes"]
	var lengths: Array = []
	for _i: int in 11:
		lengths.append(4.0)
	var chosen: Array[int] = ClimbSpritePlacement.choose_snake_arts(lengths, arts)
	var distinct: Dictionary = {}
	for index: int in chosen:
		distinct[index] = true
	assert_gte(distinct.size(), 3, "11 similar snakes do not all share one colour")


func test_choosing_is_deterministic() -> void:
	var arts: Array = _catalog()["snakes"]
	var lengths: Array = [3.2, 4.5, 4.1, 3.2, 4.5, 4.2, 5.0, 3.0]
	assert_eq(ClimbSpritePlacement.choose_snake_arts(lengths, arts), ClimbSpritePlacement.choose_snake_arts(lengths, arts))


func test_very_short_and_very_long_snakes_still_get_a_sprite() -> void:
	var arts: Array = _catalog()["snakes"]
	var chosen: Array[int] = ClimbSpritePlacement.choose_snake_arts([0.5, 15.0, 0.0], arts)
	assert_eq(chosen.size(), 3)
	for index: int in chosen:
		assert_between(index, 0, arts.size() - 1)


# --- ladders -------------------------------------------------------------------------------------------------

func _ladder(top: Vector2, foot: Vector2) -> Array[Dictionary]:
	return ClimbSpritePlacement.ladder_pieces(_catalog()["ladder"], top, foot, CELL)


func _piece_point(piece: Dictionary, local: Vector2) -> Vector2:
	return (piece["transform"] as Transform2D) * local


func test_a_ladders_top_and_foot_anchors_land_exactly_on_the_two_squares() -> void:
	var geometry: Dictionary = _catalog()["ladder"]
	var prng: Prng = Prng.new(77)
	for _i: int in 80:
		var top: Vector2 = Vector2(prng.range_int(0, 700), prng.range_int(0, 700))
		var foot: Vector2 = Vector2(prng.range_int(0, 700), prng.range_int(0, 700))
		if top.distance_to(foot) < 3.0 * CELL:
			continue
		var pieces: Array[Dictionary] = _ladder(top, foot)
		_near(_piece_point(pieces[0], geometry["top_anchor"]), top, "top anchor")
		_near(_piece_point(pieces[pieces.size() - 1], geometry["foot_anchor"]), foot, "foot anchor")


func test_a_ladder_is_a_top_piece_then_segments_then_a_bottom_piece() -> void:
	var pieces: Array[Dictionary] = _ladder(Vector2(100, 100), Vector2(100, 100 + CELL * 4.0))
	assert_eq(pieces[0]["kind"], "top")
	assert_eq(pieces[pieces.size() - 1]["kind"], "bottom")
	for i: int in range(1, pieces.size() - 1):
		assert_eq(pieces[i]["kind"], "segment")
	assert_gte(pieces.size(), 3)


func test_longer_ladders_have_more_segments() -> void:
	var short_count: int = _ladder(Vector2(0, 0), Vector2(0, CELL * 2.5)).size()
	var long_count: int = _ladder(Vector2(0, 0), Vector2(0, CELL * 7.5)).size()
	assert_gt(long_count, short_count)


func test_the_pieces_meet_with_no_gaps_or_overlaps() -> void:
	var geometry: Dictionary = _catalog()["ladder"]
	for foot_offset: Vector2 in [Vector2(0, 5.3 * CELL), Vector2(3 * CELL, 6.1 * CELL), Vector2(-4 * CELL, 2.9 * CELL), Vector2(2.2 * CELL, 8.7 * CELL)]:
		var pieces: Array[Dictionary] = _ladder(Vector2(300, 100), Vector2(300, 100) + foot_offset)
		for i: int in range(0, pieces.size() - 1):
			var upper: Dictionary = pieces[i]
			var lower: Dictionary = pieces[i + 1]
			var upper_size: Vector2 = upper["size"]
			var bottom_of_upper: Vector2 = _piece_point(upper, Vector2(upper_size.x / 2.0, upper_size.y))
			var top_of_lower: Vector2 = _piece_point(lower, Vector2(upper_size.x / 2.0, 0.0))
			if lower["kind"] == "bottom" and pieces.size() == 2:
				continue  # a very short ladder (no segments) may overlap slightly
			_near(bottom_of_upper, top_of_lower, "piece %d meets piece %d for %s" % [i, i + 1, str(foot_offset)])
	assert_not_null(geometry)


func test_the_ladder_is_the_same_width_all_the_way_and_always_as_wide_as_asked() -> void:
	var geometry: Dictionary = _catalog()["ladder"]
	for foot_offset: Vector2 in [Vector2(0, 5 * CELL), Vector2(4 * CELL, 4 * CELL), Vector2(-2 * CELL, 7 * CELL)]:
		var pieces: Array[Dictionary] = _ladder(Vector2(200, 50), Vector2(200, 50) + foot_offset)
		for piece: Dictionary in pieces:
			var across: Vector2 = (piece["transform"] as Transform2D).x
			assert_almost_eq(across.length(), ClimbSpritePlacement.LADDER_WIDTH_CELLS * CELL / float(geometry["width"]), 0.0001, "%s width" % piece["kind"])
		var width_px: float = float(geometry["width"]) * (pieces[0]["transform"] as Transform2D).x.length()
		assert_almost_eq(width_px / CELL, ClimbSpritePlacement.LADDER_WIDTH_CELLS, 0.001)


func test_segments_are_stretched_only_a_little() -> void:
	var geometry: Dictionary = _catalog()["ladder"]
	var scale: float = ClimbSpritePlacement.LADDER_WIDTH_CELLS * CELL / float(geometry["width"])
	for length_cells: float in [2.1, 2.9, 3.4, 4.6, 5.5, 6.8, 8.3]:
		var pieces: Array[Dictionary] = _ladder(Vector2(0, 0), Vector2(0, length_cells * CELL))
		for piece: Dictionary in pieces:
			if piece["kind"] == "segment":
				var stretch: float = (piece["transform"] as Transform2D).y.length() / scale
				assert_between(stretch, 0.7, 1.3, "segments for a %f-cell ladder" % length_cells)


func test_the_ladder_points_the_right_way_up_at_any_angle() -> void:
	var geometry: Dictionary = _catalog()["ladder"]
	for angle_degrees: int in range(0, 360, 20):
		var direction: Vector2 = Vector2.from_angle(deg_to_rad(float(angle_degrees)))
		var top: Vector2 = Vector2(500, 500)
		var foot: Vector2 = top + direction * 4.5 * CELL
		var pieces: Array[Dictionary] = _ladder(top, foot)
		for piece: Dictionary in pieces:
			assert_gt((piece["transform"] as Transform2D).determinant(), 0.0, "ladders are never mirrored (%d degrees)" % angle_degrees)
		# the top piece is nearer the top square than the bottom piece is
		var top_centre: Vector2 = _piece_point(pieces[0], (geometry["top_size"] as Vector2) / 2.0)
		var bottom_centre: Vector2 = _piece_point(pieces[pieces.size() - 1], (geometry["bottom_size"] as Vector2) / 2.0)
		assert_lt(top_centre.distance_to(top), bottom_centre.distance_to(top))


func test_a_ladder_between_adjacent_squares_does_not_blow_up() -> void:
	var pieces: Array[Dictionary] = _ladder(Vector2(0, 0), Vector2(CELL, 0))
	assert_gte(pieces.size(), 2)
	for piece: Dictionary in pieces:
		var t: Transform2D = piece["transform"]
		assert_true(is_finite(t.origin.x) and is_finite(t.x.x) and is_finite(t.y.y))


func test_the_ladder_pieces_reach_exactly_between_the_squares_along_its_axis() -> void:
	var geometry: Dictionary = _catalog()["ladder"]
	var top: Vector2 = Vector2(100, 100)
	var foot: Vector2 = Vector2(400, 500)
	var pieces: Array[Dictionary] = _ladder(top, foot)
	var axis: Vector2 = (foot - top).normalized()
	var top_edge: float = (_piece_point(pieces[0], Vector2(geometry["top_size"].x / 2.0, 0.0)) - top).dot(axis)
	assert_lt(top_edge, 0.0, "the top rung is below the top edge of the sprite")
	assert_almost_eq(top_edge, -(geometry["top_anchor"] as Vector2).y * ClimbSpritePlacement.LADDER_WIDTH_CELLS * CELL / float(geometry["width"]), 0.01)
