extends GutTest
## Movement, jumps, finishing, extra turns and turn rotation. Dice are rigged with ClimbRig.

const ROLL: Dictionary = {"type": "roll"}

var rules: ClimbAndSlitherRules


func before_each() -> void:
	rules = ClimbAndSlitherRules.new()


func _roll(state: Dictionary, player: String = "") -> Dictionary:
	var who: String = player if player != "" else state["current_player"]
	var result: Dictionary = rules.apply(state, who, ROLL)
	assert_true(CoreResult.is_ok(result), "roll failed: %s" % str(result))
	return result


func _types(result: Dictionary) -> Array[String]:
	return ClimbRig.event_types(result["events"])


func _valid(state: Dictionary) -> void:
	var r: Dictionary = rules.validate_state(state)
	assert_true(CoreResult.is_ok(r), "state invalid after a move: %s" % str(r))


# --- plain movement ------------------------------------------------------------------

func test_a_roll_moves_the_current_player_by_the_dice() -> void:
	var state: Dictionary = ClimbRig.game([4])
	var result: Dictionary = _roll(state)
	var next: Dictionary = result["state"]
	assert_eq(next["positions"]["p1"], 4)
	assert_eq(next["positions"]["p2"], 0)
	assert_eq(next["last_roll"], {"player_id": "p1", "dice": [4], "total": 4})
	assert_eq(next["rolls"], 1)
	assert_eq(next["turn_number"], 2)
	assert_eq(next["current_player"], "p2")
	assert_eq(_types(result), ["rolled", "moved", "turn_changed"] as Array[String])
	_valid(next)


func test_every_die_value_moves_that_many_squares() -> void:
	for value: int in range(1, 7):
		var state: Dictionary = ClimbRig.game([value], ["p1", "p2"], {}, {"p1": 50}, ClimbRig.board())
		assert_eq(_roll(state)["state"]["positions"]["p1"], 50 + value)


func test_the_moved_event_lists_every_square_walked() -> void:
	var result: Dictionary = _roll(ClimbRig.game([4], ["p1", "p2"], {}, {"p1": 10}, ClimbRig.board()))
	var moved: Dictionary = result["events"][1]
	assert_eq(moved, {"type": "moved", "player_id": "p1", "from": 10, "to": 14, "path": [11, 12, 13, 14]})


func test_a_new_player_enters_the_board_from_square_zero() -> void:
	var state: Dictionary = ClimbRig.game([3], ["p1", "p2"], {}, {}, ClimbRig.board())
	assert_eq(state["positions"]["p1"], 0)
	assert_eq(_roll(state)["state"]["positions"]["p1"], 3)


func test_players_may_share_a_square() -> void:
	var state: Dictionary = ClimbRig.game([3, 3], ["p1", "p2"], {}, {}, ClimbRig.board())
	var after: Dictionary = _roll(_roll(state)["state"])["state"]
	assert_eq(after["positions"], {"p1": 3, "p2": 3})
	_valid(after)


# --- snakes and ladders ----------------------------------------------------------------

func test_landing_on_a_ladder_climbs_it() -> void:
	var result: Dictionary = _roll(ClimbRig.game([5]))  # classic: ladder 5 -> 27
	assert_eq(result["state"]["positions"]["p1"], 27)
	assert_eq(_types(result), ["rolled", "moved", "jumped", "turn_changed"] as Array[String])
	assert_eq(result["events"][1]["to"], 5, "the walk ends on the ladder's foot")
	assert_eq(result["events"][2], {"type": "jumped", "player_id": "p1", "kind": "ladder", "from": 5, "to": 27})


func test_landing_on_a_snake_slides_down_it() -> void:
	var result: Dictionary = _roll(ClimbRig.game([4], ["p1", "p2"], {}, {"p1": 20}))  # classic: snake 24 -> 2
	assert_eq(result["state"]["positions"]["p1"], 2)
	assert_eq(result["events"][2], {"type": "jumped", "player_id": "p1", "kind": "snake", "from": 24, "to": 2})


