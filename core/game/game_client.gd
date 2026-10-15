class_name GameClient
extends RefCounted
## A player's side of a networked game: sends actions to the host and hands the host's batches
## on, in order. It holds no rules and no state (rule 12): the host decides everything.
##
## If a batch arrives out of sequence (one was lost or delayed) the screen still shows the newest
## picture (EventTimeline snaps), and this asks the host for a full snapshot (game_resync) so the
## two are certain to agree.

signal batch_ready(batch: Dictionary)
signal action_rejected(error: Dictionary)  # {code, message, action}
signal resync_requested()

const _EVENT_REASONS: Array[String] = ["action", "settle"]
## These replace the whole picture and are accepted whatever their seq (the host is authoritative).
const _SNAPSHOT_REASONS: Array[String] = ["start", "rematch", "rejoin", "resync", "load"]

var lobby: LobbyClient

var _last_seq: int = -1


func _init(lobby_client: LobbyClient) -> void:
	lobby = lobby_client
	lobby.game_message.connect(_on_message)
	lobby.action_failed.connect(_on_action_failed)


func last_seq() -> int:
	return _last_seq


## Sends a game action. The host answers with a batch, or a refusal (action_rejected).
func submit(action: Dictionary) -> void:
	lobby.session.send(Envelope.make(Protocol.T_GAME_ACTION, {"action": action}))


## Asks the host for a full snapshot.
func request_resync() -> void:
	resync_requested.emit()
	lobby.session.send(Envelope.make(Protocol.T_GAME_RESYNC))


func _on_message(message: Dictionary) -> void:
	var payload: Dictionary = message["payload"]
	match str(message["type"]):
		Protocol.T_GAME_BATCH:
			if not (payload.has("seq") and payload.has("reason") and payload.has("events") and payload.has("view")):
				return
			var seq: int = int(payload["seq"])
			var snapshot: bool = _SNAPSHOT_REASONS.has(str(payload["reason"]))
			if seq <= _last_seq and not snapshot:
				return  # a duplicate or an old batch
			var gap: bool = _last_seq >= 0 and seq != _last_seq + 1 and _EVENT_REASONS.has(str(payload["reason"]))
			_last_seq = seq
			batch_ready.emit(payload)
			if gap:
				request_resync()
		Protocol.T_GAME_ERROR:
			action_rejected.emit({"code": str(payload.get("code", "")), "message": str(payload.get("message", "")), "action": str(payload.get("action", ""))})


## The host's lobby layer refuses game messages while the game is paused.
func _on_action_failed(code: String, message: String, action_type: String) -> void:
	if action_type == Protocol.T_GAME_ACTION:
		action_rejected.emit({"code": code, "message": message, "action": action_type})
