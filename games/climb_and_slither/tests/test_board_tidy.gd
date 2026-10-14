extends GutTest
## The shipped board is meant to look clear on screen: no snake or ladder crosses another, and
## none sits right on top of another. Measured on the centres of the squares, as the board draws them.

const MIN_GAP_CELLS: float = 0.25  # closest two jumps may run, in cells (their lines, not their art)


func _segments() -> Array:
	var board: Dictionary = ClimbBoard.load_file()["board"]
	var layout: ClimbBoardLayout = ClimbBoardLayout.new(int(board["size"]), int(board["columns"]))
	var result: Array = []
	for kind: String in ["ladders", "snakes"]:
		for jump: Dictionary in board[kind]:
			result.append({"jump": jump, "kind": kind, "a": layout.center(int(jump["from"]), 1.0, Vector2.ZERO), "b": layout.center(int(jump["to"]), 1.0, Vector2.ZERO)})
	return result


static func _side(p: Vector2, q: Vector2, r: Vector2) -> float:
	return (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)


static func _crosses(s: Dictionary, t: Dictionary) -> bool:
	return _side(s["a"], s["b"], t["a"]) * _side(s["a"], s["b"], t["b"]) < 0.0 and _side(t["a"], t["b"], s["a"]) * _side(t["a"], t["b"], s["b"]) < 0.0


static func _gap(s: Dictionary, t: Dictionary) -> float:
	var best: float = INF
	for pair: Array in [[s["a"], t["a"], t["b"]], [s["b"], t["a"], t["b"]], [t["a"], s["a"], s["b"]], [t["b"], s["a"], s["b"]]]:
		var near: Vector2 = Geometry2D.get_closest_point_to_segment(pair[0], pair[1], pair[2])
		best = minf(best, (pair[0] as Vector2).distance_to(near))
	return best


func test_no_snake_or_ladder_crosses_another() -> void:
	var segments: Array = _segments()
	for i: int in segments.size():
		for j: int in range(i + 1, segments.size()):
			assert_false(_crosses(segments[i], segments[j]), "%s and %s cross" % [str(segments[i]["jump"]), str(segments[j]["jump"])])


func test_no_two_jumps_run_on_top_of_each_other() -> void:
	var segments: Array = _segments()
	for i: int in segments.size():
		for j: int in range(i + 1, segments.size()):
			assert_gte(_gap(segments[i], segments[j]), MIN_GAP_CELLS, "%s and %s are too close" % [str(segments[i]["jump"]), str(segments[j]["jump"])])


func test_every_jump_is_long_enough_to_see_and_short_enough_for_its_art() -> void:
	for s: Dictionary in _segments():
		var length: float = (s["a"] as Vector2).distance_to(s["b"])
		assert_between(length, 3.5, 9.0, "%s spans %.1f cells" % [str(s["jump"]), length])
