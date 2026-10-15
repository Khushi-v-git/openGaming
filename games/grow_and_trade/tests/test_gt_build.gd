extends GutTest
## Main-phase building: paths, villages and towns, costs, piece limits, bonuses and winning by building.

const PLAYERS: Array = ["a", "b", "c", "d"]


## A game in the playing phase, `a` to move, already rolled, with a full hand for `a`.
func _playing() -> Dictionary:
	var state: Dictionary = GtSetup.new_game(PLAYERS, GtBoard.load_file()["board"], {}, 5)["state"]
	state["phase"] = "playing"
	state["founding"] = {}
	state["turn"]["rolled"] = true
	for resource: String in GtBank.RESOURCES:
		state["hands"]["a"][resource] = 5
	return state


func _board(state: Dictionary) -> GtBoard:
	return GtBoard.new(state["board"])


func _apply(state: Dictionary, player_id: String, action: Dictionary) -> Dictionary:
	return GtBuild.apply(state, _board(state), player_id, action)


func _path(edge: String) -> Dictionary:
	return {"type": "build_path", "edge": edge}


func _village(corner: String) -> Dictionary:
	return {"type": "build_village", "corner": corner}


func _town(corner: String) -> Dictionary:
	return {"type": "build_town", "corner": corner}


func _other_end(board: GtBoard, edge: String, corner: String) -> String:
	for end: String in board.corners_of_edge(edge):
		if end != corner:
			return end
	return ""


## A walk of `count` edges away from `start`, never revisiting a corner: {edges, corners} (corners[0] = start).
func _chain(board: GtBoard, start: String, count: int) -> Dictionary:
	var edges: Array = []
	var corners: Array = [start]
	var at: String = start
	while edges.size() < count:
		for edge: String in board.edges_of_corner(at):
			var other: String = _other_end(board, edge, at)
			if not corners.has(other):
				edges.append(edge)
				corners.append(other)
				at = other
				break
	return {"edges": edges, "corners": corners}


## `count` corners no two of which are next to each other.
func _spread(board: GtBoard, count: int) -> Array:
	var chosen: Array = []
	for corner: String in board.corners():
		var clear: bool = true
		for other: String in chosen:
			if other == corner or board.adjacent_corners(corner).has(other):
				clear = false
		if clear:
			chosen.append(corner)
			if chosen.size() == count:
				break
	return chosen


func _own_village(state: Dictionary, player_id: String, corner: String) -> void:
	state["buildings"][corner] = {"owner": player_id, "kind": "village"}


func _hand(state: Dictionary, player_id: String, hand: Dictionary) -> void:
	state["hands"][player_id] = GtBank.clean_hand(hand)


func _total(state: Dictionary) -> int:
	var total: int = GtBank.hand_count(state["supply"])
	for id: String in PLAYERS:
		total += GtBank.hand_count(state["hands"][id])
	return total


func _assert_refused(state: Dictionary, player_id: String, action: Dictionary, code: String, label: String = "") -> void:
	var before: Dictionary = state.duplicate(true)
	var r: Dictionary = _apply(state, player_id, action)
	assert_false(CoreResult.is_ok(r), "%s should be refused" % label)
	assert_eq(CoreResult.error_code(r), code, label)
	assert_eq(state, before, "%s leaves the state alone" % label)


## A state where `a` has a village on c0 and the chain c0-c1-c2-c3 is free to build on.
func _scene() -> Dictionary:
	var state: Dictionary = _playing()
	var board: GtBoard = _board(state)
	var start: String = _spread(board, 1)[0]
	_own_village(state, "a", start)
	return {"state": state, "board": board, "chain": _chain(board, start, 5)}


# --- paths ---------------------------------------------------------------------------------------

func test_a_path_from_a_village_costs_a_timber_and_a_clay_and_goes_to_the_bank() -> void:
	var s: Dictionary = _scene()
	var state: Dictionary = s["state"]
	var edge: String = s["chain"]["edges"][0]
	var r: Dictionary = _apply(state, "a", _path(edge))
	assert_true(CoreResult.is_ok(r))
	assert_eq(r["state"]["paths"][edge], "a")
	assert_eq(r["state"]["hands"]["a"]["timber"], 4)
	assert_eq(r["state"]["hands"]["a"]["clay"], 4)
	assert_eq(r["state"]["supply"]["timber"], state["supply"]["timber"] + 1)
	assert_eq(_total(r["state"]), _total(state), "resources move, never vanish")
	assert_eq(r["events"], [{"type": "built", "player_id": "a", "kind": "path", "at": edge}])


