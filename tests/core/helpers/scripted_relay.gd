class_name ScriptedRelay
extends RefCounted
## Test helper: a tiny in-process relay that speaks the real wire format (see
## relay/cloudflare/src/frames.ts) over real WebSockets on localhost, so RelayTransport can be
## tested for protocol behaviour without Node or wrangler. It is deliberately simple: no grace
## period, buffering, limits or expiry (the Node tests cover those on the real relay), but it can
## be told to misbehave: drop a connection, send any frame, refuse with an error.

const CODE: String = "ABCDE2"
const TOKEN: String = "secret-host-token"

var port: int = 0
var advice: Dictionary = {"ping_sec": 15, "watchdog_sec": 45, "grace_sec": 60}
## "", or an error code every /join answers with (ROOM_FULL, HOST_AWAY ...).
var refuse_joins_with: String = ""
var refuse_hosting_with: String = ""
var refuse_resume_with: String = ""
## If true, a refusal is just a close (code 1011) with no error frame.
var refuse_silently: bool = false
## Frames received, per role: "host" and "peer:<id>".
var received: Dictionary = {}
var paths: Array[String] = []
var resumes: int = 0

var _server: TCPServer = TCPServer.new()
var _conns: Array[Dictionary] = []  # {ws, path, role, peer, greeted}
var _next_peer: int = 2


func start() -> int:
	assert(_server.listen(0, "127.0.0.1") == OK)
	port = _server.get_local_port()
	return port


func url() -> String:
	return "ws://127.0.0.1:%d" % port


func stop() -> void:
	for conn: Dictionary in _conns:
		(conn["ws"] as WebSocketPeer).close()
	_conns.clear()
	_server.stop()


func poll() -> void:
	while _server.is_connection_available():
		var ws: WebSocketPeer = WebSocketPeer.new()
		ws.inbound_buffer_size = 262144
		ws.outbound_buffer_size = 262144
		if ws.accept_stream(_server.take_connection()) == OK:
			_conns.append({"ws": ws, "path": "", "role": "", "peer": 0, "greeted": false, "kick_at": 0})
	for conn: Dictionary in _conns.duplicate():
		_poll_conn(conn)


# --- test controls ---------------------------------------------------------------------------------

func host_conn() -> Dictionary:
	for conn: Dictionary in _conns:
		if conn["role"] == "host":
			return conn
	return {}


func peer_conn(peer: int) -> Dictionary:
	for conn: Dictionary in _conns:
		if conn["role"] == "peer" and conn["peer"] == peer:
			return conn
	return {}


## Sends a raw frame to the host ("host") or to a joiner (peer id).
func send_to_host(frame: String) -> void:
	var conn: Dictionary = host_conn()
	if not conn.is_empty():
		(conn["ws"] as WebSocketPeer).send_text(frame)


func send_to_peer(peer: int, frame: String) -> void:
	var conn: Dictionary = peer_conn(peer)
	if not conn.is_empty():
		(conn["ws"] as WebSocketPeer).send_text(frame)


## Closes the host's socket the way a network drop looks to the client: no X frame, no goodbye.
func drop_host() -> void:
	var conn: Dictionary = host_conn()
	if not conn.is_empty():
		(conn["ws"] as WebSocketPeer).close(1006, "")


func drop_peer(peer: int) -> void:
	var conn: Dictionary = peer_conn(peer)
	if not conn.is_empty():
		(conn["ws"] as WebSocketPeer).close(1006, "")


func frames_of(role: String) -> Array:
	return received.get(role, [])


func count_frames(role: String, prefix: String) -> int:
	var n: int = 0
	for frame: String in frames_of(role):
		if frame.begins_with(prefix):
			n += 1
	return n


# --- the relay itself ---------------------------------------------------------------------------------

func _poll_conn(conn: Dictionary) -> void:
	var ws: WebSocketPeer = conn["ws"]
	ws.poll()
	var state: int = ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not conn["greeted"]:
			conn["greeted"] = true
			conn["path"] = ws.get_requested_url().trim_prefix("ws://127.0.0.1:%d" % port)
			paths.append(conn["path"])
			_greet(conn)
		while ws.get_available_packet_count() > 0:
			var frame: String = ws.get_packet().get_string_from_utf8()
			_on_frame(conn, frame)
		if int(conn["kick_at"]) != 0 and Time.get_ticks_msec() >= int(conn["kick_at"]):
			ws.close(4403, "KICKED")
	elif state == WebSocketPeer.STATE_CLOSED:
		_on_gone(conn)
		_conns.erase(conn)


