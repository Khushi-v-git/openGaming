extends GutTest

const TMP_DIR: String = "user://test_boards"


func after_each() -> void:
	for name: String in ["ok.json", "broken.json", "list.json", "bad_board.json"]:
		var path: String = "%s/%s" % [TMP_DIR, name]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(TMP_DIR)


func _data(snakes: Array, ladders: Array, size: int = 20, columns: int = 5) -> Dictionary:
	return {"name": "Test", "size": size, "columns": columns, "snakes": snakes, "ladders": ladders}


func _jump(from: int, to: int) -> Dictionary:
	return {"from": from, "to": to}


func _error(data: Dictionary) -> String:
	return CoreResult.error_code(ClimbBoard.validate(data))


func _message(data: Dictionary) -> String:
	var r: Dictionary = ClimbBoard.validate(data)
	return "" if CoreResult.is_ok(r) else str(r["error"]["message"])


func _write(name: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var path: String = "%s/%s" % [TMP_DIR, name]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


# --- the shipped classic board -----------------------------------------------------

func test_the_classic_board_loads_and_is_valid() -> void:
	var r: Dictionary = ClimbBoard.load_file()
	assert_true(CoreResult.is_ok(r), str(r))
	var board: Dictionary = r["board"]
	assert_eq(board["size"], 100)
	assert_eq(board["columns"], 10)
	assert_eq(board["name"], "Classic")
	assert_eq(board["ladders"].size(), 8)
	assert_eq(board["snakes"].size(), 11)


func test_the_classic_board_satisfies_every_rule_checked_independently_of_the_validator() -> void:
	# Raw JSON, no ClimbBoard code involved, so a validator bug cannot hide a bad board.
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ClimbBoard.DEFAULT_PATH))
	var size: int = int(parsed["size"])
	var starts: Dictionary = {}
	var ends: Dictionary = {}
	for entry: Dictionary in parsed["snakes"]:
		assert_lt(int(entry["to"]), int(entry["from"]), "snake %s goes down" % str(entry))
		assert_false(starts.has(int(entry["from"])), "start %d is unique" % int(entry["from"]))
		starts[int(entry["from"])] = "snake"
		ends[int(entry["to"])] = true
	for entry: Dictionary in parsed["ladders"]:
		assert_gt(int(entry["to"]), int(entry["from"]), "ladder %s goes up" % str(entry))
		assert_false(starts.has(int(entry["from"])), "start %d is unique" % int(entry["from"]))
		starts[int(entry["from"])] = "ladder"
		ends[int(entry["to"])] = true
	for square: int in starts:
		assert_gt(square, 1)
		assert_lt(square, size)
	for square: int in ends:
		assert_between(square, 1, size)
		assert_false(starts.has(square), "end %d is not also a start (no chains)" % square)
	assert_eq(parsed["snakes"].size() + parsed["ladders"].size(), starts.size())


func test_the_classic_board_has_a_shared_end_square_which_is_allowed() -> void:
	var board: Dictionary = ClimbBoard.load_file()["board"]
	var tails: Dictionary = {}
	for jump: Dictionary in board["snakes"]:
		tails[jump["to"]] = int(tails.get(jump["to"], 0)) + 1
	assert_eq(tails[34], 2, "two snakes end on 34")


func test_the_classic_board_is_stored_sorted_by_start_square() -> void:
	var board: Dictionary = ClimbBoard.load_file()["board"]
	for list: Array in [board["snakes"], board["ladders"]]:
		for i: int in range(1, list.size()):
			assert_lt(list[i - 1]["from"], list[i]["from"])


func test_validated_boards_are_plain_json_safe_data() -> void:
	var board: Dictionary = ClimbBoard.load_file()["board"]
	assert_true(Envelope.is_plain_data(board))
	assert_eq(Envelope.normalize(JSON.parse_string(JSON.stringify(board))), board)


# --- valid shapes ------------------------------------------------------------------

