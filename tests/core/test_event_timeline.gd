extends GutTest
## The timeline plays events one at a time and always ends on the true state. It is tested with
## hand-made batches (no game at all) and with the tiny count-to-N game.

var timeline: EventTimeline
var started: Array = []
var settled_views: Array = []
var snapped_views: Array = []
var instant: bool = false


func before_each() -> void:
	timeline = EventTimeline.new()
	started = []
	settled_views = []
	snapped_views = []
	instant = false
	timeline.event_started.connect(_on_started)
	timeline.settled.connect(func(view: Dictionary) -> void: settled_views.append(view))
	timeline.snapped.connect(func(view: Dictionary) -> void: snapped_views.append(view))


func _on_started(event: Dictionary, shown_view: Dictionary) -> void:
	started.append({"event": event, "shown": shown_view})
	if instant:
		timeline.event_finished()


func _batch(seq: int, events: Array, view_value: int, reason: String = "action") -> Dictionary:
	return {"seq": seq, "reason": reason, "events": events, "view": {"n": view_value}}


func _events(count: int) -> Array:
	var list: Array = []
	for i: int in count:
		list.append({"type": "e", "i": i})
	return list


# --- order and convergence ----------------------------------------------------------------------

func test_events_play_one_at_a_time_in_order() -> void:
	timeline.push(_batch(1, _events(3), 7, "start"))  # first batch snaps
	timeline.push(_batch(2, _events(3), 8))
	assert_eq(started.size(), 1, "only the first event has started")
	assert_eq(started[0]["event"]["i"], 0)
	timeline.event_finished()
	assert_eq(started.size(), 2)
	assert_eq(started[1]["event"]["i"], 1)
	timeline.event_finished()
	assert_eq(started.size(), 3)
	assert_eq(settled_views.size(), 0, "not settled until the last event is finished")
	timeline.event_finished()
	assert_eq(settled_views, [{"n": 8}])


func test_shown_stays_old_until_the_batch_settles_then_equals_its_view() -> void:
	timeline.push(_batch(1, [], 1, "start"))
	timeline.push(_batch(2, _events(2), 2))
	assert_eq(timeline.shown, {"n": 1}, "the old picture stays while events play")
	assert_eq(started[0]["shown"], {"n": 1})
	assert_eq(timeline.latest, {"n": 2})
	timeline.event_finished()
	timeline.event_finished()
	assert_eq(timeline.shown, {"n": 2})
	assert_false(timeline.is_busy())


func test_a_batch_with_no_events_settles_at_once() -> void:
	timeline.push(_batch(1, [], 1, "start"))
	timeline.push(_batch(2, [], 2))
	assert_eq(timeline.shown, {"n": 2})
	assert_eq(settled_views, [{"n": 2}])


func test_queued_batches_wait_their_turn() -> void:
	timeline.push(_batch(1, [], 0, "start"))
	timeline.push(_batch(2, _events(1), 1))
	timeline.push(_batch(3, _events(1), 2))
	assert_eq(timeline.pending_count(), 1)
	timeline.event_finished()
	assert_eq(started.size(), 2, "the second batch's event starts when the first batch is done")
	timeline.event_finished()
	assert_eq(timeline.shown, {"n": 2})
	assert_eq(settled_views, [{"n": 1}, {"n": 2}])


func test_instant_animations_do_not_recurse_and_still_converge() -> void:
	instant = true
	timeline.push(_batch(1, [], 0, "start"))
	for seq: int in range(2, 5):
		timeline.push(_batch(seq, _events(5), seq))
	assert_eq(started.size(), 15)
	assert_eq(timeline.shown, {"n": 4})
	assert_false(timeline.is_busy())


func test_event_finished_with_nothing_started_is_ignored() -> void:
	timeline.event_finished()
	timeline.push(_batch(1, [], 0, "start"))
	timeline.event_finished()
	assert_eq(started.size(), 0)


# --- snapshots --------------------------------------------------------------------------------------

func test_snapshot_reasons_replace_the_picture_without_playing_events() -> void:
	timeline.push(_batch(1, [], 0, "start"))
	var seq: int = 2
	for reason: String in ["rejoin", "resync", "rematch", "start", "load"]:
		timeline.push(_batch(seq, _events(4), seq * 10, reason))
		assert_eq(timeline.shown, {"n": seq * 10}, "%s shows the new state at once" % reason)
		seq += 1
	assert_eq(started.size(), 0, "none of their events were played")
	assert_eq(snapped_views.size(), 6)


