extends GutTest
## Thousands of seeded games, each played to the end with random players, house rules, boards and
## absences, asserting after every roll that the state is sane. A failure prints the replay of the
## game that broke, so it can be pasted into a test (see ClimbReplay).

const ROLL: Dictionary = {"type": "roll"}
const GAMES: int = 3000
const ROLL_CAP: int = 20000
const FULL_CHECK_EVERY: int = 25
const ROUND_TRIP_EVERY: int = 40
const MASTER_SEED: int = 20241014
const ALLOWED_EVENTS: Array[String] = ["rolled", "moved", "overshoot", "jumped", "extra_turn", "turn_changed", "turn_skipped", "won"]

var rules: ClimbAndSlitherRules


func before_each() -> void:
	rules = ClimbAndSlitherRules.new()


## Picks a random non-empty subset of `ids` (at least one player stays present).
func _random_active(prng: Prng, ids: Array) -> Array:
	var active: Array = []
	for id: Variant in ids:
		if prng.range_int(0, 2) != 0:
			active.append(id)
	if active.is_empty():
		active.append(ids[prng.range_int(0, ids.size() - 1)])
	return active


## Plays one game with every check on. Returns "" if all was well, otherwise a description of the
## first problem plus the replay text that reproduces it.
func _play_one(index: int, master: Prng, stats: Dictionary) -> String:
	var player_count: int = master.range_int(2, 4)
	var players: Array = ["p1", "p2", "p3", "p4"].slice(0, player_count)
	var exact: bool = master.range_int(0, 1) == 1
	var settings: Dictionary = {
		"exact_finish": exact,
		"extra_turn_on_six": master.range_int(0, 1) == 1,
		"dice_count": 1 if exact else master.range_int(1, 2),  # exact finish needs one die (see ClimbSettings)
	}
	var board: Dictionary = ClimbRig.random_board(master) if master.range_int(0, 4) == 0 else ClimbRig.classic()
	var seed_value: int = (master.next_u32() << 31) ^ master.next_u32()
	if master.range_int(0, 3) == 0:
		seed_value = -seed_value
	var wobbly: bool = master.range_int(0, 3) == 0  # players come and go in this game
	var created: Dictionary = rules.new_game(players, board, settings, seed_value)
	if not CoreResult.is_ok(created):
		return "new_game refused a valid setup: %s" % str(created)
	var state: Dictionary = created["state"]
	var replay: Dictionary = ClimbReplay.make(players, board, settings, seed_value)
	var size: int = board["size"]
	var active: Array = players.duplicate()
	var step: int = 0
	var problem: String = ""

	while state["phase"] == "in_progress":
		step += 1
		if step > ROLL_CAP:
			problem = "the game did not finish within %d rolls" % ROLL_CAP
			break
		if wobbly and master.range_int(0, 11) == 0:
			active = _random_active(master, players)
		if not active.has(state["current_player"]):
			var settled: Dictionary = rules.settle(state, active)
			if not CoreResult.is_ok(settled):
				problem = "settle failed: %s" % str(settled)
				break
			ClimbReplay.add_settle(replay, active)
			state = settled["state"]
			if not active.has(state["current_player"]) or state["extra_turn"]:
				problem = "settle left the turn with an absent player or a stale extra turn"
				break
		var actor: String = state["current_player"]
		var before_positions: Dictionary = state["positions"]
		var before_rolls: int = state["rolls"]
		var result: Dictionary = ClimbReplay.apply_and_record(rules, replay, state, actor, ROLL, active if wobbly else [])
		if not CoreResult.is_ok(result):
			problem = "a legal roll was refused: %s" % str(result)
			break
		var next: Dictionary = result["state"]

		# cheap checks, every roll
		if next["rolls"] != before_rolls + 1:
			problem = "rolls did not go up by one"
			break
		for id: String in players:
			var at: int = next["positions"][id]
			if at < 0 or at > size:
				problem = "%s is on square %d, off a %d-square board" % [id, at, size]
				break
			if id != actor and at != before_positions[id]:
				problem = "%s moved on someone else's turn" % id
				break
		if problem != "":
			break
		if not players.has(next["current_player"]):
			problem = "the turn went to a stranger"
			break
		if next["extra_turn"] and (not settings["extra_turn_on_six"] or next["current_player"] != actor):
			problem = "an extra turn that should not exist"
			break
		var events: Array = result["events"]
		for event: Dictionary in events:
			if not ALLOWED_EVENTS.has(event["type"]):
				problem = "unknown event %s" % str(event["type"])
				break
		if problem != "":
			break
		var won_events: int = 0
		for event: Dictionary in events:
			if event["type"] == "won":
				won_events += 1
		if (next["phase"] == "finished") != (won_events == 1) or won_events > 1:
			problem = "the won event and the phase disagree"
			break
		if next["phase"] == "finished" and (next["winner"] != actor or next["positions"][actor] != size):
			problem = "the winner is not the roller on the last square"
			break
		if next["turn_number"] < state["turn_number"]:
			problem = "turn_number went backwards"
			break

		# the full invariant check now and then
		if step % FULL_CHECK_EVERY == 0:
			var full: Dictionary = rules.validate_state(next)
			if not CoreResult.is_ok(full):
				problem = "validate_state: %s" % str(full)
				break
		# serialisation in the middle of the game
		if step % ROUND_TRIP_EVERY == 0:
			var through_json: Dictionary = Envelope.normalize(JSON.parse_string(JSON.stringify(next)))
			if through_json != next:
				problem = "the state changed when written as JSON and read back"
				break
			next = through_json
		state = next

	if problem == "":
		var final_check: Dictionary = rules.validate_state(state)
		if not CoreResult.is_ok(final_check):
			problem = "final state: %s" % str(final_check)
		elif state["phase"] != "finished":
			problem = "the game ended without a winner"
		else:
			var on_last: int = 0
			for id: String in players:
				if state["positions"][id] == size:
					on_last += 1
			if on_last != 1:
				problem = "%d players on the last square at the end" % on_last
	if problem == "" and index % 15 == 0:
		var replayed: Dictionary = ClimbReplay.run(replay)
		if not CoreResult.is_ok(replayed) or replayed["state"] != state:
			problem = "the recorded replay did not reproduce the game"
	stats["rolls"] += state["rolls"]
	stats["max_rolls"] = maxi(stats["max_rolls"], state["rolls"])
	stats["wobbly"] += 1 if wobbly else 0
	(stats["combos"] as Dictionary)["%d-%s-%s-%d" % [player_count, settings["exact_finish"], settings["extra_turn_on_six"], settings["dice_count"]]] = true
	stats["random_boards"] += 1 if board["name"] == "Rig" else 0
	if problem != "":
		return "game %d (seed %d, %d players, %s): %s\nREPLAY:\n%s" % [index, seed_value, player_count, str(settings), problem, ClimbReplay.to_text(replay)]
	return ""


