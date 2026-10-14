class_name LobbyLogic
extends RefCounted
## Pure lobby rules: plain-data state in, Result out. No nodes, no networking, no
## timers (rule 2). State shape:
##   {phase, game_id, min_players, max_players, host_player_id, revision,
##    slots: [{player_id, name, ready, connected, left}]}
## apply() never mutates its input; on error the caller's state is untouched.
##
## Player actions (sent by clients):  set_ready {ready}, set_name {name}, leave,
##   start (host), kick {player_id} (host).
## System actions (host code only, never accepted from the wire): join {name},
##   disconnected, reconnected.
##
## The host (host_player_id) is always ready and cannot leave; if the host goes away
## the whole session ends (see HostSession.close), so there is no host transfer.

const PHASE_OPEN: String = "open"
const PHASE_IN_GAME: String = "in_game"

## The only action types the host accepts from a connected player.
const PLAYER_ACTIONS: Array[String] = ["set_ready", "set_name", "leave", "start", "kick"]


static func create(game_id: String, min_players: int, max_players: int, host_player_id: String, host_name: String) -> Dictionary:
	return {
		"phase": PHASE_OPEN,
		"game_id": game_id,
		"min_players": min_players,
		"max_players": max_players,
		"host_player_id": host_player_id,
		"revision": 0,
		"slots": [_new_slot(host_player_id, host_name, true)],
	}


## Result {ok, state} or failure. `player_id` is who the action is for/from.
static func apply(state: Dictionary, player_id: String, action: Dictionary) -> Dictionary:
	if typeof(action.get("type")) != TYPE_STRING:
		return CoreResult.failure(ErrorCodes.BAD_ACTION, "Action needs a type.")
	var next: Dictionary = state.duplicate(true)
	var result: Dictionary
	match action["type"]:
		"join":
			result = _join(next, player_id, action)
		"set_ready":
			result = _set_ready(next, player_id, action)
		"set_name":
			result = _set_name(next, player_id, action)
		"leave":
			result = _leave(next, player_id)
		"start":
			result = _start(next, player_id)
		"kick":
			result = _kick(next, player_id, action)
		"disconnected":
			result = _disconnected(next, player_id)
		"reconnected":
			result = _reconnected(next, player_id)
		_:
			return CoreResult.failure(ErrorCodes.UNKNOWN_ACTION, "Unknown action '%s'." % action["type"])
	if not CoreResult.is_ok(result):
		return result
	next["revision"] = int(next["revision"]) + 1
	return CoreResult.success({"state": next})


## Used when a saved lobby is loaded: `host_player_id` (any saved player who has not
## left) becomes the host and is the only one online; everybody else is offline until
## they rejoin with their token. Not an action: it never comes from the wire.
static func resume(state: Dictionary, host_player_id: String) -> Dictionary:
	var index: int = find_slot(state, host_player_id)
	if index < 0:
		return CoreResult.failure(ErrorCodes.UNKNOWN_PLAYER, "That player is not in the saved game.")
	if state["slots"][index]["left"]:
		return CoreResult.failure(ErrorCodes.PLAYER_LEFT, "That player left the saved game.")
	var next: Dictionary = state.duplicate(true)
	for slot: Dictionary in next["slots"]:
		slot["connected"] = slot["player_id"] == host_player_id
	next["slots"][index]["ready"] = true
	next["host_player_id"] = host_player_id
	next["revision"] = int(next["revision"]) + 1
	return CoreResult.success({"state": next})


## Pre-check for a join, used by the host as the admission policy.
static func can_join(state: Dictionary, player_name: String) -> Dictionary:
	if state["phase"] != PHASE_OPEN:
		return CoreResult.failure(ErrorCodes.GAME_IN_PROGRESS, "This game has already started.")
	if (state["slots"] as Array).size() >= int(state["max_players"]):
		return CoreResult.failure(ErrorCodes.ROOM_FULL, "This room is full.")
	return _check_name(state, "", player_name)


## What a given player may see. The lobby has no secrets, so it is the state plus
## who "you" are; the shape exists so games with hidden info follow the same pattern.
static func view_for(state: Dictionary, player_id: String) -> Dictionary:
	var view: Dictionary = state.duplicate(true)
	view["you"] = player_id
	return view


static func ready_to_start(state: Dictionary) -> bool:
	return CoreResult.is_ok(_start_check(state, state["host_player_id"]))


## Display name of a player's slot, or "" if they have none.
static func find_slot_name(state: Dictionary, player_id: String) -> String:
	var index: int = find_slot(state, player_id)
	return str(state["slots"][index]["name"]) if index >= 0 else ""


static func find_slot(state: Dictionary, player_id: String) -> int:
	var slots: Array = state["slots"]
	for i: int in slots.size():
		if slots[i]["player_id"] == player_id:
			return i
	return -1


# --- actions (operate on an already-copied state) ---------------------------------

static func _join(state: Dictionary, player_id: String, action: Dictionary) -> Dictionary:
	if find_slot(state, player_id) >= 0:
		return CoreResult.failure(ErrorCodes.ALREADY_JOINED, "You are already in this lobby.")
	var player_name: String = str(action.get("name", ""))
	var allowed: Dictionary = can_join(state, player_name)
	if not CoreResult.is_ok(allowed):
		return allowed
	(state["slots"] as Array).append(_new_slot(player_id, Handshake.clean_name(player_name)["name"], false))
	return CoreResult.success()