func test_landing_on_the_end_of_a_jump_does_nothing_more() -> void:
	var on_tail: Dictionary = _roll(ClimbRig.game([2]))  # square 2 is the tail of the 24 snake
	assert_eq(on_tail["state"]["positions"]["p1"], 2)
	assert_eq(_types(on_tail), ["rolled", "moved", "turn_changed"] as Array[String])
	var on_top: Dictionary = _roll(ClimbRig.game([6], ["p1", "p2"], {}, {"p1": 21}))  # 27 is the top of the 5 ladder
	assert_eq(on_top["state"]["positions"]["p1"], 27)
	assert_false(_types(on_top).has("jumped"))


func test_walking_over_a_jump_square_does_not_trigger_it() -> void:
	var result: Dictionary = _roll(ClimbRig.game([4], ["p1", "p2"], {}, {"p1": 2}))  # passes the foot of the ladder on 5
	assert_eq(result["state"]["positions"]["p1"], 6)
	assert_false(_types(result).has("jumped"))


func test_two_snakes_can_share_a_tail() -> void:
	# classic: 70 -> 34 and 76 -> 34
	assert_eq(_roll(ClimbRig.game([4], ["p1", "p2"], {}, {"p1": 66}))["state"]["positions"]["p1"], 34)
	assert_eq(_roll(ClimbRig.game([2], ["p1", "p2"], {}, {"p1": 74}))["state"]["positions"]["p1"], 34)


func test_a_landing_triggers_only_one_jump_even_next_to_another_jump() -> void:
	# ladder 5 -> 20 ends right beside the snake that starts on 21: no chaining
	var board: Dictionary = ClimbRig.board([ClimbRig.jump(21, 3)], [ClimbRig.jump(5, 20)], 30, 6)
	var result: Dictionary = _roll(ClimbRig.game([5], ["p1", "p2"], {}, {}, board))
	assert_eq(result["state"]["positions"]["p1"], 20)
	assert_eq(_types(result).count("jumped"), 1)


func test_a_ladder_to_the_last_square_wins() -> void:
	var board: Dictionary = ClimbRig.board([], [ClimbRig.jump(10, 30)], 30, 6)
	var result: Dictionary = _roll(ClimbRig.game([5], ["p1", "p2"], {}, {"p1": 5}, board))
	assert_eq(result["state"]["positions"]["p1"], 30)
	assert_eq(result["state"]["phase"], "finished")
	assert_eq(result["state"]["winner"], "p1")
	assert_eq(_types(result), ["rolled", "moved", "jumped", "won"] as Array[String])
	_valid(result["state"])


func test_jumps_work_for_every_player_in_turn() -> void:
	var state: Dictionary = ClimbRig.game([5, 5])  # both climb the 5 ladder
	var after: Dictionary = _roll(_roll(state)["state"])["state"]
	assert_eq(after["positions"], {"p1": 27, "p2": 27})


# --- finishing ----------------------------------------------------------------------------

func test_an_exact_roll_to_the_last_square_wins() -> void:
	var result: Dictionary = _roll(ClimbRig.game([4], ["p1", "p2"], {}, {"p1": 96}))
	var next: Dictionary = result["state"]
	assert_eq(next["positions"]["p1"], 100)
	assert_eq(next["phase"], "finished")
	assert_eq(next["winner"], "p1")
	assert_eq(next["current_player"], "p1", "the winner stays current")
	assert_false(next["extra_turn"])
	assert_eq(_types(result), ["rolled", "moved", "won"] as Array[String])
	assert_eq(result["events"][1]["path"], [97, 98, 99, 100])
	assert_eq(result["events"][2], {"type": "won", "player_id": "p1"})
	_valid(next)


func test_overshooting_without_exact_finish_lands_on_the_last_square_and_wins() -> void:
	var result: Dictionary = _roll(ClimbRig.game([6], ["p1", "p2"], {}, {"p1": 98}))
	assert_eq(result["state"]["positions"]["p1"], 100)
	assert_eq(result["state"]["winner"], "p1")
	assert_eq(result["events"][1], {"type": "moved", "player_id": "p1", "from": 98, "to": 100, "path": [99, 100]})


