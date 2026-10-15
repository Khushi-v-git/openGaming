extends GutTest
## The two founding rounds: placement rules, the second-village payout, and the hand-over to play.

const PLAYERS: Array = ["a", "b", "c", "d"]


func _state(ids: Array = PLAYERS, seed_value: int = 3) -> Dictionary:
	return GtSetup.new_game(ids, GtBoard.load_file()["board"], {}, seed_value)["state"]


func _board(state: Dictionary) -> GtBoard:
	return GtBoard.new(state["board"])


func _apply(state: Dictionary, player_id: String, action: Dictionary) -> Dictionary:
	return GtFounding.apply(state, _board(state), player_id, action)


func _village(corner: String) -> Dictionary:
	return {"type": "place_village", "corner": corner}


func _path(edge: String) -> Dictionary:
	return {"type": "place_path", "edge": edge}


## The first corner (in board order) with this many land hexes around it.
func _corner_with(board: GtBoard, hex_count: int) -> String:
	for corner: String in board.corners():
		if board.hexes_of_corner(corner).size() == hex_count:
			return corner
	return ""


func _first_legal_corner(state: Dictionary, board: GtBoard) -> String:
	for corner: String in board.corners():
		if GtBuild.corner_problem(state, board, corner) == "":
			return corner
	return ""


func _free_edge_at(state: Dictionary, board: GtBoard, corner: String) -> String:
	for edge: String in board.edges_of_corner(corner):
		if not state["paths"].has(edge):
			return edge
	return ""


func _set_tile(state: Dictionary, hex: Vector2i, type: String, token: int) -> void:
	for tile: Dictionary in state["layout"]["tiles"]:
		if tile["q"] == hex.x and tile["r"] == hex.y:
			tile["type"] = type
			tile["token"] = token


## Puts the state at the start of the second round (the last seat places first again).
func _second_round(state: Dictionary) -> void:
	var n: int = state["players"].size()
	state["founding"]["index"] = n
	state["current_player"] = state["founding"]["order"][n]


func _total(state: Dictionary) -> int:
	var total: int = GtBank.hand_count(state["supply"])
	for id: String in GtState.seat_order(state):
		total += GtBank.hand_count(state["hands"][id])
	return total


func _assert_refused(state: Dictionary, player_id: String, action: Dictionary, code: String, label: String = "") -> void:
	var before: Dictionary = state.duplicate(true)
	var r: Dictionary = _apply(state, player_id, action)
	assert_false(CoreResult.is_ok(r), "%s should be refused" % label)
	assert_eq(CoreResult.error_code(r), code, label)
	assert_eq(state, before, "%s leaves the state alone" % label)


# --- placing -------------------------------------------------------------------------------------

func test_a_first_village_is_placed_and_a_path_is_expected() -> void:
	var state: Dictionary = _state()
	var corner: String = _first_legal_corner(state, _board(state))
	var r: Dictionary = _apply(state, "a", _village(corner))
	assert_true(CoreResult.is_ok(r))
	var next: Dictionary = r["state"]
	assert_eq(next["buildings"][corner], {"owner": "a", "kind": "village"})
	assert_eq(next["founding"]["expect"], "path")
	assert_eq(next["founding"]["last_village"], corner)
	assert_eq(next["current_player"], "a")
	assert_eq(r["events"], [{"type": "founding_placed", "player_id": "a", "kind": "village", "at": corner}])
	assert_eq(GtBank.hand_count(next["hands"]["a"]), 0, "the first village pays nothing")


func test_the_input_state_is_never_changed() -> void:
	var state: Dictionary = _state()
	var before: Dictionary = state.duplicate(true)
	var board: GtBoard = _board(state)
	var corner: String = _first_legal_corner(state, board)
	var r: Dictionary = _apply(state, "a", _village(corner))
	assert_eq(state, before)
	var edge: String = _free_edge_at(r["state"], board, corner)
	var after_village: Dictionary = r["state"].duplicate(true)
	_apply(r["state"], "a", _path(edge))
	assert_eq(r["state"], after_village)


