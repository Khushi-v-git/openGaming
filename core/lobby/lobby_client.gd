class_name LobbyClient
extends RefCounted
## Client-side lobby controller: joins a host, mirrors the host's lobby state and
## turns UI intents into lobby_action messages. It never decides anything: every
## rule is checked by the host (rules 1 and 12).
##
## Call leave() when done: it breaks the references this object holds to the session.

signal joined(player_id: String)
signal join_failed(code: String, message: String)  # handshake rejected or host unreachable
signal state_changed(state: Dictionary)
signal action_failed(code: String, message: String, action_type: String)
signal game_started(state: Dictionary)
signal game_message(message: Dictionary)  # non-lobby traffic, for the game layer
signal left(code: String, message: String)  # session over: HOST_CLOSED, KICKED, HOST_LOST ...

var session: ClientSession
var state: Dictionary = {}
var player_id: String = ""


func _init(transport: Transport, app_version: String, game_id: String, session_options: Dictionary = {}) -> void:
	session = ClientSession.new(transport, app_version, game_id, session_options)
	session.connected.connect(_on_connected)
	session.rejected.connect(_on_rejected)
	session.connect_failed.connect(_on_connect_failed)
	session.host_lost.connect(_on_host_lost)
	session.session_ended.connect(_on_session_ended)
	session.message_received.connect(_on_message)


## One LobbyClient per join attempt: after join_failed or left it is spent.
func join(address: String, player_name: String, transport_config: Dictionary = {}, rejoin: Dictionary = {}) -> void:
	session.join(address, player_name, transport_config, rejoin)


func poll() -> void:
	session.poll()


func leave() -> void:
	if session.is_active():
		act({"type": "leave"})
	session.leave()
	_release()


func act(action: Dictionary) -> void:
	session.send(Envelope.make(Protocol.T_LOBBY_ACTION, {"action": action}))


func set_ready(ready: bool) -> void:
	act({"type": "set_ready", "ready": ready})


func set_name(player_name: String) -> void:
	act({"type": "set_name", "name": player_name})


func start_game() -> void:
	act({"type": "start"})


func kick(target_player_id: String) -> void:
	act({"type": "kick", "player_id": target_player_id})


func is_host() -> bool:
	return not state.is_empty() and state["host_player_id"] == player_id


# --- session events --------------------------------------------------------------

func _on_connected(welcome: Dictionary) -> void:
	player_id = str(welcome["player_id"])
	joined.emit(player_id)


func _on_rejected(code: String, message: String) -> void:
	_release()
	join_failed.emit(code, message)


func _on_connect_failed(reason: String) -> void:
	_release()
	join_failed.emit(ErrorCodes.CONNECT_FAILED, reason)


func _on_host_lost(reason: String) -> void:
	_finish(ErrorCodes.HOST_LOST, reason)


func _on_session_ended(code: String, message: String) -> void:
	_finish(code, message)


func _on_message(message: Dictionary) -> void:
	match message["type"]:
		Protocol.T_LOBBY_STATE:
			_on_lobby_state(message["payload"].get("lobby", {}))
		Protocol.T_LOBBY_ERROR:
			var payload: Dictionary = message["payload"]
			action_failed.emit(str(payload.get("code", "")), str(payload.get("message", "")), str(payload.get("action", "")))
		_:
			game_message.emit(message)


func _on_lobby_state(lobby: Dictionary) -> void:
	if lobby.is_empty():
		return
	if not state.is_empty() and int(lobby["revision"]) <= int(state["revision"]):
		return  # stale or duplicate
	var was_open: bool = state.is_empty() or state["phase"] == LobbyLogic.PHASE_OPEN
	state = lobby
	state_changed.emit(state)
	if was_open and state["phase"] == LobbyLogic.PHASE_IN_GAME:
		game_started.emit(state)


func _finish(code: String, message: String) -> void:
	_release()
	left.emit(code, message)


## Drops the signal wiring so this object and its session can be freed.
func _release() -> void:
	if session.connected.is_connected(_on_connected):
		session.connected.disconnect(_on_connected)
		session.rejected.disconnect(_on_rejected)
		session.connect_failed.disconnect(_on_connect_failed)
		session.host_lost.disconnect(_on_host_lost)
		session.session_ended.disconnect(_on_session_ended)
		session.message_received.disconnect(_on_message)
