class_name RelayTransport
extends Transport
## Transport through a relay (relay/cloudflare): the host and every joiner connect OUTWARD to
## the relay over wss:// and meet in a room named by a 6-character code. Nothing here listens on
## a port, so there is nothing to forward or tunnel. The relay only forwards frames between the
## host and each joiner; the host stays the single authority (rules 1 and 3a).
##
## Host config:  relay_url (required: ws:// or wss://), fixed_code (tests against a dev relay).
## Join config:  relay_url, join_timeout_msec.
## Both:         ping_msec, watchdog_msec (defaults come from the relay's own advice in its first
##               reply), reconnect_backoff_msec (host only).
##
## Wire format (see relay/cloudflare/src/frames.ts). The relay only reads the first character:
##   to relay:  host  S<peer>:<payload>  K<peer>:<code>  Q        joiner  M<payload>   both  "ping"
##   from relay: host M<peer>:<payload>  J<peer>  L<peer>         joiner  M<payload>  H  B  X<code>
##               both  C<json> (hosted / joined / resumed / error)  X<code>  "pong"
## Payloads are the envelope JSON of rule 4, untouched.
##
## Liveness: the session layer's own pings are NOT sent through a relay (they would cost quota and
## wake the room), see keepalive_policy(). Instead each socket sends "ping" every ping_msec; the
## relay answers "pong" without waking up. No traffic at all for watchdog_msec means the link is
## dead: a joiner sees peer_disconnected(HOST_PEER_ID), a host reconnects and resumes its room.

const DEFAULT_PING_MSEC: int = 15000
const DEFAULT_WATCHDOG_MSEC: int = 45000
const DEFAULT_JOIN_TIMEOUT_MSEC: int = 10000
const DEFAULT_BACKOFF_MSEC: Array = [500, 1000, 2000, 4000]
const RESUME_MARGIN_MSEC: int = 5000  # beyond the relay's grace period before we give up
const MAX_QUEUED_MESSAGES: int = 100
const MAX_QUEUED_CHARS: int = 524288
const _BUFFER_BYTES: int = Protocol.MAX_MESSAGE_BYTES * 2
const ALPHABET: String = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const CODE_LENGTH: int = 6

## Relay error code -> what the player is told. Anything unexpected is RELAY_BUSY.
const REASONS: Dictionary = {
	"ROOM_NOT_FOUND": "No game was found with that room code. Check the code and try again.",
	"ROOM_FULL": "That room is full.",
	"BAD_TOKEN": "The relay did not accept this host's room key.",
	"RATE_LIMITED": "Too many attempts or messages. Wait a moment and try again.",
	"RELAY_BUSY": "The relay is busy or cannot be reached right now. Try again later, or use a direct address.",
	"HOST_AWAY": "The host's connection dropped and is being restored. Try again in a moment.",
	"ROOM_CLOSED": "The room was closed.",
	"KICKED": "You were removed from the room.",
	"TIMEOUT": "The connection to the relay timed out.",
	"REPLACED": "This host connected from somewhere else.",
	"TOO_LARGE": "A message was too large for the relay.",
	"BAD_FRAME": "The relay did not understand a message.",
}
const CLOSE_CODE_NAMES: Dictionary = {
	4404: "ROOM_NOT_FOUND", 4409: "ROOM_FULL", 4401: "BAD_TOKEN", 4429: "RATE_LIMITED", 4503: "RELAY_BUSY",
	4423: "HOST_AWAY", 4410: "ROOM_CLOSED", 4403: "KICKED", 4408: "TIMEOUT", 4412: "REPLACED", 1009: "TOO_LARGE", 1003: "BAD_FRAME",
}

enum Role { NONE, HOST, JOINING, CLIENT }
enum Link { CONNECTING, GREETING, LIVE, RECONNECTING }

## Milliseconds clock; tests replace it.
var clock: Callable = func() -> int: return Time.get_ticks_msec()
## The relay's error code behind the last failure ("" if none): for logs, tests and UI details.
var last_error_code: String = ""

var _role: Role = Role.NONE
var _link: Link = Link.CONNECTING
var _epoch: int = 0
var _ws: WebSocketPeer = null
var _base_url: String = ""
var _code: String = ""
var _token: String = ""
var _fixed_code: String = ""
var _early_failure: String = ""
var _connect_deadline: int = 0

