class_name ClimbReplay
extends RefCounted
## A replay reproduces a game exactly: (seed, board, settings, players, actions) -> final state.
## Because dice come from the seeded Prng in the state, nothing else is needed. It is plain
## JSON-safe data, so a bug report can paste one and a test can run it.
##
## {
##   "replay_version": 1,
##   "players": ["p1", "p2"],            seat order
##   "board": {...},                     the board data (embedded, so edits to the file cannot change old replays)
##   "settings": {...},
##   "seed": "123456789",                decimal string (an int is accepted too)
##   "steps": [
##     {"player_id": "p1", "action": {"type": "roll"}},
##     {"player_id": "p2", "action": {"type": "roll"}, "active_players": ["p1", "p2"]},   optional
##     {"player_id": "p1", "action": {"type": "move"}, "expect_error": "UNKNOWN_ACTION"}, a refused step
##     {"settle": ["p2"]}                                                                 settle(active)
##   ]
## }
##
## A step that is refused must say so with `expect_error`, otherwise the replay fails at that
## step. That is how a bug report can include "and then this invalid action was sent".

const VERSION: int = 1
const INVALID_REPLAY: String = "INVALID_REPLAY"
const REPLAY_STEP_FAILED: String = "REPLAY_STEP_FAILED"


static func make(players: Array, board: Dictionary, settings: Dictionary, seed_value: int) -> Dictionary:
	return {
		"replay_version": VERSION,
		"players": players.duplicate(),
		"board": board.duplicate(true),
		"settings": settings.duplicate(true),
		"seed": str(seed_value),
		"steps": [],
	}


static func add_action(replay: Dictionary, player_id: String, action: Dictionary, active_players: Array = [], expect_error: String = "") -> void:
	var step: Dictionary = {"player_id": player_id, "action": action.duplicate(true)}
	if not active_players.is_empty():
		step["active_players"] = active_players.duplicate()
	if expect_error != "":
		step["expect_error"] = expect_error
	(replay["steps"] as Array).append(step)


static func add_settle(replay: Dictionary, active_players: Array) -> void:
	(replay["steps"] as Array).append({"settle": active_players.duplicate()})


## Applies an action to a live game and records it in `replay` (a refused action is recorded
## with its error code). Returns apply()'s result unchanged.
static func apply_and_record(rules: ClimbAndSlitherRules, replay: Dictionary, state: Dictionary, player_id: String, action: Dictionary, active_players: Array = []) -> Dictionary:
	var result: Dictionary = rules.apply(state, player_id, action, active_players)
	add_action(replay, player_id, action, active_players, "" if CoreResult.is_ok(result) else CoreResult.error_code(result))
	return result


static func to_text(replay: Dictionary) -> String:
	return JSON.stringify(replay, "  ")


static func from_text(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return CoreResult.failure(INVALID_REPLAY, "The replay is not valid JSON: %s" % json.get_error_message())
	var data: Variant = Envelope.normalize(json.data)
	if typeof(data) != TYPE_DICTIONARY:
		return CoreResult.failure(INVALID_REPLAY, "A replay must be a JSON object.")
	return CoreResult.success({"replay": data})


## Plays the replay from the start. Returns {ok, state, events, steps} where events is every
## event of every step in order, or a failure: INVALID_REPLAY (bad shape), the new_game error,
## or REPLAY_STEP_FAILED with `step` (the 0-based index) and `step_error` (what apply said).
static func run(replay: Dictionary) -> Dictionary:
	var shape: Dictionary = _check_shape(replay)
	if not CoreResult.is_ok(shape):
		return shape
	var seed_text: String = str(replay["seed"])
	var rules: ClimbAndSlitherRules = ClimbAndSlitherRules.new()
	var created: Dictionary = rules.new_game(replay["players"], replay["board"], replay["settings"], seed_text.to_int())
	if not CoreResult.is_ok(created):
		return created
	var state: Dictionary = created["state"]
	var all_events: Array = []
	var steps: Array = replay["steps"]
	for i: int in steps.size():
		var step: Dictionary = steps[i]
		var expected: String = str(step.get("expect_error", ""))
		var result: Dictionary
		if step.has("settle"):
			result = rules.settle(state, step["settle"])
		else:
			result = rules.apply(state, str(step["player_id"]), step["action"], step.get("active_players", []))
		if CoreResult.is_ok(result):
			if expected != "":
				return _step_failed(i, "", "step %d should have been refused with %s but it worked" % [i, expected])
			state = result["state"]
			all_events.append_array(result["events"])
		else:
			var code: String = CoreResult.error_code(result)
			if expected != code:
				return _step_failed(i, code, "step %d was refused with %s (%s)%s" % [i, code, str(result["error"]["message"]), "" if expected == "" else ", expected %s" % expected])
	return CoreResult.success({"state": state, "events": all_events, "steps": steps.size()})


static func _check_shape(replay: Dictionary) -> Dictionary:
	if typeof(replay.get("replay_version")) != TYPE_INT or replay["replay_version"] != VERSION:
		return CoreResult.failure(INVALID_REPLAY, "Unsupported replay version.")
	for key: String in ["players", "steps"]:
		if typeof(replay.get(key)) != TYPE_ARRAY:
			return CoreResult.failure(INVALID_REPLAY, "The replay needs a list called %s." % key)
	for key: String in ["board", "settings"]:
		if typeof(replay.get(key)) != TYPE_DICTIONARY:
			return CoreResult.failure(INVALID_REPLAY, "The replay needs %s." % key)
	var seed_value: Variant = replay.get("seed")
	if not ((typeof(seed_value) == TYPE_STRING and (seed_value as String).is_valid_int()) or typeof(seed_value) == TYPE_INT):
		return CoreResult.failure(INVALID_REPLAY, "The replay seed must be a whole number (as text).")
	for i: int in (replay["steps"] as Array).size():
		var step: Variant = replay["steps"][i]
		if typeof(step) != TYPE_DICTIONARY:
			return CoreResult.failure(INVALID_REPLAY, "Step %d is not an object." % i)
		if step.has("settle"):
			if typeof(step["settle"]) != TYPE_ARRAY:
				return CoreResult.failure(INVALID_REPLAY, "Step %d: settle needs a list of players." % i)
		elif typeof(step.get("player_id")) != TYPE_STRING or typeof(step.get("action")) != TYPE_DICTIONARY:
			return CoreResult.failure(INVALID_REPLAY, "Step %d needs a player_id and an action." % i)
		if step.has("active_players") and typeof(step["active_players"]) != TYPE_ARRAY:
			return CoreResult.failure(INVALID_REPLAY, "Step %d: active_players must be a list." % i)
		if step.has("expect_error") and typeof(step["expect_error"]) != TYPE_STRING:
			return CoreResult.failure(INVALID_REPLAY, "Step %d: expect_error must be text." % i)
	return CoreResult.success()


static func _step_failed(index: int, step_error: String, message: String) -> Dictionary:
	var failure: Dictionary = CoreResult.failure(REPLAY_STEP_FAILED, message)
	failure["step"] = index
	failure["step_error"] = step_error
	return failure
