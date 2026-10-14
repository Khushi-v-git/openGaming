extends GutTest
## apply() returns events so a UI can animate without computing any rules. These tests check
## the events are complete, ordered and consistent with the new state, including a "UI" that
## rebuilds the whole game from events alone.

const ROLL: Dictionary = {"type": "roll"}

var rules: ClimbAndSlitherRules


func before_each() -> void:
	rules = ClimbAndSlitherRules.new()


func _roll(state: Dictionary) -> Dictionary:
	var result: Dictionary = rules.apply(state, state["current_player"], ROLL)
	assert_true(CoreResult.is_ok(result), str(result))
	return result


# --- exact event lists for scripted situations -----------------------------------------------

func test_a_plain_move_event_list() -> void:
	var result: Dictionary = _roll(ClimbRig.game([3], ["p1", "p2"], {}, {"p1": 10}, ClimbRig.board()))
	assert_eq(result["events"], [
		{"type": "rolled", "player_id": "p1", "dice": [3], "total": 3},
		{"type": "moved", "player_id": "p1", "from": 10, "to": 13, "path": [11, 12, 13]},
		{"type": "turn_changed", "player_id": "p2"},
	])


func test_a_ladder_event_list() -> void:
	var result: Dictionary = _roll(ClimbRig.game([2], ["p1", "p2"], {}, {"p1": 3}))  # 3 + 2 = 5, the foot of the 5 -> 27 ladder
	assert_eq(result["events"], [
		{"type": "rolled", "player_id": "p1", "dice": [2], "total": 2},
		{"type": "moved", "player_id": "p1", "from": 3, "to": 5, "path": [4, 5]},
		{"type": "jumped", "player_id": "p1", "kind": "ladder", "from": 5, "to": 27},
		{"type": "turn_changed", "player_id": "p2"},
	])


func test_a_snake_event_list() -> void:
	var result: Dictionary = _roll(ClimbRig.game([1], ["p1", "p2"], {}, {"p1": 98}))  # 99 is a snake head (99 -> 61)
	assert_eq(result["events"], [
		{"type": "rolled", "player_id": "p1", "dice": [1], "total": 1},
		{"type": "moved", "player_id": "p1", "from": 98, "to": 99, "path": [99]},
		{"type": "jumped", "player_id": "p1", "kind": "snake", "from": 99, "to": 61},
		{"type": "turn_changed", "player_id": "p2"},
	])


func test_a_winning_move_event_list() -> void:
	var result: Dictionary = _roll(ClimbRig.game([3], ["p1", "p2"], {}, {"p1": 97}))
	assert_eq(result["events"], [
		{"type": "rolled", "player_id": "p1", "dice": [3], "total": 3},
		{"type": "moved", "player_id": "p1", "from": 97, "to": 100, "path": [98, 99, 100]},
		{"type": "won", "player_id": "p1"},
	])


func test_an_overshoot_event_list() -> void:
	var result: Dictionary = _roll(ClimbRig.game([5], ["p1", "p2"], {"exact_finish": true}, {"p1": 97}))
	assert_eq(result["events"], [
		{"type": "rolled", "player_id": "p1", "dice": [5], "total": 5},
		{"type": "overshoot", "player_id": "p1", "from": 97, "needed": 3},
		{"type": "turn_changed", "player_id": "p2"},
	])


func test_an_extra_turn_event_list() -> void:
	var result: Dictionary = _roll(ClimbRig.game([6], ["p1", "p2"], {"extra_turn_on_six": true}, {}, ClimbRig.board()))
	assert_eq(result["events"], [
		{"type": "rolled", "player_id": "p1", "dice": [6], "total": 6},
		{"type": "moved", "player_id": "p1", "from": 0, "to": 6, "path": [1, 2, 3, 4, 5, 6]},
		{"type": "extra_turn", "player_id": "p1"},
	])


func test_two_dice_are_reported_separately_so_a_ui_can_show_both() -> void:
	var result: Dictionary = _roll(ClimbRig.game([[2, 5]], ["p1", "p2"], {"dice_count": 2}, {}, ClimbRig.board()))
	assert_eq(result["events"][0], {"type": "rolled", "player_id": "p1", "dice": [2, 5], "total": 7})


# --- general properties ----------------------------------------------------------------------------

func _check_event_properties(before: Dictionary, result: Dictionary) -> void:
	var events: Array = result["events"]
	var after: Dictionary = result["state"]
	var player: String = before["current_player"]
	assert_false(events.is_empty())
	assert_eq(events[0]["type"], "rolled", "every roll starts with the dice")
	for event: Dictionary in events:
		if event["type"] == "turn_changed":
			assert_eq(event["player_id"], after["current_player"], "turn_changed names whose turn is next")
		else:
			assert_eq(event["player_id"], player, "every other event of a roll belongs to the roller")
	var last: String = events.back()["type"]
	assert_true(["turn_changed", "extra_turn", "won"].has(last), "a roll ends with what happens next: %s" % last)
	var types: Array[String] = ClimbRig.event_types(events)
	assert_eq(types.count("rolled"), 1)
	assert_eq(types.count("moved") + types.count("overshoot"), 1, "either it walked or it overshot")
	assert_lte(types.count("jumped"), 1, "a landing triggers at most one jump")
	assert_eq(types.count("turn_changed") + types.count("extra_turn") + types.count("won"), 1)
	assert_eq(types.count("won"), 1 if after["phase"] == "finished" else 0)
	var board: Dictionary = before["board"]
	var from: int = before["positions"][player]
	for event: Dictionary in events:
		match event["type"]:
			"moved":
				assert_eq(event["from"], from)
				assert_eq(event["path"].size(), event["to"] - event["from"])
				for i: int in event["path"].size():
					assert_eq(event["path"][i], event["from"] + 1 + i, "the path is every square walked, in order")
				assert_lte(event["to"], board["size"])
			"jumped":
				var moved: Dictionary = events[types.find("moved")]
				assert_eq(event["from"], moved["to"], "a jump starts where the walk ended")
				assert_eq(event["kind"], ClimbBoard.jump_at(board, event["from"])["kind"])
				assert_eq(event["to"], ClimbBoard.jump_at(board, event["from"])["to"])
			"overshoot":
				assert_true(before["settings"]["exact_finish"], "only the exact-finish rule produces an overshoot")
				assert_eq(event["needed"], board["size"] - from)
				assert_gt(events[0]["total"], event["needed"])