var _ping_msec: int = DEFAULT_PING_MSEC
var _watchdog_msec: int = DEFAULT_WATCHDOG_MSEC
var _grace_msec: int = 60000
var _join_timeout_msec: int = DEFAULT_JOIN_TIMEOUT_MSEC
var _backoff: Array = DEFAULT_BACKOFF_MSEC
var _last_ping: int = 0
var _last_heard: int = 0

var _peers: Dictionary = {}  # host: peer_id -> true
var _kicked: Dictionary = {}  # host: peers we told the relay to remove (their messages are ignored)
var _outbox: Array[String] = []  # host: frames waiting for the link to come back
var _outbox_chars: int = 0
var _drop_at: int = 0
var _reconnect_at: int = 0
var _reconnect_attempt: int = 0


func keepalive_policy() -> Dictionary:
	return {"ping_interval_msec": 0, "ping_timeout_msec": 0, "host_silence_timeout_msec": 0}


# --- starting ------------------------------------------------------------------------------------

func host_session(config: Dictionary) -> Dictionary:
	if _role != Role.NONE:
		return CoreResult.failure("ALREADY_ACTIVE", "transport is already hosting or joined")
	var checked: Dictionary = _read_url(config)
	if not CoreResult.is_ok(checked):
		return checked
	_apply_config(config)
	_fixed_code = str(config.get("fixed_code", ""))
	var path: String = "/host" + ("?code=%s" % _fixed_code if not _fixed_code.is_empty() else "")
	if not _open(path):
		_reset()
		return CoreResult.failure("CONNECT_FAILED", "cannot start connecting to the relay")
	_role = Role.HOST
	_link = Link.CONNECTING
	return CoreResult.success()


func join_session(address_or_code: String, config: Dictionary) -> void:
	if _role != Role.NONE:
		_early_failure = "transport is already active"
		return
	var checked: Dictionary = _read_url(config)
	if not CoreResult.is_ok(checked):
		_early_failure = str(checked["error"]["message"])
		return
	var code: String = normalize_code(address_or_code)
	if code.is_empty():
		_early_failure = "That is not a room code. Room codes have 6 letters and digits."
		return
	_apply_config(config)
	_code = code
	if not _open("/join/" + code):
		_reset()
		_early_failure = REASONS["RELAY_BUSY"]
		return
	_role = Role.JOINING
	_link = Link.CONNECTING


## What a player typed, cleaned up: upper case, no spaces or hyphens. "" if it cannot be a code.
static func normalize_code(text: String) -> String:
	var cleaned: String = text.to_upper().replace(" ", "").replace("-", "")
	if cleaned.length() != CODE_LENGTH:
		return ""
	for i: int in cleaned.length():
		if not ALPHABET.contains(cleaned[i]):
			return ""
	return cleaned


## True if `text` looks like a room code (what the join field accepts for a relay).
static func looks_like_code(text: String) -> bool:
	return not normalize_code(text).is_empty()


func leave() -> void:
	_epoch += 1
	_early_failure = ""
	if _ws != null:
		if _role == Role.HOST and _link == Link.LIVE and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_ws.send_text("Q")  # the room ends now, no grace period
			_ws.poll()  # write it out before the close frame
		_flush_close()
	_reset()


# --- sending -------------------------------------------------------------------------------------

func send(peer_id: int, message: Dictionary) -> void:
	var text: String = _encode(message)
	match _role:
		Role.HOST:
			if _peers.has(peer_id) and not _kicked.has(peer_id):
				_send_host_frame("S%d:%s" % [peer_id, text])
		Role.CLIENT:
			if peer_id == HOST_PEER_ID and _is_open():
				_ws.send_text("M" + text)


func disconnect_peer(peer_id: int) -> void:
	match _role:
		Role.HOST:
			if _peers.has(peer_id) and not _kicked.has(peer_id):
				_kicked[peer_id] = true
				_send_host_frame("K%d:KICKED" % peer_id)  # delivered after anything sent before
		Role.CLIENT:
			if peer_id == HOST_PEER_ID:
				leave()


func get_peer_ids() -> Array[int]:
	var ids: Array[int] = []
	match _role:
		Role.HOST:
			for peer_id: Variant in _peers.keys():
				ids.append(peer_id)
		Role.CLIENT:
			ids.append(HOST_PEER_ID)
	return ids


