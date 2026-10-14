class_name FakeRelay
extends RefCounted
## In-memory stand-in for a cloud relay. Every peer (host and clients) connects
## "outward" to this object; it registers rooms, assigns peer ids and only forwards
## messages between a room's host and its clients. It never interprets them.
## Test hooks: delay_polls (latency, counted in polls of the receiving connection)
## and drop_connection() (abrupt network loss without a clean leave).

## Extra polls an event waits before delivery. 0 = delivered on the next poll.
var delay_polls: int = 0

var _next_conn_id: int = 1
var _conns: Dictionary = {}  # conn_id -> {queue: Array[Dictionary], room: String, peer: int, is_host: bool}
var _rooms: Dictionary = {}  # code -> {host: int, clients: {peer_id: conn_id}, next_peer: int}
var _room_counter: int = 0


func connect_outward() -> int:
	var conn_id: int = _next_conn_id
	_next_conn_id += 1
	_conns[conn_id] = {"queue": [] as Array[Dictionary], "room": "", "peer": 0, "is_host": false}
	return conn_id


## Clean close from the peer's side. Removes the connection entirely.
func disconnect_conn(conn_id: int) -> void:
	_leave_room(conn_id, false)
	_conns.erase(conn_id)


## Called by a transport once it has processed its own disconnect event.
func release(conn_id: int) -> void:
	_conns.erase(conn_id)


func register_room(conn_id: int, requested_code: String = "") -> Dictionary:
	var conn: Dictionary = _conns.get(conn_id, {})
	if conn.is_empty() or conn["room"] != "":
		return CoreResult.failure("BAD_CONNECTION", "connection cannot register a room")
	var code: String = requested_code
	if code.is_empty():
		_room_counter += 1
		code = "ROOM-%04d" % _room_counter
	if _rooms.has(code):
		return CoreResult.failure("ROOM_EXISTS", "room code %s is taken" % code)
	_rooms[code] = {"host": conn_id, "clients": {}, "next_peer": Transport.HOST_PEER_ID + 1}
	conn["room"] = code
	conn["is_host"] = true
	return CoreResult.success({"code": code})


## Queues join_ok / join_failed for the joiner and connected for the host.
func join_room(conn_id: int, code: String) -> void:
	var conn: Dictionary = _conns.get(conn_id, {})
	if conn.is_empty():
		return
	var room: Dictionary = _rooms.get(code, {})
	if room.is_empty() or conn["room"] != "":
		_push(conn_id, {"kind": "join_failed", "reason": "no room %s" % code})
		return
	var peer_id: int = room["next_peer"]
	room["next_peer"] = peer_id + 1
	room["clients"][peer_id] = conn_id
	conn["room"] = code
	conn["peer"] = peer_id
	_push(conn_id, {"kind": "join_ok"})
	_push(room["host"], {"kind": "connected", "peer": peer_id})


func send_to_host(conn_id: int, text: String) -> void:
	var conn: Dictionary = _conns.get(conn_id, {})
	if conn.is_empty() or conn["room"] == "" or conn["is_host"]:
		return
	var room: Dictionary = _rooms.get(conn["room"], {})
	if not room.is_empty():
		_push(room["host"], {"kind": "message", "peer": conn["peer"], "text": text})


func send_to_client(host_conn_id: int, peer_id: int, text: String) -> void:
	var room: Dictionary = _room_of_host(host_conn_id)
	if room.is_empty() or not room["clients"].has(peer_id):
		return
	_push(room["clients"][peer_id], {"kind": "message", "peer": Transport.HOST_PEER_ID, "text": text})


## The host asks the relay to drop one client.
func kick(host_conn_id: int, peer_id: int) -> void:
	var room: Dictionary = _room_of_host(host_conn_id)
	if room.is_empty() or not room["clients"].has(peer_id):
		return
	var client_conn: int = room["clients"][peer_id]
	room["clients"].erase(peer_id)
	_conns[client_conn]["room"] = ""
	_push(client_conn, {"kind": "disconnected", "peer": Transport.HOST_PEER_ID})
	_push(host_conn_id, {"kind": "disconnected", "peer": peer_id})


## Events that are due for this connection, in order. Each call is one tick.
func take_events(conn_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var conn: Dictionary = _conns.get(conn_id, {})
	if conn.is_empty():
		return out
	var queue: Array[Dictionary] = conn["queue"]
	for item: Dictionary in queue:
		item["wait"] = int(item["wait"]) - 1
	while not queue.is_empty() and int(queue[0]["wait"]) <= 0:
		out.append(queue.pop_front()["event"])
	return out


# --- test hooks ------------------------------------------------------------------

## Abrupt loss of one connection: no clean leave. The other side and the dropped
## transport itself both get disconnect events.
func drop_connection(conn_id: int) -> void:
	_leave_room(conn_id, true)


func get_room_codes() -> Array[String]:
	var codes: Array[String] = []
	for code: Variant in _rooms.keys():
		codes.append(code)
	return codes


# --- internals -------------------------------------------------------------------

func _push(conn_id: int, event: Dictionary) -> void:
	var conn: Dictionary = _conns.get(conn_id, {})
	if conn.is_empty():
		return
	var queue: Array[Dictionary] = conn["queue"]
	queue.append({"event": event, "wait": delay_polls})


func _room_of_host(host_conn_id: int) -> Dictionary:
	var conn: Dictionary = _conns.get(host_conn_id, {})
	if conn.is_empty() or not conn["is_host"]:
		return {}
	return _rooms.get(conn["room"], {})


## Removes a connection from its room and tells the other side. When notify_self
## is true the leaving connection also gets an event (it did not choose to go).
func _leave_room(conn_id: int, notify_self: bool) -> void:
	var conn: Dictionary = _conns.get(conn_id, {})
	if conn.is_empty() or conn["room"] == "":
		return
	var code: String = conn["room"]
	var room: Dictionary = _rooms.get(code, {})
	conn["room"] = ""
	if not room.is_empty():
		if conn["is_host"]:
			_rooms.erase(code)
			for client_conn: Variant in room["clients"].values():
				_conns[client_conn]["room"] = ""
				_push(client_conn, {"kind": "disconnected", "peer": Transport.HOST_PEER_ID})
		else:
			room["clients"].erase(conn["peer"])
			_push(room["host"], {"kind": "disconnected", "peer": conn["peer"]})
	if notify_self:
		if conn["is_host"]:
			_push(conn_id, {"kind": "closed"})
		else:
			_push(conn_id, {"kind": "disconnected", "peer": Transport.HOST_PEER_ID})
	conn["is_host"] = false