func test_a_path_must_follow_the_village_and_touch_it() -> void:
	var state: Dictionary = _state()
	var board: GtBoard = _board(state)
	var corner: String = _first_legal_corner(state, board)
	_assert_refused(state, "a", _path(board.edges_of_corner(corner)[0]), GtErrors.WRONG_PHASE, "path before village")
	state = _apply(state, "a", _village(corner))["state"]
	_assert_refused(state, "a", _village(_corner_with(board, 3)), GtErrors.WRONG_PHASE, "second village before the path")
	var far_edge: String = ""
	for edge: String in board.edges():
		if not board.corners_of_edge(edge).has(corner):
			far_edge = edge
			break
	_assert_refused(state, "a", _path(far_edge), GtErrors.BAD_PLACEMENT, "path elsewhere")
	var good: Dictionary = _apply(state, "a", _path(board.edges_of_corner(corner)[0]))
	assert_true(CoreResult.is_ok(good))
	assert_eq(good["state"]["paths"][board.edges_of_corner(corner)[0]], "a")


func test_only_the_player_whose_turn_it_is_may_place() -> void:
	var state: Dictionary = _state()
	var corner: String = _first_legal_corner(state, _board(state))
	_assert_refused(state, "b", _village(corner), GtErrors.NOT_YOUR_TURN, "b out of turn")


func test_a_corner_must_be_on_the_board_empty_and_one_gap_from_any_building() -> void:
	var state: Dictionary = _state()
	var board: GtBoard = _board(state)
	var corner: String = _first_legal_corner(state, board)
	for bad: String in ["", "garbage", "1,2", GtBoard.corner_id(Vector2i(50, 50), 0), board.edges()[0]]:
		_assert_refused(state, "a", _village(bad), GtErrors.BAD_PLACEMENT, "corner '%s'" % bad)
	var parts: PackedStringArray = corner.split("|")
	parts.reverse()
	_assert_refused(state, "a", _village("|".join(parts)), GtErrors.BAD_PLACEMENT, "an id that is not in canonical order")
	state = _apply(state, "a", _village(corner))["state"]
	state = _apply(state, "a", _path(_free_edge_at(state, board, corner)))["state"]
	_assert_refused(state, "b", _village(corner), GtErrors.BAD_PLACEMENT, "taken corner")
	for next_door: String in board.adjacent_corners(corner):
		_assert_refused(state, "b", _village(next_door), GtErrors.BAD_PLACEMENT, "one-gap rule")


func test_a_path_cannot_go_on_a_taken_edge() -> void:
	var state: Dictionary = _state()
	var board: GtBoard = _board(state)
	var corner: String = _first_legal_corner(state, board)
	state = _apply(state, "a", _village(corner))["state"]
	var edge: String = board.edges_of_corner(corner)[0]
	state["paths"][edge] = "b"  # forced: nothing legal puts a path here yet
	_assert_refused(state, "a", _path(edge), GtErrors.BAD_PLACEMENT, "taken edge")
	_assert_refused(state, "a", _path("nonsense"), GtErrors.BAD_PLACEMENT, "malformed edge")


func test_a_player_without_pieces_cannot_place() -> void:
	var state: Dictionary = _state()
	var board: GtBoard = _board(state)
	var corner: String = _first_legal_corner(state, board)
	state["config"]["pieces"]["village"] = 0
	_assert_refused(state, "a", _village(corner), GtErrors.NO_PIECES, "no village pieces")
	state["config"]["pieces"]["village"] = 5
	state = _apply(state, "a", _village(corner))["state"]
	state["config"]["pieces"]["path"] = 0
	_assert_refused(state, "a", _path(board.edges_of_corner(corner)[0]), GtErrors.NO_PIECES, "no path pieces")


func test_bad_action_shapes_and_other_phases_are_refused() -> void:
	var state: Dictionary = _state()
	var corner: String = _first_legal_corner(state, _board(state))
	_assert_refused(state, "a", {"type": "place_village"}, ErrorCodes.BAD_ACTION, "missing corner")
	_assert_refused(state, "a", {"type": "place_village", "corner": 5}, ErrorCodes.BAD_ACTION, "number as corner")
	_assert_refused(state, "a", {"type": "place_village", "corner": corner, "extra": 1}, ErrorCodes.BAD_ACTION, "extra field")
	_assert_refused(state, "a", {"type": "place_village", "edge": corner}, ErrorCodes.BAD_ACTION, "wrong field name")
	_assert_refused(state, "a", {"type": "build_path", "edge": "x"}, ErrorCodes.UNKNOWN_ACTION, "not a founding action")
	_assert_refused(state, "a", {"type": "roll"}, ErrorCodes.UNKNOWN_ACTION, "roll")
	state["phase"] = "playing"
	_assert_refused(state, "a", _village(corner), GtErrors.WRONG_PHASE, "after founding")
	state["phase"] = "finished"
	_assert_refused(state, "a", _village(corner), GtErrors.GAME_OVER, "finished")