func test_a_board_with_no_jumps_is_valid() -> void:
	assert_true(CoreResult.is_ok(ClimbBoard.validate(_data([], []))))


func test_a_ladder_may_end_on_the_last_square_and_a_snake_on_square_one() -> void:
	var r: Dictionary = ClimbBoard.validate(_data([_jump(15, 1)], [_jump(10, 20)]))
	assert_true(CoreResult.is_ok(r), str(r))


func test_snakes_and_ladders_may_share_an_end_square() -> void:
	assert_true(CoreResult.is_ok(ClimbBoard.validate(_data([_jump(18, 8), _jump(15, 8)], [_jump(4, 8 + 5)]))))
	assert_true(CoreResult.is_ok(ClimbBoard.validate(_data([_jump(18, 12)], [_jump(4, 12), _jump(6, 12)]))))


func test_other_board_sizes_and_columns() -> void:
	assert_true(CoreResult.is_ok(ClimbBoard.validate(_data([], [], 10, 5))))
	assert_true(CoreResult.is_ok(ClimbBoard.validate(_data([], [], 64, 8))))
	assert_true(CoreResult.is_ok(ClimbBoard.validate(_data([], [], 400, 20))))


func test_integral_floats_from_json_are_accepted_and_become_ints() -> void:
	# built by hand: the _jump/_data helpers take ints and would hide the floats
	var floaty: Dictionary = {"name": "T", "size": 20.0, "columns": 5.0, "snakes": [{"from": 15.0, "to": 3.0}], "ladders": []}
	assert_eq(typeof(floaty["size"]), TYPE_FLOAT)
	var r: Dictionary = ClimbBoard.validate(floaty)
	assert_true(CoreResult.is_ok(r), str(r))
	assert_eq(typeof(r["board"]["size"]), TYPE_INT)
	assert_eq(typeof(r["board"]["snakes"][0]["from"]), TYPE_INT)


func test_validation_does_not_change_its_input() -> void:
	var data: Dictionary = _data([_jump(15, 3)], [_jump(4, 9)])
	var copy: Dictionary = data.duplicate(true)
	ClimbBoard.validate(data)
	assert_eq(data, copy)


# --- rule: no jump starts on square 1 or the last square -------------------------------

func test_no_snake_or_ladder_starts_on_square_one() -> void:
	assert_eq(_error(_data([_jump(1, 1)], [])), ClimbErrors.INVALID_BOARD)
	assert_string_contains(_message(_data([_jump(1, 1)], [])), "square 1")
	assert_string_contains(_message(_data([], [_jump(1, 9)])), "square 1")


func test_no_snake_or_ladder_starts_on_the_last_square() -> void:
	assert_string_contains(_message(_data([_jump(20, 3)], [])), "last square")
	assert_string_contains(_message(_data([], [_jump(20, 3)])), "last square")
	assert_eq(_error(_data([], [_jump(100, 2)], 100, 10)), ClimbErrors.INVALID_BOARD)


func test_starts_off_the_board_are_refused() -> void:
	for bad: int in [0, -4, 21, 500]:
		assert_eq(_error(_data([_jump(bad, 1)], [])), ClimbErrors.INVALID_BOARD, "start %d" % bad)
		assert_eq(_error(_data([], [_jump(bad, 20)])), ClimbErrors.INVALID_BOARD, "start %d" % bad)


func test_ends_off_the_board_are_refused() -> void:
	for bad: int in [0, -1, 21, 99]:
		assert_eq(_error(_data([_jump(15, bad)], [])), ClimbErrors.INVALID_BOARD, "snake end %d" % bad)
		assert_eq(_error(_data([], [_jump(3, bad)])), ClimbErrors.INVALID_BOARD, "ladder end %d" % bad)


# --- rule: no square is used twice as a start -------------------------------------------

