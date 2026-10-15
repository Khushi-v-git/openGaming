extends GutTest
## GtValidate: fresh and hand-built states pass; each single corruption is refused.

const IDS: Array = ["a", "b", "c"]


func _new(ids: Array = IDS, seed_value: int = 987654321) -> Dictionary:
	return GtSetup.new_game(ids, GtBoard.load_file()["board"], {}, seed_value)["state"]


## Six villages (a, b, c, a, b, c), each with one path, a few resources and cards, mid-game.
func _mid_game() -> Dictionary:
	var state: Dictionary = _new()
	var board: GtBoard = GtBoard.new(state["board"])
	var chosen: Array[String] = []
	for corner: String in board.corners():
		var clash: bool = false
		for other: String in chosen:
			if other == corner or board.adjacent_corners(corner).has(other):
				clash = true
		if not clash:
			chosen.append(corner)
		if chosen.size() == 6:
			break
	var owners: Array[String] = ["a", "b", "c", "a", "b", "c"]
	for i: int in 6:
		state["buildings"][chosen[i]] = {"owner": owners[i], "kind": "village"}
		state["paths"][board.edges_of_corner(chosen[i])[0]] = owners[i]
	state["phase"] = "playing"
	state["founding"] = {}
	_give(state, "a", {"timber": 2, "wheat": 1})
	_give(state, "b", {"clay": 3})
	_deal(state, "a", "held", "guard")
	_deal(state, "a", "held", "point")
	_deal(state, "b", "fresh", "sweep")
	_deal(state, "b", "held", "point")
	state["offer"] = {"from": "a", "give": {"timber": 1}, "want": {"clay": 1}, "to": [], "accepted": ["b"], "declined": []}
	return state


func _give(state: Dictionary, player: String, hand: Dictionary) -> void:
	for resource: String in hand:
		state["hands"][player][resource] += hand[resource]
		state["supply"][resource] -= hand[resource]


func _deal(state: Dictionary, player: String, list: String, card: String) -> void:
	(state["deck"] as Array).erase(card)
	state["cards"][player][list].append(card)


## After a's first founding village: a path is due.
func _founding_path_due() -> Dictionary:
	var state: Dictionary = _new()
	var corner: String = GtBoard.new(state["board"]).corners()[0]
	state["buildings"][corner] = {"owner": "a", "kind": "village"}
	state["founding"]["expect"] = "path"
	state["founding"]["last_village"] = corner
	return state


func _finished() -> Dictionary:
	var state: Dictionary = _mid_game()
	var mine: Array = []
	for corner: String in state["buildings"]:
		if state["buildings"][corner]["owner"] == "a":
			state["buildings"][corner]["kind"] = "town"
			mine.append(corner)
	for i: int in 3:
		_deal(state, "a", "held", "point")
	state["settings"]["target_points"] = 8
	state["phase"] = "finished"
	state["winner"] = "a"
	state["offer"] = {}
	return state


func _code(state: Dictionary) -> String:
	return CoreResult.error_code(GtValidate.validate_state(state))


func _assert_valid(state: Dictionary, label: String) -> void:
	var result: Dictionary = GtValidate.validate_state(state)
	assert_true(CoreResult.is_ok(result), "%s: %s" % [label, str(result.get("error", ""))])


# --- valid states -----------------------------------------------------------------------------------------

func test_fresh_games_of_every_size_validate() -> void:
	for ids: Array in [["a", "b", "c"], ["a", "b", "c", "d"], ["a", "b", "c", "d", "e"], ["a", "b", "c", "d", "e", "f"]]:
		_assert_valid(_new(ids), "%d players" % ids.size())


func test_hand_built_states_validate() -> void:
	_assert_valid(_founding_path_due(), "founding, path due")
	_assert_valid(_mid_game(), "mid-game with an open offer")
	_assert_valid(_finished(), "finished")


func test_a_second_founding_step_validates() -> void:
	var state: Dictionary = _founding_path_due()
	var board: GtBoard = GtBoard.new(state["board"])
	state["paths"][board.edges_of_corner(state["founding"]["last_village"])[0]] = "a"
	state["founding"]["index"] = 1
	state["founding"]["expect"] = "village"
	state["founding"]["last_village"] = ""
	state["current_player"] = "b"
	_assert_valid(state, "b to place")