# --- the second village pays ---------------------------------------------------------------------

func test_the_first_round_pays_nothing_even_next_to_producing_tiles() -> void:
	var state: Dictionary = _state()
	var board: GtBoard = _board(state)
	var corner: String = _corner_with(board, 3)
	var r: Dictionary = _apply(state, "a", _village(corner))
	assert_eq(GtBank.hand_count(r["state"]["hands"]["a"]), 0)
	assert_eq(r["state"]["supply"], state["supply"])


func test_the_second_village_pays_one_resource_per_producing_tile() -> void:
	var state: Dictionary = _state()
	var board: GtBoard = _board(state)
	var corner: String = _corner_with(board, 3)
	var hexes: Array[Vector2i] = board.hexes_of_corner(corner)
	_set_tile(state, hexes[0], "timber", 6)
	_set_tile(state, hexes[1], "timber", 5)
	_set_tile(state, hexes[2], "desert", 0)
	_second_round(state)
	var player: String = state["current_player"]
	var r: Dictionary = _apply(state, player, _village(corner))
	assert_true(CoreResult.is_ok(r))
	assert_eq(r["state"]["hands"][player]["timber"], 2)
	assert_eq(GtBank.hand_count(r["state"]["hands"][player]), 2)
	assert_eq(r["state"]["supply"]["timber"], state["supply"]["timber"] - 2)
	assert_eq(_total(r["state"]), _total(state), "the bank pays, nothing is created")
	assert_eq(r["events"][1]["type"], "produced")
	assert_eq(r["events"][1]["gains"], {player: {"timber": 2}})
	assert_eq(r["events"][1]["tiles"].size(), 2)


func test_mixed_tiles_pay_each_resource() -> void:
	var state: Dictionary = _state()
	var board: GtBoard = _board(state)
	var corner: String = _corner_with(board, 3)
	var hexes: Array[Vector2i] = board.hexes_of_corner(corner)
	_set_tile(state, hexes[0], "clay", 4)
	_set_tile(state, hexes[1], "wheat", 9)
	_set_tile(state, hexes[2], "stone", 10)
	_second_round(state)
	var player: String = state["current_player"]
	var hand: Dictionary = _apply(state, player, _village(corner))["state"]["hands"][player]
	assert_eq([hand["clay"], hand["wheat"], hand["stone"], hand["timber"]], [1, 1, 1, 0])


func test_a_coastal_corner_pays_for_its_fewer_tiles() -> void:
	var state: Dictionary = _state()
	var board: GtBoard = _board(state)
	var corner: String = _corner_with(board, 1)
	for hex: Vector2i in board.hexes_of_corner(corner):
		_set_tile(state, hex, "fleece", 3)
	_second_round(state)
	var player: String = state["current_player"]
	var r: Dictionary = _apply(state, player, _village(corner))
	assert_eq(r["state"]["hands"][player]["fleece"], 1)


func test_a_desert_only_corner_pays_nothing() -> void:
	var state: Dictionary = _state()
	var board: GtBoard = _board(state)
	var corner: String = _corner_with(board, 1)
	for hex: Vector2i in board.hexes_of_corner(corner):
		_set_tile(state, hex, "desert", 0)
	_second_round(state)
	var player: String = state["current_player"]
	var r: Dictionary = _apply(state, player, _village(corner))
	assert_eq(GtBank.hand_count(r["state"]["hands"][player]), 0)
	assert_eq(r["events"][1], {"type": "nothing_produced"})


