class_name ClientRecorder
extends RefCounted
## Test helper: records ClientSession signals.

var connected: Array[Dictionary] = []  # welcome payloads
var rejected: Array[Dictionary] = []  # {code, message}
var connect_failed: Array[String] = []
var host_lost: Array[String] = []
var ended: Array[Dictionary] = []  # {code, message}
var messages: Array[Dictionary] = []


func _init(session: ClientSession) -> void:
	session.connected.connect(func(welcome: Dictionary) -> void: connected.append(welcome))
	session.rejected.connect(func(code: String, message: String) -> void: rejected.append({"code": code, "message": message}))
	session.connect_failed.connect(func(reason: String) -> void: connect_failed.append(reason))
	session.host_lost.connect(func(reason: String) -> void: host_lost.append(reason))
	session.session_ended.connect(func(code: String, message: String) -> void: ended.append({"code": code, "message": message}))
	session.message_received.connect(func(message: Dictionary) -> void: messages.append(message))


## True once the client has an outcome: connected, rejected or failed.
func has_outcome() -> bool:
	return not connected.is_empty() or not rejected.is_empty() or not connect_failed.is_empty()
