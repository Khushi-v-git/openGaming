extends GutTest
## core/game with a game that is not Climb and Slither: the count-to-N test game runs through
## the hot-seat controller and the timeline, and core/game contains no Climb-specific code.

var rules: CountGameRules
var controller: LocalGameController
var timeline: EventTimeline
var batches: Array = []
var rejected: Array = []
var played: Array = []


func before_each() -> void:
	rules = CountGameRules.new()
	controller = LocalGameController.new(rules, ["a", "b", "c"], {"target": 7}, {}, 100)
	timeline = EventTimeline.new()
	batches = []
	rejected = []
	played = []
	controller.batch_ready.connect(func(batch: Dictionary) -> void:
		batches.append(batch)
		timeline.push(batch))
	controller.action_rejected.connect(func(error: Dictionary) -> void: rejected.append(error))
	timeline.event_started.connect(func(event: Dictionary, _shown: Dictionary) -> void:
		played.append(event)
		timeline.event_finished())


func _add(n: int) -> void:
	controller.submit_action({"type": "add", "n": n})


func test_start_sends_a_start_batch_with_the_first_players_view() -> void:
	assert_true(CoreResult.is_ok(controller.start()))
	assert_eq(batches.size(), 1)
	assert_eq(batches[0]["seq"], 1)
	assert_eq(batches[0]["reason"], "start")
	assert_eq(batches[0]["view"]["current_player"], "a")
	assert_eq(timeline.shown["total"], 0)


func test_actions_are_played_as_whoever_is_to_move() -> void:
	controller.start()
	_add(2)
	assert_eq(timeline.shown["current_player"], "b")
	_add(1)
	assert_eq(timeline.shown["current_player"], "c")
	assert_eq(timeline.shown["total"], 3)
	assert_eq(played.map(func(e: Dictionary) -> String: return e["type"]), ["added", "turn_changed", "added", "turn_changed"])
	assert_eq(batches.map(func(b: Dictionary) -> int: return b["seq"]), [1, 2, 3])


func test_a_bad_action_is_rejected_and_nothing_changes() -> void:
	controller.start()
	_add(2)
	var before: Dictionary = controller.latest_view()
	_add(9)
	assert_eq(rejected.size(), 1)
	assert_eq(rejected[0]["code"], ErrorCodes.BAD_ACTION)
	assert_eq(batches.size(), 2, "no new batch")
	assert_eq(controller.latest_view(), before)


func test_actions_before_the_game_starts_are_rejected() -> void:
	_add(1)
	assert_eq(rejected[0]["code"], ErrorCodes.WRONG_PHASE)


func test_the_game_ends_and_locks_further_actions() -> void:
	controller.start()
	for n: int in [3, 3, 3]:
		_add(n)
	assert_true(rules.is_finished(timeline.shown))
	assert_eq(rules.winner(timeline.shown), "c")
	assert_eq(played.back()["type"], "won")
	_add(1)
	assert_eq(rejected.back()["code"], "GAME_OVER")


func test_views_never_carry_host_only_data() -> void:
	controller.start()
	_add(1)
	for batch: Dictionary in batches:
		assert_false((batch["view"] as Dictionary).has("secret"))
	assert_true(controller.state_for_save().has("secret"), "the host-only state does have it")


func test_rematch_is_a_snapshot_of_a_fresh_game_and_does_not_replay() -> void:
	controller.start()
	for n: int in [3, 3, 3]:
		_add(n)
	var played_before: int = played.size()
	assert_true(CoreResult.is_ok(controller.rematch()))
	assert_eq(batches.back()["reason"], "rematch")
	assert_eq(timeline.shown["total"], 0)
	assert_false(rules.is_finished(timeline.shown))
	assert_eq(played.size(), played_before)


func test_the_rules_refusing_a_setup_is_reported_by_start() -> void:
	var bad: LocalGameController = LocalGameController.new(rules, ["solo"], {}, {}, 1)
	assert_false(CoreResult.is_ok(bad.start()))


func test_the_base_rules_say_what_they_do_not_implement() -> void:
	var bare: GameRules = GameRules.new()
	assert_eq(CoreResult.error_code(bare.new_game([], {}, {}, 0)), GameRules.NOT_IMPLEMENTED)
	assert_eq(CoreResult.error_code(bare.apply({}, "a", {})), GameRules.NOT_IMPLEMENTED)
	assert_true(CoreResult.is_ok(bare.settle({"x": 1})), "settle has a harmless default")


# --- genericity --------------------------------------------------------------------------------------

func test_core_game_has_no_game_specific_code() -> void:
	var dir: DirAccess = DirAccess.open("res://core/game")
	assert_not_null(dir)
	var checked: int = 0
	for file: String in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var text: String = FileAccess.get_file_as_string("res://core/game/" + file).to_lower()
		for word: String in ["climb", "slither", "snake", "ladder", "res://games"]:
			assert_false(text.contains(word), "%s mentions '%s'" % [file, word])
		checked += 1
	assert_gte(checked, 4)
