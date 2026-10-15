extends GutTest
## The house rule "need a 1 to start": a player off the board enters only with a 1, and enters on
## square 1 exactly. Off by default, so every other test and golden game is unchanged.

const ROLL: Dictionary = {"type": "roll"}

var rules: ClimbAndSlitherRules


func before_each() -> void:
	rules = ClimbAndSlitherRules.new()


func _roll(state: Dictionary, active: Array = []) -> Dictionary:
	var result: Dictionary = rules.apply(state, state["current_player"], ROLL, active)
	assert_true(CoreResult.is_ok(result), str(result))
	return result


func _game(rolls: Array, settings: Dictionary = {"need_one_to_start": true}, positions: Dictionary = {}, players: Array = ["p1", "p2"]) -> Dictionary:
	return ClimbRig.game(rolls, players, settings, positions)


# --- the setting -------------------------------------------------------------------------------------------

func test_it_is_off_by_default_and_the_other_defaults_are_unchanged() -> void:
	assert_eq(ClimbSettings.defaults(), {"exact_finish": false, "extra_turn_on_six": false, "dice_count": 1, "need_one_to_start": false})
	var state: Dictionary = ClimbRig.game([5], ["p1", "p2"], {}, {}, ClimbRig.board())  # a board with no jumps
	assert_false(state["settings"]["need_one_to_start"])
	var result: Dictionary = _roll(state)
	assert_eq(result["state"]["positions"]["p1"], 5, "without the rule a 5 moves from the start by 5")
	assert_false(ClimbRig.event_types(result["events"]).has("needs_one"))


func test_only_a_real_boolean_is_accepted() -> void:
	for bad: Variant in [1, "true", null, [true], 0.5]:
		var result: Dictionary = ClimbSettings.normalize({"need_one_to_start": bad})
		assert_eq(CoreResult.error_code(result), ClimbErrors.INVALID_SETTINGS, str(bad))
	assert_true(ClimbSettings.normalize({"need_one_to_start": true})["settings"]["need_one_to_start"])


func test_it_combines_with_every_other_allowed_setting() -> void:
	for exact: bool in [true, false]:
		for dice: int in [1, 2]:
			var result: Dictionary = ClimbSettings.normalize({"need_one_to_start": true, "exact_finish": exact, "dice_count": dice})
			assert_eq(CoreResult.is_ok(result), not (exact and dice == 2), "exact %s, dice %d" % [exact, dice])


func test_the_settings_screen_options_are_unaffected() -> void:
	var states: Dictionary = ClimbSettings.option_states({"need_one_to_start": true})
	assert_true(states["exact_finish"]["enabled"])
	assert_true(states["two_dice"]["enabled"])
	assert_eq(ClimbSettings.allowed_combinations().size(), 3)


# --- the rule ------------------------------------------------------------------------------------------------

func test_a_roll_that_is_not_a_1_leaves_the_player_off_the_board_and_passes_the_turn() -> void:
	var result: Dictionary = _roll(_game([4]))
	assert_eq(result["state"]["positions"]["p1"], 0)
	assert_eq(ClimbRig.event_types(result["events"]), ["rolled", "needs_one", "turn_changed"] as Array[String])
	assert_eq(result["events"][1], {"type": "needs_one", "player_id": "p1", "dice": [4]})
	assert_eq(result["state"]["current_player"], "p2")
	assert_eq(result["state"]["last_roll"]["total"], 4, "the roll is still recorded")


func test_a_1_enters_the_board_on_square_1_with_a_one_square_path() -> void:
	var result: Dictionary = _roll(_game([1]))
	assert_eq(result["state"]["positions"]["p1"], 1)
	assert_eq(ClimbRig.event_types(result["events"]), ["rolled", "moved", "turn_changed"] as Array[String])
	assert_eq(result["events"][1], {"type": "moved", "player_id": "p1", "from": 0, "to": 1, "path": [1]})
	assert_eq(result["state"]["current_player"], "p2")


func test_rolling_a_1_does_not_give_an_extra_turn() -> void:
	var result: Dictionary = _roll(_game([1], {"need_one_to_start": true, "extra_turn_on_six": true}))
	assert_false(ClimbRig.event_types(result["events"]).has("extra_turn"))


func test_with_two_dice_either_die_showing_1_enters_on_square_1_not_by_the_total() -> void:
	for dice: Array in [[1, 5], [4, 1], [1, 1]]:
		var result: Dictionary = _roll(_game([dice], {"need_one_to_start": true, "dice_count": 2}))
		assert_eq(result["state"]["positions"]["p1"], 1, str(dice))
		assert_eq(result["events"][1]["path"], [1], str(dice))
	var miss: Dictionary = _roll(_game([[3, 4]], {"need_one_to_start": true, "dice_count": 2}))
	assert_eq(miss["state"]["positions"]["p1"], 0)
	assert_eq(ClimbRig.event_types(miss["events"]), ["rolled", "needs_one", "turn_changed"] as Array[String])


func test_a_6_that_does_not_enter_still_gives_the_extra_turn_when_that_rule_is_on() -> void:
	var result: Dictionary = _roll(_game([6], {"need_one_to_start": true, "extra_turn_on_six": true}))
	assert_eq(result["state"]["positions"]["p1"], 0)
	assert_eq(ClimbRig.event_types(result["events"]), ["rolled", "needs_one", "extra_turn"] as Array[String])
	assert_eq(result["state"]["current_player"], "p1")
	assert_true(result["state"]["extra_turn"])