func test_a_snap_drops_an_animation_half_way() -> void:
	timeline.push(_batch(1, [], 0, "start"))
	timeline.push(_batch(2, _events(3), 1))
	timeline.push(_batch(3, _events(2), 2))
	timeline.push(_batch(4, [], 9, "rejoin"))
	assert_false(timeline.is_busy())
	assert_eq(timeline.shown, {"n": 9})
	timeline.event_finished()  # the dropped animation reports in late: ignored
	assert_eq(timeline.shown, {"n": 9})
	assert_eq(started.size(), 1)


func test_a_gap_in_seq_snaps_to_the_newest_state() -> void:
	timeline.push(_batch(1, [], 0, "start"))
	timeline.push(_batch(2, _events(1), 1))
	timeline.event_finished()
	timeline.push(_batch(5, _events(3), 5))  # 3 and 4 never arrived
	assert_eq(snapped_views.back(), {"n": 5})
	assert_eq(timeline.shown, {"n": 5})
	assert_eq(started.size(), 1, "the events of batch 5 are not replayed")


func test_old_and_duplicate_batches_are_ignored() -> void:
	timeline.push(_batch(1, [], 0, "start"))
	timeline.push(_batch(2, [], 2))
	timeline.push(_batch(2, [], 99))
	timeline.push(_batch(1, [], 98))
	assert_eq(timeline.shown, {"n": 2})
	assert_eq(timeline.latest, {"n": 2})


func test_a_long_backlog_snaps_instead_of_replaying_everything() -> void:
	timeline.push(_batch(1, [], 0, "start"))
	for seq: int in range(2, 2 + EventTimeline.MAX_BACKLOG):
		timeline.push(_batch(seq, _events(2), seq))
	assert_eq(snapped_views.size(), 1, "only the start snapped so far")
	timeline.push(_batch(2 + EventTimeline.MAX_BACKLOG, _events(2), 99))
	assert_eq(snapped_views.size(), 2)
	assert_eq(timeline.shown, {"n": 99})
	assert_false(timeline.is_busy())


func test_skip_shows_the_newest_state_now() -> void:
	timeline.push(_batch(1, [], 0, "start"))
	timeline.push(_batch(2, _events(3), 1))
	timeline.push(_batch(3, _events(3), 2))
	timeline.skip()
	assert_eq(timeline.shown, {"n": 2})
	assert_false(timeline.is_busy())
	timeline.skip()
	assert_eq(snapped_views.size(), 2, "skip with nothing to skip does nothing")


# --- the game-over picture still arrives ------------------------------------------------------------------

func test_a_finished_game_is_shown_after_a_snap_even_if_its_events_never_play() -> void:
	var rules: CountGameRules = CountGameRules.new()
	var state: Dictionary = rules.new_game(["a", "b"], {"target": 4}, {}, 1)["state"]
	var first: Dictionary = rules.apply(state, "a", {"type": "add", "n": 3})
	var second: Dictionary = rules.apply(first["state"], "b", {"type": "add", "n": 2})
	assert_true(rules.is_finished(second["state"]))
	timeline.push({"seq": 1, "reason": "start", "events": [], "view": rules.view_for(state, "a")})
	# a rejoining player gets one snapshot of the finished game, no events at all
	timeline.push({"seq": 3, "reason": "rejoin", "events": [], "view": rules.view_for(second["state"], "a")})
	assert_true(rules.is_finished(snapped_views.back()), "the snap carries the finished game")
	assert_true(rules.is_finished(timeline.shown))
	assert_eq(rules.winner(timeline.shown), "b")


func test_a_finished_game_is_shown_after_a_long_backlog_too() -> void:
	var rules: CountGameRules = CountGameRules.new()
	var state: Dictionary = rules.new_game(["a", "b"], {"target": 30}, {}, 1)["state"]
	timeline.push({"seq": 1, "reason": "start", "events": [], "view": rules.view_for(state, "a")})
	var seq: int = 2
	var last: Dictionary = {}
	while not rules.is_finished(state):
		var who: String = rules.current_player(state)
		var result: Dictionary = rules.apply(state, who, {"type": "add", "n": 3})
		state = result["state"]
		last = {"seq": seq, "reason": "action", "events": result["events"], "view": rules.view_for(state, "a")}
		timeline.push(last)
		seq += 1
	assert_true(rules.is_finished(timeline.latest))
	timeline.skip()
	assert_true(rules.is_finished(timeline.shown), "after skipping the finished game is what is shown")
	assert_eq(timeline.shown, last["view"])