func is_active() -> bool:
	return _role != Role.NONE


## The room code once hosting is live ("" before).
func room_code() -> String:
	return _code if _role == Role.HOST and _link != Link.CONNECTING and _link != Link.GREETING else ""


# --- polling -------------------------------------------------------------------------------------

func poll() -> void:
	if not _early_failure.is_empty():
		var reason: String = _early_failure
		_early_failure = ""
		join_failed.emit(reason)
		return
	match _role:
		Role.HOST:
			_poll_host()
		Role.JOINING, Role.CLIENT:
			_poll_client()


func _poll_host() -> void:
	var epoch: int = _epoch
	var now: int = _now()
	if _ws == null:
		_poll_reconnect(now)
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if now > _connect_deadline:
				_ws.close()
				_ws = null
				_host_link_lost("The relay did not answer in time.")
		WebSocketPeer.STATE_OPEN:
			if _link == Link.CONNECTING:
				_link = Link.GREETING
				if not _token.is_empty():
					_ws.send_text("R" + _token)  # a resume: prove who we are
			if not _drain_host(epoch):
				return
			if _ws != null:
				_keepalive(now)
				if _link != Link.CONNECTING and now - _last_heard > _watchdog_msec:
					_ws.close()
					_ws = null
					_host_link_lost("No answer from the relay for %d seconds." % (_watchdog_msec / 1000))
		WebSocketPeer.STATE_CLOSED:
			var name: String = str(CLOSE_CODE_NAMES.get(_ws.get_close_code(), ""))
			_ws = null
			if name in ["ROOM_CLOSED", "REPLACED", "BAD_TOKEN", "ROOM_NOT_FOUND", "RELAY_BUSY", "RATE_LIMITED"]:
				_fail_host(name)
			else:
				_host_link_lost("The connection to the relay closed.")


## Reads waiting frames. Returns false if the transport was left or failed while doing so.
func _drain_host(epoch: int) -> bool:
	while _ws != null and _ws.get_available_packet_count() > 0:
		var packet: PackedByteArray = _ws.get_packet()
		if not _ws.was_string_packet():
			continue
		_last_heard = _now()
		_handle_host_frame(packet.get_string_from_utf8())
		if epoch != _epoch or _role != Role.HOST:
			return false
	return true


func _handle_host_frame(text: String) -> void:
	if text.is_empty():
		return
	var body: String = text.substr(1)
	match text[0]:
		"C":
			_handle_host_control(body)
		"M":
			var split: Dictionary = _split_peer(body)
			if split.is_empty() or not _peers.has(split["peer"]) or _kicked.has(split["peer"]):
				return
			var decoded: Dictionary = _decode(split["rest"])
			if CoreResult.is_ok(decoded):
				message_received.emit(split["peer"], decoded["message"])
		"J":
			if body.is_valid_int():
				var peer: int = body.to_int()
				_peers[peer] = true
				peer_connected.emit(peer)
		"L":
			if body.is_valid_int():
				var gone: int = body.to_int()
				if _peers.erase(gone):
					_kicked.erase(gone)
					peer_disconnected.emit(gone)
		"X":
			if _link == Link.LIVE or _link == Link.GREETING:
				_fail_host(body)
		"p":
			pass  # "pong": _last_heard is already updated


