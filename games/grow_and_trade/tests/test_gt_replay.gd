extends GutTest
## A recorded game (seed + settings + every action) plays back to exactly the same state. Includes golden
## values for one seed, so a change to the draw order (which would break saves and replays) is caught.

var rules: GrowAndTradeRules


func before_each() -> void:
	rules = GrowAndTradeRules.new()


## Plays `actions` bot actions of a fresh game, recording them. Returns {state, replay}.
func _record(players: Array, settings: Dictionary, seed_value: int, actions: int, bot_seed: int = 3) -> Dictionary:
	var created: Dictionary = rules.new_game(players, GtRig.board(), settings, seed_value)
	assert_true(CoreResult.is_ok(created), str(created))
	var state: Dictionary = created["state"]
	var replay: Dictionary = GtReplay.make(players, GtRig.board(), settings, seed_value)
	var bot: GtBot = GtBot.new(bot_seed)
	for _i: int in actions:
		if state["phase"] == "finished":
			break
		var picked: Dictionary = bot.pick(state)
		var result: Dictionary = GtReplay.apply_and_record(rules, replay, state, picked["player_id"], picked["action"])
		assert_true(CoreResult.is_ok(result), str(result))
		state = result["state"]
	return {"state": state, "replay": replay}


func _bad_code(replay: Dictionary) -> String:
	return CoreResult.error_code(GtReplay.run(replay))


# --- the round trip ----------------------------------------------------------------------------------

func test_a_recorded_game_replays_to_the_same_state() -> void:
	var recorded: Dictionary = _record(GtRig.players(5), {"target_points": 8}, 8675309, 320)
	var replayed: Dictionary = GtReplay.run(recorded["replay"])
	assert_true(CoreResult.is_ok(replayed), str(replayed))
	assert_eq(replayed["steps"], (recorded["replay"]["steps"] as Array).size())
	assert_eq(JSON.stringify(replayed["state"]), JSON.stringify(recorded["state"]), "byte for byte")
	assert_ne(recorded["state"]["phase"], "founding", "the recording went past the founding rounds")


func test_a_replay_survives_being_written_as_text() -> void:
	var recorded: Dictionary = _record(GtRig.players(4), {"friendly_blocker": true}, 99, 220)
	var text: String = GtReplay.to_text(recorded["replay"])
	var parsed: Dictionary = GtReplay.from_text(text)
	assert_true(CoreResult.is_ok(parsed), str(parsed))
	var replayed: Dictionary = GtReplay.run(parsed["replay"])
	assert_true(CoreResult.is_ok(replayed), str(replayed))
	assert_eq(replayed["state"], recorded["state"])
	assert_eq(GtReplay.to_text(parsed["replay"]), text, "writing it again gives the same text")


func test_replaying_a_finished_game_ends_with_the_winner() -> void:
	var recorded: Dictionary = _record(GtRig.players(3), {"target_points": 8}, 5150, 6000, 11)
	assert_eq(recorded["state"]["phase"], "finished", "the bot finishes a 3 player game")
	var replayed: Dictionary = GtReplay.run(recorded["replay"])
	assert_eq(replayed["state"]["winner"], recorded["state"]["winner"])
	var won: int = 0
	for event: Dictionary in replayed["events"]:
		won += 1 if event["type"] == "won" else 0
	assert_eq(won, 1)


func test_the_seed_may_be_text_or_a_number() -> void:
	var recorded: Dictionary = _record(GtRig.players(3), {}, 4242, 40)
	var as_number: Dictionary = recorded["replay"].duplicate(true)
	as_number["seed"] = 4242
	assert_eq(GtReplay.run(as_number)["state"], recorded["state"])
	assert_eq(typeof(recorded["replay"]["seed"]), TYPE_STRING, "recorded as text, so 64-bit seeds survive JSON")


func test_huge_and_negative_seeds_replay() -> void:
	for seed_value: int in [9007199254740993, -9007199254740993, 4611686018427387904]:
		var recorded: Dictionary = _record(GtRig.players(4), {}, seed_value, 60)
		var through_text: Dictionary = GtReplay.from_text(GtReplay.to_text(recorded["replay"]))
		assert_eq(GtReplay.run(through_text["replay"])["state"], recorded["state"], "seed %d" % seed_value)


# --- refused steps and settle steps -------------------------------------------------------------------------

func test_a_refused_step_must_say_so() -> void:
	var replay: Dictionary = GtReplay.make(GtRig.players(3), GtRig.board(), {}, 1)
	GtReplay.add_action(replay, "p1", {"type": "roll"}, [], "WRONG_PHASE")
	var ok: Dictionary = GtReplay.run(replay)
	assert_true(CoreResult.is_ok(ok), str(ok))
	GtReplay.add_action(replay, "p1", {"type": "roll"})  # refused again, but not declared
	var failed: Dictionary = GtReplay.run(replay)
	assert_eq(CoreResult.error_code(failed), GtReplay.REPLAY_STEP_FAILED)
	assert_eq(failed["step"], 1)
	assert_eq(failed["step_error"], "WRONG_PHASE")


