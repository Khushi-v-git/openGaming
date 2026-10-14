extends GutTest


func _classic() -> ClimbBoardLayout:
	return ClimbBoardLayout.new(100, 10)


# --- squares ---------------------------------------------------------------------------------

func test_the_corners_of_the_classic_board() -> void:
	var layout: ClimbBoardLayout = _classic()
	assert_eq(layout.cell_of(1), Vector2i(0, 9), "square 1: bottom-left")
	assert_eq(layout.cell_of(10), Vector2i(9, 9), "square 10: bottom-right")
	assert_eq(layout.cell_of(11), Vector2i(9, 8), "square 11 is directly above 10")
	assert_eq(layout.cell_of(20), Vector2i(0, 8), "the second row runs right to left")
	assert_eq(layout.cell_of(21), Vector2i(0, 7), "square 21 is directly above 20")
	assert_eq(layout.cell_of(91), Vector2i(9, 0), "row 10 runs right to left again")
	assert_eq(layout.cell_of(100), Vector2i(0, 0), "square 100: top-left")


func test_the_zigzag_for_other_board_shapes() -> void:
	var layout: ClimbBoardLayout = ClimbBoardLayout.new(30, 6)  # 5 rows of 6
	assert_eq(layout.cell_of(1), Vector2i(0, 4))
	assert_eq(layout.cell_of(6), Vector2i(5, 4))
	assert_eq(layout.cell_of(7), Vector2i(5, 3))
	assert_eq(layout.cell_of(12), Vector2i(0, 3))
	assert_eq(layout.cell_of(30), Vector2i(5, 0), "an odd number of rows ends on the right")
	var big: ClimbBoardLayout = ClimbBoardLayout.new(64, 8)
	assert_eq(big.cell_of(64), Vector2i(0, 0), "8 rows: even, so it ends top-left")


func test_every_square_has_its_own_cell_and_square_at_is_the_inverse() -> void:
	for dims: Array in [[100, 10], [30, 6], [64, 8], [20, 5], [140, 10], [400, 20], [12, 6]]:
		var layout: ClimbBoardLayout = ClimbBoardLayout.new(dims[0], dims[1])
		var seen: Dictionary = {}
		for square: int in range(1, layout.size + 1):
			var at: Vector2i = layout.cell_of(square)
			assert_false(seen.has(at), "%s: square %d shares a cell" % [str(dims), square])
			seen[at] = true
			assert_true(at.x >= 0 and at.x < layout.columns and at.y >= 0 and at.y < layout.rows)
			assert_eq(layout.square_at(at.x, at.y), square, "%s: round trip of %d" % [str(dims), square])
		assert_eq(seen.size(), layout.size)


func test_consecutive_squares_are_always_neighbours() -> void:
	for dims: Array in [[100, 10], [30, 6], [64, 8], [400, 20]]:
		var layout: ClimbBoardLayout = ClimbBoardLayout.new(dims[0], dims[1])
		for square: int in range(1, layout.size):
			var a: Vector2i = layout.cell_of(square)
			var b: Vector2i = layout.cell_of(square + 1)
			assert_eq(absi(a.x - b.x) + absi(a.y - b.y), 1, "%s: %d to %d is one step" % [str(dims), square, square + 1])


func test_square_at_off_the_board_is_minus_one() -> void:
	var layout: ClimbBoardLayout = _classic()
	for cell: Vector2i in [Vector2i(-1, 0), Vector2i(10, 0), Vector2i(0, -1), Vector2i(0, 11), Vector2i(3, 10)]:
		assert_eq(layout.square_at(cell.x, cell.y), -1, str(cell))


func test_square_zero_is_the_start_strip_under_square_one() -> void:
	var layout: ClimbBoardLayout = _classic()
	assert_eq(layout.cell_of(0), Vector2i(0, 10))
	assert_eq(layout.square_at(0, 10), 0)
	assert_eq(layout.cell_of(-5), Vector2i(0, 10), "anything below the board is the start strip")
	var below_one: Vector2 = layout.center(0, 60.0, Vector2.ZERO)
	var one: Vector2 = layout.center(1, 60.0, Vector2.ZERO)
	assert_eq(below_one.x, one.x)
	assert_eq(below_one.y - one.y, 60.0)