func test_a_pending_discard_and_blocker_validate() -> void:
	var state: Dictionary = _mid_game()
	_give(state, "b", {"clay": 5, "stone": 4})
	state["offer"] = {}
	state["turn"]["rolled"] = true
	state["turn"]["dice"] = [3, 4]
	state["turn"]["pending"] = "discard"
	state["turn"]["source"] = "seven"
	state["turn"]["owed"] = {"b": 6}
	_assert_valid(state, "discard owed")
	state["turn"]["owed"] = {}
	state["turn"]["pending"] = "move_blocker"
	_assert_valid(state, "blocker to move")
	state["turn"]["pending"] = ""
	state["turn"]["source"] = ""
	state["turn"]["free_paths"] = 2
	_assert_valid(state, "free paths")


func test_longest_path_and_largest_guard_holders_validate_when_consistent() -> void:
	var state: Dictionary = _mid_game()
	state["guards_played"]["c"] = 3
	for i: int in 3:
		(state["deck"] as Array).erase("guard")  # played guards are out of the deck
	state["bonuses"]["largest_guard"] = "c"
	_assert_valid(state, "guard holder")
	state["bonuses"]["largest_guard"] = ""
	assert_eq(_code(state), GtErrors.INVALID_STATE, "a holder is missing")


func test_a_json_round_trip_needs_the_ints_restored() -> void:
	var state: Dictionary = _mid_game()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(state))
	assert_eq(_code(parsed), GtErrors.INVALID_STATE, "floats are refused, never silently accepted")
	_assert_valid(Envelope.normalize(parsed), "after Envelope.normalize, as core does on load")


func test_validation_does_not_change_the_state() -> void:
	var state: Dictionary = _mid_game()
	var before: Dictionary = state.duplicate(true)
	GtValidate.validate_state(state)
	assert_eq(state, before)


# --- corruptions --------------------------------------------------------------------------------------------

func _first_with(state: Dictionary, key: String) -> String:
	return (state[key] as Dictionary).keys()[0]


func _first_corner_of(state: Dictionary, owner: String) -> String:
	for corner: String in state["buildings"]:
		if state["buildings"][corner]["owner"] == owner:
			return corner
	return ""