func _handle_host_control(json_text: String) -> void:
	var data: Variant = JSON.parse_string(json_text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	match str(data.get("t", "")):
		"hosted":
			_code = str(data.get("code", ""))
			_token = str(data.get("token", ""))
			_read_advice(data)
			_link = Link.LIVE
			_last_ping = _now()
			session_ready.emit({
				"address": _code,
				"kind": "relay",
				"code": _code,
				"share_label": "room code",
				"relay_url": _base_url,
			})
		"resumed":
			_read_advice(data)
			_link = Link.LIVE
			_reconnect_attempt = 0
			_flush_outbox()
			link_state_changed.emit(LINK_OK)
		"error":
			_fail_host(str(data.get("code", "RELAY_BUSY")))


## The host's connection to the relay dropped. The room is held for a while: reconnect and resume.
func _host_link_lost(why: String) -> void:
	if _token.is_empty():
		_fail_host("RELAY_BUSY")  # never got as far as having a room
		return
	if _link == Link.LIVE:
		_drop_at = _now()
		_reconnect_attempt = 0
		link_state_changed.emit(LINK_RECONNECTING)
	_link = Link.RECONNECTING
	_reconnect_at = _now() + _backoff_for(_reconnect_attempt)
	_reconnect_attempt += 1
	push_warning("relay link lost (%s); resuming room %s" % [why, _code])


func _poll_reconnect(now: int) -> void:
	if _link != Link.RECONNECTING:
		return
	if now - _drop_at > _grace_msec + RESUME_MARGIN_MSEC:
		_fail_host("ROOM_CLOSED")
		return
	if now < _reconnect_at:
		return
	if _open("/resume/" + _code):
		_link = Link.CONNECTING
	else:
		_reconnect_at = now + _backoff_for(_reconnect_attempt)
		_reconnect_attempt += 1


func _fail_host(code: String) -> void:
	var reason: String = _reason(code)
	_flush_close()
	_reset()
	last_error_code = code if REASONS.has(code) else "RELAY_BUSY"
	host_failed.emit(reason)


func _send_host_frame(frame: String) -> void:
	if _link == Link.LIVE and _is_open():
		_ws.send_text(frame)
		return
	if _link == Link.RECONNECTING or _link == Link.CONNECTING or _link == Link.GREETING:
		if _outbox.size() >= MAX_QUEUED_MESSAGES or _outbox_chars + frame.length() > MAX_QUEUED_CHARS:
			_fail_host("RELAY_BUSY")  # we cannot promise delivery any more
			return
		_outbox.append(frame)
		_outbox_chars += frame.length()


func _flush_outbox() -> void:
	for frame: String in _outbox:
		if _is_open():
			_ws.send_text(frame)
	_outbox.clear()
	_outbox_chars = 0


# --- joiner --------------------------------------------------------------------------------------

func _poll_client() -> void:
	var epoch: int = _epoch
	var now: int = _now()
	if _ws == null:
		return
	_ws.poll()
	var state: int = _ws.get_ready_state()
	if state == WebSocketPeer.STATE_CONNECTING:
		if now > _connect_deadline:
			_ws.close()
			_fail_join("RELAY_BUSY")
		return
	if state == WebSocketPeer.STATE_OPEN:
		if _link == Link.CONNECTING:
			_link = Link.GREETING
			_last_heard = now
			_last_ping = now
		while _ws != null and _ws.get_available_packet_count() > 0:
			var packet: PackedByteArray = _ws.get_packet()
			if not _ws.was_string_packet():
				continue
			_last_heard = now
			_handle_client_frame(packet.get_string_from_utf8())
			if epoch != _epoch or _role == Role.NONE:
				return
		if _ws != null:
			_keepalive(now)
			if now - _last_heard > _watchdog_msec:
				_ws.close()
				_client_gone("TIMEOUT")
	elif state == WebSocketPeer.STATE_CLOSED:
		var name: String = str(CLOSE_CODE_NAMES.get(_ws.get_close_code(), ""))
		if _role == Role.JOINING:
			_fail_join(name if not name.is_empty() else "RELAY_BUSY")
		else:
			_client_gone(name)


func _handle_client_frame(text: String) -> void:
	if text.is_empty():
		return
	var body: String = text.substr(1)
	match text[0]:
		"C":
			var data: Variant = JSON.parse_string(body)
			if typeof(data) != TYPE_DICTIONARY:
				return
			match str(data.get("t", "")):
				"joined":
					_read_advice(data)
					_role = Role.CLIENT
					_link = Link.LIVE
					join_succeeded.emit()
				"error":
					if _role == Role.JOINING:
						_fail_join(str(data.get("code", "RELAY_BUSY")))
					else:
						_client_gone(str(data.get("code", "")))
		"M":
			if _role != Role.CLIENT:
				return
			var decoded: Dictionary = _decode(body)
			if CoreResult.is_ok(decoded):
				message_received.emit(HOST_PEER_ID, decoded["message"])
		"H":
			if _role == Role.CLIENT:
				link_state_changed.emit(LINK_HOST_AWAY)
		"B":
			if _role == Role.CLIENT:
				link_state_changed.emit(LINK_OK)
		"X":
			# Final: everything sent before it has been delivered above. We close the socket
			# ourselves so no close frame can overtake a packet we have not read yet.
			if _role == Role.JOINING:
				_fail_join(body)
			else:
				_client_gone(body)


func _fail_join(code: String) -> void:
	var reason: String = _reason(code)
	last_error_code = code if REASONS.has(code) else "RELAY_BUSY"
	_flush_close()
	_reset()
	join_failed.emit(reason)


func _client_gone(code: String) -> void:
	last_error_code = code
	_flush_close()
	_reset()
	peer_disconnected.emit(HOST_PEER_ID)


# --- shared --------------------------------------------------------------------------------------

func _keepalive(now: int) -> void:
	if _link == Link.LIVE and _is_open() and now - _last_ping >= _ping_msec:
		_last_ping = now
		_ws.send_text("ping")


func _is_open() -> bool:
	return _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func _open(path: String) -> bool:
	var ws: WebSocketPeer = WebSocketPeer.new()
	ws.inbound_buffer_size = _BUFFER_BYTES
	ws.outbound_buffer_size = _BUFFER_BYTES
	if ws.connect_to_url(_base_url + path) != OK:
		return false
	_ws = ws
	_connect_deadline = _now() + _join_timeout_msec
	_last_heard = _now()
	_last_ping = _now()
	return true


func _read_url(config: Dictionary) -> Dictionary:
	var url: String = str(config.get("relay_url", "")).strip_edges()
	if url.is_empty():
		return CoreResult.failure("NO_RELAY", "No relay is configured. Set a relay URL in the settings, or use a direct address.")
	if not (url.begins_with("wss://") or url.begins_with("ws://")):
		return CoreResult.failure("BAD_RELAY_URL", "The relay URL must start with wss:// (or ws:// for a local relay).")
	_base_url = url.rstrip("/")
	return CoreResult.success()


func _apply_config(config: Dictionary) -> void:
	for key: String in ["ping_msec", "watchdog_msec"]:
		if config.has(key):
			_overridden[key] = true
	_ping_msec = int(config.get("ping_msec", DEFAULT_PING_MSEC))
	_watchdog_msec = int(config.get("watchdog_msec", DEFAULT_WATCHDOG_MSEC))
	_join_timeout_msec = int(config.get("join_timeout_msec", DEFAULT_JOIN_TIMEOUT_MSEC))
	_backoff = config.get("reconnect_backoff_msec", DEFAULT_BACKOFF_MSEC)


## The relay tells us how often to ping and how long its host grace period is.
func _read_advice(data: Dictionary) -> void:
	if data.has("ping_sec") and not _config_overrides("ping_msec"):
		_ping_msec = int(float(data["ping_sec"]) * 1000.0)
	if data.has("watchdog_sec") and not _config_overrides("watchdog_msec"):
		_watchdog_msec = int(float(data["watchdog_sec"]) * 1000.0)
	if data.has("grace_sec"):
		_grace_msec = int(float(data["grace_sec"]) * 1000.0)


var _overridden: Dictionary = {}


func _config_overrides(key: String) -> bool:
	return _overridden.has(key)


func _backoff_for(attempt: int) -> int:
	return int(_backoff[mini(attempt, _backoff.size() - 1)])


func _reason(code: String) -> String:
	return str(REASONS.get(code, REASONS["RELAY_BUSY"]))


## "<peer>:<rest>" -> {peer, rest}, or {} if malformed.
static func _split_peer(body: String) -> Dictionary:
	var colon: int = body.find(":")
	if colon < 1:
		return {}
	var digits: String = body.substr(0, colon)
	if not digits.is_valid_int():
		return {}
	return {"peer": digits.to_int(), "rest": body.substr(colon + 1)}


## Sends the close frame now instead of waiting for a later poll.
func _flush_close() -> void:
	if _ws != null:
		_ws.close(1000, "bye")
		_ws.poll()


func _reset() -> void:
	_role = Role.NONE
	_link = Link.CONNECTING
	_ws = null
	_code = ""
	_token = ""
	_fixed_code = ""
	_peers.clear()
	_kicked.clear()
	_outbox.clear()
	_outbox_chars = 0
	_reconnect_attempt = 0
	_overridden.clear()


func _now() -> int:
	return int(clock.call())
