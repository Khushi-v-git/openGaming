class_name HostSession
extends RefCounted
## Host side of a session: runs the handshake, tracks players, enforces limits and
## routes post-handshake messages. Works over any Transport; knows nothing about
## sockets. The owner calls poll() every frame (it polls the transport too).
##
## Hooks (set before start):
##   admission_policy(player_name) -> Result   veto a join (room full, name taken...).
##   rejoin_policy(player_id) -> Result         veto a rejoin (player left, room full...).
##   claim_policy(player_name) -> String        a fresh hello whose name matches an offline
##                                              player's seat returns that player_id: the host
##                                              is asked (claim_requested) and answers with
##                                              answer_claim(). "" means no claim.
##   welcome_extra(player_id) -> Dictionary    extra data for that player's welcome.
##
## Options (all optional): max_pending_handshakes, handshake_timeout_msec,
## ping_interval_msec, ping_timeout_msec (0 turns pings / the silence kick off; the defaults come
## from transport.keepalive_policy()), rate_burst, rate_per_sec,
## max_rate_violations, pending_burst, pending_per_sec, close_grace_msec, claim_timeout_msec.

signal player_joined(player_id: String, rejoined: bool)
signal player_disconnected(player_id: String)
signal player_message(player_id: String, message: Dictionary)
signal hosting(info: Dictionary)  # transport is live: info.address is what to share
signal host_failed(reason: String)
signal claim_requested(player_id: String, player_name: String)  # a returning player asks to take their seat back
signal claim_cancelled(player_id: String)  # ... and gave up, timed out or was replaced
signal closed()  # after close(): everyone has left or the grace period ended

var transport: Transport
var registry: PlayerRegistry = PlayerRegistry.new()
## Milliseconds clock. Tests replace it to move time without waiting.
var clock: Callable = func() -> int: return Time.get_ticks_msec()
var admission_policy: Callable = Callable()
var rejoin_policy: Callable = Callable()
var claim_policy: Callable = Callable()
var welcome_extra: Callable = Callable()

var _app_version: String
var _game_id: String
var _max_pending: int
var _handshake_timeout: int
var _ping_interval: int
var _ping_timeout: int
var _rate_burst: float
var _rate_per_sec: float
var _max_violations: int
var _pending_burst: float
var _pending_per_sec: float
var _close_grace: int
var _claim_timeout: int
var _shutdown_deadline: int = 0  # non-zero once close() was called
var _closed: bool = false

var _pending: Dictionary = {}  # peer_id -> {since, limiter}
var _players: Dictionary = {}  # peer_id -> {limiter, last_heard, last_ping, violations}
var _claims: Dictionary = {}  # peer_id -> {player_id, name, since}: waiting for the host's answer
var _closing: Dictionary = {}  # peer_id -> true (we already sent a reject/kick)


func _init(host_transport: Transport, app_version: String, game_id: String, options: Dictionary = {}) -> void:
	transport = host_transport
	_app_version = app_version
	_game_id = game_id
	_max_pending = int(options.get("max_pending_handshakes", 8))
	_handshake_timeout = int(options.get("handshake_timeout_msec", 5000))
	_ping_interval = int(options.get("ping_interval_msec", -1))  # 0 = no pings; -1 = ask the transport
	_ping_timeout = int(options.get("ping_timeout_msec", -1))  # 0 = never kick for silence
	_rate_burst = float(options.get("rate_burst", 30))
	_rate_per_sec = float(options.get("rate_per_sec", 20))
	_max_violations = int(options.get("max_rate_violations", 20))
	_pending_burst = float(options.get("pending_burst", 5))
	_pending_per_sec = float(options.get("pending_per_sec", 2))
	_close_grace = int(options.get("close_grace_msec", 1000))
	_claim_timeout = int(options.get("claim_timeout_msec", 60000))
	transport.peer_connected.connect(_on_peer_connected)
	transport.peer_disconnected.connect(_on_peer_disconnected)
	transport.message_received.connect(_on_message)
	transport.session_ready.connect(_on_session_ready)
	transport.host_failed.connect(_on_host_failed)


## Starts hosting. Returns a failure if it could not even start; otherwise the address
## to share arrives with the `hosting` signal (or `host_failed`).
func start(transport_config: Dictionary) -> Dictionary:
	var started: Dictionary = transport.host_session(transport_config)
	if CoreResult.is_ok(started):
		_resolve_keepalive()
	return started