func test_a_square_cannot_start_both_a_snake_and_a_ladder() -> void:
	var data: Dictionary = _data([_jump(10, 2)], [_jump(10, 15)])
	assert_eq(_error(data), ClimbErrors.INVALID_BOARD)
	assert_string_contains(_message(data), "both a snake and a ladder")
	assert_string_contains(_message(data), "10")


func test_a_square_cannot_start_two_snakes_or_two_ladders() -> void:
	assert_string_contains(_message(_data([_jump(12, 3), _jump(12, 5)], [])), "two snakes")
	assert_string_contains(_message(_data([], [_jump(4, 9), _jump(4, 12)])), "two ladders")


# --- rule: direction ------------------------------------------------------------------------

func test_snakes_must_go_down_and_ladders_must_go_up() -> void:
	assert_string_contains(_message(_data([_jump(5, 9)], [])), "must go down")
	assert_string_contains(_message(_data([_jump(5, 5)], [])), "must go down")
	assert_string_contains(_message(_data([], [_jump(9, 5)])), "must go up")
	assert_string_contains(_message(_data([], [_jump(9, 9)])), "must go up")


# --- rule: no chains, hence no loops ------------------------------------------------------

func test_a_jump_may_not_end_on_another_jumps_start() -> void:
	# snake -> ladder, ladder -> snake, snake -> snake, ladder -> ladder
	assert_string_contains(_message(_data([_jump(18, 4)], [_jump(4, 12)])), "may not chain")
	assert_string_contains(_message(_data([_jump(15, 2)], [_jump(3, 15)])), "may not chain")
	assert_string_contains(_message(_data([_jump(18, 12), _jump(12, 3)], [])), "may not chain")
	assert_string_contains(_message(_data([], [_jump(3, 8), _jump(8, 14)])), "may not chain")


func test_a_loop_is_refused_because_it_is_a_chain() -> void:
	# ladder 6 -> 14 and snake 14 -> 6: each ends where the other starts
	var data: Dictionary = _data([_jump(14, 6)], [_jump(6, 14)])
	assert_eq(_error(data), ClimbErrors.INVALID_BOARD)
	assert_string_contains(_message(data), "may not chain")


func test_the_chain_message_names_the_squares() -> void:
	var message: String = _message(_data([_jump(18, 4)], [_jump(4, 12)]))
	assert_string_contains(message, "18")
	assert_string_contains(message, "4")


func test_a_long_chain_is_refused_too() -> void:
	assert_eq(_error(_data([], [_jump(2, 5), _jump(5, 8), _jump(8, 11), _jump(11, 14)])), ClimbErrors.INVALID_BOARD)


# --- size and shape -------------------------------------------------------------------------

func test_bad_sizes_are_refused() -> void:
	for bad: Variant in [0, 9, 401, -100, "100", 100.5, null, true]:
		var data: Dictionary = _data([], [])
		data["size"] = bad
		assert_eq(_error(data), ClimbErrors.INVALID_BOARD, "size %s" % str(bad))
	var no_size: Dictionary = _data([], [])
	no_size.erase("size")
	assert_eq(_error(no_size), ClimbErrors.INVALID_BOARD)


func test_columns_must_divide_the_size() -> void:
	for bad: Variant in [0, 1, 3, 6, 21, 40, "5", null]:
		var data: Dictionary = _data([], [], 20, 5)
		data["columns"] = bad
		assert_eq(_error(data), ClimbErrors.INVALID_BOARD, "columns %s" % str(bad))


