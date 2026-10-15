extends GutTest
## Longest Path length (graph logic) and the Longest Path / Largest Guard holder rules.


func _line(count: int) -> Array:
	var edges: Array = []
	for i: int in count:
		edges.append([i, i + 1])
	return edges


# --- length ------------------------------------------------------------------------------

func test_no_paths_is_zero() -> void:
	assert_eq(GtLongestPath.longest_path_length([]), 0)


func test_a_straight_line_counts_every_path() -> void:
	assert_eq(GtLongestPath.longest_path_length(_line(1)), 1)
	assert_eq(GtLongestPath.longest_path_length(_line(7)), 7)


func test_path_direction_and_order_do_not_matter() -> void:
	assert_eq(GtLongestPath.longest_path_length([[3, 2], [1, 0], [2, 1]]), 3)


func test_a_branch_counts_only_the_longer_arm() -> void:
	# a stem 0-1-2-3 with arms 3-4-5 and 3-6: best is 0..3 then 4,5
	var edges: Array = [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [3, 6]]
	assert_eq(GtLongestPath.longest_path_length(edges), 5)


func test_a_plain_fork_is_the_two_longest_arms() -> void:
	# centre 0 with arms of 3, 2 and 1 paths: the best trail joins the two longest arms
	var edges: Array = [[0, 1], [1, 2], [2, 3], [0, 4], [4, 5], [0, 6]]
	assert_eq(GtLongestPath.longest_path_length(edges), 5)


func test_a_loop_is_walked_all_the_way_round() -> void:
	var ring: Array = [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 0]]
	assert_eq(GtLongestPath.longest_path_length(ring), 6)


func test_a_loop_with_a_tail_uses_the_tail_and_the_loop() -> void:
	# triangle 1-2-3 with a tail 0-1: 0-1-2-3-1 walks all four paths
	assert_eq(GtLongestPath.longest_path_length([[0, 1], [1, 2], [2, 3], [3, 1]]), 4)
	# a second tail at 3 makes four odd corners, so no trail uses all five: best is 4
	assert_eq(GtLongestPath.longest_path_length([[0, 1], [1, 2], [2, 3], [3, 1], [3, 4]]), 4)


func test_a_figure_eight_is_one_trail_through_the_crossing() -> void:
	# two triangles sharing corner 0: a trail can go round both
	var edges: Array = [[0, 1], [1, 2], [2, 0], [0, 3], [3, 4], [4, 0]]
	assert_eq(GtLongestPath.longest_path_length(edges), 6)


func test_repeated_and_degenerate_paths_are_ignored() -> void:
	assert_eq(GtLongestPath.longest_path_length([[0, 1], [1, 0], [0, 1], [2, 2]]), 1)


func test_string_corner_ids_work() -> void:
	assert_eq(GtLongestPath.longest_path_length([["a", "b"], ["b", "c"], ["c", "d"]]), 3)


func test_the_input_is_not_changed() -> void:
	var edges: Array = [[0, 1], [1, 2], [2, 0]]
	var before: Array = edges.duplicate(true)
	GtLongestPath.longest_path_length(edges, [1])
	assert_eq(edges, before)


# --- blocked corners ---------------------------------------------------------------------

func test_a_blocked_corner_in_the_middle_cuts_the_chain() -> void:
	assert_eq(GtLongestPath.longest_path_length(_line(6), [3]), 3, "0-1-2-3 or 3-4-5-6")


func test_a_chain_may_end_on_a_blocked_corner() -> void:
	assert_eq(GtLongestPath.longest_path_length(_line(3), [3]), 3)
	assert_eq(GtLongestPath.longest_path_length(_line(3), [0]), 3, "or start on one")


func test_a_blocked_corner_cuts_a_loop_into_a_line() -> void:
	var ring: Array = [[0, 1], [1, 2], [2, 3], [3, 0]]
	assert_eq(GtLongestPath.longest_path_length(ring, [0]), 4, "start at 0, go round, end at 0")
	assert_eq(GtLongestPath.longest_path_length(ring, [2]), 4, "start at 2, round, end at 2")


func test_a_blocked_corner_on_a_figure_eight_crossing_stops_passing_through() -> void:
	var edges: Array = [[0, 1], [1, 2], [2, 0], [0, 3], [3, 4], [4, 0]]
	# from 0 round one triangle ends on 0 (3); cannot go on into the other one
	assert_eq(GtLongestPath.longest_path_length(edges, [0]), 3)


func test_blocked_corners_nobody_touches_change_nothing() -> void:
	assert_eq(GtLongestPath.longest_path_length(_line(4), [99, "x"]), 4)


# --- holder rules ------------------------------------------------------------------------

func test_nobody_under_the_minimum_gets_it() -> void:
	assert_eq(GtLongestPath.holder_after("", {"a": 4, "b": 3}), "")


func test_the_first_to_reach_the_minimum_takes_it() -> void:
	assert_eq(GtLongestPath.holder_after("", {"a": 5, "b": 3}), "a")


