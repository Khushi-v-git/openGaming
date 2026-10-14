class_name LobbyHostRecorder
extends RefCounted
## Test helper: records LobbyHost signals.

var states: Array[Dictionary] = []
var started: int = 0
var closed: int = 0
var rejoin_requests: Array[Dictionary] = []  # {player_id, name}
var rejoin_cancelled: Array[String] = []
var hosting: Array[Dictionary] = []
var host_failures: Array[String] = []
var game_messages: Array[Dictionary] = []  # {player_id, message}


func _init(host: LobbyHost) -> void:
	host.state_changed.connect(func(state: Dictionary) -> void: states.append(state))
	host.game_started.connect(func(_state: Dictionary) -> void: started += 1)
	host.rejoin_requested.connect(func(player_id: String, player_name: String) -> void: rejoin_requests.append({"player_id": player_id, "name": player_name}))
	host.rejoin_request_cancelled.connect(func(player_id: String) -> void: rejoin_cancelled.append(player_id))
	host.hosting.connect(func(info: Dictionary) -> void: hosting.append(info))
	host.host_failed.connect(func(reason: String) -> void: host_failures.append(reason))
	host.closed.connect(func() -> void: closed += 1)
	host.game_message.connect(func(player_id: String, message: Dictionary) -> void: game_messages.append({"player_id": player_id, "message": message}))