func test_jump_lists_must_be_lists_of_objects_with_int_squares() -> void:
	var no_snakes: Dictionary = _data([], [])
	no_snakes.erase("snakes")
	assert_eq(_error(no_snakes), ClimbErrors.INVALID_BOARD)
	var no_ladders: Dictionary = _data([], [])
	no_ladders.erase("ladders")
	assert_eq(_error(no_ladders), ClimbErrors.INVALID_BOARD)
	var bad_list: Dictionary = _data([], [])
	bad_list["snakes"] = "none"
	assert_eq(_error(bad_list), ClimbErrors.INVALID_BOARD)
	assert_eq(_error(_data([5], [])), ClimbErrors.INVALID_BOARD, "entry is not an object")
	assert_eq(_error(_data([{"from": 15}], [])), ClimbErrors.INVALID_BOARD, "missing 'to'")
	assert_eq(_error(_data([{"to": 3}], [])), ClimbErrors.INVALID_BOARD, "missing 'from'")
	assert_eq(_error(_data([{"from": 15.5, "to": 3}], [])), ClimbErrors.INVALID_BOARD, "fractional start")
	assert_eq(_error(_data([{"from": 15, "to": 3.5}], [])), ClimbErrors.INVALID_BOARD, "fractional end")
	assert_eq(_error(_data([{"from": "15", "to": 3}], [])), ClimbErrors.INVALID_BOARD, "text square")
	assert_eq(_error(_data([{"from": true, "to": 3}], [])), ClimbErrors.INVALID_BOARD, "boolean square")


func test_the_name_must_be_text_if_given() -> void:
	var data: Dictionary = _data([], [])
	data["name"] = 5
	assert_eq(_error(data), ClimbErrors.INVALID_BOARD)
	data.erase("name")
	assert_true(CoreResult.is_ok(ClimbBoard.validate(data)), "a nameless board gets a default name")


# --- jump_at ------------------------------------------------------------------------------------

func test_jump_at_finds_snakes_and_ladders_by_start_square() -> void:
	var board: Dictionary = ClimbBoard.validate(_data([_jump(15, 3)], [_jump(4, 9)]))["board"]
	assert_eq(ClimbBoard.jump_at(board, 15), {"kind": "snake", "from": 15, "to": 3})
	assert_eq(ClimbBoard.jump_at(board, 4), {"kind": "ladder", "from": 4, "to": 9})
	assert_eq(ClimbBoard.jump_at(board, 9), {}, "an end square is not a jump")
	assert_eq(ClimbBoard.jump_at(board, 3), {})
	assert_eq(ClimbBoard.jump_at(board, 0), {})
	assert_eq(ClimbBoard.jump_at(board, 7), {})


# --- loading ------------------------------------------------------------------------------------

func test_loading_a_file_validates_it() -> void:
	var path: String = _write("ok.json", JSON.stringify(_data([_jump(15, 3)], [_jump(4, 9)])))
	var r: Dictionary = ClimbBoard.load_file(path)
	assert_true(CoreResult.is_ok(r), str(r))
	assert_eq(r["board"]["snakes"], [{"from": 15, "to": 3}])


func test_a_file_with_an_invalid_board_is_refused() -> void:
	var path: String = _write("bad_board.json", JSON.stringify(_data([_jump(1, 1)], [])))
	var r: Dictionary = ClimbBoard.load_file(path)
	assert_eq(CoreResult.error_code(r), ClimbErrors.INVALID_BOARD)
	assert_string_contains(str(r["error"]["message"]), "square 1")


func test_missing_unreadable_and_non_object_files_are_refused_with_a_clear_message() -> void:
	var missing: Dictionary = ClimbBoard.load_file(TMP_DIR + "/nope.json")
	assert_eq(CoreResult.error_code(missing), ClimbErrors.INVALID_BOARD)
	assert_string_contains(str(missing["error"]["message"]), "no board file")
	var broken: Dictionary = ClimbBoard.load_file(_write("broken.json", "{ not json"))
	assert_eq(CoreResult.error_code(broken), ClimbErrors.INVALID_BOARD)
	assert_string_contains(str(broken["error"]["message"]), "not valid JSON")
	var list: Dictionary = ClimbBoard.load_file(_write("list.json", "[1, 2]"))
	assert_eq(CoreResult.error_code(list), ClimbErrors.INVALID_BOARD)
	assert_string_contains(str(list["error"]["message"]), "JSON object")