# --- positions and fit ------------------------------------------------------------------------------

func test_centres_are_in_the_middle_of_their_cells() -> void:
	var layout: ClimbBoardLayout = _classic()
	assert_eq(layout.center(1, 60.0, Vector2(100, 50)), Vector2(130, 50 + 9.5 * 60.0))
	assert_eq(layout.center(100, 60.0, Vector2(100, 50)), Vector2(130, 80))
	assert_eq(layout.center(10, 60.0, Vector2.ZERO), Vector2(9.5 * 60.0, 9.5 * 60.0))


func test_fit_chooses_the_biggest_whole_pixel_cell_that_fits() -> void:
	var layout: ClimbBoardLayout = _classic()
	var fitted: Dictionary = layout.fit(Vector2(800, 700), 10.0)
	# height is the limit: (700 - 20) / 11 rows (10 + the start strip) = 61.8
	assert_eq(fitted["cell"], 61.0)
	var full: Rect2 = fitted["full_rect"]
	assert_true(Rect2(Vector2.ZERO, Vector2(800, 700)).grow(-10.0).encloses(full), "inside the margins")
	assert_eq(full.size, Vector2(610, 671))
	assert_eq(fitted["board_rect"].size, Vector2(610, 610))


func test_fit_is_centred() -> void:
	var fitted: Dictionary = _classic().fit(Vector2(900, 720), 16.0)
	var full: Rect2 = fitted["full_rect"]
	assert_lte(absf((full.position.x + full.size.x / 2.0) - 450.0), 1.0)
	assert_lte(absf((full.position.y + full.size.y / 2.0) - 360.0), 1.0)


func test_fit_at_the_two_target_window_sizes() -> void:
	# the board gets about 62% of the width, all of the height
	for window: Vector2 in [Vector2(1280, 720), Vector2(1920, 1080)]:
		var area: Vector2 = Vector2(floorf(window.x * 0.62), window.y)
		var fitted: Dictionary = _classic().fit(area, 24.0)
		var cell: float = fitted["cell"]
		assert_gte(cell, 55.0, "%s: cells stay big enough to read" % str(window))
		assert_true(Rect2(Vector2.ZERO, area).encloses(fitted["full_rect"]))
		assert_eq(cell, floorf(cell), "whole pixels")
	assert_gt(_classic().fit(Vector2(1190, 1080), 24.0)["cell"], _classic().fit(Vector2(793, 720), 24.0)["cell"], "1080p draws a bigger board")


func test_fit_never_returns_a_cell_smaller_than_one_and_survives_tiny_areas() -> void:
	var fitted: Dictionary = _classic().fit(Vector2(5, 5), 10.0)
	assert_eq(fitted["cell"], 1.0)


func test_fit_is_stable_for_the_same_area() -> void:
	var layout: ClimbBoardLayout = _classic()
	assert_eq(layout.fit(Vector2(793, 720), 24.0), layout.fit(Vector2(793, 720), 24.0))


func test_resizing_there_and_back_gives_the_same_layout() -> void:
	var layout: ClimbBoardLayout = _classic()
	var before: Dictionary = layout.fit(Vector2(793, 720), 24.0)
	layout.fit(Vector2(1190, 1080), 24.0)
	layout.fit(Vector2(500, 400), 24.0)
	assert_eq(layout.fit(Vector2(793, 720), 24.0), before)


func test_wider_boards_and_odd_shapes_fit_too() -> void:
	for dims: Array in [[30, 6], [140, 10], [400, 20], [20, 5]]:
		var layout: ClimbBoardLayout = ClimbBoardLayout.new(dims[0], dims[1])
		var area: Vector2 = Vector2(793, 720)
		var fitted: Dictionary = layout.fit(area, 24.0)
		assert_true(Rect2(Vector2.ZERO, area).encloses(fitted["full_rect"]), str(dims))


