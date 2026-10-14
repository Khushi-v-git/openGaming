class_name ClimbAndSlitherRules
extends RefCounted
## Climb and Slither (a Snakes and Ladders game): the rules, as pure logic (rule 2).
## No nodes, no UI, no networking, no timers. Randomness comes from core's Prng, whose
## seed and state live in the game state.
##
## State (plain data, JSON-safe; see validate_state for every invariant):
##   state_version, game_id, phase ("in_progress" | "finished"),
##   board {name, size, columns, snakes, ladders}   embedded copy, so saves and replays
##                                                   do not depend on the data file
##   settings {exact_finish, extra_turn_on_six, dice_count}
##   players [{player_id, color}]   seat order = turn order; colors by seat
##   positions {player_id: int}     0 = not on the board yet, board.size = the last square
##   current_player, extra_turn     extra_turn: the current player rolls again
##   last_roll {player_id, dice, total} or {}
##   turn_number, rolls, winner ("" until someone finishes)
##   rng {seed, state}              HOST-ONLY decimal strings; view_for never includes them

const GAME_ID: String = "climb_and_slither"
const STATE_VERSION: int = 1
const MIN_PLAYERS: int = 2
const MAX_PLAYERS: int = 4
const COLORS: Array[String] = ["red", "blue", "green", "yellow"]

const PHASE_IN_PROGRESS: String = "in_progress"
const PHASE_FINISHED: String = "finished"

const _STATE_KEYS: Array[String] = [
	"state_version", "game_id", "phase", "board", "settings", "players", "positions",
	"current_player", "extra_turn", "last_roll", "turn_number", "rolls", "winner", "rng",
]


## Starts a game. `player_ids` is the seat order (the first player moves first). `board` is
## board data (validated here, then embedded), `settings` any subset of the house rules.
## Returns {ok, state, events: []} or a failure (BAD_PLAYERS, INVALID_BOARD, INVALID_SETTINGS).
func new_game(player_ids: Array, board: Dictionary, settings: Dictionary, seed_value: int) -> Dictionary:
	if player_ids.size() < MIN_PLAYERS or player_ids.size() > MAX_PLAYERS:
		return CoreResult.failure(ClimbErrors.BAD_PLAYERS, "Climb and Slither needs %d to %d players." % [MIN_PLAYERS, MAX_PLAYERS])
	var seen: Dictionary = {}
	var players: Array = []
	var positions: Dictionary = {}
	for i: int in player_ids.size():
		var id: Variant = player_ids[i]
		if typeof(id) != TYPE_STRING or (id as String).is_empty():
			return CoreResult.failure(ClimbErrors.BAD_PLAYERS, "Player ids must be non-empty text.")
		if seen.has(id):
			return CoreResult.failure(ClimbErrors.BAD_PLAYERS, "Player id '%s' appears twice." % id)
		seen[id] = true
		players.append({"player_id": id, "color": COLORS[i]})
		positions[id] = 0
	var checked_board: Dictionary = ClimbBoard.validate(board)
	if not CoreResult.is_ok(checked_board):
		return checked_board
	var checked_settings: Dictionary = ClimbSettings.normalize(settings)
	if not CoreResult.is_ok(checked_settings):
		return checked_settings
	var prng: Prng = Prng.new(seed_value)
	var state: Dictionary = {
		"state_version": STATE_VERSION,
		"game_id": GAME_ID,
		"phase": PHASE_IN_PROGRESS,
		"board": checked_board["board"],
		"settings": checked_settings["settings"],
		"players": players,
		"positions": positions,
		"current_player": player_ids[0],
		"extra_turn": false,
		"last_roll": {},
		"turn_number": 1,
		"rolls": 0,
		"winner": "",
		"rng": {"seed": prng.seed_text(), "state": prng.state_text()},
	}
	return CoreResult.success({"state": state, "events": []})