# --- the last square must be reachable (winnability) --------------------------------------------

## `count` snake heads on consecutive squares starting at `first`, all sliding down to square 1.
func _heads(first: int, count: int) -> Array:
	var snakes: Array = []
	for square: int in range(first, first + count):
		snakes.append(_jump(square, 1))
	return snakes


func test_a_board_whose_last_six_squares_are_all_snake_heads_is_refused() -> void:
	# size 20: heads on 14..19 and nothing leads to the last square, so nobody can ever finish
	var data: Dictionary = _data(_heads(14, 6), [])
	assert_eq(_error(data), ClimbErrors.INVALID_BOARD)
	var message: String = _message(data)
	assert_string_contains(message, "last square")
	assert_string_contains(message, "(20)")
	assert_string_contains(message, "can never be reached")
	assert_string_contains(message, "square 13", "it says how far anyone can get")


func test_the_same_six_snake_heads_are_fine_if_a_ladder_goes_straight_to_the_last_square() -> void:
	var r: Dictionary = ClimbBoard.validate(_data(_heads(14, 6), [_jump(5, 20)]))
	assert_true(CoreResult.is_ok(r), str(r))


func test_five_snake_heads_in_a_row_can_be_crossed() -> void:
	assert_true(CoreResult.is_ok(ClimbBoard.validate(_data(_heads(14, 5), []))), "square 19 is free: land there and roll a 1")
	assert_true(CoreResult.is_ok(ClimbBoard.validate(_data(_heads(15, 5), []))), "square 14 is free: land there and roll a 6")


func test_six_snake_heads_in_a_row_anywhere_form_a_wall_that_cannot_be_crossed() -> void:
	var wall: Dictionary = _data(_heads(8, 6), [], 30, 6)  # heads on 8..13
	assert_eq(_error(wall), ClimbErrors.INVALID_BOARD)
	assert_string_contains(_message(wall), "square 7")
	assert_true(CoreResult.is_ok(ClimbBoard.validate(_data(_heads(8, 5), [], 30, 6))), "five in a row is crossable")


func test_a_ladder_that_skips_the_wall_makes_the_board_winnable_again() -> void:
	assert_true(CoreResult.is_ok(ClimbBoard.validate(_data(_heads(8, 6), [_jump(3, 20)], 30, 6))))


func test_a_ladder_into_the_wall_does_not_help_if_it_lands_inside_it() -> void:
	# a ladder cannot end on a snake head (that would be a chain), so landing inside the wall is
	# impossible; a ladder to just before it leads nowhere new
	var data: Dictionary = _data(_heads(8, 6), [_jump(3, 7)], 30, 6)
	assert_eq(_error(data), ClimbErrors.INVALID_BOARD)


func test_a_trap_near_the_start_is_refused() -> void:
	# heads on 2..7 all slide to 1: a player can only ever stand on 0 or 1
	var data: Dictionary = _data(_heads(2, 6), [])
	assert_eq(_error(data), ClimbErrors.INVALID_BOARD)
	assert_string_contains(_message(data), "square 1")


func test_a_board_with_many_snakes_but_a_way_through_is_fine() -> void:
	var snakes: Array = _heads(3, 3) + _heads(9, 4) + _heads(15, 3)
	assert_true(CoreResult.is_ok(ClimbBoard.validate(_data(snakes, []))))


func test_a_ladder_that_is_the_only_way_forward_counts() -> void:
	# heads on 2..7 would trap the start, but a ladder from 1 is not allowed; so the only escape
	# is a roll landing on... nothing: the board stays refused
	assert_eq(_error(_data(_heads(2, 6), [_jump(8, 20)])), ClimbErrors.INVALID_BOARD, "square 8 cannot be reached from 0 or 1")


func test_the_classic_board_is_winnable_by_an_independent_search() -> void:
	var board: Dictionary = ClimbBoard.load_file()["board"]
	assert_true(_independent_winnable(board), "checked by a differently written algorithm")
	assert_true(ClimbBoard.reachable_squares(board).has(100))


