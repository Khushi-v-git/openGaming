class_name GameController
extends RefCounted
## What a game screen talks to. The screen shows what the controller tells it and sends the
## player's actions to it; it never knows whether the game runs on this computer (hot-seat),
## on the host's app (the host's own screen) or somewhere across the network (a client).
## Implementations: LocalGameController now; the network ones later.
##
## A batch is plain data: {seq, reason, events, view}.
##   seq     1, 2, 3 ... one per host broadcast; a gap tells the receiver it missed something
##   reason  why it was sent: "action" or "settle" (normal play), or "start", "rejoin",
##           "resync", "rematch", "load" (the whole picture changed: show it, do not replay it)
##   events  what happened, in order, for animation (empty for a snapshot)
##   view    what this player may see once the events are over
## Batches arrive from an action call or poll(), never from a timer.

signal batch_ready(batch: Dictionary)
## An action was refused: {code, message}. The game state did not change.
signal action_rejected(error: Dictionary)
## Who is here changed (networked games): see presence().
signal presence_changed(info: Dictionary)
## The host sent everyone back to the lobby: leave the game screen.
signal ended()
## The session is over (the host closed it, you were removed, the connection was lost): {code, message}.
signal lost(error: Dictionary)
## The link to the host or relay is degraded or restored: a Transport LINK_* value.
signal link_changed(state: String)

const REASON_START: String = "start"
const REASON_ACTION: String = "action"
const REASON_SETTLE: String = "settle"
const REASON_REJOIN: String = "rejoin"
const REASON_RESYNC: String = "resync"
const REASON_REMATCH: String = "rematch"
const REASON_LOAD: String = "load"


## The player this screen acts as. "" means "whoever's turn it is" (hot-seat).
func local_player_id() -> String:
	return ""


## Sends an action as the local player. The result arrives as batch_ready or action_rejected.
func submit_action(_action: Dictionary) -> void:
	pass


## Whether this screen may start a new game with the same players (the host, or hot-seat).
func can_rematch() -> bool:
	return false


## Starts a new game with the same players and settings. Every screen jumps to the fresh game
## (reason "rematch") instead of replaying anything. Returns {ok} or a failure.
func rematch() -> Dictionary:
	return CoreResult.failure(ErrorCodes.NOT_HOST, "Only the host can start a rematch.")


## Who is at the table, in seat order: [{player_id, name}]. Empty if the controller does not know.
func players() -> Array:
	return []


## {paused, away: [{player_id, name}], can_continue, is_host, min_active}. A game with everyone present is
## not paused. While paused the host refuses game actions (GAME_PAUSED).
func presence() -> Dictionary:
	return {"paused": false, "away": [], "can_continue": true, "is_host": true, "min_active": 1}


## Host decisions while someone is away (rule 7). Only the host may; others get NOT_HOST.
func continue_without_waiting() -> Dictionary:
	return _not_host()


func wait_again() -> Dictionary:
	return _not_host()


func remove_player(_player_id: String) -> Dictionary:
	return _not_host()


## Sends everyone back to the lobby (host only).
func end_game() -> Dictionary:
	return _not_host()


## Leaves the table politely (a guest leaves; the host closes the session).
func leave() -> void:
	pass


func _not_host() -> Dictionary:
	return CoreResult.failure(ErrorCodes.NOT_HOST, "Only the host can do that.")


## The rules object, for the screen's read-only questions (is_finished, current_player).
func rules() -> GameRules:
	return null


## The newest view, or {} before the game starts.
func latest_view() -> Dictionary:
	return {}