## Applies one action by one player. The only action is {"type": "roll"}: the dice always
## come from the seeded generator in the state, never from the caller (so any other field in
## the action is refused). `active_players` are the players present and still in the game, in
## seat order; the turn passes to the next of them, and an absent player cannot act. Leave it
## empty to mean everybody.
##
## Returns {ok: true, state, events} or {ok: false, error: {code, message}}; on error the
## state you passed in is untouched. Events (in order) tell a UI what happened so it never
## has to work out rules itself:
##   rolled {player_id, dice, total}      moved {player_id, from, to, path}
##   overshoot {player_id, from, needed}  jumped {player_id, kind, from, to}
##   extra_turn {player_id}               turn_changed {player_id}
##   won {player_id}
func apply(state: Dictionary, player_id: String, action: Dictionary, active_players: Array = []) -> Dictionary:
	var action_check: Dictionary = _check_action(action)
	if not CoreResult.is_ok(action_check):
		return action_check
	var state_check: Dictionary = _quick_check(state)
	if not CoreResult.is_ok(state_check):
		return state_check
	if state["phase"] == PHASE_FINISHED:
		return CoreResult.failure(ClimbErrors.GAME_OVER, "The game is over.")
	var order: Array[String] = _seat_order(state)
	if not order.has(player_id):
		return CoreResult.failure(ErrorCodes.UNKNOWN_PLAYER, "%s is not playing in this game." % player_id)
	var active: Array[String] = _strings(active_players)
	if not active.is_empty() and not active.has(player_id):
		return CoreResult.failure(ClimbErrors.PLAYER_INACTIVE, "You are not in the game right now.")
	if state["current_player"] != player_id:
		return CoreResult.failure(ClimbErrors.NOT_YOUR_TURN, "It is not your turn.")
	var prng: Prng = Prng.restore(state["rng"]["seed"], state["rng"]["state"])
	if prng == null:
		return CoreResult.failure(ClimbErrors.INVALID_STATE, "The random generator state is not valid.")

	var next: Dictionary = state.duplicate(true)
	var events: Array = []
	var board: Dictionary = next["board"]
	var settings: Dictionary = next["settings"]
	var size: int = board["size"]

	var dice: Array[int] = draw_dice(prng, settings["dice_count"])
	var total: int = 0
	for die: int in dice:
		total += die
	next["rng"]["state"] = prng.state_text()
	next["rolls"] = int(next["rolls"]) + 1
	next["last_roll"] = {"player_id": player_id, "dice": dice.duplicate(), "total": total}
	events.append({"type": "rolled", "player_id": player_id, "dice": dice.duplicate(), "total": total})

	var from: int = next["positions"][player_id]
	var target: int = from + total
	if target > size:
		if settings["exact_finish"]:
			events.append({"type": "overshoot", "player_id": player_id, "from": from, "needed": size - from})
			target = from  # stays where it is
		else:
			target = size
	var finished: bool = false
	if target != from:
		var path: Array[int] = []
		for square: int in range(from + 1, target + 1):
			path.append(square)
		events.append({"type": "moved", "player_id": player_id, "from": from, "to": target, "path": path})
		next["positions"][player_id] = target
		if target == size:
			finished = true
		else:
			var jump: Dictionary = ClimbBoard.jump_at(board, target)
			if not jump.is_empty():
				events.append({"type": "jumped", "player_id": player_id, "kind": jump["kind"], "from": target, "to": jump["to"]})
				next["positions"][player_id] = jump["to"]
				finished = jump["to"] == size

	if finished:
		next["phase"] = PHASE_FINISHED
		next["winner"] = player_id
		next["extra_turn"] = false
		events.append({"type": "won", "player_id": player_id})
	elif settings["extra_turn_on_six"] and dice.has(ClimbSettings.DIE_SIDES):
		next["extra_turn"] = true
		events.append({"type": "extra_turn", "player_id": player_id})
	else:
		next["extra_turn"] = false
		var following: String = TurnOrder.next_active(order, player_id, active if not active.is_empty() else order)
		next["current_player"] = following
		next["turn_number"] = int(next["turn_number"]) + 1
		events.append({"type": "turn_changed", "player_id": following})
	return CoreResult.success({"state": next, "events": events})