func test_reachable_squares_includes_the_start_and_everything_a_player_can_stand_on() -> void:
	var board: Dictionary = ClimbBoard.validate(_data([_jump(15, 3)], [_jump(4, 9)]))["board"]
	var reachable: Dictionary = ClimbBoard.reachable_squares(board)
	assert_true(reachable.has(0))
	assert_true(reachable.has(20))
	assert_false(reachable.has(15), "landing on a snake head sends you down, you never stand on it")
	assert_false(reachable.has(4), "same for the foot of a ladder")
	assert_true(reachable.has(9), "the top of the ladder")
	assert_true(reachable.has(3), "the tail of the snake")


func test_an_unwinnable_board_cannot_start_a_game() -> void:
	var rules: ClimbAndSlitherRules = ClimbAndSlitherRules.new()
	var result: Dictionary = rules.new_game(["p1", "p2"], _data(_heads(14, 6), []), {}, 1)
	assert_eq(CoreResult.error_code(result), ClimbErrors.INVALID_BOARD)


func test_a_saved_game_whose_board_was_edited_to_be_unwinnable_is_refused() -> void:
	var rules: ClimbAndSlitherRules = ClimbAndSlitherRules.new()
	var state: Dictionary = rules.new_game(["p1", "p2"], ClimbBoard.load_file()["board"], {}, 1)["state"]
	assert_true(CoreResult.is_ok(rules.validate_state(state)))
	state["board"]["snakes"] = []
	state["board"]["ladders"] = []
	for square: int in range(94, 100):
		state["board"]["snakes"].append({"from": square, "to": 1})
	assert_eq(CoreResult.error_code(rules.validate_state(state)), ClimbErrors.INVALID_STATE)


func test_big_boards_are_checked_quickly() -> void:
	var started: int = Time.get_ticks_msec()
	assert_true(CoreResult.is_ok(ClimbBoard.validate(_data([], [], 400, 20))))
	assert_lt(Time.get_ticks_msec() - started, 500)


# --- the validator against a separately written check, on many random boards -----------------------

## Where a roll of `total` takes a player standing on `square`: the new square after any jump.
## With exact finish an overshooting roll does not move; without it the player lands on the last
## square. Written separately from the validator, from the rules text.
func _landing(jump_to: Dictionary, size: int, square: int, total: int, exact: bool) -> int:
	var target: int = square + total
	if target > size:
		return square if exact else size
	return jump_to.get(target, target)


func _jump_map(board: Dictionary) -> Dictionary:
	var jump_to: Dictionary = {}
	for kind_list: Array in [board["snakes"], board["ladders"]]:
		for jump: Dictionary in kind_list:
			jump_to[int(jump["from"])] = int(jump["to"])
	return jump_to


## Winnability by repeated relaxation until nothing changes: deliberately a different algorithm
## from the validator's queue search. `dice` 1 means rolls 1..6, 2 means rolls 2..12.
func _independent_winnable(board: Dictionary, dice: int = 1, exact: bool = true) -> bool:
	var size: int = board["size"]
	var jump_to: Dictionary = _jump_map(board)
	var can_stand: Dictionary = {0: true}
	var changed: bool = true
	while changed:
		changed = false
		for square: int in range(0, size):
			if not can_stand.has(square):
				continue
			for roll: int in range(dice, 6 * dice + 1):
				var landing: int = _landing(jump_to, size, square, roll, exact)
				if not can_stand.has(landing):
					can_stand[landing] = true
					changed = true
	return can_stand.has(size)


