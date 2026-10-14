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
