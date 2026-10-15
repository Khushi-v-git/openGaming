class_name GameHost
extends RefCounted
## Runs one game for a LobbyHost: the host's app holds the only copy of the rules and the state
## (rule 1). Players send actions; the host validates each against the rules, applies it and
## sends every present player a batch {seq, reason, events, view} built from view_for (rule 9).
## The raw state, with its random generator, never leaves this object.
##
## Game-agnostic: it knows GameRules and the lobby, nothing about any particular game.
##
## Batches (`seq` only ever goes up, also across rematches):
##   "start" / "rematch"  a fresh game: everyone shows it at once
##   "action"             one player's action and what it caused (events for animation)
##   "settle"             the turn moved on because the current player is absent
##   "rejoin" / "resync"  a snapshot for one player who came back or asked for it (no events)
## Messages from players: game_action {action}, game_resync. Refusals go back as game_error
## {code, message, action} to that player only, and change nothing.

signal batch_ready(batch: Dictionary)  # the host player's own copy
signal action_rejected(error: Dictionary)  # the host player's own action was refused
signal ended()  # the game ended: everyone is back in the lobby

var lobby: LobbyHost
var rules: GameRules

var _setup: Dictionary
var _seed_source: int
var _games_started: int = 0
var _state: Dictionary = {}
var _seq: int = 0


func _init(lobby_host: LobbyHost, game_rules: GameRules, setup: Dictionary, seed_value: int) -> void:
	lobby = lobby_host
	rules = game_rules
	_setup = setup
	_seed_source = seed_value
	lobby.settings_validator = _validate_settings
	lobby.game_message.connect(_on_game_message)
	lobby.state_changed.connect(_on_lobby_changed)
	lobby.player_returned.connect(_on_player_returned)
	lobby.game_ended.connect(_on_game_ended)


func is_running() -> bool:
	return not _state.is_empty()


func current_seq() -> int:
	return _seq


## What the host player sees right now ({} before the game starts).
func local_view() -> Dictionary:
	return {} if _state.is_empty() else rules.view_for(_state, lobby.local_player_id)


## The game's own state for a save file. PRIVATE: it holds the random generator.
func state_for_save() -> Dictionary:
	return _state.duplicate(true)


## Starts the game for the seated players with the lobby's settings. Call it when the lobby has
## started. Returns {ok} or the rules' refusal (the host can then end the game and fix the settings).
func start() -> Dictionary:
	return _begin("start", _seat_ids())


## A new game with the same players and settings. Host only (this object lives on the host).
func rematch() -> Dictionary:
	if _state.is_empty():
		return CoreResult.failure(ErrorCodes.WRONG_PHASE, "There is no game to restart.")
	if lobby.is_game_paused():
		return CoreResult.failure(ErrorCodes.GAME_PAUSED, "The game is paused while the host waits for a player.")
	return _begin("rematch", _seat_ids())


## Resumes a saved game (after lobby.restore()). Validates the state; players get a snapshot as
## each of them rejoins.
func adopt_state(saved_state: Dictionary) -> Dictionary:
	var checked: Dictionary = rules.validate_state(saved_state)
	if not CoreResult.is_ok(checked):
		return checked
	_state = saved_state.duplicate(true)
	return CoreResult.success()


## The host player's own action (the same checks as everybody's).
func submit_local(action: Dictionary) -> Dictionary:
	var result: Dictionary = _apply(lobby.local_player_id, action)
	if not CoreResult.is_ok(result):
		action_rejected.emit(result["error"])
	return result


# --- from players ---------------------------------------------------------------------------------

func _on_game_message(player_id: String, message: Dictionary) -> void:
	match str(message["type"]):
		Protocol.T_GAME_ACTION:
			var action: Variant = message["payload"].get("action")
			if typeof(action) != TYPE_DICTIONARY:
				_refuse(player_id, ErrorCodes.MALFORMED, "game_action needs an 'action' object.", "")
				return
			var result: Dictionary = _apply(player_id, action)
			if not CoreResult.is_ok(result):
				_refuse(player_id, CoreResult.error_code(result), str(result["error"]["message"]), str(action.get("type", "")))
		Protocol.T_GAME_RESYNC:
			if not _state.is_empty():
				_send_snapshot(player_id, "resync")
		_:
			_refuse(player_id, ErrorCodes.UNKNOWN_ACTION, "Unknown message '%s'." % str(message["type"]), str(message["type"]))


func _apply(player_id: String, action: Dictionary) -> Dictionary:
	if _state.is_empty():
		return CoreResult.failure(ErrorCodes.WRONG_PHASE, "The game has not started.")
	if lobby.is_game_paused():
		return CoreResult.failure(ErrorCodes.GAME_PAUSED, "The game is paused while the host waits for a player.")
	var result: Dictionary = rules.apply(_state, player_id, action, lobby.active_players())
	if CoreResult.is_ok(result):
		_state = result["state"]
		_commit("action", result["events"])
	return result


# --- from the lobby ----------------------------------------------------------------------------------

## Presence changes: when the host continues without waiting, or a player is removed, the game
## may need to hand the turn on (rules.settle). Nothing happens while the host is waiting.
func _on_lobby_changed(lobby_state: Dictionary) -> void:
	if _state.is_empty() or lobby_state["phase"] != LobbyLogic.PHASE_IN_GAME or lobby.is_game_paused():
		return
	var settled: Dictionary = rules.settle(_state, lobby.active_players())
	if CoreResult.is_ok(settled) and not (settled["events"] as Array).is_empty():
		_state = settled["state"]
		_commit("settle", settled["events"])


func _on_player_returned(player_id: String) -> void:
	if not _state.is_empty():
		_send_snapshot(player_id, "rejoin")


func _on_game_ended() -> void:
	_state = {}
	ended.emit()


func _validate_settings(settings: Dictionary) -> Dictionary:
	return rules.validate_settings(settings)


# --- sending ---------------------------------------------------------------------------------------------

func _begin(reason: String, player_ids: Array) -> Dictionary:
	var created: Dictionary = rules.new_game(player_ids, _setup, lobby.state.get("game_settings", {}), _seed_source + _games_started)
	if not CoreResult.is_ok(created):
		return created
	_games_started += 1
	_state = created["state"]
	_commit(reason, created["events"])
	return created


## Everyone who holds a seat (present or not): a rematch keeps the table, and a player who is
## away comes back to it.
func _seat_ids() -> Array:
	var ids: Array = []
	for slot: Dictionary in lobby.state["slots"]:
		if not slot["left"]:
			ids.append(slot["player_id"])
	return ids


func _commit(reason: String, events: Array) -> void:
	_seq += 1
	for slot: Dictionary in lobby.state["slots"]:
		if slot["left"] or not slot["connected"]:
			continue
		_deliver(slot["player_id"], _batch(reason, events, slot["player_id"]))


func _send_snapshot(player_id: String, reason: String) -> void:
	_deliver(player_id, _batch(reason, [], player_id))


func _batch(reason: String, events: Array, player_id: String) -> Dictionary:
	return {"seq": _seq, "reason": reason, "events": events.duplicate(true), "view": rules.view_for(_state, player_id)}


func _deliver(player_id: String, batch: Dictionary) -> void:
	if player_id == lobby.local_player_id:
		batch_ready.emit(batch)
	else:
		lobby.session.send_to_player(player_id, Envelope.make(Protocol.T_GAME_BATCH, batch))


func _refuse(player_id: String, code: String, message: String, action_type: String) -> void:
	lobby.session.send_to_player(player_id, Envelope.make(Protocol.T_GAME_ERROR, {"code": code, "message": message, "action": action_type}))
