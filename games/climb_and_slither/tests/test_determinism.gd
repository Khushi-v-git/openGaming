extends GutTest
## Same seed, same game, on any machine and Godot version. The golden games below were played
## by an independent implementation of the written rules (written in Python from the plan, not
## from this code, using the same Prng algorithm), so they check the rules themselves, not just
## that the code agrees with itself.

const ROLL: Dictionary = {"type": "roll"}

var rules: ClimbAndSlitherRules


func before_each() -> void:
	rules = ClimbAndSlitherRules.new()


## Plays to the end; returns {state, first_totals, events}.
func _play_out(players: Array, settings: Dictionary, seed_value: int, board: Dictionary = {}) -> Dictionary:
	var chosen: Dictionary = board if not board.is_empty() else ClimbRig.classic()
	var state: Dictionary = rules.new_game(players, chosen, settings, seed_value)["state"]
	var totals: Array[int] = []
	var events: Array = []
	var guard: int = 0
	while state["phase"] == "in_progress" and guard < 20000:
		guard += 1
		var result: Dictionary = rules.apply(state, state["current_player"], ROLL)
		assert_true(CoreResult.is_ok(result), str(result))
		state = result["state"]
		totals.append(state["last_roll"]["total"])
		events.append_array(result["events"])
	return {"state": state, "first_totals": totals.slice(0, 12), "events": events}


# --- same seed, same game -------------------------------------------------------------------------

func test_the_same_seed_gives_the_same_game_every_time() -> void:
	for settings: Dictionary in [{}, {"exact_finish": true, "extra_turn_on_six": true}, {"extra_turn_on_six": true, "dice_count": 2}]:
		var first: Dictionary = _play_out(["p1", "p2", "p3"], settings, 555)
		var second: Dictionary = _play_out(["p1", "p2", "p3"], settings, 555)
		assert_eq(second["state"], first["state"])
		assert_eq(second["events"], first["events"])


func test_different_seeds_give_different_games() -> void:
	var finals: Dictionary = {}
	for seed_value: int in range(1, 21):
		finals[var_to_str(_play_out(["p1", "p2"], {}, seed_value)["state"])] = true
	assert_gte(finals.size(), 19, "twenty seeds give (almost certainly) twenty different games")


func test_looking_at_the_game_does_not_change_it() -> void:
	var plain: Dictionary = _play_out(["p1", "p2"], {}, 8)
	var state: Dictionary = rules.new_game(["p1", "p2"], ClimbRig.classic(), {}, 8)["state"]
	while state["phase"] == "in_progress":
		rules.view_for(state, "p1")
		rules.validate_state(state)
		rules.settle(state, ["p1", "p2"])
		state = rules.apply(state, state["current_player"], ROLL)["state"]
	assert_eq(state, plain["state"], "views, validation and settle are free of side effects")


func test_the_seed_is_not_changed_by_playing() -> void:
	var played: Dictionary = _play_out(["p1", "p2"], {}, 4711)
	assert_eq(played["state"]["rng"]["seed"], "4711")


# --- golden games from the independent reference implementation ------------------------------------------

func _golden(seed_value: int, players: Array, settings: Dictionary, winner: String, rolls: int, positions: Dictionary, first_totals: Array, final_rng: String) -> void:
	var played: Dictionary = _play_out(players, settings, seed_value)
	var state: Dictionary = played["state"]
	assert_eq(state["winner"], winner, "winner (seed %d)" % seed_value)
	assert_eq(state["rolls"], rolls, "rolls (seed %d)" % seed_value)
	assert_eq(state["positions"], positions, "final positions (seed %d)" % seed_value)
	assert_eq(played["first_totals"], first_totals, "first rolls (seed %d)" % seed_value)
	assert_eq(state["rng"]["state"], final_rng, "generator state at the end (seed %d)" % seed_value)


func test_golden_game_default_rules_two_players() -> void:
	_golden(1, ["p1", "p2"], {}, "p2", 50, {"p1": 68, "p2": 100},
		[6, 1, 3, 3, 4, 2, 6, 5, 6, 4, 2, 6], "3018192862,3958684438,1823986565,176107398")


