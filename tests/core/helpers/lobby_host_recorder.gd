class_name LobbyHostRecorder
extends RefCounted
## Test helper: records LobbyHost signals.

var states: Array[Dictionary] = []
var started: int = 0
var closed: int = 0
var game_messages: Array[Dictionary] = []  # {player_id, message}


func _init(host: LobbyHost) -> void:
	host.state_changed.connect(func(state: Dictionary) -> void: states.append(state))
	host.game_started.connect(func(_state: Dictionary) -> void: started += 1)
	host.closed.connect(func() -> void: closed += 1)
	host.game_message.connect(func(player_id: String, message: Dictionary) -> void: game_messages.append({"player_id": player_id, "message": message}))