# --- pawns ---------------------------------------------------------------------------------------------

func test_one_pawn_sits_in_the_middle_of_its_square() -> void:
	var layout: ClimbBoardLayout = _classic()
	var spots: Dictionary = layout.pawn_positions({"a": 7}, ["a", "b"], 60.0, Vector2.ZERO)
	assert_eq(spots["a"], layout.center(7, 60.0, Vector2.ZERO))


func test_pawns_sharing_a_square_get_different_spots_in_seat_order() -> void:
	var layout: ClimbBoardLayout = _classic()
	var middle: Vector2 = layout.center(33, 60.0, Vector2.ZERO)
	for count: int in [2, 3, 4]:
		var ids: Array = ["a", "b", "c", "d"].slice(0, count)
		var positions: Dictionary = {}
		for id: String in ids:
			positions[id] = 33
		var spots: Dictionary = layout.pawn_positions(positions, ids, 60.0, Vector2.ZERO)
		var distinct: Dictionary = {}
		for id: String in ids:
			distinct[spots[id]] = true
			assert_lt(spots[id].distance_to(middle), 60.0 * 0.4, "stays inside its square")
		assert_eq(distinct.size(), count, "%d pawns on one square all have their own spot" % count)
	var two: Dictionary = layout.pawn_positions({"a": 33, "b": 33}, ["a", "b"], 60.0, Vector2.ZERO)
	assert_lt(two["a"].x, two["b"].x, "seat order: the first seat takes the left slot")


func test_pawn_spots_depend_only_on_the_positions_and_seat_order() -> void:
	var layout: ClimbBoardLayout = _classic()
	var a: Dictionary = layout.pawn_positions({"x": 5, "y": 5, "z": 9}, ["x", "y", "z"], 60.0, Vector2(10, 10))
	var b: Dictionary = layout.pawn_positions({"z": 9, "y": 5, "x": 5}, ["x", "y", "z"], 60.0, Vector2(10, 10))
	assert_eq(a, b)


func test_a_pawn_alone_after_others_left_goes_back_to_the_middle() -> void:
	var layout: ClimbBoardLayout = _classic()
	var shared: Dictionary = layout.pawn_positions({"a": 12, "b": 12}, ["a", "b"], 60.0, Vector2.ZERO)
	var alone: Dictionary = layout.pawn_positions({"a": 12, "b": 40}, ["a", "b"], 60.0, Vector2.ZERO)
	assert_ne(shared["a"], alone["a"])
	assert_eq(alone["a"], layout.center(12, 60.0, Vector2.ZERO))


func test_pawns_not_yet_on_the_board_wait_in_their_own_start_slot() -> void:
	var layout: ClimbBoardLayout = _classic()
	var spots: Dictionary = layout.pawn_positions({"a": 0, "b": 0, "c": 0, "d": 4}, ["a", "b", "c", "d"], 60.0, Vector2.ZERO)
	assert_eq(spots["a"], layout.start_slot(0, 60.0, Vector2.ZERO))
	assert_eq(spots["b"], layout.start_slot(1, 60.0, Vector2.ZERO))
	assert_eq(spots["c"], layout.start_slot(2, 60.0, Vector2.ZERO))
	assert_eq(spots["d"], layout.center(4, 60.0, Vector2.ZERO))
	assert_gt(spots["a"].y, layout.fit(Vector2(800, 800), 0.0)["board_rect"].end.y * 0.0 + layout.rows * 60.0, "below the board")


func test_pawn_offsets_for_every_group_size() -> void:
	for count: int in [1, 2, 3, 4]:
		assert_eq(ClimbBoardLayout.pawn_offsets(count).size(), count)
	assert_eq(ClimbBoardLayout.pawn_offsets(0).size(), 1, "clamped")
	assert_eq(ClimbBoardLayout.pawn_offsets(9).size(), 4, "clamped")