static func _set_ready(state: Dictionary, player_id: String, action: Dictionary) -> Dictionary:
	var index: int = find_slot(state, player_id)
	if index < 0:
		return CoreResult.failure(ErrorCodes.NOT_IN_LOBBY, "You are not in this lobby.")
	if state["phase"] != PHASE_OPEN:
		return CoreResult.failure(ErrorCodes.WRONG_PHASE, "The game has already started.")
	if typeof(action.get("ready")) != TYPE_BOOL:
		return CoreResult.failure(ErrorCodes.BAD_ACTION, "set_ready needs a true/false 'ready'.")
	if player_id != state["host_player_id"]:
		state["slots"][index]["ready"] = action["ready"]
	return CoreResult.success()


static func _set_name(state: Dictionary, player_id: String, action: Dictionary) -> Dictionary:
	var index: int = find_slot(state, player_id)
	if index < 0:
		return CoreResult.failure(ErrorCodes.NOT_IN_LOBBY, "You are not in this lobby.")
	if state["phase"] != PHASE_OPEN:
		return CoreResult.failure(ErrorCodes.WRONG_PHASE, "Names are locked once the game starts.")
	var checked: Dictionary = _check_name(state, player_id, str(action.get("name", "")))
	if not CoreResult.is_ok(checked):
		return checked
	state["slots"][index]["name"] = checked["name"]
	return CoreResult.success()


static func _leave(state: Dictionary, player_id: String) -> Dictionary:
	var index: int = find_slot(state, player_id)
	if index < 0:
		return CoreResult.failure(ErrorCodes.NOT_IN_LOBBY, "You are not in this lobby.")
	if player_id == state["host_player_id"]:
		return CoreResult.failure(ErrorCodes.HOST_CANNOT_LEAVE, "The host ends the session instead of leaving.")
	_remove_or_mark_left(state, index)
	return CoreResult.success()


static func _start(state: Dictionary, player_id: String) -> Dictionary:
	var checked: Dictionary = _start_check(state, player_id)
	if not CoreResult.is_ok(checked):
		return checked
	state["phase"] = PHASE_IN_GAME
	return CoreResult.success()


static func _kick(state: Dictionary, player_id: String, action: Dictionary) -> Dictionary:
	if player_id != state["host_player_id"]:
		return CoreResult.failure(ErrorCodes.NOT_HOST, "Only the host can remove players.")
	var target: String = str(action.get("player_id", ""))
	var index: int = find_slot(state, target)
	if index < 0:
		return CoreResult.failure(ErrorCodes.UNKNOWN_PLAYER, "No such player.")
	if target == state["host_player_id"]:
		return CoreResult.failure(ErrorCodes.HOST_CANNOT_LEAVE, "The host cannot be removed.")
	_remove_or_mark_left(state, index)
	return CoreResult.success()


static func _disconnected(state: Dictionary, player_id: String) -> Dictionary:
	var index: int = find_slot(state, player_id)
	if index < 0:
		return CoreResult.failure(ErrorCodes.NOT_IN_LOBBY, "No such player.")
	if player_id == state["host_player_id"]:
		return CoreResult.failure(ErrorCodes.HOST_CANNOT_LEAVE, "The host's connection is the session itself.")
	if state["phase"] == PHASE_OPEN:
		(state["slots"] as Array).remove_at(index)
	else:
		state["slots"][index]["connected"] = false
	return CoreResult.success()


static func _reconnected(state: Dictionary, player_id: String) -> Dictionary:
	var index: int = find_slot(state, player_id)
	if index < 0:
		return CoreResult.failure(ErrorCodes.NOT_IN_LOBBY, "No such player.")
	if state["slots"][index]["left"]:
		return CoreResult.failure(ErrorCodes.PLAYER_LEFT, "This player has left the game.")
	state["slots"][index]["connected"] = true
	return CoreResult.success()


# --- helpers ---------------------------------------------------------------------

static func _start_check(state: Dictionary, player_id: String) -> Dictionary:
	if player_id != state["host_player_id"]:
		return CoreResult.failure(ErrorCodes.NOT_HOST, "Only the host can start the game.")
	if state["phase"] != PHASE_OPEN:
		return CoreResult.failure(ErrorCodes.WRONG_PHASE, "The game has already started.")
	var slots: Array = state["slots"]
	if slots.size() < int(state["min_players"]):
		return CoreResult.failure(ErrorCodes.NOT_ENOUGH_PLAYERS, "Need at least %d players." % int(state["min_players"]))
	for slot: Dictionary in slots:
		if slot["player_id"] != state["host_player_id"] and (not slot["ready"] or not slot["connected"]):
			return CoreResult.failure(ErrorCodes.NOT_ALL_READY, "Everyone must be ready.")
	return CoreResult.success()


## Validates a display name and checks nobody else (case-insensitive) already uses it.
static func _check_name(state: Dictionary, own_player_id: String, raw_name: String) -> Dictionary:
	var cleaned: Dictionary = Handshake.clean_name(raw_name)
	if not CoreResult.is_ok(cleaned):
		return cleaned
	var wanted: String = (cleaned["name"] as String).to_lower()
	for slot: Dictionary in state["slots"]:
		if slot["player_id"] != own_player_id and (slot["name"] as String).to_lower() == wanted:
			return CoreResult.failure(ErrorCodes.NAME_TAKEN, "The name '%s' is already taken." % cleaned["name"])
	return CoreResult.success({"name": cleaned["name"]})


static func _remove_or_mark_left(state: Dictionary, index: int) -> void:
	if state["phase"] == PHASE_OPEN:
		(state["slots"] as Array).remove_at(index)
	else:
		state["slots"][index]["left"] = true
		state["slots"][index]["connected"] = false


static func _new_slot(player_id: String, player_name: String, ready: bool) -> Dictionary:
	return {"player_id": player_id, "name": player_name, "ready": ready, "connected": true, "left": false}
