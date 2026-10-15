extends GutTest


func _ops(steps: Array[Dictionary]) -> Array:
	return steps.map(func(s: Dictionary) -> String: return s["op"])


func test_a_roll_becomes_a_dice_step_with_the_values() -> void:
	var steps: Array[Dictionary] = ClimbAnimationPlan.steps_for({"type": "rolled", "player_id": "p1", "dice": [3, 4], "total": 7})
	assert_eq(_ops(steps), ["dice"])
	assert_eq(steps[0]["dice"], [3, 4])
	assert_eq(steps[0]["total"], 7)


func test_a_move_hops_square_by_square() -> void:
	var steps: Array[Dictionary] = ClimbAnimationPlan.steps_for({"type": "moved", "player_id": "p1", "from": 4, "to": 7, "path": [5, 6, 7]})
	assert_eq(_ops(steps), ["hop", "hop", "hop"])
	assert_eq(steps.map(func(s: Dictionary) -> int: return s["to"]), [5, 6, 7])


func test_ladders_and_snakes_slide_between_their_squares() -> void:
	var up: Array[Dictionary] = ClimbAnimationPlan.steps_for({"type": "jumped", "player_id": "p1", "kind": "ladder", "from": 5, "to": 27})
	var down: Array[Dictionary] = ClimbAnimationPlan.steps_for({"type": "jumped", "player_id": "p1", "kind": "snake", "from": 24, "to": 2})
	assert_eq(up[0]["op"], "slide")
	assert_eq([up[0]["from"], up[0]["to"], up[0]["kind"]], [5, 27, "ladder"])
	assert_eq([down[0]["from"], down[0]["to"], down[0]["kind"]], [24, 2, "snake"])
	assert_gt(up[0]["duration"], 0.0)


func test_an_overshoot_shakes_and_says_what_is_needed() -> void:
	var steps: Array[Dictionary] = ClimbAnimationPlan.steps_for({"type": "overshoot", "player_id": "p2", "from": 98, "needed": 2}, {"p2": "Mira"})
	assert_eq(_ops(steps), ["shake", "banner"])
	assert_eq(steps[1]["text"], "Mira needs exactly 2")


func test_extra_turn_skip_turn_change_and_win() -> void:
	var names: Dictionary = {"p1": "Asha"}
	assert_eq(ClimbAnimationPlan.steps_for({"type": "extra_turn", "player_id": "p1"}, names)[0]["text"], "Asha rolls again")
	assert_string_contains(ClimbAnimationPlan.steps_for({"type": "turn_skipped", "player_id": "p1"}, names)[0]["text"], "Asha")
	assert_eq(_ops(ClimbAnimationPlan.steps_for({"type": "turn_changed", "player_id": "p1"})), ["turn"])
	assert_eq(_ops(ClimbAnimationPlan.steps_for({"type": "won", "player_id": "p1"})), ["win"])


func test_a_roll_that_cannot_start_the_game_shows_a_banner() -> void:
	var steps: Array[Dictionary] = ClimbAnimationPlan.steps_for({"type": "needs_one", "player_id": "p1", "dice": [4]}, {"p1": "Asha"})
	assert_eq(_ops(steps), ["banner"])
	assert_eq(steps[0]["text"], "Asha needs a 1 to start")


func test_an_unknown_event_is_no_steps_not_an_error() -> void:
	assert_eq(ClimbAnimationPlan.steps_for({"type": "something_new"}).size(), 0)
	assert_eq(ClimbAnimationPlan.steps_for({}).size(), 0)


func test_every_step_has_a_positive_duration() -> void:
	var events: Array = [
		{"type": "rolled", "player_id": "p", "dice": [1], "total": 1}, {"type": "moved", "player_id": "p", "path": [1]},
		{"type": "overshoot", "player_id": "p", "needed": 1}, {"type": "jumped", "player_id": "p", "kind": "snake", "from": 9, "to": 3},
		{"type": "extra_turn", "player_id": "p"}, {"type": "turn_skipped", "player_id": "p"},
		{"type": "needs_one", "player_id": "p", "dice": [2]},
		{"type": "turn_changed", "player_id": "p"}, {"type": "won", "player_id": "p"},
	]
	for event: Dictionary in events:
		for step: Dictionary in ClimbAnimationPlan.steps_for(event):
			assert_gt(float(step["duration"]), 0.0, str(step))


func test_speed_scales_the_total_and_instant_is_zero() -> void:
	var steps: Array[Dictionary] = ClimbAnimationPlan.steps_for({"type": "moved", "player_id": "p1", "path": [1, 2, 3, 4]})
	var base: float = ClimbAnimationPlan.total_duration(steps, 1.0)
	assert_almost_eq(ClimbAnimationPlan.total_duration(steps, 2.0), base / 2.0, 0.0001)
	assert_almost_eq(ClimbAnimationPlan.total_duration(steps, 0.5), base * 2.0, 0.0001)
	assert_eq(ClimbAnimationPlan.total_duration(steps, 0.0), 0.0)
	assert_eq(ClimbAnimationPlan.SPEEDS["Instant"], 0.0)


func test_every_event_the_rules_make_has_steps() -> void:
	# play a real game and check no event type is silently ignored by the plan
	var rules: ClimbAndSlitherRules = ClimbAndSlitherRules.new()
	var state: Dictionary = rules.new_game(["p1", "p2"], ClimbRig.classic(), {"extra_turn_on_six": true, "exact_finish": true}, 3)["state"]
	var seen: Dictionary = {}
	var guard: int = 0
	while state["phase"] != "finished" and guard < 4000:
		var result: Dictionary = rules.apply(state, state["current_player"], {"type": "roll"})
		state = result["state"]
		for event: Dictionary in result["events"]:
			seen[event["type"]] = true
			if event["type"] == "moved" and (event["path"] as Array).is_empty():
				continue
			assert_gt(ClimbAnimationPlan.steps_for(event).size(), 0, "no steps for %s" % str(event))
		guard += 1
	for type: String in ["rolled", "moved", "jumped", "overshoot", "extra_turn", "turn_changed", "won"]:
		assert_true(seen.has(type), "the test game produced a %s event" % type)