## Options win; anything left unset comes from the transport that was actually chosen (a
## "auto" transport only knows once hosting has started).
func _resolve_keepalive() -> void:
	var keepalive: Dictionary = transport.keepalive_policy()
	if _ping_interval < 0:
		_ping_interval = int(keepalive["ping_interval_msec"])
	if _ping_timeout < 0:
		_ping_timeout = int(keepalive["ping_timeout_msec"])


func poll() -> void:
	if _closed:
		return
	transport.poll()
	var now: int = _now()
	if _shutdown_deadline != 0:
		if _players.is_empty() or now >= _shutdown_deadline:
			_finish_close()
		return
	for peer_id: int in _pending.keys():
		if now - int(_pending[peer_id]["since"]) >= _handshake_timeout:
			_refuse(peer_id, ErrorCodes.HANDSHAKE_TIMEOUT, "The handshake took too long.")
	for peer_id: int in _claims.keys():
		if now - int(_claims[peer_id]["since"]) >= _claim_timeout:
			_refuse(peer_id, ErrorCodes.HANDSHAKE_TIMEOUT, "The host did not answer in time.")
	for peer_id: int in _players.keys():
		if _closing.has(peer_id):
			continue
		var entry: Dictionary = _players[peer_id]
		if _ping_timeout > 0 and now - int(entry["last_heard"]) > _ping_timeout:
			_kick(peer_id, ErrorCodes.PING_TIMEOUT, "No response from your connection.")
		elif _ping_interval > 0 and now - int(entry["last_ping"]) >= _ping_interval:
			entry["last_ping"] = now
			_send(peer_id, Envelope.make(Protocol.T_PING))


func send_to_player(player_id: String, message: Dictionary) -> void:
	var peer_id: int = registry.peer_of(player_id)
	if peer_id != 0 and _players.has(peer_id):
		_send(peer_id, message)


## Sends to every player who has completed the handshake.
func broadcast(message: Dictionary) -> void:
	for peer_id: int in _players.keys():
		if not _closing.has(peer_id):
			_send(peer_id, message)


func kick_player(player_id: String, code: String, message: String) -> void:
	var peer_id: int = registry.peer_of(player_id)
	if peer_id != 0 and _players.has(peer_id):
		_kick(peer_id, code, message)


## The host's answer to claim_requested. Approving binds the waiting connection to the
## seat with a brand-new token (the old one dies); declining refuses it.
func answer_claim(player_id: String, approve: bool) -> void:
	var peer_id: int = _claim_peer(player_id)
	if peer_id == 0:
		return
	if not approve:
		_refuse(peer_id, ErrorCodes.CLAIM_DENIED, "The host did not let you back in.")
		return
	_claims.erase(peer_id)
	var stale_peer: int = registry.peer_of(player_id)
	if stale_peer != 0:
		_replace_connection(stale_peer)
	registry.rotate_token(player_id)
	_admit(peer_id, player_id, true)


## Player ids with a request waiting for the host.
func pending_claims() -> Array[String]:
	var ids: Array[String] = []
	for peer_id: int in _claims:
		ids.append(_claims[peer_id]["player_id"])
	return ids


func connected_player_ids() -> Array[String]:
	var ids: Array[String] = []
	for peer_id: int in _players.keys():
		var player_id: String = registry.player_of_peer(peer_id)
		if not player_id.is_empty():
			ids.append(player_id)
	return ids


## Tells players the session is over, then stops hosting once they have gone (or
## after close_grace_msec). Keep calling poll() until `closed` is emitted, so the
## goodbye actually reaches everyone; use close_now() when that is not possible.
func close(reason: String = "The host closed the session.") -> void:
	if _shutdown_deadline != 0:
		return
	broadcast(Envelope.make(Protocol.T_SESSION_END, {"code": "HOST_CLOSED", "message": reason}))
	for peer_id: int in _players.keys():
		_closing[peer_id] = true
	_shutdown_deadline = _now() + _close_grace


## Stops hosting immediately. Players see a lost connection, not a goodbye.
func close_now() -> void:
	_finish_close()


func is_closed() -> bool:
	return _closed


# --- transport events ------------------------------------------------------------