func test_the_input_state_is_never_changed_by_a_success() -> void:
	var s: Dictionary = _scene()
	var before: Dictionary = s["state"].duplicate(true)
	_apply(s["state"], "a", _path(s["chain"]["edges"][0]))
	assert_eq(s["state"], before)


func test_a_path_can_continue_a_path() -> void:
	var s: Dictionary = _scene()
	var state: Dictionary = s["state"]
	for edge: String in s["chain"]["edges"].slice(0, 3):
		var r: Dictionary = _apply(state, "a", _path(edge))
		assert_true(CoreResult.is_ok(r), edge)
		state = r["state"]
	assert_eq(GtState.path_count(state, "a"), 3)


func test_a_path_must_touch_a_building_or_a_path_of_the_player() -> void:
	var s: Dictionary = _scene()
	_assert_refused(s["state"], "a", _path(s["chain"]["edges"][1]), GtErrors.BAD_PLACEMENT, "gap in the chain")
	_assert_refused(s["state"], "b", _path(s["chain"]["edges"][0]), GtErrors.NOT_YOUR_TURN, "other player")
	var state: Dictionary = s["state"]
	state["current_player"] = "b"
	_hand(state, "b", {"timber": 1, "clay": 1})
	_assert_refused(state, "b", _path(s["chain"]["edges"][0]), GtErrors.BAD_PLACEMENT, "a rival's village does not help")


func test_a_path_cannot_be_taken_or_off_the_board_or_malformed() -> void:
	var s: Dictionary = _scene()
	var state: Dictionary = s["state"]
	var edge: String = s["chain"]["edges"][0]
	state["paths"][edge] = "b"
	_assert_refused(state, "a", _path(edge), GtErrors.BAD_PLACEMENT, "taken edge")
	for bad: String in ["", "x", "1,2|3", GtBoard.edge_id(Vector2i(60, 60), 0), s["chain"]["corners"][0]]:
		_assert_refused(s["state"], "a", _path(bad), GtErrors.BAD_PLACEMENT, "edge '%s'" % bad)


func test_a_path_cannot_continue_through_a_rival_building() -> void:
	var s: Dictionary = _scene()
	var state: Dictionary = s["state"]
	var chain: Dictionary = s["chain"]
	state["paths"][chain["edges"][0]] = "a"
	_own_village(state, "b", chain["corners"][1])  # forced: b's village sits at the end of a's path
	_assert_refused(state, "a", _path(chain["edges"][1]), GtErrors.BAD_PLACEMENT, "through the rival village")


func test_a_path_may_end_at_a_rival_building_and_pass_through_an_own_one() -> void:
	var s: Dictionary = _scene()
	var state: Dictionary = s["state"]
	var chain: Dictionary = s["chain"]
	_own_village(state, "b", chain["corners"][1])
	assert_true(CoreResult.is_ok(_apply(state, "a", _path(chain["edges"][0]))), "ending at a rival building is fine")
	var own: Dictionary = _scene()
	own["state"]["paths"][own["chain"]["edges"][0]] = "a"
	own["state"]["buildings"][own["chain"]["corners"][1]] = {"owner": "a", "kind": "village"}
	assert_true(CoreResult.is_ok(_apply(own["state"], "a", _path(own["chain"]["edges"][1]))))


func test_a_path_needs_the_resources() -> void:
	var s: Dictionary = _scene()
	_hand(s["state"], "a", {"timber": 1})
	_assert_refused(s["state"], "a", _path(s["chain"]["edges"][0]), GtErrors.CANNOT_AFFORD, "no clay")


func test_a_player_out_of_path_pieces_cannot_build_one() -> void:
	var s: Dictionary = _scene()
	s["state"]["config"]["pieces"]["path"] = 1
	var state: Dictionary = _apply(s["state"], "a", _path(s["chain"]["edges"][0]))["state"]
	_assert_refused(state, "a", _path(s["chain"]["edges"][1]), GtErrors.NO_PIECES, "second path")


