class_name HostRecorder
extends RefCounted
## Test helper: records HostSession signals.

var joined: Array[String] = []
var rejoined: Array[String] = []
var left: Array[String] = []
var hosting: Array[Dictionary] = []
var host_failures: Array[String] = []
var messages: Array[Dictionary] = []  # {player_id, message}


func _init(session: HostSession) -> void:
	session.player_joined.connect(func(player_id: String, was_rejoin: bool) -> void:
		if was_rejoin:
			rejoined.append(player_id)
		else:
			joined.append(player_id))
	session.hosting.connect(func(info: Dictionary) -> void: hosting.append(info))
	session.host_failed.connect(func(reason: String) -> void: host_failures.append(reason))
	session.player_disconnected.connect(func(player_id: String) -> void: left.append(player_id))
	session.player_message.connect(func(player_id: String, message: Dictionary) -> void: messages.append({"player_id": player_id, "message": message}))