## Hands the turn on if the current player is not among the active players (they dropped
## while it was their turn). A pending extra turn dies with it. The host calls this when it
## continues without waiting, and after anyone leaves or returns. Does nothing if the game is
## over, `active_players` is empty (= everybody) or the current player is present. Fails with
## NO_ACTIVE_PLAYERS if none of the game's players is active.
## Returns {ok, state, events: [turn_skipped, turn_changed]} like apply().
func settle(state: Dictionary, active_players: Array = []) -> Dictionary:
	var state_check: Dictionary = _quick_check(state)
	if not CoreResult.is_ok(state_check):
		return state_check
	var active: Array[String] = _strings(active_players)
	if state["phase"] == PHASE_FINISHED or active.is_empty() or active.has(state["current_player"]):
		return CoreResult.success({"state": state.duplicate(true), "events": []})
	var order: Array[String] = _seat_order(state)
	var following: String = TurnOrder.next_active(order, state["current_player"], active)
	if following == "":
		return CoreResult.failure(ClimbErrors.NO_ACTIVE_PLAYERS, "None of the players in this game is present.")
	var next: Dictionary = state.duplicate(true)
	var skipped: String = next["current_player"]
	next["current_player"] = following
	next["extra_turn"] = false
	next["turn_number"] = int(next["turn_number"]) + 1
	var events: Array = [
		{"type": "turn_skipped", "player_id": skipped},
		{"type": "turn_changed", "player_id": following},
	]
	return CoreResult.success({"state": next, "events": events})


## Rolls `count` dice, one `range_int(1, 6)` draw per die in order. Public so tests (and the
## replay checker) can reproduce exactly what apply() draws.
static func draw_dice(prng: Prng, count: int) -> Array[int]:
	var dice: Array[int] = []
	for _i: int in count:
		dice.append(prng.range_int(1, ClimbSettings.DIE_SIDES))
	return dice


## Checks every invariant of a game state: used by tests, and by the host before it trusts
## a loaded save. Returns {ok} or INVALID_STATE with a message saying what is wrong.
func validate_state(state: Dictionary) -> Dictionary:
	for key: String in _STATE_KEYS:
		if not state.has(key):
			return _invalid("The state has no '%s'." % key)
	if state.size() != _STATE_KEYS.size():
		return _invalid("The state has unexpected extra fields.")
	if typeof(state["state_version"]) != TYPE_INT or state["state_version"] != STATE_VERSION:
		return _invalid("Unsupported state version.")
	if typeof(state["game_id"]) != TYPE_STRING or state["game_id"] != GAME_ID:
		return _invalid("This state belongs to another game.")
	var phase: Variant = state["phase"]
	if typeof(phase) != TYPE_STRING or (phase != PHASE_IN_PROGRESS and phase != PHASE_FINISHED):
		return _invalid("Unknown phase.")

	if typeof(state["board"]) != TYPE_DICTIONARY:
		return _invalid("The board is damaged.")
	var board_check: Dictionary = ClimbBoard.validate(state["board"])
	if not CoreResult.is_ok(board_check) or board_check["board"] != state["board"]:
		return _invalid("The board is not valid.")
	var size: int = state["board"]["size"]
	if typeof(state["settings"]) != TYPE_DICTIONARY:
		return _invalid("The settings are damaged.")
	var settings_check: Dictionary = ClimbSettings.normalize(state["settings"])
	if not CoreResult.is_ok(settings_check) or settings_check["settings"] != state["settings"]:
		return _invalid("The settings are not valid.")

	var players: Variant = state["players"]
	if typeof(players) != TYPE_ARRAY or players.size() < MIN_PLAYERS or players.size() > MAX_PLAYERS:
		return _invalid("The player list is not valid.")
	var ids: Array[String] = []
	for i: int in players.size():
		var entry: Variant = players[i]
		if typeof(entry) != TYPE_DICTIONARY or entry.size() != 2 or typeof(entry.get("player_id")) != TYPE_STRING or (entry["player_id"] as String).is_empty():
			return _invalid("A player entry is damaged.")
		if ids.has(entry["player_id"]):
			return _invalid("A player appears twice.")
		if typeof(entry.get("color")) != TYPE_STRING or entry["color"] != COLORS[i]:
			return _invalid("Player colors must follow seat order.")
		ids.append(entry["player_id"])

	var positions: Variant = state["positions"]
	if typeof(positions) != TYPE_DICTIONARY or positions.size() != ids.size():
		return _invalid("The positions do not match the players.")
	var at_end: Array[String] = []
	for id: String in ids:
		if not positions.has(id) or typeof(positions[id]) != TYPE_INT or positions[id] < 0 or positions[id] > size:
			return _invalid("A position is off the board.")
		if positions[id] == size:
			at_end.append(id)

	if typeof(state["current_player"]) != TYPE_STRING or not ids.has(state["current_player"]):
		return _invalid("The current player is not in the game.")
	if typeof(state["extra_turn"]) != TYPE_BOOL:
		return _invalid("'extra_turn' must be true or false.")
	if typeof(state["turn_number"]) != TYPE_INT or state["turn_number"] < 1:
		return _invalid("'turn_number' is not valid.")
	if typeof(state["rolls"]) != TYPE_INT or state["rolls"] < 0:
		return _invalid("'rolls' is not valid.")
	var roll_check: Dictionary = _validate_last_roll(state["last_roll"], ids, state["settings"]["dice_count"])
	if not CoreResult.is_ok(roll_check):
		return roll_check

	if typeof(state["winner"]) != TYPE_STRING:
		return _invalid("'winner' must be text.")
	if phase == PHASE_IN_PROGRESS:
		if state["winner"] != "" or not at_end.is_empty():
			return _invalid("Nobody can be on the last square before the game is finished.")
	else:
		if at_end.size() != 1 or state["winner"] != at_end[0]:
			return _invalid("A finished game has exactly one winner, on the last square.")
		if state["current_player"] != state["winner"] or state["extra_turn"]:
			return _invalid("A finished game has no turn left to play.")

	var rng: Variant = state["rng"]
	if typeof(rng) != TYPE_DICTIONARY or rng.size() != 2 or typeof(rng.get("seed")) != TYPE_STRING or typeof(rng.get("state")) != TYPE_STRING:
		return _invalid("The random generator state is damaged.")
	if Prng.restore(rng["seed"], rng["state"]) == null:
		return _invalid("The random generator state is not valid.")
	return CoreResult.success()