func test_overshooting_with_exact_finish_does_not_move() -> void:
	var state: Dictionary = ClimbRig.game([6], ["p1", "p2"], {"exact_finish": true}, {"p1": 98})
	var result: Dictionary = _roll(state)
	var next: Dictionary = result["state"]
	assert_eq(next["positions"]["p1"], 98)
	assert_eq(next["phase"], "in_progress")
	assert_eq(next["winner"], "")
	assert_eq(next["current_player"], "p2", "the turn passes")
	assert_eq(next["rolls"], 1)
	assert_eq(next["last_roll"]["total"], 6)
	assert_eq(_types(result), ["rolled", "overshoot", "turn_changed"] as Array[String])
	assert_eq(result["events"][1], {"type": "overshoot", "player_id": "p1", "from": 98, "needed": 2})
	_valid(next)


func test_exact_finish_still_lets_the_exact_roll_win() -> void:
	var result: Dictionary = _roll(ClimbRig.game([2], ["p1", "p2"], {"exact_finish": true}, {"p1": 98}))
	assert_eq(result["state"]["winner"], "p1")


func test_exact_finish_lets_a_short_roll_move_normally() -> void:
	var result: Dictionary = _roll(ClimbRig.game([1], ["p1", "p2"], {"exact_finish": true}, {"p1": 98}))
	assert_eq(result["state"]["positions"]["p1"], 61, "98 + 1 = 99, the head of a snake on the classic board")
	assert_eq(result["state"]["phase"], "in_progress")


func test_a_player_needing_one_stays_put_on_every_roll_but_a_one_with_exact_finish() -> void:
	var board: Dictionary = ClimbRig.board()
	for value: int in range(2, 7):
		var state: Dictionary = ClimbRig.game([value], ["p1", "p2"], {"exact_finish": true}, {"p1": 99}, board)
		var next: Dictionary = _roll(state)["state"]
		assert_eq(next["positions"]["p1"], 99, "rolled %d" % value)
	var winning: Dictionary = ClimbRig.game([1], ["p1", "p2"], {"exact_finish": true}, {"p1": 99}, board)
	assert_eq(_roll(winning)["state"]["winner"], "p1")


func test_two_dice_add_up_for_the_exact_finish() -> void:
	var state: Dictionary = ClimbRig.game([[4, 6]], ["p1", "p2"], {"exact_finish": true, "dice_count": 2}, {"p1": 90}, ClimbRig.board())
	var result: Dictionary = _roll(state)
	assert_eq(result["state"]["winner"], "p1")
	assert_eq(result["events"][0]["dice"], [4, 6])
	assert_eq(result["events"][0]["total"], 10)


func test_two_dice_overshoot_with_exact_finish_does_not_move() -> void:
	var state: Dictionary = ClimbRig.game([[5, 4]], ["p1", "p2"], {"exact_finish": true, "dice_count": 2}, {"p1": 95}, ClimbRig.board())
	var result: Dictionary = _roll(state)
	assert_eq(result["state"]["positions"]["p1"], 95)
	assert_true(_types(result).has("overshoot"))


func test_the_game_is_over_once_someone_wins() -> void:
	var finished: Dictionary = _roll(ClimbRig.game([4, 1], ["p1", "p2"], {}, {"p1": 96}))["state"]
	var again: Dictionary = rules.apply(finished, "p2", ROLL)
	assert_eq(CoreResult.error_code(again), ClimbErrors.GAME_OVER)
	assert_eq(CoreResult.error_code(rules.apply(finished, "p1", ROLL)), ClimbErrors.GAME_OVER, "even the winner")


# --- extra turn on a six --------------------------------------------------------------------

