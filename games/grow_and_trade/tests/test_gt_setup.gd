extends GutTest
## Settings and new_game: the starting state every other Grow & Trade module is tested against.

const PLAYERS: Array = ["a", "b", "c", "d", "e"]


func _board() -> Dictionary:
	return GtBoard.load_file()["board"]


func _new(ids: Array = PLAYERS, settings: Dictionary = {}, seed_value: int = 7) -> Dictionary:
	return GtSetup.new_game(ids, _board(), settings, seed_value)


func test_new_game_builds_a_founding_state() -> void:
	var r: Dictionary = _new()
	assert_true(CoreResult.is_ok(r))
	var state: Dictionary = r["state"]
	assert_eq(state["phase"], "founding")
	assert_eq(state["current_player"], "a")
	assert_eq(state["founding"]["order"], ["a", "b", "c", "d", "e", "e", "d", "c", "b", "a"])
	assert_eq(state["players"][4]["color"], "orange")
	assert_eq(state["supply"]["timber"], 30, "5 players get the larger bank")
	assert_eq(state["deck"].size(), 25)
	assert_eq(GtBank.hand_count(state["hands"]["a"]), 0)
	assert_eq(state["layout"]["tiles"].size(), 30)
	assert_false(state["blocker"].is_empty())


func test_three_players_get_the_smaller_bank() -> void:
	assert_eq(_new(["a", "b", "c"])["state"]["supply"]["clay"], 24)


func test_the_same_seed_gives_the_same_game_and_another_seed_a_different_one() -> void:
	assert_eq(_new(PLAYERS, {}, 5)["state"], _new(PLAYERS, {}, 5)["state"])
	assert_ne(_new(PLAYERS, {}, 5)["state"]["layout"], _new(PLAYERS, {}, 6)["state"]["layout"])


func test_the_state_survives_json() -> void:
	var state: Dictionary = _new()["state"]
	var round_trip: Variant = JSON.parse_string(JSON.stringify(state))
	assert_eq(round_trip["founding"]["order"], state["founding"]["order"])
	assert_eq(round_trip["rng"], state["rng"])
	assert_eq(round_trip["deck"], state["deck"])


func test_bad_player_lists_are_refused() -> void:
	for ids: Array in [["a", "b"], ["a", "b", "c", "d", "e", "f", "g"], ["a", "a", "b"], ["a", "", "b"]]:
		assert_eq(CoreResult.error_code(_new(ids)), GtErrors.BAD_PLAYERS, str(ids))


func test_settings_defaults_and_validation() -> void:
	assert_eq(GtSetup.normalize({})["settings"], GtSetup.defaults())
	for bad: Dictionary in [{"target_points": 7}, {"target_points": 15}, {"hand_limit": 4}, {"bank_rate": 2}, {"bank_rate": "4"}, {"nope": true}]:
		assert_eq(CoreResult.error_code(GtSetup.normalize(bad)), GtErrors.INVALID_SETTINGS, str(bad))
	assert_true(CoreResult.is_ok(GtSetup.normalize({"target_points": 12, "bank_rate": 3, "friendly_blocker": true})))


func test_describe_lists_the_chosen_rules() -> void:
	assert_eq(GtSetup.describe({})[0], "First to 10 points")
	assert_true(GtSetup.describe({"bank_rate": 3}).has("Bank trades 3 for 1"))


func test_points_count_buildings_bonuses_and_point_cards() -> void:
	var state: Dictionary = _new()["state"]
	state["buildings"]["c1"] = {"owner": "a", "kind": "village"}
	state["buildings"]["c2"] = {"owner": "a", "kind": "town"}
	state["bonuses"]["longest_path"] = "a"
	state["cards"]["a"]["held"] = ["point", "guard"]
	state["cards"]["a"]["fresh"] = ["point"]
	assert_eq(GtScore.points(state, "a", false), 5)
	assert_eq(GtScore.points(state, "a", true), 7)
	assert_eq(GtScore.points(state, "b", true), 0)


func test_bonuses_follow_paths_and_guards() -> void:
	var state: Dictionary = _new()["state"]
	var board: GtBoard = GtBoard.new(state["board"])
	# a straight chain of five edges starting at some corner
	var corner: String = board.corners()[0]
	var chain: Array = []
	var seen: Dictionary = {corner: true}
	var at: String = corner
	while chain.size() < 5:
		var next_edge: String = ""
		for edge: String in board.edges_of_corner(at):
			var other: String = board.corners_of_edge(edge)[0] if board.corners_of_edge(edge)[0] != at else board.corners_of_edge(edge)[1]
			if not seen.has(other):
				next_edge = edge
				seen[other] = true
				at = other
				break
		chain.append(next_edge)
	for edge: String in chain:
		state["paths"][edge] = "b"
	state["guards_played"]["c"] = 3
	var events: Array = []
	GtScore.refresh_bonuses(state, events)
	assert_eq(state["bonuses"]["longest_path"], "b")
	assert_eq(state["bonuses"]["largest_guard"], "c")
	assert_eq(events.size(), 2)


func test_finish_if_won_needs_the_target_and_the_playing_phase() -> void:
	var state: Dictionary = _new()["state"]
	state["buildings"]["c1"] = {"owner": "a", "kind": "town"}
	state["cards"]["a"]["held"] = ["point", "point", "point", "point", "point", "point", "point", "point"]
	var events: Array = []
	GtScore.finish_if_won(state, "a", events)
	assert_eq(state["phase"], "founding", "nothing is decided during founding")
	state["phase"] = "playing"
	GtScore.finish_if_won(state, "a", events)
	assert_eq(state["phase"], "finished")
	assert_eq(state["winner"], "a")
	assert_eq(events[0]["type"], "won")
