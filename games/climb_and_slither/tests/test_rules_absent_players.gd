extends GutTest
## Turn rotation with players who are away (active_players), and settle().

const ROLL: Dictionary = {"type": "roll"}

var rules: ClimbAndSlitherRules


func before_each() -> void:
	rules = ClimbAndSlitherRules.new()


func _four(rolls: Array, settings: Dictionary = {}) -> Dictionary:
	return ClimbRig.game(rolls, ["p1", "p2", "p3", "p4"], settings, {}, ClimbRig.board())


func _roll(state: Dictionary, player: String, active: Array = []) -> Dictionary:
	var result: Dictionary = rules.apply(state, player, ROLL, active)
	assert_true(CoreResult.is_ok(result), str(result))
	return result


func _settle(state: Dictionary, active: Array) -> Dictionary:
	var result: Dictionary = rules.settle(state, active)
	assert_true(CoreResult.is_ok(result), str(result))
	return result


# --- apply skips absent players ---------------------------------------------------------

func test_the_turn_skips_players_who_are_away() -> void:
	var result: Dictionary = _roll(_four([2, 2]), "p1", ["p1", "p3", "p4"])
	assert_eq(result["state"]["current_player"], "p3", "p2 is away")
	assert_eq(result["events"].back(), {"type": "turn_changed", "player_id": "p3"})


func test_several_absent_players_in_a_row_are_all_skipped() -> void:
	var result: Dictionary = _roll(_four([2]), "p1", ["p1", "p4"])
	assert_eq(result["state"]["current_player"], "p4")


func test_the_turn_wraps_past_absent_players_back_to_the_start() -> void:
	var state: Dictionary = _four([2, 2, 2])
	var active: Array = ["p1", "p3"]
	state = _roll(state, "p1", active)["state"]
	assert_eq(state["current_player"], "p3")
	state = _roll(state, "p3", active)["state"]
	assert_eq(state["current_player"], "p1", "wraps over the absent p4 and p2")


func test_a_returning_player_gets_their_turn_in_their_own_seat() -> void:
	var state: Dictionary = _four([1, 1, 1, 1])
	state = _roll(state, "p1", ["p1", "p3", "p4"])["state"]  # p2 away: p3 next
	assert_eq(state["current_player"], "p3")
	state = _roll(state, "p3", ["p1", "p2", "p3", "p4"])["state"]  # p2 is back
	assert_eq(state["current_player"], "p4")
	state = _roll(state, "p4", ["p1", "p2", "p3", "p4"])["state"]
	assert_eq(state["current_player"], "p1")
	state = _roll(state, "p1", ["p1", "p2", "p3", "p4"])["state"]
	assert_eq(state["current_player"], "p2", "p2 plays again in seat order")


func test_one_present_player_keeps_getting_the_turn() -> void:
	var state: Dictionary = _four([2, 2])
	state = _roll(state, "p1", ["p1"])["state"]
	assert_eq(state["current_player"], "p1")
	assert_eq(state["turn_number"], 2)
	var result: Dictionary = _roll(state, "p1", ["p1"])
	assert_eq(result["state"]["current_player"], "p1")
	assert_eq(result["events"].back(), {"type": "turn_changed", "player_id": "p1"})


func test_unknown_ids_in_the_active_list_are_ignored() -> void:
	var result: Dictionary = _roll(_four([2]), "p1", ["ghost", "p1", "p3", "nobody"])
	assert_eq(result["state"]["current_player"], "p3")


func test_the_active_order_does_not_matter_only_the_seat_order() -> void:
	var result: Dictionary = _roll(_four([2]), "p1", ["p4", "p3", "p1"])
	assert_eq(result["state"]["current_player"], "p3")


func test_an_extra_turn_stays_with_the_same_player_even_with_others_away() -> void:
	var state: Dictionary = _four([6, 2], {"extra_turn_on_six": true})
	var result: Dictionary = _roll(state, "p1", ["p1", "p3"])
	assert_eq(result["state"]["current_player"], "p1")
	assert_true(result["state"]["extra_turn"])


# --- settle ------------------------------------------------------------------------------------------

func test_settle_hands_the_turn_on_when_the_current_player_is_away() -> void:
	var state: Dictionary = _four([2])
	var result: Dictionary = _settle(state, ["p2", "p3", "p4"])
	assert_eq(result["state"]["current_player"], "p2")
	assert_eq(result["state"]["turn_number"], 2)
	assert_eq(result["events"], [
		{"type": "turn_skipped", "player_id": "p1"},
		{"type": "turn_changed", "player_id": "p2"},
	])