func _mid_corruptions() -> Dictionary:
	var table: Dictionary = {}
	table["extra key"] = func(s: Dictionary) -> void: s["extra"] = 1
	table["missing rng"] = func(s: Dictionary) -> void: s.erase("rng")
	table["version"] = func(s: Dictionary) -> void: s["state_version"] = 2
	table["version as bool"] = func(s: Dictionary) -> void: s["state_version"] = true
	table["game id"] = func(s: Dictionary) -> void: s["game_id"] = "climb_and_slither"
	table["phase"] = func(s: Dictionary) -> void: s["phase"] = "bogus"
	table["settings range"] = func(s: Dictionary) -> void: s["settings"]["target_points"] = 99
	table["settings extra key"] = func(s: Dictionary) -> void: s["settings"]["x"] = 1
	table["config broken"] = func(s: Dictionary) -> void: s["config"]["costs"].erase("path")
	table["board broken"] = func(s: Dictionary) -> void: s["board"]["hexes"].pop_back()
	table["tiles short"] = func(s: Dictionary) -> void: s["layout"]["tiles"].pop_back()
	table["tile type unknown"] = func(s: Dictionary) -> void: s["layout"]["tiles"][0]["type"] = "bogus"
	table["tile type counts"] = func(s: Dictionary) -> void:
		var tile: Dictionary = s["layout"]["tiles"][0]
		tile["type"] = "timber" if tile["type"] != "timber" else "clay"
	table["token seven"] = func(s: Dictionary) -> void:
		for tile: Dictionary in s["layout"]["tiles"]:
			if tile["token"] > 0:
				tile["token"] = 7
				return
	table["token out of range"] = func(s: Dictionary) -> void:
		for tile: Dictionary in s["layout"]["tiles"]:
			if tile["token"] > 0:
				tile["token"] = 13
				return
	table["harbor kind"] = func(s: Dictionary) -> void: s["layout"]["harbors"][0]["kind"] = "bogus"
	table["harbor ratio"] = func(s: Dictionary) -> void: s["layout"]["harbors"][0]["ratio"] = 9
	table["blocker in the sea"] = func(s: Dictionary) -> void: s["blocker"]["q"] = 99
	table["duplicate player"] = func(s: Dictionary) -> void: s["players"][1]["player_id"] = "a"
	table["player color"] = func(s: Dictionary) -> void: s["players"][0]["color"] = "blue"
	table["hands missing a player"] = func(s: Dictionary) -> void: s["hands"].erase("c")
	table["negative hand"] = func(s: Dictionary) -> void: s["hands"]["a"]["timber"] = -1
	table["hand missing resource"] = func(s: Dictionary) -> void: s["hands"]["a"].erase("clay")
	table["decimal hand"] = func(s: Dictionary) -> void: s["hands"]["a"]["timber"] = 2.0
	table["resources not conserved"] = func(s: Dictionary) -> void: s["supply"]["timber"] += 1
	table["unknown held card"] = func(s: Dictionary) -> void: s["cards"]["a"]["held"].append("bogus")
	table["unknown deck card"] = func(s: Dictionary) -> void: s["deck"][0] = "bogus"
	table["too many guards played"] = func(s: Dictionary) -> void: s["guards_played"]["a"] = 20
	table["too many point cards"] = func(s: Dictionary) -> void:
		for i: int in 6:
			s["cards"]["c"]["held"].append("point")
	table["building off the board"] = func(s: Dictionary) -> void: s["buildings"]["90,90|90,91|91,90"] = {"owner": "a", "kind": "village"}
	table["building owner"] = func(s: Dictionary) -> void:
		s["buildings"][s["buildings"].keys()[0]]["owner"] = "zed"
	table["building kind"] = func(s: Dictionary) -> void:
		s["buildings"][s["buildings"].keys()[0]]["kind"] = "castle"
	table["two buildings side by side"] = func(s: Dictionary) -> void:
		var board: GtBoard = GtBoard.new(s["board"])
		var first: String = s["buildings"].keys()[0]
		s["buildings"][board.adjacent_corners(first)[0]] = {"owner": "c", "kind": "village"}
	table["village limit"] = func(s: Dictionary) -> void: s["config"]["pieces"]["village"] = 1
	table["path off the board"] = func(s: Dictionary) -> void: s["paths"]["bogus"] = "a"
	table["path owner"] = func(s: Dictionary) -> void: s["paths"][s["paths"].keys()[0]] = "zed"
	table["path limit"] = func(s: Dictionary) -> void:
		var board: GtBoard = GtBoard.new(s["board"])
		for corner: String in s["buildings"]:
			if s["buildings"][corner]["owner"] == "a":
				s["paths"][board.edges_of_corner(corner)[1]] = "a"
				break
		s["config"]["pieces"]["path"] = 1
	table["bonus holder unknown"] = func(s: Dictionary) -> void: s["bonuses"]["longest_path"] = "zed"
	table["bonus not earned"] = func(s: Dictionary) -> void: s["bonuses"]["largest_guard"] = "b"
	table["founding record left over"] = func(s: Dictionary) -> void: s["founding"] = {"order": [], "index": 0, "expect": "village", "last_village": ""}
	table["turn key missing"] = func(s: Dictionary) -> void: s["turn"].erase("dice")
	table["dice without a roll"] = func(s: Dictionary) -> void: s["turn"]["rolled"] = true
	table["bad die"] = func(s: Dictionary) -> void:
		s["turn"]["rolled"] = true
		s["turn"]["dice"] = [3, 7]
	table["discard pending, nobody owes"] = func(s: Dictionary) -> void:
		s["turn"]["pending"] = "discard"
		s["turn"]["source"] = "seven"
	table["owed without pending"] = func(s: Dictionary) -> void: s["turn"]["owed"] = {"a": 1}
	table["owes more than held"] = func(s: Dictionary) -> void:
		s["turn"]["pending"] = "discard"
		s["turn"]["source"] = "seven"
		s["turn"]["owed"] = {"b": 99}
	table["blocker move without a reason"] = func(s: Dictionary) -> void: s["turn"]["pending"] = "move_blocker"
	table["free paths"] = func(s: Dictionary) -> void: s["turn"]["free_paths"] = 5
	table["offer from the wrong player"] = func(s: Dictionary) -> void: s["offer"]["from"] = "b"
	table["answer to an offer not addressed to them"] = func(s: Dictionary) -> void:
		s["offer"]["to"] = ["b"]
		s["offer"]["accepted"] = ["c"]
	table["accepted and declined"] = func(s: Dictionary) -> void: s["offer"]["declined"] = ["b"]
	table["offer card map"] = func(s: Dictionary) -> void: s["offer"]["give"] = {"timber": 0}
	table["offer wants nothing"] = func(s: Dictionary) -> void: s["offer"]["want"] = {}
	table["offer to oneself"] = func(s: Dictionary) -> void: s["offer"]["to"] = ["a"]
	table["current player unknown"] = func(s: Dictionary) -> void: s["current_player"] = "zed"
	table["turn number"] = func(s: Dictionary) -> void: s["turn_number"] = 0
	table["turn number decimal"] = func(s: Dictionary) -> void: s["turn_number"] = 1.0
	table["winner before the end"] = func(s: Dictionary) -> void: s["winner"] = "a"
	table["rng seed type"] = func(s: Dictionary) -> void: s["rng"]["seed"] = 5
	table["rng state words"] = func(s: Dictionary) -> void: s["rng"]["state"] = "1,2"
	table["rng all zero"] = func(s: Dictionary) -> void: s["rng"]["state"] = "0,0,0,0"
	return table


