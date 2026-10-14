class_name FakeRelayTransport
extends Transport
## Relay-style transport over a FakeRelay: host and clients each hold one outward
## connection to the relay and never reference each other. The host's "address"
## is a room code. Proves the Transport interface fits a relay.

enum Role { NONE, HOST, JOINING, CLIENT }

var _relay: FakeRelay
var _conn_id: int = 0
var _role: Role = Role.NONE
var _peers: Dictionary = {}  # peer_id -> true, updated as events are delivered
var _epoch: int = 0


func _init(relay: FakeRelay) -> void:
	_relay = relay


func host_session(config: Dictionary) -> Dictionary:
	if _role != Role.NONE:
		return CoreResult.failure("ALREADY_ACTIVE", "transport is already hosting or joined")
	var conn_id: int = _relay.connect_outward()
	var registered: Dictionary = _relay.register_room(conn_id, str(config.get("room_code", "")))
	if not CoreResult.is_ok(registered):
		_relay.disconnect_conn(conn_id)
		return registered
	_conn_id = conn_id
	_role = Role.HOST
	return CoreResult.success({"address": registered["code"], "kind": "fake_relay"})


func join_session(address_or_code: String, _config: Dictionary) -> void:
	if _role != Role.NONE:
		join_failed.emit("transport is already active")
		return
	_conn_id = _relay.connect_outward()
	_role = Role.JOINING
	_relay.join_room(_conn_id, address_or_code)


func leave() -> void:
	_epoch += 1
	if _conn_id != 0:
		_relay.disconnect_conn(_conn_id)
	_reset()


func send(peer_id: int, message: Dictionary) -> void:
	var text: String = _encode(message)
	match _role:
		Role.HOST:
			_relay.send_to_client(_conn_id, peer_id, text)
		Role.CLIENT:
			if peer_id == HOST_PEER_ID:
				_relay.send_to_host(_conn_id, text)


func disconnect_peer(peer_id: int) -> void:
	match _role:
		Role.HOST:
			_relay.kick(_conn_id, peer_id)
		Role.CLIENT:
			if peer_id == HOST_PEER_ID:
				leave()


func poll() -> void:
	if _conn_id == 0:
		return
	var epoch: int = _epoch
	for event: Dictionary in _relay.take_events(_conn_id):
		if epoch != _epoch:
			return
		match event["kind"]:
			"join_ok":
				_role = Role.CLIENT
				_peers[HOST_PEER_ID] = true
				join_succeeded.emit()
			"join_failed":
				_release_and_reset()
				join_failed.emit(event["reason"])
			"connected":
				_peers[event["peer"]] = true
				peer_connected.emit(event["peer"])
			"disconnected":
				var peer_id: int = event["peer"]
				_peers.erase(peer_id)
				if _role == Role.CLIENT and peer_id == HOST_PEER_ID:
					_release_and_reset()
				peer_disconnected.emit(peer_id)
			"closed":
				var lost: Array[int] = get_peer_ids()
				_release_and_reset()
				for peer: int in lost:
					peer_disconnected.emit(peer)
			"message":
				var decoded: Dictionary = _decode(event["text"])
				if CoreResult.is_ok(decoded):
					message_received.emit(event["peer"], decoded["message"])


func get_peer_ids() -> Array[int]:
	var ids: Array[int] = []
	for peer_id: Variant in _peers.keys():
		ids.append(peer_id)
	return ids


func is_active() -> bool:
	return _role != Role.NONE


## Test hook: id of this transport's outward connection (0 if none).
func connection_id() -> int:
	return _conn_id


func _release_and_reset() -> void:
	if _conn_id != 0:
		_relay.release(_conn_id)
	_reset()


func _reset() -> void:
	_conn_id = 0
	_role = Role.NONE
	_peers.clear()