func test_the_validator_agrees_with_the_independent_check_on_random_boards() -> void:
	var prng: Prng = Prng.new(31415)
	var patterns: Dictionary = {}
	for i: int in 900:
		# every other board is dense in snakes, every third has a wall of 5 to 7 snake heads,
		# every fifth has a trap in front of the last square
		var data: Dictionary = ClimbRig.random_board_data(prng, i % 2 == 0, i % 3 == 0, i % 5 == 0)
		var verdict: Dictionary = ClimbBoard.validate(data)
		var strict_one: bool = _independent_winnable(data, 1, true)
		var lenient_one: bool = _independent_winnable(data, 1, false)
		var lenient_two: bool = _independent_winnable(data, 2, false)
		assert_eq(CoreResult.is_ok(verdict), strict_one and lenient_one and lenient_two, "board %d (size %d): validator and independent check disagree" % [i, data["size"]])
		# the relationships between the three combinations (why the first one decides in practice)
		assert_eq(strict_one, lenient_one, "board %d: one die wins with exact finish exactly when it wins without it" % i)
		if strict_one:
			assert_true(lenient_two, "board %d: if one die can win, two dice can too" % i)
		var pattern: String = "%s%s%s" % ["T" if strict_one else "F", "T" if lenient_one else "F", "T" if lenient_two else "F"]
		patterns[pattern] = int(patterns.get(pattern, 0)) + 1
		if not CoreResult.is_ok(verdict):
			assert_eq(CoreResult.error_code(verdict), ClimbErrors.INVALID_BOARD)
			var message: String = str(verdict["error"]["message"])
			assert_string_contains(message, "can never be reached")
			# the message names the first combination that fails
			assert_string_contains(message, "one die with exact finish" if not strict_one else ("one die" if not lenient_one else "two dice"))
	gut.p("winnability: patterns (one die exact / one die / two dice) %s; validator and independent check agreed on all 900 boards" % str(patterns))
	assert_gt(int(patterns.get("TTT", 0)), 100, "plenty of boards winnable under every combination")
	assert_gte(int(patterns.get("FFT", 0)), 10, "boards only two dice can finish (one die is blocked) were compared")
	assert_gte(int(patterns.get("FFF", 0)), 5, "boards nobody can finish were compared")
	assert_eq(patterns.keys().size(), 3, "no other combination pattern can occur: %s" % str(patterns))


# --- the settings combinations --------------------------------------------------------------------------

func test_every_allowed_settings_combination_is_checked() -> void:
	assert_eq(ClimbSettings.allowed_combinations(), [
		{"dice_count": 1, "exact_finish": true},
		{"dice_count": 1, "exact_finish": false},
		{"dice_count": 2, "exact_finish": false},
	] as Array[Dictionary])
	for combo: Dictionary in ClimbSettings.allowed_combinations():
		assert_true(CoreResult.is_ok(ClimbSettings.normalize(combo)))
	assert_false(CoreResult.is_ok(ClimbSettings.normalize({"dice_count": 2, "exact_finish": true})), "the refused one is not in the list")


func test_the_search_models_exactly_what_the_rules_do_for_every_position_and_roll() -> void:
	# the checks above are only as good as the model of one move: compare it with the real rules
	var rules: ClimbAndSlitherRules = ClimbAndSlitherRules.new()
	var board: Dictionary = ClimbBoard.validate(_data([_jump(17, 4), _jump(12, 6)], [_jump(3, 9), _jump(14, 19)]))["board"]
	var jump_to: Dictionary = _jump_map(board)
	var size: int = board["size"]
	var compared: int = 0
	for combo: Dictionary in ClimbSettings.allowed_combinations():
		var dice: int = combo["dice_count"]
		var settings: Dictionary = {"exact_finish": combo["exact_finish"], "dice_count": dice}
		var rolls: Array = []
		if dice == 1:
			for die: int in range(1, 7):
				rolls.append([die])
		else:
			for a: int in range(1, 7):
				for b: int in range(1, 7):
					rolls.append([a, b])
		for square: int in range(0, size):
			for dice_values: Array in rolls:
				var total: int = 0
				for die: int in dice_values:
					total += die
				var state: Dictionary = ClimbRig.game([dice_values], ["p1", "p2"], settings, {"p1": square}, board)
				var result: Dictionary = rules.apply(state, "p1", {"type": "roll"})
				assert_true(CoreResult.is_ok(result), str(result))
				var expected: int = _landing(jump_to, size, square, total, combo["exact_finish"])
				assert_eq(result["state"]["positions"]["p1"], expected, "%s: from %d rolling %s" % [str(combo), square, str(dice_values)])
				compared += 1
	assert_gt(compared, 900)