func test_each_mid_game_corruption_is_refused() -> void:
	_assert_valid(_mid_game(), "the base state")
	var table: Dictionary = _mid_corruptions()
	assert_gte(table.size(), 40)
	for label: String in table:
		var state: Dictionary = _mid_game()
		(table[label] as Callable).call(state)
		assert_eq(_code(state), GtErrors.INVALID_STATE, label)


func test_each_founding_corruption_is_refused() -> void:
	var table: Dictionary = {}
	table["order"] = func(s: Dictionary) -> void:
		s["founding"]["order"][0] = "b"
		s["founding"]["order"][1] = "a"
	table["index out of range"] = func(s: Dictionary) -> void: s["founding"]["index"] = 99
	table["unknown step"] = func(s: Dictionary) -> void: s["founding"]["expect"] = "bogus"
	table["wrong placer"] = func(s: Dictionary) -> void: s["current_player"] = "b"
	table["path due without a village"] = func(s: Dictionary) -> void: s["founding"]["last_village"] = ""
	table["village is somebody else's"] = func(s: Dictionary) -> void: s["buildings"][s["founding"]["last_village"]]["owner"] = "b"
	table["more paths than steps"] = func(s: Dictionary) -> void: s["paths"][GtBoard.new(s["board"]).edges()[0]] = "a"
	table["founding record cleared"] = func(s: Dictionary) -> void: s["founding"] = {}
	table["turn already begun"] = func(s: Dictionary) -> void: s["turn"]["rolled"] = true
	table["offer during founding"] = func(s: Dictionary) -> void: s["offer"] = {"from": "a", "give": {"timber": 1}, "want": {"clay": 1}, "to": [], "accepted": [], "declined": []}
	for label: String in table:
		var state: Dictionary = _founding_path_due()
		(table[label] as Callable).call(state)
		assert_eq(_code(state), GtErrors.INVALID_STATE, label)


func test_each_finished_corruption_is_refused() -> void:
	var table: Dictionary = {}
	table["no winner"] = func(s: Dictionary) -> void: s["winner"] = ""
	table["unknown winner"] = func(s: Dictionary) -> void: s["winner"] = "zed"
	table["winner is not the turn owner"] = func(s: Dictionary) -> void: s["current_player"] = "b"
	table["winner short of the target"] = func(s: Dictionary) -> void: s["settings"]["target_points"] = 14
	table["offer left open"] = func(s: Dictionary) -> void: s["offer"] = {"from": "a", "give": {"timber": 1}, "want": {"clay": 1}, "to": [], "accepted": [], "declined": []}
	for label: String in table:
		var state: Dictionary = _finished()
		(table[label] as Callable).call(state)
		assert_eq(_code(state), GtErrors.INVALID_STATE, label)
