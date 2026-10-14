class_name EventTimeline
extends RefCounted
## Plays what happened one event at a time, so animations never fight each other, and keeps
## the picture on screen equal to the real game state once they finish. Knows nothing about any
## particular game: events are opaque dicts handed to whoever animates them.
##
## Flow: the controller's batches go in through push(). When an event is due the timeline emits
## event_started(event, shown_view); whoever animates it calls event_finished() when it is
## done (at once for Instant speed). When a batch has run out of events, `shown` becomes that
## batch's view (the convergence rule: whatever the animations did, the screen ends up showing
## the true state) and settled(view) fires.
##
## A snapshot replaces everything instead of playing: a batch whose reason says the whole
## picture changed (start, rejoin, resync, rematch, load), a gap in `seq` (something was
## missed), or a backlog of MAX_BACKLOG batches or more (a player who was busy or slow).
## snapped(view) fires, `shown` is the newest view, and anything half-played is dropped.

signal event_started(event: Dictionary, shown_view: Dictionary)
signal settled(view: Dictionary)
signal snapped(view: Dictionary)

const MAX_BACKLOG: int = 4
const SNAP_REASONS: Array[String] = ["start", "rejoin", "resync", "rematch", "load"]

## The view the screen shows right now (between events it lags behind `latest`).
var shown: Dictionary = {}
## The view of the newest batch received: what the game really looks like.
var latest: Dictionary = {}

var _pending: Array[Dictionary] = []  # batches waiting, oldest first
var _current: Dictionary = {}  # the batch being played, {} when idle
var _events_left: Array = []
var _waiting_for_event: bool = false
var _last_seq: int = -1
var _advancing: bool = false


func push(batch: Dictionary) -> void:
	assert(batch.has("seq") and batch.has("reason") and batch.has("events") and batch.has("view"), "malformed batch")
	var seq: int = int(batch["seq"])
	if _last_seq >= 0 and seq <= _last_seq:
		return  # already seen (a duplicate or a late arrival)
	var gap: bool = _last_seq >= 0 and seq != _last_seq + 1
	var backlog: int = _pending.size() + (1 if not _current.is_empty() else 0)
	_last_seq = seq
	latest = batch["view"]
	if SNAP_REASONS.has(String(batch["reason"])) or gap or backlog >= MAX_BACKLOG:
		_snap()
		return
	_pending.append(batch)
	_advance()


## The animation of the event that was started is over.
func event_finished() -> void:
	if not _waiting_for_event:
		return
	_waiting_for_event = false
	_advance()


## Skip: drop everything half-played and show the real state now.
func skip() -> void:
	if is_busy():
		_snap()


## True while events are being played or are waiting.
func is_busy() -> bool:
	return not _current.is_empty() or not _pending.is_empty()


func pending_count() -> int:
	return _pending.size()


func _snap() -> void:
	_pending.clear()
	_current = {}
	_events_left = []
	_waiting_for_event = false
	shown = latest
	snapped.emit(shown)


## Starts the next event, or settles a batch that has none left. An animation that finishes
## inside event_started (instant speed) calls event_finished() re-entrantly; the loop here
## carries on instead of recursing.
func _advance() -> void:
	if _advancing:
		return
	_advancing = true
	while not _waiting_for_event:
		if _current.is_empty():
			if _pending.is_empty():
				break
			_current = _pending.pop_front()
			_events_left = (_current["events"] as Array).duplicate()
		if _events_left.is_empty():
			shown = _current["view"]
			_current = {}
			settled.emit(shown)
			continue
		var event: Dictionary = _events_left.pop_front()
		_waiting_for_event = true
		event_started.emit(event, shown)
	_advancing = false