func test_events_describe_every_roll_of_many_games() -> void:
	var settings_options: Array[Dictionary] = [
		{}, {"exact_finish": true}, {"extra_turn_on_six": true}, {"dice_count": 2},
		{"exact_finish": true, "extra_turn_on_six": true, "dice_count": 2},
	]
	for game_index: int in 20:
		var settings: Dictionary = settings_options[game_index % settings_options.size()]
		var players: Array = ["p1", "p2", "p3", "p4"].slice(0, 2 + game_index % 3)
		var state: Dictionary = rules.new_game(players, ClimbRig.classic(), settings, 1000 + game_index)["state"]
		var guard: int = 0
		while state["phase"] == "in_progress" and guard < 3000:
			guard += 1
			var result: Dictionary = _roll(state)
			_check_event_properties(state, result)
			state = result["state"]
		assert_eq(state["phase"], "finished", "game %d finished" % game_index)


func test_events_are_plain_data_and_share_nothing_with_the_state() -> void:
	var state: Dictionary = ClimbRig.game([4])
	var result: Dictionary = _roll(state)
	assert_true(Envelope.is_plain_data(result["events"]))
	assert_eq(Envelope.normalize(JSON.parse_string(JSON.stringify(result["events"]))), result["events"])
	var snapshot: Dictionary = result["state"].duplicate(true)
	for event: Dictionary in result["events"]:
		if event.has("dice"):
			(event["dice"] as Array).append(99)
		if event.has("path"):
			(event["path"] as Array).clear()
	assert_eq(result["state"], snapshot, "editing the events cannot change the state")
	assert_eq(result["state"]["last_roll"]["dice"], [4])


# --- a UI that only reads events ----------------------------------------------------------------------

## A stand-in for a future scene: it knows nothing about the rules, it only follows events.
func _ui_start(view: Dictionary) -> Dictionary:
	return {
		"positions": view["positions"].duplicate(),
		"current_player": view["current_player"],
		"extra_turn": view["extra_turn"],
		"winner": view["winner"],
		"last_dice": [],
		"squares_walked": 0,
	}


func _ui_follow(ui: Dictionary, events: Array) -> void:
	ui["extra_turn"] = false
	for event: Dictionary in events:
		match event["type"]:
			"rolled":
				ui["last_dice"] = event["dice"]
			"moved":
				ui["positions"][event["player_id"]] = event["to"]
				ui["squares_walked"] += event["path"].size()
			"jumped":
				ui["positions"][event["player_id"]] = event["to"]
			"extra_turn":
				ui["extra_turn"] = true
			"turn_changed":
				ui["current_player"] = event["player_id"]
			"turn_skipped":
				pass
			"won":
				ui["winner"] = event["player_id"]


func test_a_ui_following_only_the_events_always_shows_the_true_game() -> void:
	var settings_options: Array[Dictionary] = [
		{}, {"exact_finish": true}, {"extra_turn_on_six": true}, {"dice_count": 2},
		{"exact_finish": true, "extra_turn_on_six": true, "dice_count": 2},
	]
	for game_index: int in 25:
		var players: Array = ["p1", "p2", "p3", "p4"].slice(0, 2 + game_index % 3)
		var state: Dictionary = rules.new_game(players, ClimbRig.classic(), settings_options[game_index % settings_options.size()], 5000 + game_index)["state"]
		var ui: Dictionary = _ui_start(rules.view_for(state, "p1"))
		var guard: int = 0
		while state["phase"] == "in_progress" and guard < 3000:
			guard += 1
			var result: Dictionary = _roll(state)
			state = result["state"]
			_ui_follow(ui, result["events"])
			assert_eq(ui["positions"], state["positions"], "game %d roll %d: positions" % [game_index, guard])
			assert_eq(ui["current_player"], state["current_player"], "game %d roll %d: whose turn" % [game_index, guard])
			assert_eq(ui["extra_turn"], state["extra_turn"], "game %d roll %d: extra turn" % [game_index, guard])
			assert_eq(ui["winner"], state["winner"])
			assert_eq(ui["last_dice"], state["last_roll"]["dice"])
		assert_ne(ui["winner"], "", "the UI saw the game end")


func test_settle_events_let_a_ui_follow_a_skipped_turn() -> void:
	var state: Dictionary = ClimbRig.game([6, 2], ["p1", "p2", "p3"], {"extra_turn_on_six": true}, {}, ClimbRig.board())
	state = _roll(state)["state"]
	var ui: Dictionary = _ui_start(rules.view_for(state, "p2"))
	var settled: Dictionary = rules.settle(state, ["p2", "p3"])
	_ui_follow(ui, settled["events"])
	assert_eq(ui["current_player"], settled["state"]["current_player"])
	assert_eq(ui["extra_turn"], settled["state"]["extra_turn"])