func _greet(conn: Dictionary) -> void:
	var ws: WebSocketPeer = conn["ws"]
	var path: String = conn["path"]
	if path.begins_with("/host"):
		if not refuse_hosting_with.is_empty():
			_refuse(conn, refuse_hosting_with)
			return
		conn["role"] = "host"
		ws.send_text("C" + JSON.stringify(advice.merged({"t": "hosted", "code": CODE, "token": TOKEN})))
	elif path.begins_with("/join/"):
		if not refuse_joins_with.is_empty():
			_refuse(conn, refuse_joins_with)
			return
		if path.trim_prefix("/join/") != CODE or host_conn().is_empty():
			_refuse(conn, "ROOM_NOT_FOUND")
			return
		conn["role"] = "peer"
		conn["peer"] = _next_peer
		_next_peer += 1
		ws.send_text("C" + JSON.stringify(advice.merged({"t": "joined"})))
		send_to_host("J%d" % conn["peer"])
	elif path.begins_with("/resume/"):
		conn["role"] = "resume"  # waits for R<token>


func _on_frame(conn: Dictionary, frame: String) -> void:
	var ws: WebSocketPeer = conn["ws"]
	if frame == "ping":
		ws.send_text("pong")  # the real runtime answers this without waking the room
		return
	var key: String = "host" if conn["role"] == "host" else ("peer:%d" % conn["peer"] if conn["role"] == "peer" else str(conn["role"]))
	if not received.has(key):
		received[key] = []
	received[key].append(frame)
	match conn["role"]:
		"resume":
			if frame == "R" + TOKEN and refuse_resume_with.is_empty():
				resumes += 1
				var old: Dictionary = host_conn()
				if not old.is_empty():
					old["role"] = "replaced"
					(old["ws"] as WebSocketPeer).close(4412, "REPLACED")
				conn["role"] = "host"
				received["host"] = []
				ws.send_text("C" + JSON.stringify(advice.merged({"t": "resumed"})))
				for peer_conn_entry: Dictionary in _conns:
					if peer_conn_entry["role"] == "peer":
						(peer_conn_entry["ws"] as WebSocketPeer).send_text("B")
			else:
				_refuse(conn, refuse_resume_with if not refuse_resume_with.is_empty() else "BAD_TOKEN")
		"host":
			_on_host_frame(frame)
		"peer":
			if frame.begins_with("M"):
				send_to_host("M%d:%s" % [conn["peer"], frame.substr(1)])


func _on_host_frame(frame: String) -> void:
	var body: String = frame.substr(1)
	match frame[0]:
		"S":
			var colon: int = body.find(":")
			send_to_peer(body.substr(0, colon).to_int(), "M" + body.substr(colon + 1))
		"K":
			var colon: int = body.find(":")
			var target: Dictionary = peer_conn(body.substr(0, colon).to_int())
			if not target.is_empty():
				(target["ws"] as WebSocketPeer).send_text("X" + body.substr(colon + 1))
				target["kick_at"] = Time.get_ticks_msec() + 1500  # the relay's own fallback
		"Q":
			for other: Dictionary in _conns:
				if other["role"] == "peer":
					(other["ws"] as WebSocketPeer).send_text("XROOM_CLOSED")


func _on_gone(conn: Dictionary) -> void:
	match conn["role"]:
		"peer":
			send_to_host("L%d" % conn["peer"])
		"host":
			for other: Dictionary in _conns:
				if other["role"] == "peer":
					(other["ws"] as WebSocketPeer).send_text("H")


func _refuse(conn: Dictionary, code: String) -> void:
	var ws: WebSocketPeer = conn["ws"]
	if refuse_silently:
		ws.close(1011, "boom")
		return
	ws.send_text("C" + JSON.stringify({"t": "error", "code": code}))
	ws.close(int(RelayTransport.CLOSE_CODE_NAMES.find_key(code)) if RelayTransport.CLOSE_CODE_NAMES.find_key(code) != null else 4503, code)
