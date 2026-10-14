extends GutTest

const ROLL: Dictionary = {"type": "roll"}

var rules: ClimbAndSlitherRules


func before_each() -> void:
	rules = ClimbAndSlitherRules.new()


## Plays a whole game while recording it. Returns {state, replay, events}.
func _record_game(players: Array, settings: Dictionary, seed_value: int, rolls_cap: int = 5000) -> Dictionary:
	var board: Dictionary = ClimbRig.classic()
	var replay: Dictionary = ClimbReplay.make(players, board, settings, seed_value)
	var state: Dictionary = rules.new_game(players, board, settings, seed_value)["state"]
	var events: Array = []
	var guard: int = 0
	while state["phase"] == "in_progress" and guard < rolls_cap:
		guard += 1
		var result: Dictionary = ClimbReplay.apply_and_record(rules, replay, state, state["current_player"], ROLL)
		assert_true(CoreResult.is_ok(result))
		state = result["state"]
		events.append_array(result["events"])
	return {"state": state, "replay": replay, "events": events}


# --- running a replay -----------------------------------------------------------------------

func test_an_empty_replay_is_just_the_new_game() -> void:
	var replay: Dictionary = ClimbReplay.make(["p1", "p2"], ClimbRig.classic(), {}, 12)
	var result: Dictionary = ClimbReplay.run(replay)
	assert_true(CoreResult.is_ok(result), str(result))
	assert_eq(result["state"], rules.new_game(["p1", "p2"], ClimbRig.classic(), {}, 12)["state"])
	assert_eq(result["steps"], 0)
	assert_eq(result["events"], [])


func test_a_recorded_game_replays_to_the_same_final_state_and_events() -> void:
	for settings: Dictionary in [{}, {"exact_finish": true}, {"extra_turn_on_six": true, "dice_count": 2}]:
		var played: Dictionary = _record_game(["p1", "p2", "p3"], settings, 4242)
		var replayed: Dictionary = ClimbReplay.run(played["replay"])
		assert_true(CoreResult.is_ok(replayed), str(replayed))
		assert_eq(replayed["state"], played["state"], str(settings))
		assert_eq(replayed["events"], played["events"], str(settings))
		assert_eq(replayed["state"]["phase"], "finished")


func test_a_replay_survives_being_written_as_text_and_read_back() -> void:
	var played: Dictionary = _record_game(["p1", "p2", "p3", "p4"], {"extra_turn_on_six": true}, 9007199254740993)
	var parsed: Dictionary = ClimbReplay.from_text(ClimbReplay.to_text(played["replay"]))
	assert_true(CoreResult.is_ok(parsed), str(parsed))
	assert_eq(parsed["replay"], played["replay"])
	var replayed: Dictionary = ClimbReplay.run(parsed["replay"])
	assert_eq(replayed["state"], played["state"])


func test_a_replay_can_stop_part_way() -> void:
	var played: Dictionary = _record_game(["p1", "p2"], {}, 3)
	var replay: Dictionary = played["replay"].duplicate(true)
	replay["steps"] = replay["steps"].slice(0, 5)
	var partial: Dictionary = ClimbReplay.run(replay)
	assert_eq(partial["state"]["rolls"], 5)
	assert_eq(partial["state"]["phase"], "in_progress")


func test_replays_are_plain_json_safe_data() -> void:
	var played: Dictionary = _record_game(["p1", "p2"], {}, 8)
	assert_true(Envelope.is_plain_data(played["replay"]))


func test_the_seed_is_stored_as_text_and_an_int_seed_is_accepted_too() -> void:
	var replay: Dictionary = ClimbReplay.make(["p1", "p2"], ClimbRig.classic(), {}, 4611686018427387904)
	assert_eq(replay["seed"], "4611686018427387904")
	var as_int: Dictionary = replay.duplicate(true)
	as_int["seed"] = 5
	assert_true(CoreResult.is_ok(ClimbReplay.run(as_int)))


func test_the_board_in_a_replay_is_embedded_so_old_replays_do_not_change() -> void:
	var played: Dictionary = _record_game(["p1", "p2"], {}, 17)
	var replay: Dictionary = played["replay"].duplicate(true)
	assert_eq(replay["board"], ClimbRig.classic())
	replay["board"]["snakes"] = []
	replay["board"]["ladders"] = []
	var other: Dictionary = ClimbReplay.run(replay)
	# without snakes and ladders the recorded moves no longer fit (the game may even end sooner
	# and later steps be refused): either way it is not the same game
	assert_true(not CoreResult.is_ok(other) or other["state"] != played["state"], "a different board really gives a different game")