func test_settle_clears_a_pending_extra_turn_when_it_hands_the_turn_over() -> void:
	var state: Dictionary = _four([6, 3], {"extra_turn_on_six": true})
	state = _roll(state, "p1")["state"]  # a six: p1 owes an extra roll
	assert_true(state["extra_turn"])
	assert_eq(state["current_player"], "p1")
	var settled: Dictionary = _settle(state, ["p2", "p3", "p4"])  # p1 drops before using it
	assert_eq(settled["state"]["current_player"], "p2")
	assert_false(settled["state"]["extra_turn"], "the extra turn belonged to p1 and is gone")
	assert_true(CoreResult.is_ok(rules.validate_state(settled["state"])))
	# p2's next roll is an ordinary roll, and p1 cannot use the lost turn
	assert_eq(CoreResult.error_code(rules.apply(settled["state"], "p1", ROLL)), ClimbErrors.NOT_YOUR_TURN)
	var p2_roll: Dictionary = _roll(settled["state"], "p2")
	assert_eq(p2_roll["state"]["current_player"], "p3")


func test_the_player_who_got_the_turn_from_settle_does_not_inherit_the_extra_turn_flag() -> void:
	var state: Dictionary = _four([6, 2], {"extra_turn_on_six": true})
	state = _roll(state, "p1")["state"]
	var settled: Dictionary = _settle(state, ["p3", "p4"])
	assert_eq(settled["state"]["current_player"], "p3")
	assert_false(settled["state"]["extra_turn"])
	var after: Dictionary = _roll(settled["state"], "p3", ["p3", "p4"])
	assert_eq(after["state"]["current_player"], "p4", "a normal turn, so it moves on")


func test_settle_does_nothing_when_the_current_player_is_present() -> void:
	var state: Dictionary = _four([2])
	var result: Dictionary = _settle(state, ["p1", "p3"])
	assert_eq(result["state"], state)
	assert_eq(result["events"], [])


func test_settle_with_an_empty_list_means_everybody_and_changes_nothing() -> void:
	var state: Dictionary = _four([2])
	assert_eq(_settle(state, [])["state"], state)


func test_settle_does_nothing_after_the_game_is_over() -> void:
	var state: Dictionary = ClimbRig.game([4], ["p1", "p2"], {}, {"p1": 96})
	var finished: Dictionary = _roll(state, "p1")["state"]
	var result: Dictionary = _settle(finished, ["p2"])
	assert_eq(result["state"], finished)
	assert_eq(result["events"], [])


func test_settle_skips_over_several_absent_seats() -> void:
	var settled: Dictionary = _settle(_four([2]), ["p4"])
	assert_eq(settled["state"]["current_player"], "p4")
	var wrapped: Dictionary = _settle(_four([2, 2, 2]), ["p1", "p3"])
	assert_eq(wrapped["state"]["current_player"], "p1", "p1 is present: nothing to do")


func test_settle_wraps_around_the_table() -> void:
	var state: Dictionary = _four([2, 2, 2])
	state = _roll(state, "p1")["state"]
	state = _roll(state, "p2")["state"]
	state = _roll(state, "p3")["state"]
	assert_eq(state["current_player"], "p4")
	var settled: Dictionary = _settle(state, ["p2", "p3"])
	assert_eq(settled["state"]["current_player"], "p2", "from p4 the next present seat is p2")


func test_settle_fails_if_nobody_from_this_game_is_present() -> void:
	var state: Dictionary = _four([2])
	var snapshot: Dictionary = state.duplicate(true)
	var result: Dictionary = rules.settle(state, ["ghost", "nobody"])
	assert_eq(CoreResult.error_code(result), ClimbErrors.NO_ACTIVE_PLAYERS)
	assert_eq(state, snapshot)


func test_settle_does_not_change_its_input() -> void:
	var state: Dictionary = _four([2])
	var snapshot: Dictionary = state.duplicate(true)
	var result: Dictionary = _settle(state, ["p3"])
	assert_eq(state, snapshot)
	result["state"]["positions"]["p1"] = 50
	assert_eq(state, snapshot)


func test_settle_refuses_a_damaged_state() -> void:
	var state: Dictionary = _four([2])
	state.erase("players")
	assert_eq(CoreResult.error_code(rules.settle(state, ["p2"])), ClimbErrors.INVALID_STATE)


func test_after_settle_the_absent_player_returns_and_rotation_includes_them_again() -> void:
	var state: Dictionary = _four([2, 2, 2, 2])
	state = _settle(state, ["p2", "p3", "p4"])["state"]  # p1 away, p2 up
	state = _roll(state, "p2", ["p2", "p3", "p4"])["state"]
	state = _roll(state, "p3", ["p1", "p2", "p3", "p4"])["state"]  # p1 is back
	state = _roll(state, "p4", ["p1", "p2", "p3", "p4"])["state"]
	assert_eq(state["current_player"], "p1", "p1 has their turn again")


func test_states_stay_valid_through_skips_and_settles() -> void:
	var state: Dictionary = _four([1, 2, 3, 4, 5])
	state = _settle(state, ["p3", "p4"])["state"]
	assert_true(CoreResult.is_ok(rules.validate_state(state)))
	state = _roll(state, "p3", ["p3", "p4"])["state"]
	assert_true(CoreResult.is_ok(rules.validate_state(state)))