func _validate_last_roll(last_roll: Variant, ids: Array[String], dice_count: int) -> Dictionary:
	if typeof(last_roll) != TYPE_DICTIONARY:
		return _invalid("'last_roll' is damaged.")
	if (last_roll as Dictionary).is_empty():
		return CoreResult.success()
	if last_roll.size() != 3 or not ids.has(last_roll.get("player_id")) or typeof(last_roll.get("dice")) != TYPE_ARRAY or typeof(last_roll.get("total")) != TYPE_INT:
		return _invalid("'last_roll' is damaged.")
	var dice: Array = last_roll["dice"]
	if dice.size() != dice_count:
		return _invalid("'last_roll' has the wrong number of dice.")
	var total: int = 0
	for die: Variant in dice:
		if typeof(die) != TYPE_INT or die < 1 or die > ClimbSettings.DIE_SIDES:
			return _invalid("A die shows an impossible number.")
		total += die
	if total != last_roll["total"]:
		return _invalid("'last_roll' total does not match the dice.")
	return CoreResult.success()


func _invalid(message: String) -> Dictionary:
	return CoreResult.failure(ClimbErrors.INVALID_STATE, message)


## The action must be exactly {"type": "roll"}.
func _check_action(action: Dictionary) -> Dictionary:
	if typeof(action.get("type")) != TYPE_STRING:
		return CoreResult.failure(ErrorCodes.BAD_ACTION, "An action needs a text type.")
	if action["type"] != "roll":
		return CoreResult.failure(ErrorCodes.UNKNOWN_ACTION, "Unknown action %s." % action["type"])
	if action.size() != 1:
		return CoreResult.failure(ErrorCodes.BAD_ACTION, "A roll takes no extra fields: the game rolls the dice.")
	return CoreResult.success()


## A cheap sanity check on the fields apply() reads. Full checking is validate_state().
func _quick_check(state: Dictionary) -> Dictionary:
	for key: String in _STATE_KEYS:
		if not state.has(key):
			return _invalid("The state has no %s." % key)
	if typeof(state["phase"]) != TYPE_STRING or typeof(state["current_player"]) != TYPE_STRING:
		return _invalid("The state is damaged.")
	if typeof(state["board"]) != TYPE_DICTIONARY or typeof(state["settings"]) != TYPE_DICTIONARY or typeof(state["positions"]) != TYPE_DICTIONARY or typeof(state["rng"]) != TYPE_DICTIONARY or typeof(state["players"]) != TYPE_ARRAY:
		return _invalid("The state is damaged.")
	if typeof(state["rng"].get("seed")) != TYPE_STRING or typeof(state["rng"].get("state")) != TYPE_STRING:
		return _invalid("The random generator state is damaged.")
	return CoreResult.success()


func _seat_order(state: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for entry: Variant in state["players"]:
		ids.append(str(entry["player_id"]))
	return ids


func _strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value: Variant in values:
		out.append(str(value))
	return out