func test_free_paths_cost_nothing_and_run_out() -> void:
	var s: Dictionary = _scene()
	var state: Dictionary = s["state"]
	_hand(state, "a", {})
	state["turn"]["free_paths"] = 2
	var edges: Array = s["chain"]["edges"]
	state = _apply(state, "a", _path(edges[0]))["state"]
	assert_eq(state["turn"]["free_paths"], 1)
	state = _apply(state, "a", _path(edges[1]))["state"]
	assert_eq(state["turn"]["free_paths"], 0)
	assert_eq(GtBank.hand_count(state["hands"]["a"]), 0)
	assert_eq(state["supply"]["timber"], GtBank.supply_for(state["config"], 4)["supply"]["timber"], "free paths pay the bank nothing")
	_assert_refused(state, "a", _path(edges[2]), GtErrors.CANNOT_AFFORD, "third path is not free")


func test_a_fifth_connected_path_takes_longest_path() -> void:
	var s: Dictionary = _scene()
	var state: Dictionary = s["state"]
	var edges: Array = s["chain"]["edges"]
	var last: Dictionary = {}
	for i: int in 5:
		last = _apply(state, "a", _path(edges[i]))
		assert_true(CoreResult.is_ok(last))
		state = last["state"]
		assert_eq(state["bonuses"]["longest_path"], "a" if i == 4 else "", "after path %d" % (i + 1))
	assert_eq(last["events"].size(), 2)
	assert_eq(last["events"][1], {"type": "bonus_changed", "bonus": "longest_path", "from": "", "to": "a"})
	assert_eq(GtScore.points(state, "a", false), 3, "village 1 plus the bonus 2")


func test_a_village_that_cuts_a_chain_takes_the_bonus_away() -> void:
	var s: Dictionary = _scene()
	var state: Dictionary = s["state"]
	var chain: Dictionary = s["chain"]
	for edge: String in chain["edges"]:
		state["paths"][edge] = "a"
	state["bonuses"]["longest_path"] = "a"
	state["current_player"] = "b"
	var cut: String = chain["corners"][3]
	# b's village at corner 3 needs a path of its own to touch: give it a side path, spaced from every building
	var side: String = ""
	for edge: String in _board(state).edges_of_corner(cut):
		if not chain["edges"].has(edge):
			side = edge
	state["paths"][side] = "b"
	_hand(state, "b", {"timber": 1, "clay": 1, "fleece": 1, "wheat": 1})
	var r: Dictionary = _apply(state, "b", _village(cut))
	assert_true(CoreResult.is_ok(r), str(r))
	assert_eq(r["state"]["bonuses"]["longest_path"], "")
	assert_eq(r["events"][1]["type"], "bonus_changed")


# --- villages ------------------------------------------------------------------------------------

func test_a_village_two_steps_from_another_building_on_an_own_path() -> void:
	var s: Dictionary = _scene()
	var state: Dictionary = s["state"]
	var chain: Dictionary = s["chain"]
	state["paths"][chain["edges"][0]] = "a"
	state["paths"][chain["edges"][1]] = "a"
	var site: String = chain["corners"][2]
	var r: Dictionary = _apply(state, "a", _village(site))
	assert_true(CoreResult.is_ok(r), str(r))
	assert_eq(r["state"]["buildings"][site], {"owner": "a", "kind": "village"})
	for resource: String in ["timber", "clay", "fleece", "wheat"]:
		assert_eq(r["state"]["hands"]["a"][resource], 4, resource)
	assert_eq(r["state"]["hands"]["a"]["stone"], 5)
	assert_eq(_total(r["state"]), _total(state))
	assert_eq(r["events"][0], {"type": "built", "player_id": "a", "kind": "village", "at": site})
	assert_eq(GtScore.points(r["state"], "a", false), 2)


func test_a_village_needs_an_own_path_free_corner_and_one_gap() -> void:
	var s: Dictionary = _scene()
	var state: Dictionary = s["state"]
	var chain: Dictionary = s["chain"]
	state["paths"][chain["edges"][0]] = "a"
	state["paths"][chain["edges"][1]] = "a"
	_assert_refused(state, "a", _village(chain["corners"][3]), GtErrors.BAD_PLACEMENT, "no path touches corner 3")
	_assert_refused(state, "a", _village(chain["corners"][1]), GtErrors.BAD_PLACEMENT, "next to own village")
	_assert_refused(state, "a", _village(chain["corners"][0]), GtErrors.BAD_PLACEMENT, "own village's corner")
	var site: String = chain["corners"][2]
	var neighbor: String = ""
	for other: String in _board(state).adjacent_corners(site):
		if other != chain["corners"][1]:
			neighbor = other
	_own_village(state, "b", neighbor)
	_assert_refused(state, "a", _village(site), GtErrors.BAD_PLACEMENT, "next to a rival village")
	for bad: String in ["", "oops", GtBoard.corner_id(Vector2i(60, 60), 1)]:
		_assert_refused(state, "a", _village(bad), GtErrors.BAD_PLACEMENT, "corner '%s'" % bad)


