class_name LobbyClientRecorder
extends RefCounted
## Test helper: records LobbyClient signals.

var joined: Array[String] = []
var join_failures: Array[Dictionary] = []  # {code, message, host_info}
var states: Array[Dictionary] = []
var action_failures: Array[Dictionary] = []  # {code, message, action}
var started: int = 0
var left: Array[Dictionary] = []  # {code, message}
var game_messages: Array[Dictionary] = []
var waiting: Array[String] = []


func _init(client: LobbyClient) -> void:
	client.waiting.connect(func(message: String) -> void: waiting.append(message))
	client.joined.connect(func(player_id: String) -> void: joined.append(player_id))
	client.join_failed.connect(func(code: String, message: String, host_info: Dictionary) -> void: join_failures.append({"code": code, "message": message, "host_info": host_info}))
	client.state_changed.connect(func(state: Dictionary) -> void: states.append(state))
	client.action_failed.connect(func(code: String, message: String, action: String) -> void: action_failures.append({"code": code, "message": message, "action": action}))
	client.game_started.connect(func(_state: Dictionary) -> void: started += 1)
	client.left.connect(func(code: String, message: String) -> void: left.append({"code": code, "message": message}))
	client.game_message.connect(func(message: Dictionary) -> void: game_messages.append(message))


func has_outcome() -> bool:
	return not joined.is_empty() or not join_failures.is_empty()
