class_name TransportRecorder
extends RefCounted
## Test helper: records every event a Transport emits.

var connected: Array[int] = []
var disconnected: Array[int] = []
var messages: Array[Dictionary] = []  # {peer_id, message}
var join_ok_count: int = 0
var join_failures: Array[String] = []


func _init(transport: Transport) -> void:
	transport.peer_connected.connect(func(peer_id: int) -> void: connected.append(peer_id))
	transport.peer_disconnected.connect(func(peer_id: int) -> void: disconnected.append(peer_id))
	transport.message_received.connect(func(peer_id: int, message: Dictionary) -> void: messages.append({"peer_id": peer_id, "message": message}))
	transport.join_succeeded.connect(func() -> void: join_ok_count += 1)
	transport.join_failed.connect(func(reason: String) -> void: join_failures.append(reason))


func messages_of_type(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in messages:
		if entry["message"]["type"] == type:
			out.append(entry)
	return out
