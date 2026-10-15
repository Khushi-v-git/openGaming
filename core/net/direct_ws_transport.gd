class_name DirectWsTransport
extends Transport
## Direct transport over plain WebSocket (ws://), for LAN, IP and tunnel use
## (e.g. a playit.gg TCP tunnel). The host listens on a configurable port; clients
## join by "host:port". Built from TCPServer + WebSocketPeer, deliberately NOT
## the high-level multiplayer API, so there is no RPC coupling (rules 3, 4).
##
## Host config (all optional):
##   port: int            listen port; 0 = let the OS choose (tests). Default DEFAULT_PORT.
##   bind_address: String interface to listen on. Default "*" (all interfaces).
##   max_pending: int     max connections still in the WebSocket upgrade. Default 8.
##   max_connections: int hard cap on pending + connected peers. Default 32.
## Join config (all optional):
##   default_port: int    used when the address has no port. Default DEFAULT_PORT.
##   join_timeout_msec: int

## Default for the port *setting*. Code paths always read the setting/config first.
const DEFAULT_PORT: int = 24680

const _BUFFER_BYTES: int = Protocol.MAX_MESSAGE_BYTES * 2
const _HEARTBEAT_SEC: float = 15.0  # keepalive for idle tunnels; liveness is the app-level ping
const _PENDING_TIMEOUT_MSEC: int = 5000
const _CLOSE_GRACE_MSEC: int = 250  # how long a kicked peer gets to close first
const _DEFAULT_JOIN_TIMEOUT_MSEC: int = 10000

enum Role { NONE, HOST, JOINING, CLIENT }

var _role: Role = Role.NONE
var _epoch: int = 0

# host
var _server: TCPServer = null
var _pending: Array[Dictionary] = []  # {ws: WebSocketPeer, since: int}
var _peers: Dictionary = {}  # peer_id -> {ws: WebSocketPeer, close_deadline: int (0 = open)}
var _next_peer_id: int = HOST_PEER_ID + 1
var _max_pending: int = 8
var _max_connections: int = 32

# client
var _ws: WebSocketPeer = null
var _join_deadline: int = 0
var _early_failure: String = ""
var _ready_info: Dictionary = {}  # emitted as session_ready from the next poll()


func host_session(config: Dictionary) -> Dictionary:
	if _role != Role.NONE:
		return CoreResult.failure("ALREADY_ACTIVE", "transport is already hosting or joined")
	var port: int = int(config.get("port", DEFAULT_PORT))
	var bind_address: String = str(config.get("bind_address", "*"))
	_max_pending = int(config.get("max_pending", 8))
	_max_connections = int(config.get("max_connections", 32))
	var server: TCPServer = TCPServer.new()
	var err: Error = server.listen(port, bind_address)
	if err != OK:
		return CoreResult.failure("LISTEN_FAILED", "cannot listen on port %d (%s)" % [port, error_string(err)])
	_server = server
	_role = Role.HOST
	var bound_port: int = server.get_local_port()
	var shown_host: String = bind_address
	if bind_address == "*" or bind_address == "0.0.0.0":
		shown_host = _guess_lan_address()
	_ready_info = {
		"address": "%s:%d" % [shown_host, bound_port],
		"kind": "direct_ws",
		"public_address_editable": true,  # the host may share a different address (DDNS, forwarded port)
		"port": bound_port,
		"lan_addresses": _local_ipv4_addresses(),
	}
	return CoreResult.success()


func join_session(address_or_code: String, config: Dictionary) -> void:
	if _role != Role.NONE:
		_early_failure = "transport is already active"
		return
	var parsed: Dictionary = AddressParser.parse(address_or_code, int(config.get("default_port", DEFAULT_PORT)))
	if not CoreResult.is_ok(parsed):
		_early_failure = str(parsed["error"]["message"])
		return
	var ws: WebSocketPeer = _new_socket()
	var err: Error = ws.connect_to_url("ws://%s:%d" % [parsed["host"], parsed["port"]])
	if err != OK:
		_early_failure = "cannot connect (%s)" % error_string(err)
		return
	_ws = ws
	_role = Role.JOINING
	_join_deadline = Time.get_ticks_msec() + int(config.get("join_timeout_msec", _DEFAULT_JOIN_TIMEOUT_MSEC))


func leave() -> void:
	_epoch += 1
	_early_failure = ""
	_ready_info = {}
	match _role:
		Role.HOST:
			for peer_id: Variant in _peers.keys():
				_flush_close(_peers[peer_id]["ws"])
			for entry: Dictionary in _pending:
				(entry["ws"] as WebSocketPeer).close()
			if _server != null:
				_server.stop()
		Role.JOINING, Role.CLIENT:
			if _ws != null:
				_flush_close(_ws)
	_reset()


func send(peer_id: int, message: Dictionary) -> void:
	var text: String = _encode(message)
	var ws: WebSocketPeer = null
	match _role:
		Role.HOST:
			var entry: Dictionary = _peers.get(peer_id, {})
			if not entry.is_empty() and entry["close_deadline"] == 0:
				ws = entry["ws"]
		Role.CLIENT:
			if peer_id == HOST_PEER_ID:
				ws = _ws
	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(text)


func disconnect_peer(peer_id: int) -> void:
	match _role:
		Role.HOST:
			var entry: Dictionary = _peers.get(peer_id, {})
			if entry.is_empty() or entry["close_deadline"] != 0:
				return
			# Godot's WebSocketPeer drops unread inbound packets when a close frame arrives
			# in the same poll, so a message sent just before a kick (a reject, or the
			# reason for it) could be lost. Flush it now and let the peer close first;
			# we force the close after a short grace period.
			(entry["ws"] as WebSocketPeer).poll()
			entry["close_deadline"] = Time.get_ticks_msec() + _CLOSE_GRACE_MSEC
		Role.CLIENT:
			if peer_id == HOST_PEER_ID:
				leave()