# --- absent players and refused steps -------------------------------------------------------------

func test_settles_and_active_lists_are_part_of_a_replay() -> void:
	var board: Dictionary = ClimbRig.classic()
	var players: Array = ["p1", "p2", "p3"]
	var live: Dictionary = rules.new_game(players, board, {"extra_turn_on_six": true}, 606)["state"]
	var replay: Dictionary = ClimbReplay.make(players, board, {"extra_turn_on_six": true}, 606)
	var active: Array = ["p1", "p3"]
	for _i: int in 30:
		if live["phase"] != "in_progress":
			break
		var settled: Dictionary = rules.settle(live, active)
		if not settled["events"].is_empty():
			ClimbReplay.add_settle(replay, active)
		live = settled["state"]
		live = ClimbReplay.apply_and_record(rules, replay, live, live["current_player"], ROLL, active)["state"]
	var replayed: Dictionary = ClimbReplay.run(replay)
	assert_true(CoreResult.is_ok(replayed), str(replayed))
	assert_eq(replayed["state"], live)
	assert_eq(replayed["state"]["positions"]["p2"], 0, "p2 never played")


func test_a_refused_step_replays_when_it_says_what_it_expects() -> void:
	var replay: Dictionary = ClimbReplay.make(["p1", "p2"], ClimbRig.classic(), {}, 21)
	ClimbReplay.add_action(replay, "p2", ROLL, [], ClimbErrors.NOT_YOUR_TURN)
	ClimbReplay.add_action(replay, "p1", {"type": "move"}, [], ErrorCodes.UNKNOWN_ACTION)
	ClimbReplay.add_action(replay, "p1", ROLL)
	var result: Dictionary = ClimbReplay.run(replay)
	assert_true(CoreResult.is_ok(result), str(result))
	assert_eq(result["state"]["rolls"], 1, "only the real roll counted")
	assert_eq(result["steps"], 3)


func test_apply_and_record_notes_refusals_with_their_codes() -> void:
	var replay: Dictionary = ClimbReplay.make(["p1", "p2"], ClimbRig.classic(), {}, 21)
	var state: Dictionary = rules.new_game(["p1", "p2"], ClimbRig.classic(), {}, 21)["state"]
	var refused: Dictionary = ClimbReplay.apply_and_record(rules, replay, state, "p2", ROLL)
	assert_false(CoreResult.is_ok(refused))
	assert_eq(replay["steps"][0]["expect_error"], ClimbErrors.NOT_YOUR_TURN)
	assert_true(CoreResult.is_ok(ClimbReplay.run(replay)))


func test_an_unexpected_refusal_fails_the_replay_at_that_step() -> void:
	var replay: Dictionary = ClimbReplay.make(["p1", "p2"], ClimbRig.classic(), {}, 21)
	ClimbReplay.add_action(replay, "p1", ROLL)
	ClimbReplay.add_action(replay, "p1", ROLL)  # p2's turn: refused, and the replay did not say so
	var result: Dictionary = ClimbReplay.run(replay)
	assert_eq(CoreResult.error_code(result), ClimbReplay.REPLAY_STEP_FAILED)
	assert_eq(result["step"], 1)
	assert_eq(result["step_error"], ClimbErrors.NOT_YOUR_TURN)
	assert_string_contains(str(result["error"]["message"]), "step 1")


func test_a_wrong_expectation_fails_the_replay() -> void:
	var replay: Dictionary = ClimbReplay.make(["p1", "p2"], ClimbRig.classic(), {}, 21)
	ClimbReplay.add_action(replay, "p2", ROLL, [], ErrorCodes.UNKNOWN_ACTION)  # really NOT_YOUR_TURN
	var result: Dictionary = ClimbReplay.run(replay)
	assert_eq(CoreResult.error_code(result), ClimbReplay.REPLAY_STEP_FAILED)
	assert_eq(result["step"], 0)


func test_a_step_that_was_expected_to_fail_but_works_fails_the_replay() -> void:
	var replay: Dictionary = ClimbReplay.make(["p1", "p2"], ClimbRig.classic(), {}, 21)
	ClimbReplay.add_action(replay, "p1", ROLL, [], ClimbErrors.NOT_YOUR_TURN)
	var result: Dictionary = ClimbReplay.run(replay)
	assert_eq(CoreResult.error_code(result), ClimbReplay.REPLAY_STEP_FAILED)
	assert_string_contains(str(result["error"]["message"]), "should have been refused")