func test_a_village_needs_resources_and_a_piece() -> void:
	var s: Dictionary = _scene()
	var state: Dictionary = s["state"]
	var chain: Dictionary = s["chain"]
	state["paths"][chain["edges"][0]] = "a"
	state["paths"][chain["edges"][1]] = "a"
	var site: String = chain["corners"][2]
	_hand(state, "a", {"timber": 1, "clay": 1, "fleece": 1})
	_assert_refused(state, "a", _village(site), GtErrors.CANNOT_AFFORD, "no wheat")
	_hand(state, "a", {"timber": 1, "clay": 1, "fleece": 1, "wheat": 1})
	state["config"]["pieces"]["village"] = 1  # the one already on the board
	_assert_refused(state, "a", _village(site), GtErrors.NO_PIECES, "no village pieces")


# --- towns ---------------------------------------------------------------------------------------

func test_a_town_replaces_an_own_village_and_returns_its_piece() -> void:
	var s: Dictionary = _scene()
	var state: Dictionary = s["state"]
	var start: String = s["chain"]["corners"][0]
	var r: Dictionary = _apply(state, "a", _town(start))
	assert_true(CoreResult.is_ok(r))
	assert_eq(r["state"]["buildings"][start], {"owner": "a", "kind": "town"})
	assert_eq(r["state"]["hands"]["a"]["stone"], 2)
	assert_eq(r["state"]["hands"]["a"]["wheat"], 3)
	assert_eq(_total(r["state"]), _total(state))
	assert_eq(GtState.pieces_left(r["state"], "a", "village"), 5)
	assert_eq(GtState.pieces_left(r["state"], "a", "town"), 3)
	assert_eq(GtScore.points(r["state"], "a", false), 2)
	assert_eq(r["events"][0], {"type": "built", "player_id": "a", "kind": "town", "at": start})


func test_a_town_needs_an_own_village_the_resources_and_a_piece() -> void:
	var s: Dictionary = _scene()
	var state: Dictionary = s["state"]
	var start: String = s["chain"]["corners"][0]
	_assert_refused(state, "a", _town(s["chain"]["corners"][2]), GtErrors.BAD_PLACEMENT, "empty corner")
	_own_village(state, "b", s["chain"]["corners"][3])
	_assert_refused(state, "a", _town(s["chain"]["corners"][3]), GtErrors.BAD_PLACEMENT, "rival village")
	_assert_refused(state, "a", _town("nope"), GtErrors.BAD_PLACEMENT, "malformed corner")
	_hand(state, "a", {"stone": 2, "wheat": 2})
	_assert_refused(state, "a", _town(start), GtErrors.CANNOT_AFFORD, "not enough stone")
	_hand(state, "a", {"stone": 3, "wheat": 2})
	state["config"]["pieces"]["town"] = 0
	_assert_refused(state, "a", _town(start), GtErrors.NO_PIECES, "no town pieces")
	state["config"]["pieces"]["town"] = 4
	state["buildings"][start]["kind"] = "town"
	_assert_refused(state, "a", _town(start), GtErrors.BAD_PLACEMENT, "already a town")


# --- who may build when --------------------------------------------------------------------------

func test_building_needs_the_roll_the_turn_and_no_pending_step() -> void:
	var s: Dictionary = _scene()
	var state: Dictionary = s["state"]
	var edge: String = s["chain"]["edges"][0]
	state["turn"]["rolled"] = false
	_assert_refused(state, "a", _path(edge), GtErrors.NOT_ROLLED, "before the roll")
	state["turn"]["rolled"] = true
	state["turn"]["pending"] = "discard"
	_assert_refused(state, "a", _path(edge), GtErrors.MUST_DISCARD, "while players discard")
	state["turn"]["pending"] = "move_blocker"
	_assert_refused(state, "a", _path(edge), GtErrors.WRONG_PHASE, "before the blocker moves")
	state["turn"]["pending"] = ""
	state["phase"] = "founding"
	_assert_refused(state, "a", _path(edge), GtErrors.WRONG_PHASE, "during founding")
	state["phase"] = "finished"
	_assert_refused(state, "a", _path(edge), GtErrors.GAME_OVER, "after the game")