func test_a_step_that_works_but_was_expected_to_fail_is_reported() -> void:
	var state: Dictionary = GtRig.new_state(3, {}, 1)
	var corner: String = GtBoard.new(state["board"]).corners()[0]
	var replay: Dictionary = GtReplay.make(GtRig.players(3), GtRig.board(), {}, 1)
	GtReplay.add_action(replay, "p1", {"type": "place_village", "corner": corner}, [], "BAD_PLACEMENT")
	var failed: Dictionary = GtReplay.run(replay)
	assert_eq(CoreResult.error_code(failed), GtReplay.REPLAY_STEP_FAILED)
	assert_eq(failed["step_error"], "")


func test_a_wrongly_declared_error_is_reported() -> void:
	var replay: Dictionary = GtReplay.make(GtRig.players(3), GtRig.board(), {}, 1)
	GtReplay.add_action(replay, "p1", {"type": "roll"}, [], "NOT_YOUR_TURN")
	assert_eq(CoreResult.error_code(GtReplay.run(replay)), GtReplay.REPLAY_STEP_FAILED)


func test_settle_steps_and_active_players_replay() -> void:
	var replay: Dictionary = GtReplay.make(GtRig.players(4), GtRig.board(), {}, 21)
	var live: Dictionary = rules.new_game(GtRig.players(4), GtRig.board(), {}, 21)
	var state: Dictionary = live["state"]
	var active: Array = ["p2", "p3", "p4"]
	var blocked: Dictionary = GtReplay.apply_and_record(rules, replay, state, "p1", {"type": "roll"}, active)
	assert_eq(CoreResult.error_code(blocked), "PLAYER_INACTIVE")
	GtReplay.add_settle(replay, active)
	state = rules.settle(state, active)["state"]
	assert_eq(state["current_player"], "p2", "p1 is away, so the placement went on")
	var replayed: Dictionary = GtReplay.run(replay)
	assert_true(CoreResult.is_ok(replayed), str(replayed))
	assert_eq(replayed["state"], state)


# --- bad replays -------------------------------------------------------------------------------------------

func test_damaged_replays_are_refused_with_invalid_replay() -> void:
	var good: Dictionary = GtReplay.make(GtRig.players(3), GtRig.board(), {}, 1)
	var damaged: Array = [
		{"replay_version": 2},
		{"players": "p1"},
		{"steps": {}},
		{"board": []},
		{"settings": 3},
		{"seed": "abc"},
		{"seed": 1.5},
		{"steps": ["roll"]},
		{"steps": [{"player_id": "p1"}]},
		{"steps": [{"player_id": "p1", "action": {"type": "roll"}, "active_players": "p1"}]},
		{"steps": [{"player_id": "p1", "action": {"type": "roll"}, "expect_error": 3}]},
		{"steps": [{"settle": "p1"}]},
	]
	for change: Dictionary in damaged:
		var replay: Dictionary = good.duplicate(true)
		for key: String in change:
			replay[key] = change[key]
		assert_eq(_bad_code(replay), GtReplay.INVALID_REPLAY, str(change))
	for key: String in ["replay_version", "players", "steps", "board", "settings", "seed"]:
		var missing: Dictionary = good.duplicate(true)
		missing.erase(key)
		assert_eq(_bad_code(missing), GtReplay.INVALID_REPLAY, "without %s" % key)
	assert_eq(CoreResult.error_code(GtReplay.from_text("{nope")), GtReplay.INVALID_REPLAY)
	assert_eq(CoreResult.error_code(GtReplay.from_text("[1, 2]")), GtReplay.INVALID_REPLAY)


func test_a_replay_with_a_bad_setup_returns_the_new_game_error() -> void:
	var replay: Dictionary = GtReplay.make(["p1", "p2"], GtRig.board(), {}, 1)
	assert_eq(_bad_code(replay), GtErrors.BAD_PLAYERS)
	var settings: Dictionary = GtReplay.make(GtRig.players(3), GtRig.board(), {"hand_limit": 1}, 1)
	assert_eq(_bad_code(settings), GtErrors.INVALID_SETTINGS)


# --- golden values -------------------------------------------------------------------------------------------

## Seed 20260601 with 4 players. If this fails the draw order changed: that breaks every saved game and
## replay and needs STATE_VERSION bumped (see the design doc), it is never "just update the numbers".
func test_golden_layout_deck_and_first_roll_for_a_fixed_seed() -> void:
	var state: Dictionary = GtRig.new_state(4, {}, 20260601)
	var types: Array = []
	var tokens: Array = []
	for tile: Dictionary in state["layout"]["tiles"].slice(0, 7):
		types.append(tile["type"])
		tokens.append(tile["token"])
	assert_eq(types, ["stone", "fleece", "timber", "desert", "wheat", "stone", "timber"])
	assert_eq(tokens, [6, 3, 8, 0, 11, 3, 9])
	assert_eq(state["blocker"], {"q": -1, "r": -2})
	assert_eq(state["deck"].slice(0, 4), ["point", "guard", "sweep", "guard"])
	assert_eq(state["rng"]["state"], "2315302650,1843714756,1272707444,4102167077")

	var playing: Dictionary = GtRig.playing(4, {}, 20260601)
	assert_eq(playing["rng"]["state"], state["rng"]["state"], "founding draws nothing")
	assert_eq(playing["current_player"], "p1")
	var rolled: Dictionary = rules.apply(playing, "p1", {"type": "roll"})
	assert_eq(rolled["state"]["turn"]["dice"], [1, 5])
	assert_eq(rolled["state"]["rng"]["state"], "2304700314,3073844447,1679959445,3301706961")