func test_a_lone_free_square_before_the_last_is_fine_because_two_dice_overshoot_and_win() -> void:
	# size 20: heads on 8..18, a ladder from 3 to 19. One die lands on 19 and rolls a 1. Two
	# dice cannot roll a 1, but without exact finish an overshoot lands on the last square.
	var data: Dictionary = _data(_heads(8, 11), [_jump(3, 19)])
	assert_true(CoreResult.is_ok(ClimbBoard.validate(data)), str(ClimbBoard.validate(data)))
	assert_true(_independent_winnable(data, 1, true))
	assert_true(_independent_winnable(data, 1, false))
	assert_true(_independent_winnable(data, 2, false))
	assert_false(_independent_winnable(data, 2, true), "two dice with exact finish would be stuck, which is why settings refuse that combination")
	var board: Dictionary = ClimbBoard.validate(data)["board"]
	assert_false(ClimbBoard.reachable_squares(board, 2, true).has(20))
	assert_true(ClimbBoard.reachable_squares(board, 2, false).has(20))


func test_a_wall_refused_names_the_first_combination_that_fails() -> void:
	var wall: Dictionary = _data(_heads(8, 6), [], 30, 6)
	assert_eq(_error(wall), ClimbErrors.INVALID_BOARD)
	assert_string_contains(_message(wall), "one die with exact finish")
	assert_false(_message(wall).contains("two dice"))


func test_a_wall_only_two_dice_can_cross_is_still_refused_because_one_die_cannot() -> void:
	var wall: Dictionary = _data(_heads(8, 6), [], 30, 6)
	assert_false(_independent_winnable(wall, 1, true))
	assert_false(_independent_winnable(wall, 1, false))
	assert_true(_independent_winnable(wall, 2, false), "two dice step over six heads")
	assert_eq(_error(wall), ClimbErrors.INVALID_BOARD)


func test_a_board_nobody_can_finish_is_reported_for_the_first_combination() -> void:
	var data: Dictionary = _data(_heads(2, 18), [])
	assert_false(_independent_winnable(data, 1, true))
	assert_false(_independent_winnable(data, 2, false))
	assert_string_contains(_message(data), "one die with exact finish")


func test_reachable_squares_depends_on_the_dice_and_the_overshoot_rule() -> void:
	var valid: Dictionary = ClimbBoard.validate({"name": "T", "size": 20, "columns": 5, "snakes": [], "ladders": []})["board"]
	assert_true(ClimbBoard.reachable_squares(valid, 1).has(1))
	assert_false(ClimbBoard.reachable_squares(valid, 2).has(1), "two dice can never stand on square 1")
	assert_true(ClimbBoard.reachable_squares(valid, 2).has(2))
	for exact: bool in [true, false]:
		assert_true(ClimbBoard.reachable_squares(valid, 1, exact).has(20))
		assert_true(ClimbBoard.reachable_squares(valid, 2, exact).has(20))


func test_the_classic_board_is_winnable_under_every_allowed_combination() -> void:
	var board: Dictionary = ClimbBoard.load_file()["board"]
	for combo: Dictionary in ClimbSettings.allowed_combinations():
		assert_true(_independent_winnable(board, combo["dice_count"], combo["exact_finish"]), str(combo))
		assert_true(ClimbBoard.reachable_squares(board, combo["dice_count"], combo["exact_finish"]).has(100), str(combo))