func test_a_short_bank_pays_what_is_left_and_reports_the_shortage() -> void:
	var state: Dictionary = _state()
	var board: GtBoard = _board(state)
	var corner: String = _corner_with(board, 3)
	var hexes: Array[Vector2i] = board.hexes_of_corner(corner)
	_set_tile(state, hexes[0], "timber", 6)
	_set_tile(state, hexes[1], "timber", 5)
	_set_tile(state, hexes[2], "desert", 0)
	state["supply"]["timber"] = 1
	_second_round(state)
	var player: String = state["current_player"]
	var r: Dictionary = _apply(state, player, _village(corner))
	assert_eq(r["state"]["hands"][player]["timber"], 1, "a lone claimant gets what is left")
	assert_eq(r["state"]["supply"]["timber"], 0)
	var shortage: Dictionary = r["events"][2]
	assert_eq(shortage["type"], "shortage")
	assert_eq([shortage["resource"], shortage["owed"], shortage["available"], shortage["paid"]], ["timber", 2, 1, 1])
	state["supply"]["timber"] = 0
	var empty: Dictionary = _apply(state, player, _village(corner))
	assert_eq(GtBank.hand_count(empty["state"]["hands"][player]), 0)
	assert_eq(empty["events"][1], {"type": "nothing_produced"})
	assert_eq(empty["events"][2]["paid"], 0)


# --- the whole founding --------------------------------------------------------------------------

## Plays every founding placement with the first legal corner and an adjacent free edge. Returns the
## names of the players in the order they placed their villages.
func _play_founding(state: Dictionary) -> Dictionary:
	var board: GtBoard = _board(state)
	var seen: Array = []
	var all_events: Array = []
	while state["phase"] == "founding":
		var player: String = state["current_player"]
		seen.append(player)
		var corner: String = _first_legal_corner(state, board)
		var village: Dictionary = _apply(state, player, _village(corner))
		assert_true(CoreResult.is_ok(village), "village for %s" % player)
		state = village["state"]
		all_events.append_array(village["events"])
		var path: Dictionary = _apply(state, player, _path(_free_edge_at(state, board, corner)))
		assert_true(CoreResult.is_ok(path), "path for %s" % player)
		state = path["state"]
		all_events.append_array(path["events"])
	return {"state": state, "order": seen, "events": all_events}


func test_four_players_found_in_snake_order_and_then_play_starts_with_seat_one() -> void:
	var start: Dictionary = _state()
	var done: Dictionary = _play_founding(start)
	var state: Dictionary = done["state"]
	assert_eq(done["order"], ["a", "b", "c", "d", "d", "c", "b", "a"])
	assert_eq(state["phase"], "playing")
	assert_eq(state["founding"], {})
	assert_eq(state["current_player"], "a")
	assert_eq(state["turn_number"], 1)
	assert_eq(state["turn"], GtSetup.new_turn())
	for id: String in PLAYERS:
		assert_eq(GtState.building_count(state, id, "village"), 2, "%s villages" % id)
		assert_eq(GtState.path_count(state, id), 2, "%s paths" % id)
	assert_eq(_total(state), _total(start), "payouts come from the bank")
	assert_eq(done["events"].back(), {"type": "turn_changed", "player_id": "a"})


func test_six_players_also_found_in_snake_order() -> void:
	var ids: Array = ["a", "b", "c", "d", "e", "f"]
	var done: Dictionary = _play_founding(_state(ids, 11))
	assert_eq(done["order"], ["a", "b", "c", "d", "e", "f", "f", "e", "d", "c", "b", "a"])
	assert_eq(done["state"]["phase"], "playing")
	assert_eq(done["state"]["current_player"], "a")


func test_the_turn_passes_with_a_turn_changed_event_between_placements() -> void:
	var done: Dictionary = _play_founding(_state())
	var changes: Array = []
	for event: Dictionary in done["events"]:
		if event["type"] == "turn_changed":
			changes.append(event["player_id"])
	assert_eq(changes, ["b", "c", "d", "c", "b", "a", "a"], "no event while d places twice in a row")


func test_second_round_villages_gave_every_player_their_starting_hand() -> void:
	var done: Dictionary = _play_founding(_state())
	var produced: int = 0
	for event: Dictionary in done["events"]:
		if event["type"] == "produced":
			produced += 1
	var held: int = 0
	for id: String in PLAYERS:
		held += GtBank.hand_count(done["state"]["hands"][id])
	assert_gt(held, 0)
	assert_gt(produced, 0)


func test_founding_results_are_json_safe() -> void:
	var done: Dictionary = _play_founding(_state())
	assert_not_null(JSON.parse_string(JSON.stringify(done["state"])))
	var events: Variant = JSON.parse_string(JSON.stringify(done["events"]))
	assert_not_null(events)
	assert_eq(events.size(), done["events"].size())
