class_name ClientSession
extends RefCounted
## Client side of a session: joins a host through any Transport, performs the
## handshake, answers pings and reports what happened through signals.
## The owner calls poll() every frame (it polls the transport too).

signal connected(welcome: Dictionary)  # welcome payload: player_id, rejoin_token, extras
signal rejected(code: String, message: String, host_info: Dictionary)  # handshake refused; host_info = {game_id, app_version} of the host
signal connect_failed(reason: String)  # could not reach the host or handshake never finished
signal host_lost(reason: String)  # connection dropped after a successful join
signal session_ended(code: String, message: String)  # host closed the session or removed us
signal message_received(message: Dictionary)  # any non-handshake, non-liveness message

enum State { IDLE, CONNECTING, HANDSHAKING, ACTIVE }

var transport: Transport
var clock: Callable = func() -> int: return Time.get_ticks_msec()
var player_id: String = ""
var rejoin_token: String = ""
## What the host runs, from its welcome or reject ("" until we hear from it).
var host_game_id: String = ""
var host_app_version: String = ""

var _app_version: String
var _game_id: String
var _handshake_timeout: int
var _host_silence_timeout: int
var _state: State = State.IDLE
var _player_name: String = ""
var _rejoin: Dictionary = {}
var _handshake_deadline: int = 0
var _last_heard: int = 0


func _init(client_transport: Transport, app_version: String, game_id: String = "", options: Dictionary = {}) -> void:
	transport = client_transport
	_app_version = app_version
	_game_id = game_id
	_handshake_timeout = int(options.get("handshake_timeout_msec", 5000))
	_host_silence_timeout = int(options.get("host_silence_timeout_msec", 20000))
	transport.join_succeeded.connect(_on_join_succeeded)
	transport.join_failed.connect(_on_join_failed)
	transport.peer_disconnected.connect(_on_peer_disconnected)
	transport.message_received.connect(_on_message)


## rejoin: optional {player_id, rejoin_token} to reclaim an existing player.
func join(address: String, player_name: String, transport_config: Dictionary = {}, rejoin: Dictionary = {}) -> void:
	_player_name = player_name
	_rejoin = rejoin
	_state = State.CONNECTING
	transport.join_session(address, transport_config)


func leave() -> void:
	_state = State.IDLE
	transport.leave()


func is_active() -> bool:
	return _state == State.ACTIVE


func send(message: Dictionary) -> void:
	if _state == State.ACTIVE:
		_send(message)


func poll() -> void:
	transport.poll()
	var now: int = _now()
	if _state == State.HANDSHAKING and now > _handshake_deadline:
		_state = State.IDLE
		transport.leave()
		connect_failed.emit("The host did not answer the handshake.")
	elif _state == State.ACTIVE and now - _last_heard > _host_silence_timeout:
		_state = State.IDLE
		transport.leave()
		host_lost.emit("The host stopped responding.")


func _on_join_succeeded() -> void:
	_state = State.HANDSHAKING
	var now: int = _now()
	_handshake_deadline = now + _handshake_timeout
	_last_heard = now
	_send(Handshake.hello(_app_version, _game_id, _player_name, str(_rejoin.get("player_id", "")), str(_rejoin.get("rejoin_token", ""))))


func _on_join_failed(reason: String) -> void:
	_state = State.IDLE
	connect_failed.emit(reason)


func _on_peer_disconnected(peer_id: int) -> void:
	if peer_id != Transport.HOST_PEER_ID:
		return
	var previous: State = _state
	_state = State.IDLE
	if previous == State.ACTIVE:
		host_lost.emit("Lost connection to the host.")
	elif previous == State.HANDSHAKING or previous == State.CONNECTING:
		connect_failed.emit("The host closed the connection during the handshake.")


func _on_message(peer_id: int, message: Dictionary) -> void:
	if peer_id != Transport.HOST_PEER_ID:
		return
	MessageLog.log_in(peer_id, player_id, str(message.get("type", "")))
	_last_heard = _now()
	var payload: Dictionary = message["payload"]
	match _state:
		State.HANDSHAKING:
			if message["type"] == Protocol.T_WELCOME:
				_state = State.ACTIVE
				player_id = str(payload.get("player_id", ""))
				rejoin_token = str(payload.get("rejoin_token", ""))
				host_game_id = str(payload.get("game_id", ""))
				host_app_version = str(payload.get("app_version", ""))
				connected.emit(payload)
			elif message["type"] == Protocol.T_REJECT:
				_state = State.IDLE
				transport.leave()
				host_game_id = str(payload.get("game_id", ""))
				host_app_version = str(payload.get("app_version", ""))
				rejected.emit(str(payload.get("code", "")), str(payload.get("message", "")), {"game_id": host_game_id, "app_version": host_app_version})
		State.ACTIVE:
			match message["type"]:
				Protocol.T_PING:
					_send(Envelope.make(Protocol.T_PONG))
				Protocol.T_PONG, Protocol.T_WELCOME, Protocol.T_REJECT:
					pass
				Protocol.T_SESSION_END:
					_state = State.IDLE
					transport.leave()
					session_ended.emit(str(payload.get("code", "")), str(payload.get("message", "")))
				_:
					message_received.emit(message)


func _send(message: Dictionary) -> void:
	MessageLog.log_out(Transport.HOST_PEER_ID, player_id, str(message["type"]))
	transport.send(Transport.HOST_PEER_ID, message)


func _now() -> int:
	return int(clock.call())