func test_a_six_gives_an_extra_turn_when_the_house_rule_is_on() -> void:
	var state: Dictionary = ClimbRig.game([6, 3, 2], ["p1", "p2"], {"extra_turn_on_six": true}, {}, ClimbRig.board())
	var first: Dictionary = _roll(state)
	assert_eq(first["state"]["current_player"], "p1", "p1 rolls again")
	assert_true(first["state"]["extra_turn"])
	assert_eq(first["state"]["turn_number"], 1, "the turn has not passed")
	assert_eq(_types(first), ["rolled", "moved", "extra_turn"] as Array[String])
	assert_false(_types(first).has("turn_changed"))
	_valid(first["state"])
	var second: Dictionary = _roll(first["state"])
	assert_eq(second["state"]["positions"]["p1"], 9)
	assert_eq(second["state"]["current_player"], "p2", "now the turn passes")
	assert_false(second["state"]["extra_turn"])
	assert_eq(second["state"]["turn_number"], 2)
	assert_eq(_roll(second["state"])["state"]["positions"]["p2"], 2)


func test_several_sixes_in_a_row_keep_the_turn_with_no_cap() -> void:
	var state: Dictionary = ClimbRig.game([6, 6, 6, 1], ["p1", "p2"], {"extra_turn_on_six": true}, {}, ClimbRig.board())
	for _i: int in 3:
		state = _roll(state)["state"]
		assert_eq(state["current_player"], "p1")
		assert_true(state["extra_turn"])
	assert_eq(state["positions"]["p1"], 18)
	state = _roll(state)["state"]
	assert_eq(state["positions"]["p1"], 19)
	assert_eq(state["current_player"], "p2")
	assert_eq(state["rolls"], 4)


func test_a_six_passes_the_turn_when_the_house_rule_is_off() -> void:
	var result: Dictionary = _roll(ClimbRig.game([6]))
	assert_eq(result["state"]["current_player"], "p2")
	assert_false(result["state"]["extra_turn"])
	assert_false(_types(result).has("extra_turn"))


func test_the_extra_turn_is_kept_after_an_exact_finish_overshoot() -> void:
	var state: Dictionary = ClimbRig.game([6], ["p1", "p2"], {"exact_finish": true, "extra_turn_on_six": true}, {"p1": 98})
	var result: Dictionary = _roll(state)
	assert_eq(result["state"]["positions"]["p1"], 98)
	assert_eq(result["state"]["current_player"], "p1")
	assert_eq(_types(result), ["rolled", "overshoot", "extra_turn"] as Array[String])


func test_the_extra_turn_is_kept_when_the_six_lands_on_a_snake() -> void:
	var state: Dictionary = ClimbRig.game([6], ["p1", "p2"], {"extra_turn_on_six": true}, {"p1": 18})  # 18 + 6 = 24, a snake
	var result: Dictionary = _roll(state)
	assert_eq(result["state"]["positions"]["p1"], 2)
	assert_eq(_types(result), ["rolled", "moved", "jumped", "extra_turn"] as Array[String])
	assert_eq(result["state"]["current_player"], "p1")


func test_a_winning_six_gives_no_extra_turn() -> void:
	var state: Dictionary = ClimbRig.game([6], ["p1", "p2"], {"extra_turn_on_six": true}, {"p1": 24}, ClimbRig.board([], [], 30, 6))
	var result: Dictionary = _roll(state)
	assert_eq(result["state"]["winner"], "p1")
	assert_false(result["state"]["extra_turn"])
	assert_eq(_types(result), ["rolled", "moved", "won"] as Array[String])


func test_other_numbers_never_give_an_extra_turn() -> void:
	for value: int in range(1, 6):
		var state: Dictionary = ClimbRig.game([value], ["p1", "p2"], {"extra_turn_on_six": true}, {}, ClimbRig.board())
		assert_eq(_roll(state)["state"]["current_player"], "p2", "rolled %d" % value)


func test_two_dice_extra_turn_needs_a_six_on_either_die() -> void:
	var settings: Dictionary = {"extra_turn_on_six": true, "dice_count": 2}
	for dice: Array in [[6, 2], [2, 6], [6, 6]]:
		var result: Dictionary = _roll(ClimbRig.game([dice], ["p1", "p2"], settings, {}, ClimbRig.board()))
		assert_eq(result["state"]["current_player"], "p1", "dice %s" % str(dice))
		assert_eq(_types(result).count("extra_turn"), 1, "one extra turn, not two, for %s" % str(dice))
	for dice: Array in [[3, 4], [5, 5], [1, 1]]:
		var result: Dictionary = _roll(ClimbRig.game([dice], ["p1", "p2"], settings, {}, ClimbRig.board()))
		assert_eq(result["state"]["current_player"], "p2", "dice %s" % str(dice))


