extends GutTest

const IDS: Array[String] = ["p1", "p2", "p3", "p4"]

var rules: ClimbAndSlitherRules


func before_each() -> void:
	rules = ClimbAndSlitherRules.new()


func _board() -> Dictionary:
	return ClimbBoard.load_file()["board"]


func _new(players: Array = ["p1", "p2"], settings: Dictionary = {}, seed_value: int = 1) -> Dictionary:
	var r: Dictionary = rules.new_game(players, _board(), settings, seed_value)
	assert_true(CoreResult.is_ok(r), str(r))
	return r["state"]


func _round_trip(state: Dictionary) -> Dictionary:
	return Envelope.normalize(JSON.parse_string(JSON.stringify(state)))


# --- a new game ------------------------------------------------------------------

func test_new_game_has_the_agreed_shape() -> void:
	var state: Dictionary = _new(["p1", "p2", "p3"], {}, 42)
	assert_eq(state["state_version"], 1)
	assert_eq(state["game_id"], "climb_and_slither")
	assert_eq(state["phase"], "in_progress")
	assert_eq(state["current_player"], "p1")
	assert_eq(state["extra_turn"], false)
	assert_eq(state["last_roll"], {})
	assert_eq(state["turn_number"], 1)
	assert_eq(state["rolls"], 0)
	assert_eq(state["winner"], "")
	assert_eq(state["positions"], {"p1": 0, "p2": 0, "p3": 0})
	assert_eq(state["settings"], ClimbSettings.defaults())
	assert_eq(state["board"], _board())


func test_players_keep_seat_order_and_get_colors_by_seat() -> void:
	var state: Dictionary = _new(IDS)
	assert_eq(state["players"], [
		{"player_id": "p1", "color": "red"},
		{"player_id": "p2", "color": "blue"},
		{"player_id": "p3", "color": "green"},
		{"player_id": "p4", "color": "yellow"},
	])
	var reversed: Dictionary = _new(["zed", "amy"])
	assert_eq(reversed["players"][0], {"player_id": "zed", "color": "red"}, "seat order, not alphabetical")
	assert_eq(reversed["current_player"], "zed")


func test_two_three_and_four_players_are_allowed() -> void:
	for count: int in [2, 3, 4]:
		var ids: Array = IDS.slice(0, count)
		assert_true(CoreResult.is_ok(rules.new_game(ids, _board(), {}, 1)), "%d players" % count)


func test_the_wrong_number_of_players_is_refused() -> void:
	assert_eq(CoreResult.error_code(rules.new_game([], _board(), {}, 1)), ClimbErrors.BAD_PLAYERS)
	assert_eq(CoreResult.error_code(rules.new_game(["p1"], _board(), {}, 1)), ClimbErrors.BAD_PLAYERS)
	assert_eq(CoreResult.error_code(rules.new_game(["a", "b", "c", "d", "e"], _board(), {}, 1)), ClimbErrors.BAD_PLAYERS)


func test_bad_player_ids_are_refused() -> void:
	assert_eq(CoreResult.error_code(rules.new_game(["p1", "p1"], _board(), {}, 1)), ClimbErrors.BAD_PLAYERS, "duplicate")
	assert_eq(CoreResult.error_code(rules.new_game(["p1", ""], _board(), {}, 1)), ClimbErrors.BAD_PLAYERS, "empty")
	assert_eq(CoreResult.error_code(rules.new_game(["p1", 2], _board(), {}, 1)), ClimbErrors.BAD_PLAYERS, "not text")
	assert_eq(CoreResult.error_code(rules.new_game(["p1", null], _board(), {}, 1)), ClimbErrors.BAD_PLAYERS)


func test_a_bad_board_or_bad_settings_are_refused() -> void:
	var broken: Dictionary = _board()
	broken["snakes"].append({"from": 1, "to": 1})
	assert_eq(CoreResult.error_code(rules.new_game(IDS, broken, {}, 1)), ClimbErrors.INVALID_BOARD)
	assert_eq(CoreResult.error_code(rules.new_game(IDS, _board(), {"dice_count": 5}, 1)), ClimbErrors.INVALID_SETTINGS)
	assert_eq(CoreResult.error_code(rules.new_game(IDS, _board(), {"nope": 1}, 1)), ClimbErrors.INVALID_SETTINGS)


func test_settings_given_to_new_game_live_in_the_state() -> void:
	var state: Dictionary = _new(["p1", "p2"], {"exact_finish": true, "dice_count": 1})
	assert_eq(state["settings"], {"exact_finish": true, "extra_turn_on_six": false, "dice_count": 1})
	var two_dice: Dictionary = _new(["p1", "p2"], {"extra_turn_on_six": true, "dice_count": 2})
	assert_eq(two_dice["settings"], {"exact_finish": false, "extra_turn_on_six": true, "dice_count": 2})