func test_a_tie_at_the_top_with_no_holder_gives_it_to_nobody() -> void:
	assert_eq(GtLongestPath.holder_after("", {"a": 6, "b": 6, "c": 2}), "")


func test_a_tie_keeps_the_current_holder() -> void:
	assert_eq(GtLongestPath.holder_after("a", {"a": 6, "b": 6}), "a")


func test_a_rival_must_strictly_exceed_the_holder() -> void:
	assert_eq(GtLongestPath.holder_after("a", {"a": 6, "b": 7}), "b")
	assert_eq(GtLongestPath.holder_after("a", {"a": 7, "b": 6}), "a")


func test_a_holder_cut_under_the_minimum_loses_it() -> void:
	assert_eq(GtLongestPath.holder_after("a", {"a": 4, "b": 3}), "")
	assert_eq(GtLongestPath.holder_after("a", {"a": 4, "b": 5}), "b")


func test_a_holder_cut_so_two_rivals_tie_above_them_leaves_it_with_nobody() -> void:
	assert_eq(GtLongestPath.holder_after("a", {"a": 5, "b": 7, "c": 7}), "")


func test_a_holder_cut_so_a_rival_ties_them_keeps_it() -> void:
	assert_eq(GtLongestPath.holder_after("a", {"a": 7, "b": 7, "c": 7}), "a")


func test_a_custom_minimum_is_honoured() -> void:
	assert_eq(GtLongestPath.holder_after("", {"a": 3}, 3), "a")
	assert_eq(GtLongestPath.holder_after("", {"a": 3}, 4), "")


func test_no_players_means_no_holder() -> void:
	assert_eq(GtLongestPath.holder_after("", {}), "")
	assert_eq(GtLongestPath.holder_after("a", {}), "")


# --- Largest Guard -----------------------------------------------------------------------

func test_largest_guard_needs_three_played() -> void:
	assert_eq(GtLongestPath.largest_guard_holder_after("", {"a": 2, "b": 1}), "")
	assert_eq(GtLongestPath.largest_guard_holder_after("", {"a": 3, "b": 1}), "a")


func test_largest_guard_changes_hands_only_on_a_strictly_larger_count() -> void:
	assert_eq(GtLongestPath.largest_guard_holder_after("a", {"a": 3, "b": 3}), "a")
	assert_eq(GtLongestPath.largest_guard_holder_after("a", {"a": 3, "b": 4}), "b")


# --- from the board ----------------------------------------------------------------------

func test_holder_from_board_blocks_with_other_players_buildings_only() -> void:
	var paths: Dictionary = {"a": _line(6), "b": [[10, 11]]}
	assert_eq(GtLongestPath.holder_from_board("", paths, {0: "a", 6: "a"}), "a", "own buildings do not cut")
	assert_eq(GtLongestPath.holder_from_board("", paths, {3: "b"}), "", "a rival's building at 3 cuts 6 into 3 and 3")
	assert_eq(GtLongestPath.holder_from_board("a", paths, {3: "b"}), "", "and a holder that is cut loses it")


# --- cross-check against brute force -----------------------------------------------------

## Every ordered selection of distinct paths, checked as a walk. Independent of the recursive search.
func _brute_force(edges: Array, blocked: Array) -> int:
	var best: Array[int] = [0]
	_extend_sequence(edges, blocked, [], best)
	return best[0]


func _extend_sequence(edges: Array, blocked: Array, chosen: Array, best: Array[int]) -> void:
	if _is_walk(edges, blocked, chosen):
		best[0] = maxi(best[0], chosen.size())
	for i: int in edges.size():
		if not chosen.has(i):
			var next: Array = chosen.duplicate()
			next.append(i)
			_extend_sequence(edges, blocked, next, best)


func _is_walk(edges: Array, blocked: Array, sequence: Array) -> bool:
	if sequence.size() <= 1:
		return true
	for flip: bool in [false, true]:
		var first: Array = edges[sequence[0]]
		var at: int = first[0] if flip else first[1]
		var ok: bool = true
		for k: int in range(1, sequence.size()):
			if blocked.has(at):
				ok = false
				break
			var edge: Array = edges[sequence[k]]
			if edge[0] == at:
				at = edge[1]
			elif edge[1] == at:
				at = edge[0]
			else:
				ok = false
				break
		if ok:
			return true
	return false


func test_matches_brute_force_on_small_random_graphs() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260515
	for round: int in 120:
		var corner_count: int = rng.randi_range(3, 6)
		var edges: Array = []
		var pool: Array = []
		for a: int in corner_count:
			for b: int in range(a + 1, corner_count):
				pool.append([a, b])
		for i: int in rng.randi_range(1, mini(6, pool.size())):
			edges.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
		var blocked: Array = []
		for c: int in corner_count:
			if rng.randf() < 0.25:
				blocked.append(c)
		assert_eq(GtLongestPath.longest_path_length(edges, blocked), _brute_force(edges, blocked), "round %d edges %s blocked %s" % [round, str(edges), str(blocked)])
