extends GutTest
## Every refused action leaves the state exactly as it was and returns a clear error.

const ROLL: Dictionary = {"type": "roll"}

var rules: ClimbAndSlitherRules


func before_each() -> void:
	rules = ClimbAndSlitherRules.new()


func _state() -> Dictionary:
	return ClimbRig.game([3, 4, 5], ["p1", "p2", "p3"])


## Applies, then checks it failed with `code`, the input did not change, and no state came back.
func _refused(state: Dictionary, player: String, action: Dictionary, code: String, active: Array = []) -> Dictionary:
	var snapshot: Dictionary = state.duplicate(true)
	var result: Dictionary = rules.apply(state, player, action, active)
	assert_false(CoreResult.is_ok(result), "should be refused: %s %s" % [player, str(action)])
	assert_eq(CoreResult.error_code(result), code, "%s %s -> %s" % [player, str(action), str(result)])
	assert_false(result.has("state"), "a refusal returns no state")
	assert_false(result.has("events"), "a refusal returns no events")
	assert_ne(str(result["error"]["message"]), "", "the error says what is wrong")
	assert_eq(state, snapshot, "the state is unchanged after a refusal")
	return result


# --- wrong player ------------------------------------------------------------------------

func test_a_player_who_is_not_up_cannot_roll() -> void:
	_refused(_state(), "p2", ROLL, ClimbErrors.NOT_YOUR_TURN)
	_refused(_state(), "p3", ROLL, ClimbErrors.NOT_YOUR_TURN)


func test_the_player_who_just_moved_cannot_roll_again() -> void:
	var after: Dictionary = rules.apply(_state(), "p1", ROLL)["state"]
	_refused(after, "p1", ROLL, ClimbErrors.NOT_YOUR_TURN)
	assert_true(CoreResult.is_ok(rules.apply(after, "p2", ROLL)))


func test_someone_who_is_not_in_the_game_cannot_roll() -> void:
	_refused(_state(), "stranger", ROLL, ErrorCodes.UNKNOWN_PLAYER)
	_refused(_state(), "", ROLL, ErrorCodes.UNKNOWN_PLAYER)
	_refused(_state(), "P1", ROLL, ErrorCodes.UNKNOWN_PLAYER)  # ids are exact


func test_a_player_who_is_away_cannot_roll_even_on_their_turn() -> void:
	_refused(_state(), "p1", ROLL, ClimbErrors.PLAYER_INACTIVE, ["p2", "p3"])


func test_an_empty_active_list_means_everyone_is_present() -> void:
	assert_true(CoreResult.is_ok(rules.apply(_state(), "p1", ROLL, [])))
	assert_true(CoreResult.is_ok(rules.apply(_state(), "p1", ROLL)))


# --- invalid actions ----------------------------------------------------------------------

func test_unknown_actions_are_refused() -> void:
	for type: String in ["move", "ROLL", "Roll", "roll ", "", "pass", "start", "quit", "roll2"]:
		_refused(_state(), "p1", {"type": type}, ErrorCodes.UNKNOWN_ACTION)


func test_actions_without_a_text_type_are_refused() -> void:
	_refused(_state(), "p1", {}, ErrorCodes.BAD_ACTION)
	_refused(_state(), "p1", {"action": "roll"}, ErrorCodes.BAD_ACTION)
	for junk: Variant in [null, 5, true, ["roll"], {"a": 1}, 1.5]:
		_refused(_state(), "p1", {"type": junk}, ErrorCodes.BAD_ACTION)


func test_a_roll_cannot_carry_a_dice_value_so_clients_cannot_pick_their_dice() -> void:
	for extra: Dictionary in [{"value": 6}, {"dice": [6]}, {"roll": 6}, {"total": 6}, {"seed": 1}, {"anything": null}]:
		var action: Dictionary = {"type": "roll"}
		action.merge(extra)
		_refused(_state(), "p1", action, ErrorCodes.BAD_ACTION)


func test_a_malformed_action_is_reported_before_whose_turn_it_is() -> void:
	_refused(_state(), "p2", {"type": "move"}, ErrorCodes.UNKNOWN_ACTION)
	_refused(_state(), "stranger", {"type": 5}, ErrorCodes.BAD_ACTION)


# --- game over ------------------------------------------------------------------------------

func _finished() -> Dictionary:
	var state: Dictionary = ClimbRig.game([4], ["p1", "p2", "p3"], {}, {"p1": 96})
	var result: Dictionary = rules.apply(state, "p1", ROLL)
	assert_eq(result["state"]["phase"], "finished")
	return result["state"]


func test_game_over_locks_every_further_action() -> void:
	var state: Dictionary = _finished()
	for player: String in ["p1", "p2", "p3"]:
		_refused(state, player, ROLL, ClimbErrors.GAME_OVER)


func test_game_over_is_reported_even_for_strangers_and_absent_players() -> void:
	var state: Dictionary = _finished()
	_refused(state, "stranger", ROLL, ClimbErrors.GAME_OVER)
	_refused(state, "p2", ROLL, ClimbErrors.GAME_OVER, ["p3"])


func test_a_malformed_action_is_still_refused_as_malformed_after_game_over() -> void:
	_refused(_finished(), "p1", {"type": "move"}, ErrorCodes.UNKNOWN_ACTION)


func test_the_finished_state_stays_exactly_the_same_however_many_times_it_is_poked() -> void:
	var state: Dictionary = _finished()
	var snapshot: Dictionary = state.duplicate(true)
	for _i: int in 20:
		rules.apply(state, "p1", ROLL)
		rules.apply(state, "p2", ROLL)
	assert_eq(state, snapshot)


# --- damaged state ------------------------------------------------------------------------------

func test_a_damaged_state_is_refused_instead_of_crashing() -> void:
	for key: String in ["positions", "board", "settings", "players", "rng", "phase", "current_player"]:
		var broken: Dictionary = _state()
		broken.erase(key)
		_refused(broken, "p1", ROLL, ClimbErrors.INVALID_STATE)
	var wrong_types: Dictionary = _state()
	wrong_types["positions"] = "nope"
	_refused(wrong_types, "p1", ROLL, ClimbErrors.INVALID_STATE)
	var bad_rng: Dictionary = _state()
	bad_rng["rng"]["state"] = "garbage"
	_refused(bad_rng, "p1", ROLL, ClimbErrors.INVALID_STATE)
	var rng_numbers: Dictionary = _state()
	rng_numbers["rng"] = {"seed": 1, "state": 2}
	_refused(rng_numbers, "p1", ROLL, ClimbErrors.INVALID_STATE)


# --- the refusals leave the game playable -----------------------------------------------------------

func test_a_refused_action_does_not_consume_a_die() -> void:
	var state: Dictionary = _state()
	rules.apply(state, "p2", ROLL)  # refused: not p2's turn
	rules.apply(state, "p1", {"type": "move"})  # refused
	var after: Dictionary = rules.apply(state, "p1", ROLL)
	assert_eq(after["state"]["last_roll"]["dice"], [3], "p1 still gets the first die of the sequence")