func test_two_dice_with_a_1_and_a_6_enters_and_also_gets_the_extra_turn() -> void:
	var result: Dictionary = _roll(_game([[1, 6]], {"need_one_to_start": true, "dice_count": 2, "extra_turn_on_six": true}))
	assert_eq(result["state"]["positions"]["p1"], 1)
	assert_eq(ClimbRig.event_types(result["events"]), ["rolled", "moved", "extra_turn"] as Array[String])


func test_a_player_already_on_the_board_moves_normally() -> void:
	var result: Dictionary = _roll(_game([4], {"need_one_to_start": true}, {"p1": 10}))
	assert_eq(result["state"]["positions"]["p1"], 14)
	assert_false(ClimbRig.event_types(result["events"]).has("needs_one"))


func test_each_player_needs_their_own_1_and_others_are_not_affected() -> void:
	var state: Dictionary = _game([3, 1], {"need_one_to_start": true})
	var first: Dictionary = _roll(state)
	var second: Dictionary = _roll(first["state"])
	assert_eq(second["state"]["positions"], {"p1": 0, "p2": 1})


func test_a_player_who_has_not_entered_cannot_finish_or_jump() -> void:
	var board: Dictionary = ClimbRig.board([ClimbRig.jump(5, 2)], [ClimbRig.jump(3, 20)], 30, 6)
	var state: Dictionary = ClimbRig.game([3], ["p1", "p2"], {"need_one_to_start": true}, {}, board)
	var result: Dictionary = _roll(state)
	assert_eq(result["state"]["positions"]["p1"], 0, "a 3 would have climbed a ladder without the rule")
	assert_false(ClimbRig.event_types(result["events"]).has("jumped"))


func test_exact_finish_still_applies_after_entering() -> void:
	var state: Dictionary = _game([5], {"need_one_to_start": true, "exact_finish": true}, {"p1": 98})
	var result: Dictionary = _roll(state)
	assert_true(ClimbRig.event_types(result["events"]).has("overshoot"))
	assert_eq(result["state"]["positions"]["p1"], 98)


# --- state, views, saves, determinism ------------------------------------------------------------------------------

func test_states_stay_valid_and_old_states_without_the_key_are_still_accepted() -> void:
	var state: Dictionary = _game([4])
	assert_true(CoreResult.is_ok(rules.validate_state(state)))
	assert_true(CoreResult.is_ok(rules.validate_state(_roll(state)["state"])))
	var old: Dictionary = _game([4], {})
	old["settings"].erase("need_one_to_start")
	assert_true(CoreResult.is_ok(rules.validate_state(old)), "a state saved before this rule existed")
	var broken: Dictionary = _game([4])
	broken["settings"]["need_one_to_start"] = "yes"
	assert_false(CoreResult.is_ok(rules.validate_state(broken)))


func test_the_setting_survives_views_and_save_text() -> void:
	var state: Dictionary = _roll(_game([4]))["state"]
	assert_true(rules.view_for(state, "p2")["settings"]["need_one_to_start"])
	var text: String = JSON.stringify(state)
	var loaded: Dictionary = Envelope.normalize(JSON.parse_string(text))
	assert_eq(loaded, state)
	assert_true(CoreResult.is_ok(rules.validate_state(loaded)))
	assert_true(CoreResult.is_ok(rules.apply(loaded, loaded["current_player"], ROLL)))


func test_the_same_seed_plays_the_same_game() -> void:
	var a: Dictionary = _play_out(["p1", "p2", "p3"], {"need_one_to_start": true}, 99)
	var b: Dictionary = _play_out(["p1", "p2", "p3"], {"need_one_to_start": true}, 99)
	assert_eq(a["state"], b["state"])
	assert_eq(a["rolls"], b["rolls"])


func _play_out(players: Array, settings: Dictionary, seed_value: int) -> Dictionary:
	var state: Dictionary = rules.new_game(players, ClimbRig.classic(), settings, seed_value)["state"]
	var rolls: int = 0
	while state["phase"] != "finished" and rolls < 20000:
		var result: Dictionary = rules.apply(state, state["current_player"], ROLL)
		assert_true(CoreResult.is_ok(result), str(result))
		state = result["state"]
		rolls += 1
	return {"state": state, "rolls": rolls}


func test_hundreds_of_random_games_with_the_rule_all_finish_and_stay_valid() -> void:
	var master: Prng = Prng.new(20261015)
	for index: int in 300:
		var count: int = master.range_int(1, 4)
		if count < 2:
			count = 2
		var players: Array = []
		for i: int in count:
			players.append("p%d" % (i + 1))
		var dice: int = master.range_int(1, 2)
		var settings: Dictionary = {
			"need_one_to_start": true,
			"dice_count": dice,
			"exact_finish": dice == 1 and master.range_int(0, 1) == 1,
			"extra_turn_on_six": master.range_int(0, 1) == 1,
		}
		var played: Dictionary = _play_out(players, settings, master.range_int(1, 1000000))
		assert_eq(played["state"]["phase"], "finished", "game %d finished" % index)
		assert_true(CoreResult.is_ok(rules.validate_state(played["state"])), "game %d valid" % index)
		assert_ne(played["state"]["winner"], "")