func _finish_close() -> void:
	if _closed:
		return
	_closed = true
	transport.leave()
	_pending.clear()
	_players.clear()
	_claims.clear()
	_closing.clear()
	transport.peer_connected.disconnect(_on_peer_connected)
	transport.peer_disconnected.disconnect(_on_peer_disconnected)
	transport.message_received.disconnect(_on_message)
	transport.session_ready.disconnect(_on_session_ready)
	transport.host_failed.disconnect(_on_host_failed)
	closed.emit()


func _on_session_ready(info: Dictionary) -> void:
	hosting.emit(info)


func _on_host_failed(reason: String) -> void:
	host_failed.emit(reason)


func _on_peer_connected(peer_id: int) -> void:
	if _shutdown_deadline != 0:
		_refuse(peer_id, ErrorCodes.KICKED, "The host is closing the session.")
		return
	if _pending.size() >= _max_pending:
		_refuse(peer_id, ErrorCodes.TOO_MANY_PENDING, "The host is busy. Try again in a moment.")
		return
	var now: int = _now()
	_pending[peer_id] = {"since": now, "limiter": RateLimiter.new(_pending_burst, _pending_per_sec, now)}


func _on_peer_disconnected(peer_id: int) -> void:
	_pending.erase(peer_id)
	_drop_claim(peer_id)
	_closing.erase(peer_id)
	_players.erase(peer_id)
	var player_id: String = registry.unbind_peer(peer_id)
	if not player_id.is_empty():
		player_disconnected.emit(player_id)


func _on_message(peer_id: int, message: Dictionary) -> void:
	MessageLog.log_in(peer_id, registry.player_of_peer(peer_id), str(message.get("type", "")))
	if _closing.has(peer_id):
		return
	var now: int = _now()
	if _claims.has(peer_id):
		return  # waiting for the host; nothing they say matters until it answers
	if _pending.has(peer_id):
		if not (_pending[peer_id]["limiter"] as RateLimiter).allow(now):
			_refuse(peer_id, ErrorCodes.RATE_LIMITED, "Too many messages.")
			return
		_on_pending_message(peer_id, message)
	elif _players.has(peer_id):
		var entry: Dictionary = _players[peer_id]
		entry["last_heard"] = now
		if entry["unconfirmed"]:
			entry["unconfirmed"] = false
			registry.confirm_token(registry.player_of_peer(peer_id))
		if not (entry["limiter"] as RateLimiter).allow(now):
			entry["violations"] = int(entry["violations"]) + 1
			if int(entry["violations"]) > _max_violations:
				_kick(peer_id, ErrorCodes.RATE_LIMITED, "You are sending too many messages.")
			return
		_on_player_message(peer_id, message)


func _on_pending_message(peer_id: int, message: Dictionary) -> void:
	if message["type"] != Protocol.T_HELLO:
		_refuse(peer_id, ErrorCodes.UNEXPECTED_MESSAGE, "Expected a hello message first.")
		return
	var checked: Dictionary = Handshake.validate_hello(message, _app_version, _game_id)
	if not CoreResult.is_ok(checked):
		_refuse(peer_id, CoreResult.error_code(checked), str(checked["error"]["message"]))
		return
	if not str(checked["player_id"]).is_empty():
		_handle_rejoin(peer_id, str(checked["player_id"]), str(checked["rejoin_token"]))
		return
	if claim_policy.is_valid():
		var claimed: String = str(claim_policy.call(checked["player_name"]))
		if not claimed.is_empty():
			_begin_claim(peer_id, claimed, checked["player_name"])
			return
	if admission_policy.is_valid():
		var verdict: Dictionary = admission_policy.call(checked["player_name"])
		if not CoreResult.is_ok(verdict):
			_refuse(peer_id, CoreResult.error_code(verdict), str(verdict["error"]["message"]))
			return
	var player: Dictionary = registry.create(checked["player_name"])
	_admit(peer_id, player["player_id"], false)


func _on_player_message(peer_id: int, message: Dictionary) -> void:
	var player_id: String = registry.player_of_peer(peer_id)
	if player_id.is_empty():
		return  # the player was removed (kicked/left) but the connection is still closing
	match message["type"]:
		Protocol.T_PING:
			_send(peer_id, Envelope.make(Protocol.T_PONG))
		Protocol.T_PONG:
			pass
		Protocol.T_HELLO:
			_kick(peer_id, ErrorCodes.UNEXPECTED_MESSAGE, "Already connected.")
		_:
			if message["protocol_version"] != Protocol.PROTOCOL_VERSION:
				_kick(peer_id, ErrorCodes.PROTOCOL_MISMATCH, "Protocol version changed mid-session.")
				return
			player_message.emit(player_id, message)