func test_two_dice_move_by_their_sum_and_report_both() -> void:
	var result: Dictionary = _roll(ClimbRig.game([[3, 5]], ["p1", "p2"], {"dice_count": 2}, {"p1": 30}, ClimbRig.board()))
	assert_eq(result["state"]["positions"]["p1"], 38)
	assert_eq(result["state"]["last_roll"], {"player_id": "p1", "dice": [3, 5], "total": 8})
	assert_eq(result["events"][0], {"type": "rolled", "player_id": "p1", "dice": [3, 5], "total": 8})


# --- turn rotation ----------------------------------------------------------------------------

func test_turns_rotate_in_seat_order_and_wrap_around() -> void:
	for count: int in [2, 3, 4]:
		var ids: Array = ["p1", "p2", "p3", "p4"].slice(0, count)
		var state: Dictionary = ClimbRig.game([1, 1, 1, 1, 1], ids, {}, {}, ClimbRig.board())
		var seen: Array[String] = []
		for _i: int in count + 1:
			seen.append(state["current_player"])
			state = _roll(state)["state"]
		var expected: Array[String] = []
		for i: int in count + 1:
			expected.append(ids[i % count])
		assert_eq(seen, expected, "%d players" % count)


func test_turn_number_goes_up_only_when_the_turn_passes() -> void:
	var state: Dictionary = ClimbRig.game([6, 2], ["p1", "p2"], {"extra_turn_on_six": true}, {}, ClimbRig.board())
	assert_eq(state["turn_number"], 1)
	state = _roll(state)["state"]
	assert_eq(state["turn_number"], 1, "extra turn")
	assert_eq(state["rolls"], 1)
	state = _roll(state)["state"]
	assert_eq(state["turn_number"], 2)
	assert_eq(state["rolls"], 2)


func test_the_turn_changed_event_names_the_next_player() -> void:
	var result: Dictionary = _roll(ClimbRig.game([2], ["a", "b", "c"], {}, {}, ClimbRig.board()))
	assert_eq(result["events"].back(), {"type": "turn_changed", "player_id": "b"})


# --- apply is pure ---------------------------------------------------------------------------------

func test_apply_does_not_change_the_state_it_is_given() -> void:
	var state: Dictionary = ClimbRig.game([5])
	var snapshot: Dictionary = state.duplicate(true)
	var result: Dictionary = _roll(state)
	assert_eq(state, snapshot, "the input is untouched")
	result["state"]["positions"]["p1"] = 99
	result["state"]["board"]["snakes"].clear()
	assert_eq(state, snapshot, "the result shares nothing with the input")


func test_the_same_state_and_action_always_give_the_same_result() -> void:
	var state: Dictionary = ClimbRig.game([4, 2, 6])
	var a: Dictionary = rules.apply(state, "p1", ROLL)
	var b: Dictionary = rules.apply(state, "p1", ROLL)
	assert_eq(a, b)


func test_the_dice_come_from_the_state_not_from_the_caller() -> void:
	# two games with different seeds roll differently from the same position
	var one: Dictionary = ClimbRig.game([1])
	var two: Dictionary = ClimbRig.game([6])
	assert_ne(_roll(one)["state"]["last_roll"]["total"], _roll(two)["state"]["last_roll"]["total"])


func test_each_roll_advances_the_generator_state() -> void:
	var state: Dictionary = ClimbRig.game([3, 3])
	var after: Dictionary = _roll(state)["state"]
	assert_ne(after["rng"]["state"], state["rng"]["state"])
	assert_eq(after["rng"]["seed"], state["rng"]["seed"])


func test_every_state_along_a_game_stays_valid() -> void:
	var state: Dictionary = ClimbRig.game([1, 2, 3, 4, 5], ["p1", "p2", "p3"])
	for _i: int in 5:
		state = _roll(state)["state"]
		_valid(state)