# --- bad replays --------------------------------------------------------------------------------------

func test_malformed_replays_are_refused_not_crashed_on() -> void:
	var good: Dictionary = ClimbReplay.make(["p1", "p2"], ClimbRig.classic(), {}, 1)
	var cases: Dictionary = {
		"wrong version": func(r: Dictionary) -> void: r["replay_version"] = 2,
		"no version": func(r: Dictionary) -> void: r.erase("replay_version"),
		"players not a list": func(r: Dictionary) -> void: r["players"] = "p1,p2",
		"steps not a list": func(r: Dictionary) -> void: r["steps"] = {},
		"board missing": func(r: Dictionary) -> void: r.erase("board"),
		"settings missing": func(r: Dictionary) -> void: r.erase("settings"),
		"seed missing": func(r: Dictionary) -> void: r.erase("seed"),
		"seed not a number": func(r: Dictionary) -> void: r["seed"] = "lucky",
		"seed a float": func(r: Dictionary) -> void: r["seed"] = 1.5,
		"step not an object": func(r: Dictionary) -> void: r["steps"] = [5],
		"step without an action": func(r: Dictionary) -> void: r["steps"] = [{"player_id": "p1"}],
		"step without a player": func(r: Dictionary) -> void: r["steps"] = [{"action": {"type": "roll"}}],
		"settle not a list": func(r: Dictionary) -> void: r["steps"] = [{"settle": "p1"}],
		"active not a list": func(r: Dictionary) -> void: r["steps"] = [{"player_id": "p1", "action": {"type": "roll"}, "active_players": "p1"}],
		"expect_error not text": func(r: Dictionary) -> void: r["steps"] = [{"player_id": "p1", "action": {"type": "roll"}, "expect_error": 5}],
	}
	for label: String in cases:
		var broken: Dictionary = good.duplicate(true)
		(cases[label] as Callable).call(broken)
		assert_eq(CoreResult.error_code(ClimbReplay.run(broken)), ClimbReplay.INVALID_REPLAY, label)


func test_a_replay_with_bad_game_setup_reports_that_error() -> void:
	var one_player: Dictionary = ClimbReplay.make(["p1"], ClimbRig.classic(), {}, 1)
	assert_eq(CoreResult.error_code(ClimbReplay.run(one_player)), ClimbErrors.BAD_PLAYERS)
	var bad_settings: Dictionary = ClimbReplay.make(["p1", "p2"], ClimbRig.classic(), {"dice_count": 9}, 1)
	assert_eq(CoreResult.error_code(ClimbReplay.run(bad_settings)), ClimbErrors.INVALID_SETTINGS)


func test_from_text_refuses_garbage() -> void:
	assert_eq(CoreResult.error_code(ClimbReplay.from_text("{ not json")), ClimbReplay.INVALID_REPLAY)
	assert_eq(CoreResult.error_code(ClimbReplay.from_text("[1,2]")), ClimbReplay.INVALID_REPLAY)


# --- a pasted bug report ----------------------------------------------------------------------------------

func test_a_replay_pasted_as_text_reproduces_a_known_game() -> void:
	# Seed 1, two players, default rules, classic board: the dice are 6,1,3,3,4,2,6,5,6,4,...
	# so p1 climbs the 5 ladder on its 3rd roll... this text is what a bug report would contain.
	var text: String = '''{
  "replay_version": 1,
  "players": ["p1", "p2"],
  "board": %s,
  "settings": {},
  "seed": "1",
  "steps": [
    {"player_id": "p1", "action": {"type": "roll"}},
    {"player_id": "p2", "action": {"type": "roll"}},
    {"player_id": "p1", "action": {"type": "roll"}},
    {"player_id": "p2", "action": {"type": "roll"}}
  ]
}''' % JSON.stringify(ClimbRig.classic())
	var parsed: Dictionary = ClimbReplay.from_text(text)
	assert_true(CoreResult.is_ok(parsed), str(parsed))
	var result: Dictionary = ClimbReplay.run(parsed["replay"])
	assert_true(CoreResult.is_ok(result), str(result))
	# dice 6,1,3,3: p1 goes 6, then 6+3 = 9; p2 goes 1, then 1+3 = 4
	assert_eq(result["state"]["positions"], {"p1": 9, "p2": 4})
	assert_eq(result["state"]["rolls"], 4)
	assert_eq(result["state"]["current_player"], "p1")