func test_new_game_refuses_exact_finish_with_two_dice() -> void:
	assert_eq(CoreResult.error_code(rules.new_game(["p1", "p2"], _board(), {"exact_finish": true, "dice_count": 2}, 1)), ClimbErrors.INVALID_SETTINGS)


func test_a_loaded_state_with_that_combination_is_refused_too() -> void:
	var state: Dictionary = _new(["p1", "p2"])
	state["settings"]["exact_finish"] = true
	state["settings"]["dice_count"] = 2
	assert_eq(CoreResult.error_code(rules.validate_state(state)), ClimbErrors.INVALID_STATE)


func test_the_board_in_the_state_is_a_copy() -> void:
	var board: Dictionary = _board()
	var state: Dictionary = rules.new_game(["p1", "p2"], board, {}, 1)["state"]
	state["board"]["snakes"].clear()
	assert_eq(board["snakes"].size(), 11, "the caller's board is untouched")


func test_new_game_returns_an_empty_event_list() -> void:
	assert_eq(rules.new_game(["p1", "p2"], _board(), {}, 1)["events"], [])


# --- the random generator state ---------------------------------------------------------

func test_the_seed_and_state_are_decimal_strings() -> void:
	var state: Dictionary = _new(["p1", "p2"], {}, 123456789)
	assert_eq(typeof(state["rng"]["seed"]), TYPE_STRING)
	assert_eq(typeof(state["rng"]["state"]), TYPE_STRING)
	assert_eq(state["rng"]["seed"], "123456789")
	assert_eq(state["rng"]["state"], Prng.new(123456789).state_text())


func test_huge_and_negative_seeds_keep_every_bit_through_json() -> void:
	for seed_value: int in [9007199254740993, -9007199254740993, 4611686018427387904, -1, 0]:
		var state: Dictionary = _new(["p1", "p2"], {}, seed_value)
		assert_eq(state["rng"]["seed"], str(seed_value))
		var again: Dictionary = _round_trip(state)
		assert_eq(again["rng"], state["rng"], "seed %d" % seed_value)
		assert_eq(Prng.restore(again["rng"]["seed"], again["rng"]["state"]).state_text(), Prng.new(seed_value).state_text())


func test_same_seed_same_rng_state_different_seed_different() -> void:
	assert_eq(_new(["p1", "p2"], {}, 5)["rng"], _new(["p1", "p2"], {}, 5)["rng"])
	assert_ne(_new(["p1", "p2"], {}, 5)["rng"], _new(["p1", "p2"], {}, 6)["rng"])


# --- plain data / save-friendly -------------------------------------------------------------

func test_a_new_state_is_plain_data_and_survives_json_unchanged() -> void:
	var state: Dictionary = _new(IDS, {"dice_count": 2}, 99)
	assert_true(Envelope.is_plain_data(state))
	assert_eq(_round_trip(state), state)


func test_a_new_state_is_valid() -> void:
	for count: int in [2, 3, 4]:
		var r: Dictionary = rules.validate_state(_new(IDS.slice(0, count)))
		assert_true(CoreResult.is_ok(r), str(r))
	assert_true(CoreResult.is_ok(rules.validate_state(_round_trip(_new(IDS)))))


# --- validate_state rejects damaged states ---------------------------------------------------------

func _error_after(mutate: Callable) -> String:
	var state: Dictionary = _new(["p1", "p2", "p3"])
	mutate.call(state)
	return CoreResult.error_code(rules.validate_state(state))


func test_validate_state_refuses_missing_and_extra_fields() -> void:
	for key: String in _new().keys():
		var state: Dictionary = _new()
		state.erase(key)
		assert_eq(CoreResult.error_code(rules.validate_state(state)), ClimbErrors.INVALID_STATE, "missing %s" % key)
	var extra: Dictionary = _new()
	extra["secret"] = 1
	assert_eq(CoreResult.error_code(rules.validate_state(extra)), ClimbErrors.INVALID_STATE)


func test_validate_state_refuses_wrong_types_without_crashing() -> void:
	var original: Dictionary = _new()
	for key: String in original.keys():
		for junk: Variant in [null, 5, "text", true, [1], {"a": 1}, 2.5]:
			var state: Dictionary = _new()
			state[key] = junk
			var r: Dictionary = rules.validate_state(state)  # must never crash, whatever the junk
			if typeof(junk) != typeof(original[key]):
				assert_eq(CoreResult.error_code(r), ClimbErrors.INVALID_STATE, "%s = %s" % [key, str(junk)])