func test_thousands_of_random_games_all_finish_and_stay_valid() -> void:
	var master: Prng = Prng.new(MASTER_SEED)
	var stats: Dictionary = {"rolls": 0, "max_rolls": 0, "wobbly": 0, "random_boards": 0, "combos": {}}
	var failures: Array[String] = []
	for index: int in GAMES:
		var problem: String = _play_one(index, master, stats)
		if problem != "":
			failures.append(problem)
			if failures.size() >= 3:
				break  # three examples are plenty to start from
	for failure: String in failures:
		gut.p(failure.split("
REPLAY:")[0])
	assert_eq(failures, [], "fuzz failures (paste a REPLAY into ClimbReplay.from_text to reproduce)")
	gut.p("fuzz: %d games, %d rolls (avg %.1f, longest %d), %d with players coming and going, %d on random boards" % [GAMES, stats["rolls"], float(stats["rolls"]) / GAMES, stats["max_rolls"], stats["wobbly"], stats["random_boards"]])
	assert_gt(stats["wobbly"], GAMES / 8, "a good share of games had absences")
	assert_gt(stats["random_boards"], GAMES / 8, "a good share of games used random boards")
	assert_lt(float(stats["rolls"]) / GAMES, 400.0, "games end in a sensible number of rolls")
	# 2, 3 or 4 players x (exact finish: 1 die, extra turn on/off) + (no exact: 1 or 2 dice, extra turn on/off)
	assert_eq((stats["combos"] as Dictionary).size(), 3 * (2 + 4), "every player count and every legal house-rule combination was played")


func test_random_boards_are_always_valid_boards() -> void:
	var prng: Prng = Prng.new(99)
	var with_snakes: int = 0
	var with_ladders: int = 0
	for _i: int in 500:
		var board: Dictionary = ClimbRig.random_board(prng)
		var checked: Dictionary = ClimbBoard.validate(board)
		assert_true(CoreResult.is_ok(checked), str(checked))
		assert_eq(checked["board"], board, "the generator already produces canonical boards")
		with_snakes += 1 if not board["snakes"].is_empty() else 0
		with_ladders += 1 if not board["ladders"].is_empty() else 0
	assert_gt(with_snakes, 300)
	assert_gt(with_ladders, 300)