func test_golden_game_exact_finish_three_players() -> void:
	_golden(2024, ["p1", "p2", "p3"], {"exact_finish": true}, "p1", 73, {"p1": 100, "p2": 66, "p3": 26},
		[4, 1, 2, 5, 4, 5, 5, 1, 5, 3, 5, 1], "152671465,4260315782,3869672863,3728180684")


func test_golden_game_extra_turn_on_six_four_players() -> void:
	_golden(777, ["p1", "p2", "p3", "p4"], {"extra_turn_on_six": true}, "p2", 64, {"p1": 34, "p2": 100, "p3": 93, "p4": 27},
		[3, 1, 1, 3, 4, 2, 5, 1, 5, 1, 4, 2], "713264282,4194764379,935917157,650006835")


func test_golden_game_two_dice() -> void:
	_golden(31337, ["a", "b"], {"dice_count": 2}, "b", 30, {"a": 57, "b": 100},
		[5, 4, 9, 4, 7, 7, 11, 3, 7, 7, 4, 11], "159604452,3330296023,2784129176,2559453415")


func test_golden_game_two_dice_and_extra_turns_with_a_seed_that_needs_all_64_bits() -> void:
	_golden(9007199254740993, ["p1", "p2", "p3"], {"extra_turn_on_six": true, "dice_count": 2}, "p1", 55, {"p1": 100, "p2": 84, "p3": 16},
		[11, 11, 3, 8, 6, 4, 11, 6, 10, 6, 2, 3], "1957244003,74796400,3910331898,3130265690")


func test_golden_game_negative_seed_exact_finish_and_extra_turns() -> void:
	_golden(-42, ["p1", "p2", "p3", "p4"], {"exact_finish": true, "extra_turn_on_six": true}, "p3", 128, {"p1": 52, "p2": 37, "p3": 100, "p4": 96},
		[6, 3, 3, 1, 6, 6, 2, 2, 3, 3, 1, 2], "4227951031,628967099,3060967154,4098994528")


func test_golden_game_huge_seed() -> void:
	_golden(4611686018427387904, ["x", "y"], {}, "y", 30, {"x": 27, "y": 100},
		[1, 4, 1, 1, 5, 3, 2, 4, 6, 5, 1, 1], "2159265979,3652310298,2422471979,2327722878")


# --- the rules code stays pure (rule 2) ----------------------------------------------------------------------

func test_the_rules_use_no_engine_state_nodes_timers_or_other_randomness() -> void:
	var forbidden: Array[String] = [
		"randi(", "randf(", "randomize(", "RandomNumberGenerator", "rand_range", "shuffle(", "pick_random(",
		"Time.", "OS.", "Engine.", "get_tree", "await ", "Timer", "extends Node", "extends Control", "preload(\"res://scenes",
		"@rpc", "multiplayer", "WebSocket", "StreamPeer", "TCPServer", "DisplayServer",
	]
	var dir: DirAccess = DirAccess.open("res://games/climb_and_slither/rules")
	assert_not_null(dir)
	var checked: int = 0
	for file: String in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		checked += 1
		var source: String = FileAccess.get_file_as_string("res://games/climb_and_slither/rules/" + file)
		for word: String in forbidden:
			assert_false(source.contains(word), "%s must not use '%s'" % [file, word])
		assert_true(source.contains("extends RefCounted"), "%s extends RefCounted" % file)
	assert_gte(checked, 5, "all the rules files were scanned")


func test_the_rules_only_depend_on_core_and_themselves() -> void:
	# Rule: a game depends only on core's public interfaces and never on another game.
	var dir: DirAccess = DirAccess.open("res://games/climb_and_slither/rules")
	for file: String in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var source: String = FileAccess.get_file_as_string("res://games/climb_and_slither/rules/" + file)
		assert_false(source.contains("res://games/") and not source.contains("res://games/climb_and_slither"), "%s refers to another game" % file)
		assert_false(source.contains("res://main"), "%s refers to main/" % file)
