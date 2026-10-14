extends GutTest
## Climb and Slither fulfils the shared GameRules contract and runs through the hot-seat
## controller and the timeline exactly like the tiny test game does.


func _controller(players: Array = ["p1", "p2"], settings: Dictionary = {}) -> LocalGameController:
	return LocalGameController.new(ClimbAndSlitherRules.new(), players, ClimbRig.classic(), settings, 5)


func test_climb_and_slither_is_a_game_rules() -> void:
	var rules: GameRules = ClimbAndSlitherRules.new()
	assert_true(rules is GameRules)
	assert_true(rules is RefCounted)


func test_the_queries_work_on_a_state_and_on_a_view() -> void:
	var rules: ClimbAndSlitherRules = ClimbAndSlitherRules.new()
	var state: Dictionary = rules.new_game(["p1", "p2"], ClimbRig.classic(), {}, 1)["state"]
	var view: Dictionary = rules.view_for(state, "p2")
	for source: Dictionary in [state, view]:
		assert_eq(rules.current_player(source), "p1")
		assert_false(rules.is_finished(source))
		assert_eq(rules.winner(source), "")
	state["phase"] = "finished"
	state["winner"] = "p2"
	var done: Dictionary = rules.view_for(state, "p1")
	for source: Dictionary in [state, done]:
		assert_true(rules.is_finished(source))
		assert_eq(rules.winner(source), "p2")
		assert_eq(rules.current_player(source), "", "nobody is to move once it is over")


func test_a_whole_game_through_the_controller_and_timeline() -> void:
	var controller: LocalGameController = _controller()
	var timeline: EventTimeline = EventTimeline.new()
	controller.batch_ready.connect(func(batch: Dictionary) -> void: timeline.push(batch))
	var seen_types: Dictionary = {}
	timeline.event_started.connect(func(event: Dictionary, _shown: Dictionary) -> void:
		seen_types[event["type"]] = true
		timeline.event_finished())
	assert_true(CoreResult.is_ok(controller.start()))
	var rules: GameRules = controller.rules()
	var guard: int = 0
	while not rules.is_finished(timeline.shown) and guard < 5000:
		controller.submit_action({"type": "roll"})
		guard += 1
	assert_true(rules.is_finished(timeline.shown), "the game finished")
	assert_ne(rules.winner(timeline.shown), "")
	assert_eq(timeline.shown, timeline.latest,"the screen ended on the true state")
	for type: String in ["rolled", "moved", "won", "turn_changed"]:
		assert_true(seen_types.has(type), type)
	assert_false((timeline.shown as Dictionary).has("rng"), "no host-only data reached the screen")