func poll() -> void:
	if not _ready_info.is_empty():
		var info: Dictionary = _ready_info
		_ready_info = {}
		session_ready.emit(info)
		if not is_active():
			return
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


## The port actually being listened on (host only; 0 otherwise).
func listening_port() -> int:
	return _server.get_local_port() if _server != null and _server.is_listening() else 0


# --- host ------------------------------------------------------------------------

func _poll_host() -> void:
	var epoch: int = _epoch
	var now: int = Time.get_ticks_msec()
	_accept_new_connections()
	_advance_pending(now)
	for peer_id: int in get_peer_ids():
		if epoch != _epoch:
			return
		_poll_peer(peer_id, now)


func _accept_new_connections() -> void:
	while _server.is_connection_available():
		var stream: StreamPeerTCP = _server.take_connection()
		if _pending.size() >= _max_pending or _pending.size() + _peers.size() >= _max_connections:
			stream.disconnect_from_host()
			continue
		var ws: WebSocketPeer = _new_socket()
		if ws.accept_stream(stream) != OK:
			stream.disconnect_from_host()
			continue
		_pending.append({"ws": ws, "since": Time.get_ticks_msec()})


func _advance_pending(now: int) -> void:
	var still_pending: Array[Dictionary] = []
	for entry: Dictionary in _pending:
		var ws: WebSocketPeer = entry["ws"]
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				var peer_id: int = _next_peer_id
				_next_peer_id += 1
				_peers[peer_id] = {"ws": ws, "close_deadline": 0}
				peer_connected.emit(peer_id)
			WebSocketPeer.STATE_CONNECTING:
				if now - int(entry["since"]) > _PENDING_TIMEOUT_MSEC:
					ws.close()
				else:
					still_pending.append(entry)
			_:
				pass  # closing or closed before the upgrade finished: drop silently
	_pending = still_pending


func _poll_peer(peer_id: int, now: int) -> void:
	var entry: Dictionary = _peers.get(peer_id, {})
	if entry.is_empty():
		return
	var ws: WebSocketPeer = entry["ws"]
	ws.poll()
	var closing: bool = entry["close_deadline"] != 0
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not closing:
		if not _drain_packets(peer_id, ws):
			disconnect_peer(peer_id)
			return
	var state: int = ws.get_ready_state()
	var grace_over: bool = closing and now >= int(entry["close_deadline"])
	if state == WebSocketPeer.STATE_CLOSED or grace_over:
		if state != WebSocketPeer.STATE_CLOSED:
			_flush_close(ws)
		_peers.erase(peer_id)
		peer_disconnected.emit(peer_id)


## Reads waiting packets. Returns false if the peer misbehaved (binary, malformed,
## oversized) and should be dropped.
func _drain_packets(peer_id: int, ws: WebSocketPeer) -> bool:
	var epoch: int = _epoch
	while ws.get_available_packet_count() > 0:
		var packet: PackedByteArray = ws.get_packet()
		if not ws.was_string_packet():
			return false
		var decoded: Dictionary = _decode(packet.get_string_from_utf8())
		if not CoreResult.is_ok(decoded):
			return false
		message_received.emit(peer_id, decoded["message"])
		if epoch != _epoch or not _peers.has(peer_id):
			return true
	return true


# --- client ----------------------------------------------------------------------

func _poll_client() -> void:
	var epoch: int = _epoch
	_ws.poll()
	var state: int = _ws.get_ready_state()
	if _role == Role.JOINING:
		if state == WebSocketPeer.STATE_OPEN:
			_role = Role.CLIENT
			join_succeeded.emit()
			if epoch != _epoch:
				return
		elif state == WebSocketPeer.STATE_CLOSED:
			_reset()
			join_failed.emit("could not reach the host")
			return
		elif Time.get_ticks_msec() > _join_deadline:
			_ws.close()
			_reset()
			join_failed.emit("connection timed out")
			return
		else:
			return
	while _ws.get_available_packet_count() > 0:
		var packet: PackedByteArray = _ws.get_packet()
		if not _ws.was_string_packet():
			continue
		var decoded: Dictionary = _decode(packet.get_string_from_utf8())
		if CoreResult.is_ok(decoded):
			message_received.emit(HOST_PEER_ID, decoded["message"])
			if epoch != _epoch:
				return
	if _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		_reset()
		peer_disconnected.emit(HOST_PEER_ID)


# --- shared ----------------------------------------------------------------------

func _new_socket() -> WebSocketPeer:
	var ws: WebSocketPeer = WebSocketPeer.new()
	ws.inbound_buffer_size = _BUFFER_BYTES
	ws.outbound_buffer_size = _BUFFER_BYTES
	ws.heartbeat_interval = _HEARTBEAT_SEC
	return ws


## Sends the close frame now instead of waiting for a later poll.
func _flush_close(ws: WebSocketPeer) -> void:
	ws.close(1001, "going away")
	ws.poll()


func _reset() -> void:
	_role = Role.NONE
	_server = null
	_pending.clear()
	_peers.clear()
	_ws = null
	_join_deadline = 0
	_next_peer_id = HOST_PEER_ID + 1


static func _local_ipv4_addresses() -> Array[String]:
	var out: Array[String] = []
	for address: String in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
			out.append(address)
	return out


static func _guess_lan_address() -> String:
	var candidates: Array[String] = _local_ipv4_addresses()
	for address: String in candidates:
		if address.begins_with("192.168.") or address.begins_with("10.") or address.begins_with("172."):
			return address
	return candidates[0] if not candidates.is_empty() else "127.0.0.1"