# --- helpers ---------------------------------------------------------------------

## A returning player proves who they are with player_id + rejoin_token. Unknown ids
## and wrong tokens get the same answer so ids cannot be probed.
func _handle_rejoin(peer_id: int, player_id: String, token: String) -> void:
	if not registry.verify_token(player_id, token):
		_refuse(peer_id, ErrorCodes.BAD_TOKEN, "Unknown player or rejoin token.")
		return
	if rejoin_policy.is_valid():
		var verdict: Dictionary = rejoin_policy.call(player_id)
		if not CoreResult.is_ok(verdict):
			_refuse(peer_id, CoreResult.error_code(verdict), str(verdict["error"]["message"]))
			return
	var stale_peer: int = registry.peer_of(player_id)
	if stale_peer != 0:
		_replace_connection(stale_peer)
	registry.rotate_token(player_id, token)
	_admit(peer_id, player_id, true)


## The same player connected again before we noticed the old connection died.
func _replace_connection(old_peer_id: int) -> void:
	_send(old_peer_id, Envelope.make(Protocol.T_SESSION_END, {"code": ErrorCodes.REPLACED, "message": "You connected from somewhere else."}))
	_closing[old_peer_id] = true
	_players.erase(old_peer_id)
	registry.unbind_peer(old_peer_id)
	transport.disconnect_peer(old_peer_id)


func _admit(peer_id: int, player_id: String, rejoined: bool) -> void:
	var now: int = _now()
	_pending.erase(peer_id)
	_players[peer_id] = {
		"limiter": RateLimiter.new(_rate_burst, _rate_per_sec, now),
		"last_heard": now,
		"last_ping": now,
		"violations": 0,
		"unconfirmed": rejoined,  # until their first message proves they got the new token
	}
	registry.bind_peer(player_id, peer_id)
	var extra: Dictionary = {}
	if welcome_extra.is_valid():
		extra = welcome_extra.call(player_id)
	_send(peer_id, Handshake.welcome(player_id, registry.token_of(player_id), _game_id, _app_version, extra))
	player_joined.emit(player_id, rejoined)


## A returning player (no saved identity) asks for their seat by name. The connection
## waits, told so with `pending`, until the host answers.
func _begin_claim(peer_id: int, player_id: String, player_name: String) -> void:
	var earlier: int = _claim_peer(player_id)
	if earlier != 0:
		_refuse(earlier, ErrorCodes.CLAIM_DENIED, "Another request for this seat replaced yours.")
	_pending.erase(peer_id)
	_claims[peer_id] = {"player_id": player_id, "name": player_name, "since": _now()}
	_send(peer_id, Envelope.make(Protocol.T_PENDING, {"reason": "claim", "message": "Waiting for the host to let you back in."}))
	claim_requested.emit(player_id, player_name)


func _claim_peer(player_id: String) -> int:
	for peer_id: int in _claims:
		if _claims[peer_id]["player_id"] == player_id:
			return peer_id
	return 0


func _drop_claim(peer_id: int) -> void:
	if _claims.has(peer_id):
		var player_id: String = _claims[peer_id]["player_id"]
		_claims.erase(peer_id)
		claim_cancelled.emit(player_id)


## Rejects a peer that has not completed the handshake, then closes it.
func _refuse(peer_id: int, code: String, message: String) -> void:
	_drop_claim(peer_id)
	_pending.erase(peer_id)
	_closing[peer_id] = true
	_send(peer_id, Handshake.reject(code, message, _game_id, _app_version))
	transport.disconnect_peer(peer_id)


## Removes a handshaken player and tells them why.
func _kick(peer_id: int, code: String, message: String) -> void:
	_closing[peer_id] = true
	_send(peer_id, Envelope.make(Protocol.T_SESSION_END, {"code": code, "message": message}))
	transport.disconnect_peer(peer_id)


func _send(peer_id: int, message: Dictionary) -> void:
	MessageLog.log_out(peer_id, registry.player_of_peer(peer_id), str(message["type"]))
	transport.send(peer_id, message)


func _now() -> int:
	return int(clock.call())
