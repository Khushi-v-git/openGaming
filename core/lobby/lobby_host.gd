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
## Optional: (player_id) -> Dictionary, the game's view_for() for that player. Used to
## resend the full current game state to a player who rejoins mid-game (rules 7, 9).
var game_view_provider: Callable = Callable()

var _app_version: String
var _game_id: String
var _started: bool = false


func _init(transport: Transport, app_version: String, game_id: String, host_name: String, min_players: int, max_players: int, session_options: Dictionary = {}) -> void:
	_app_version = app_version
	_game_id = game_id
	session = HostSession.new(transport, app_version, game_id, session_options)
	local_player_id = session.registry.create(host_name)["player_id"]
	state = LobbyLogic.create(game_id, min_players, max_players, local_player_id, host_name)
	session.admission_policy = _admission
	session.rejoin_policy = _rejoin_policy
	session.player_joined.connect(_on_player_joined)
	session.player_disconnected.connect(_on_player_disconnected)
	session.player_message.connect(_on_player_message)
	session.closed.connect(_on_session_closed)


## Starts listening/registering. Returns the transport's session info (address etc.).
func start(transport_config: Dictionary) -> Dictionary:
	_started = true
	return session.start(transport_config)


## The whole session as plain data, for saving (see SessionSnapshot: it is PRIVATE,
## it contains rejoin tokens). `game_state` is the game's own serialized state.
func snapshot(game_state: Dictionary = {}) -> Dictionary:
	return SessionSnapshot.capture(_app_version, _game_id, state, session.registry, game_state)


## Resumes a saved session. Call on a fresh LobbyHost, before start(). `as_player_id`
## is which saved player is hosting now (default: the saved host); everyone else is
## offline until they rejoin with the identity in the save. Returns {ok, game_state}.
func restore(saved: Dictionary, as_player_id: String = "") -> Dictionary:
	if _started:
		return CoreResult.failure(ErrorCodes.WRONG_PHASE, "A save can only be loaded before hosting starts.")
	var checked: Dictionary = SessionSnapshot.validate(saved, _app_version, _game_id)
	if not CoreResult.is_ok(checked):
		return checked
	var host_id: String = as_player_id if not as_player_id.is_empty() else str(saved["lobby"]["host_player_id"])
	var resumed: Dictionary = LobbyLogic.resume(saved["lobby"], host_id)
	if not CoreResult.is_ok(resumed):
		return resumed
	session.registry = PlayerRegistry.from_dict(saved["players"])
	state = resumed["state"]
	local_player_id = host_id
	return CoreResult.success({"game_state": saved["game_state"].duplicate(true)})


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


func _rejoin_policy(player_id: String) -> Dictionary:
	var index: int = LobbyLogic.find_slot(state, player_id)
	if index >= 0:
		if state["slots"][index]["left"]:
			return CoreResult.failure(ErrorCodes.PLAYER_LEFT, "You left this game.")
		return CoreResult.success()
	if state["phase"] != LobbyLogic.PHASE_OPEN:
		return CoreResult.failure(ErrorCodes.NOT_IN_LOBBY, "You are no longer part of this game.")
	# Their slot was freed when they dropped from the open lobby: they need a free seat.
	return LobbyLogic.can_join(state, session.registry.name_of(player_id))


func _on_player_joined(player_id: String, rejoined: bool) -> void:
	var action: Dictionary = {"type": "join", "name": session.registry.name_of(player_id)}
	if rejoined and LobbyLogic.find_slot(state, player_id) >= 0:
		action = {"type": "reconnected"}
	var result: Dictionary = LobbyLogic.apply(state, player_id, action)
	if CoreResult.is_ok(result):
		state = result["state"]
		_publish()  # everyone, including a rejoiner, gets the full current lobby state
		if rejoined:
			_send_game_view(player_id)
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
	session.rejoin_policy = Callable()
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
			var target: String = str(action["player_id"])
			session.kick_player(target, ErrorCodes.KICKED, "You were removed by the host.")
			_revoke_if_gone(target)
		"leave":
			session.kick_player(player_id, ErrorCodes.LEFT, "You left the lobby.")  # closes their connection
			_revoke_if_gone(player_id)
		"start":
			_forget_players_without_a_seat()
	_publish()
	if type == "start":
		game_started.emit(state)
	return result


## A player with no slot left (kicked or left in the open lobby) must not be able to
## come back with their old token.
func _revoke_if_gone(player_id: String) -> void:
	if LobbyLogic.find_slot(state, player_id) < 0:
		session.registry.remove(player_id)


## Once the game starts, drop identities of players who dropped out of the open lobby.
func _forget_players_without_a_seat() -> void:
	for player_id: String in session.registry.player_ids():
		_revoke_if_gone(player_id)


func _send_game_view(player_id: String) -> void:
	if state["phase"] != LobbyLogic.PHASE_IN_GAME or not game_view_provider.is_valid():
		return
	var view: Dictionary = game_view_provider.call(player_id)
	session.send_to_player(player_id, Envelope.make(Protocol.T_GAME_STATE, {"rejoin": true, "view": view}))


func _publish() -> void:
	session.broadcast(Envelope.make(Protocol.T_LOBBY_STATE, {"lobby": state}))
	state_changed.emit(state)
