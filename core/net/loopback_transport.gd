class_name LoopbackTransport
extends Transport
## In-memory transport: host and clients live in one process and find each other
## through a LoopbackHub. No sockets. Used by tests and hot-seat/local play.
## Like a real wire: messages are serialized on send, delivered only from poll(),
## and a receiver always gets an independent copy.

enum Role { NONE, HOST, CLIENT }

var _hub: LoopbackHub
var _role: Role = Role.NONE
var _inbox: Array[Dictionary] = []
var _epoch: int = 0  # bumped by leave() so poll() stops emitting stale events
var _address: String = ""

# host side
var _clients: Dictionary = {}  # peer_id -> LoopbackTransport
var _next_peer_id: int = HOST_PEER_ID + 1

# client side
var _host: LoopbackTransport = null
var _my_peer_id: int = 0


func _init(hub: LoopbackHub = null) -> void:
	_hub = hub if hub != null else LoopbackHub.shared()


func host_session(config: Dictionary) -> Dictionary:
	if _role != Role.NONE:
		return CoreResult.failure("ALREADY_ACTIVE", "transport is already hosting or joined")
	var address: String = str(config.get("address", ""))
	if address.is_empty():
		address = _hub.allocate_address()
	if not _hub.register(address, self):
		return CoreResult.failure("ADDRESS_IN_USE", "address %s is already hosted" % address)
	_role = Role.HOST
	_address = address
	_inbox.append({"kind": "session_ready", "info": {"address": address, "kind": "loopback"}})
	return CoreResult.success()


func join_session(address_or_code: String, _config: Dictionary) -> void:
	if _role != Role.NONE:
		_inbox.append({"kind": "join_failed", "reason": "transport is already active"})
		return
	var host: LoopbackTransport = _hub.find_host(address_or_code) as LoopbackTransport
	if host == null:
		_inbox.append({"kind": "join_failed", "reason": "no session at %s" % address_or_code})
		return
	_role = Role.CLIENT
	_host = host
	_my_peer_id = host._accept(self)
	_inbox.append({"kind": "join_ok"})


func leave() -> void:
	_epoch += 1
	match _role:
		Role.HOST:
			_hub.unregister(_address)
			for client: Variant in _clients.values():
				(client as LoopbackTransport)._dropped_by_host()
			_clients.clear()
		Role.CLIENT:
			if _host != null:
				_host._client_left(_my_peer_id)
	_reset_role()
	_inbox.clear()


func send(peer_id: int, message: Dictionary) -> void:
	var text: String = _encode(message)
	match _role:
		Role.HOST:
			var client: LoopbackTransport = _clients.get(peer_id, null) as LoopbackTransport
			if client != null:
				client._inbox.append({"kind": "message", "peer": HOST_PEER_ID, "text": text})
		Role.CLIENT:
			if peer_id == HOST_PEER_ID and _host != null:
				_host._receive_from_client(_my_peer_id, text)


func disconnect_peer(peer_id: int) -> void:
	match _role:
		Role.HOST:
			var client: LoopbackTransport = _clients.get(peer_id, null) as LoopbackTransport
			if client == null:
				return
			_clients.erase(peer_id)
			client._dropped_by_host()
			_inbox.append({"kind": "disconnected", "peer": peer_id})
		Role.CLIENT:
			if peer_id == HOST_PEER_ID:
				leave()


func poll() -> void:
	var events: Array[Dictionary] = _inbox
	_inbox = []
	var epoch: int = _epoch
	for event: Dictionary in events:
		if epoch != _epoch:
			return
		match event["kind"]:
			"session_ready":
				session_ready.emit(event["info"])
			"join_ok":
				join_succeeded.emit()
			"join_failed":
				join_failed.emit(event["reason"])
			"connected":
				peer_connected.emit(event["peer"])
			"disconnected":
				peer_disconnected.emit(event["peer"])
			"message":
				var decoded: Dictionary = _decode(event["text"])
				if CoreResult.is_ok(decoded):
					message_received.emit(event["peer"], decoded["message"])


func get_peer_ids() -> Array[int]:
	var ids: Array[int] = []
	match _role:
		Role.HOST:
			for peer_id: Variant in _clients.keys():
				ids.append(peer_id)
		Role.CLIENT:
			ids.append(HOST_PEER_ID)
	return ids


func is_active() -> bool:
	return _role != Role.NONE


# --- internals called by the other end -------------------------------------------

func _accept(client: LoopbackTransport) -> int:
	var peer_id: int = _next_peer_id
	_next_peer_id += 1
	_clients[peer_id] = client
	_inbox.append({"kind": "connected", "peer": peer_id})
	return peer_id


func _receive_from_client(peer_id: int, text: String) -> void:
	if _clients.has(peer_id):
		_inbox.append({"kind": "message", "peer": peer_id, "text": text})


func _client_left(peer_id: int) -> void:
	if _clients.erase(peer_id):
		_inbox.append({"kind": "disconnected", "peer": peer_id})


func _dropped_by_host() -> void:
	_reset_role()
	_inbox.append({"kind": "disconnected", "peer": HOST_PEER_ID})


func _reset_role() -> void:
	_role = Role.NONE
	_host = null
	_my_peer_id = 0
	_address = ""
