class_name LobbyHost
extends RefCounted
## Host-side lobby controller: owns a HostSession and the authoritative lobby state.
## Clients send lobby_action messages; the host validates them with LobbyLogic,
## applies them and broadcasts the new state (rule 1). The host's own player acts
## through act(), without going over the transport.
##
## Call close() when done: it breaks the references this object holds to the session.

signal state_changed(state: Dictionary)
signal game_started(state: Dictionary)
signal game_message(player_id: String, message: Dictionary)  # non-lobby traffic, for the game layer
signal closed()

var session: HostSession
var state: Dictionary
var local_player_id: String


func _init(transport: Transport, app_version: String, game_id: String, host_name: String, min_players: int, max_players: int, session_options: Dictionary = {}) -> void:
	session = HostSession.new(transport, app_version, game_id, session_options)
	local_player_id = session.registry.create(host_name)["player_id"]
	state = LobbyLogic.create(game_id, min_players, max_players, local_player_id, host_name)
	session.admission_policy = _admission
	session.player_joined.connect(_on_player_joined)
	session.player_disconnected.connect(_on_player_disconnected)
	session.player_message.connect(_on_player_message)
	session.closed.connect(_on_session_closed)


## Starts listening/registering. Returns the transport's session info (address etc.).
func start(transport_config: Dictionary) -> Dictionary:
	return session.start(transport_config)


func poll() -> void:
	session.poll()


## An action by the host's own player (same rules as any other player).
func act(action: Dictionary) -> Dictionary:
	return _apply_player_action(local_player_id, action)


## Ends the session: tells players, then stops. `closed` fires when finished.
func close(reason: String = "The host closed the session.") -> void:
	session.close(reason)


# --- session events --------------------------------------------------------------

func _admission(player_name: String) -> Dictionary:
	return LobbyLogic.can_join(state, player_name)


func _on_player_joined(player_id: String, _rejoined: bool) -> void:
	var result: Dictionary = LobbyLogic.apply(state, player_id, {"type": "join", "name": session.registry.name_of(player_id)})
	if CoreResult.is_ok(result):
		state = result["state"]
		_publish()
	else:
		# Lost a race between admission and join (e.g. last seat taken): remove them.
		session.kick_player(player_id, CoreResult.error_code(result), str(result["error"]["message"]))


func _on_player_disconnected(player_id: String) -> void:
	var result: Dictionary = LobbyLogic.apply(state, player_id, {"type": "disconnected"})
	if CoreResult.is_ok(result):
		state = result["state"]
		_publish()


func _on_player_message(player_id: String, message: Dictionary) -> void:
	if message["type"] != Protocol.T_LOBBY_ACTION:
		game_message.emit(player_id, message)
		return
	var action: Variant = message["payload"].get("action")
	var result: Dictionary
	if typeof(action) != TYPE_DICTIONARY:
		result = CoreResult.failure(ErrorCodes.MALFORMED, "lobby_action needs an 'action' object.")
	else:
		result = _apply_player_action(player_id, action)
	if not CoreResult.is_ok(result):
		var failed_type: String = str(action.get("type", "")) if typeof(action) == TYPE_DICTIONARY else ""
		session.send_to_player(player_id, Envelope.make(Protocol.T_LOBBY_ERROR, {
			"code": CoreResult.error_code(result),
			"message": result["error"]["message"],
			"action": failed_type,
		}))


func _on_session_closed() -> void:
	session.admission_policy = Callable()
	session.player_joined.disconnect(_on_player_joined)
	session.player_disconnected.disconnect(_on_player_disconnected)
	session.player_message.disconnect(_on_player_message)
	session.closed.disconnect(_on_session_closed)
	closed.emit()


# --- helpers ---------------------------------------------------------------------

func _apply_player_action(player_id: String, action: Dictionary) -> Dictionary:
	var type: String = str(action.get("type", ""))
	if not LobbyLogic.PLAYER_ACTIONS.has(type):
		return CoreResult.failure(ErrorCodes.UNKNOWN_ACTION, "Unknown action '%s'." % type)
	var result: Dictionary = LobbyLogic.apply(state, player_id, action)
	if not CoreResult.is_ok(result):
		return result
	state = result["state"]
	match type:
		"set_name":
			session.registry.set_name(player_id, str(LobbyLogic.find_slot_name(state, player_id)))
		"kick":
			session.kick_player(str(action["player_id"]), ErrorCodes.KICKED, "You were removed by the host.")
	_publish()
	if type == "start":
		game_started.emit(state)
	return result


func _publish() -> void:
	session.broadcast(Envelope.make(Protocol.T_LOBBY_STATE, {"lobby": state}))
	state_changed.emit(state)