func test_validate_state_refuses_specific_corruptions() -> void:
	var cases: Dictionary = {
		"future version": func(s: Dictionary) -> void: s["state_version"] = 2,
		"other game": func(s: Dictionary) -> void: s["game_id"] = "ludo",
		"unknown phase": func(s: Dictionary) -> void: s["phase"] = "paused",
		"position below zero": func(s: Dictionary) -> void: s["positions"]["p1"] = -1,
		"position past the end": func(s: Dictionary) -> void: s["positions"]["p1"] = 101,
		"position as text": func(s: Dictionary) -> void: s["positions"]["p1"] = "5",
		"position for a stranger": func(s: Dictionary) -> void: s["positions"]["zz"] = 4,
		"position missing": func(s: Dictionary) -> void: s["positions"].erase("p2"),
		"current player unknown": func(s: Dictionary) -> void: s["current_player"] = "zz",
		"wrong colors": func(s: Dictionary) -> void: s["players"][0]["color"] = "blue",
		"duplicate player": func(s: Dictionary) -> void: s["players"][1]["player_id"] = "p1",
		"one player": func(s: Dictionary) -> void: s["players"].resize(1),
		"turn number zero": func(s: Dictionary) -> void: s["turn_number"] = 0,
		"negative rolls": func(s: Dictionary) -> void: s["rolls"] = -1,
		"extra turn not a bool": func(s: Dictionary) -> void: s["extra_turn"] = 1,
		"someone on the last square while in progress": func(s: Dictionary) -> void: s["positions"]["p2"] = 100,
		"a winner while in progress": func(s: Dictionary) -> void: s["winner"] = "p1",
		"finished without a winner": func(s: Dictionary) -> void: s["phase"] = "finished",
		"bad board": func(s: Dictionary) -> void: s["board"]["snakes"].append({"from": 1, "to": 1}),
		"board not in canonical form": func(s: Dictionary) -> void: s["board"]["snakes"].reverse(),
		"bad settings": func(s: Dictionary) -> void: s["settings"]["dice_count"] = 7,
		"unknown setting": func(s: Dictionary) -> void: s["settings"]["turbo"] = true,
		"rng seed not text": func(s: Dictionary) -> void: s["rng"]["seed"] = 5,
		"rng state garbage": func(s: Dictionary) -> void: s["rng"]["state"] = "1,2,3",
		"rng state all zero": func(s: Dictionary) -> void: s["rng"]["state"] = "0,0,0,0",
		"last roll with a stranger": func(s: Dictionary) -> void: s["last_roll"] = {"player_id": "zz", "dice": [3], "total": 3},
		"last roll wrong total": func(s: Dictionary) -> void: s["last_roll"] = {"player_id": "p1", "dice": [3], "total": 4},
		"last roll impossible die": func(s: Dictionary) -> void: s["last_roll"] = {"player_id": "p1", "dice": [7], "total": 7},
		"last roll wrong dice count": func(s: Dictionary) -> void: s["last_roll"] = {"player_id": "p1", "dice": [3, 3], "total": 6},
	}
	for label: String in cases:
		assert_eq(_error_after(cases[label]), ClimbErrors.INVALID_STATE, label)


func test_validate_state_accepts_a_correct_finished_state() -> void:
	var state: Dictionary = _new(["p1", "p2"])
	state["phase"] = "finished"
	state["winner"] = "p2"
	state["current_player"] = "p2"
	state["positions"]["p2"] = 100
	assert_true(CoreResult.is_ok(rules.validate_state(state)))


func test_a_finished_state_needs_the_winner_to_be_the_one_on_the_last_square() -> void:
	var state: Dictionary = _new(["p1", "p2"])
	state["phase"] = "finished"
	state["winner"] = "p2"
	state["current_player"] = "p2"
	state["positions"]["p1"] = 100
	assert_eq(CoreResult.error_code(rules.validate_state(state)), ClimbErrors.INVALID_STATE)
	state["positions"]["p2"] = 100
	assert_eq(CoreResult.error_code(rules.validate_state(state)), ClimbErrors.INVALID_STATE, "two players on the last square")


func test_a_valid_last_roll_is_accepted() -> void:
	var state: Dictionary = _new(["p1", "p2"], {"dice_count": 2})
	state["last_roll"] = {"player_id": "p2", "dice": [4, 6], "total": 10}
	assert_true(CoreResult.is_ok(rules.validate_state(state)))