func test_bad_shapes_and_foreign_actions_are_refused() -> void:
	var s: Dictionary = _scene()
	var state: Dictionary = s["state"]
	var edge: String = s["chain"]["edges"][0]
	_assert_refused(state, "a", {"type": "build_path"}, ErrorCodes.BAD_ACTION, "no edge")
	_assert_refused(state, "a", {"type": "build_path", "corner": edge}, ErrorCodes.BAD_ACTION, "corner for a path")
	_assert_refused(state, "a", {"type": "build_village", "edge": edge}, ErrorCodes.BAD_ACTION, "edge for a village")
	_assert_refused(state, "a", {"type": "build_path", "edge": 3}, ErrorCodes.BAD_ACTION, "number")
	_assert_refused(state, "a", {"type": "build_path", "edge": edge, "free": true}, ErrorCodes.BAD_ACTION, "extra field")
	_assert_refused(state, "a", {"type": "place_village", "corner": edge}, ErrorCodes.UNKNOWN_ACTION, "founding action")
	_assert_refused(state, "a", {"type": "end_turn"}, ErrorCodes.UNKNOWN_ACTION, "another module's action")


# --- winning -------------------------------------------------------------------------------------

func _win_scene() -> Dictionary:
	var s: Dictionary = _scene()
	var state: Dictionary = s["state"]
	state["settings"]["target_points"] = 8
	var board: GtBoard = s["board"]
	var spots: Array = _spread(board, 5)
	state["buildings"] = {}
	_own_village(state, "a", spots[0])
	for i: int in range(1, 4):
		state["buildings"][spots[i]] = {"owner": "a", "kind": "town"}  # 1 + 6 = 7 points
	var edge: String = board.edges_of_corner(spots[4])[0]
	state["paths"][edge] = "a"
	s["spots"] = spots
	return s


func test_building_the_last_point_wins_the_game() -> void:
	var s: Dictionary = _win_scene()
	var state: Dictionary = s["state"]
	assert_eq(GtScore.points(state, "a", true), 7)
	var r: Dictionary = _apply(state, "a", _village(s["spots"][4]))
	assert_true(CoreResult.is_ok(r), str(r))
	assert_eq(r["state"]["phase"], "finished")
	assert_eq(r["state"]["winner"], "a")
	assert_eq(r["events"].back(), {"type": "won", "player_id": "a"})
	assert_eq(_apply(r["state"], "a", _path("x"))["error"]["code"], GtErrors.GAME_OVER)


func test_a_player_who_is_not_on_turn_does_not_win_from_someone_elses_move() -> void:
	var s: Dictionary = _win_scene()
	var state: Dictionary = s["state"]
	for i: int in 4:
		state["buildings"]["rival%d" % i] = {"owner": "b", "kind": "town"}  # b has 8 points
	var r: Dictionary = _apply(state, "a", _town(s["spots"][0]))
	assert_true(CoreResult.is_ok(r))
	assert_eq(r["state"]["phase"], "finished", "a reaches 8 with the town")
	assert_eq(r["state"]["winner"], "a")
	var quiet: Dictionary = _win_scene()
	quiet["state"]["settings"]["target_points"] = 14
	for i: int in 4:
		quiet["state"]["buildings"]["rival%d" % i] = {"owner": "b", "kind": "town"}
	var path: Dictionary = _apply(quiet["state"], "a", _path(_board(quiet["state"]).edges_of_corner(quiet["spots"][0])[0]))
	assert_true(CoreResult.is_ok(path))
	assert_eq(path["state"]["phase"], "playing")
	assert_eq(path["state"]["winner"], "")


func test_results_are_json_safe() -> void:
	var s: Dictionary = _scene()
	var r: Dictionary = _apply(s["state"], "a", _path(s["chain"]["edges"][0]))
	assert_not_null(JSON.parse_string(JSON.stringify(r["state"])))
	assert_not_null(JSON.parse_string(JSON.stringify(r["events"])))
