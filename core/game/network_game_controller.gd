class_name NetworkGameController
extends GameController
## A GameController for a networked game: one class, two ends.
##   for_host(game_host)         the host's own screen (actions go straight to the GameHost)
##   for_client(game_client, rules)  a guest's screen (actions go to the host over the network)
## The screen cannot tell them, or the hot-seat controller, apart.
##
## It does not poll anything: whoever owns the LobbyHost / LobbyClient keeps polling them.

var _host: GameHost = null
var _client: GameClient = null
var _lobby_host: LobbyHost = null
var _lobby_client: LobbyClient = null
var _rules: GameRules
var _last_view: Dictionary = {}
var _last_presence: Dictionary = {}


static func for_host(game_host: GameHost) -> NetworkGameController:
	var controller: NetworkGameController = NetworkGameController.new()
	controller._rules = game_host.rules
	controller._host = game_host
	controller._lobby_host = game_host.lobby
	game_host.batch_ready.connect(controller._on_batch)
	game_host.action_rejected.connect(controller._on_rejected)
	game_host.ended.connect(controller._on_ended)
	game_host.lobby.state_changed.connect(controller._on_lobby_state)
	game_host.lobby.closed.connect(func() -> void: controller.lost.emit({"code": "HOST_CLOSED", "message": "The session was closed."}))
	return controller


static func for_client(game_client: GameClient, game_rules: GameRules) -> NetworkGameController:
	var controller: NetworkGameController = NetworkGameController.new()
	controller._rules = game_rules
	controller._client = game_client
	controller._lobby_client = game_client.lobby
	game_client.batch_ready.connect(controller._on_batch)
	game_client.action_rejected.connect(controller._on_rejected)
	game_client.lobby.state_changed.connect(controller._on_lobby_state)
	game_client.lobby.game_ended.connect(controller._on_ended)
	game_client.lobby.left.connect(func(code: String, message: String) -> void: controller.lost.emit({"code": code, "message": message}))
	game_client.lobby.session.transport.link_state_changed.connect(func(state: String) -> void: controller.link_changed.emit(state))
	return controller


func is_host() -> bool:
	return _host != null


func rules() -> GameRules:
	return _rules


func local_player_id() -> String:
	return _lobby_host.local_player_id if is_host() else _lobby_client.player_id


func latest_view() -> Dictionary:
	return _last_view


func submit_action(action: Dictionary) -> void:
	if is_host():
		_host.submit_local(action)  # a refusal comes back through action_rejected
	else:
		_client.submit(action)


func can_rematch() -> bool:
	return is_host() and _host.is_running()


func rematch() -> Dictionary:
	return _host.rematch() if is_host() else _not_host()


func end_game() -> Dictionary:
	return _lobby_host.act({"type": "end_game"}) if is_host() else _not_host()


func leave() -> void:
	if is_host():
		_lobby_host.close()
	else:
		_lobby_client.leave()


func players() -> Array:
	var out: Array = []
	for slot: Dictionary in _lobby_state().get("slots", []):
		if not slot["left"]:
			out.append({"player_id": slot["player_id"], "name": slot["name"]})
	return out


func presence() -> Dictionary:
	var lobby_state: Dictionary = _lobby_state()
	var away: Array = []
	if not lobby_state.is_empty():
		for slot: Dictionary in LobbyLogic.away_players(lobby_state):
			away.append({"player_id": slot["player_id"], "name": slot["name"]})
	return {
		"paused": not lobby_state.is_empty() and LobbyLogic.is_paused(lobby_state),
		"away": away,
		"can_continue": lobby_state.is_empty() or LobbyLogic.can_continue(lobby_state),
		"is_host": is_host(),
		"min_active": LobbyLogic.min_active(lobby_state) if not lobby_state.is_empty() else 1,
	}


func continue_without_waiting() -> Dictionary:
	return _lobby_host.act({"type": "set_paused", "paused": false}) if is_host() else _not_host()


func wait_again() -> Dictionary:
	return _lobby_host.act({"type": "set_paused", "paused": true}) if is_host() else _not_host()


func remove_player(player_id: String) -> Dictionary:
	return _lobby_host.act({"type": "kick", "player_id": player_id}) if is_host() else _not_host()


func _lobby_state() -> Dictionary:
	return _lobby_host.state if is_host() else _lobby_client.state


func _on_batch(batch: Dictionary) -> void:
	_last_view = batch["view"]
	batch_ready.emit(batch)


func _on_rejected(error: Dictionary) -> void:
	action_rejected.emit(error)


func _on_ended() -> void:
	_last_view = {}
	ended.emit()


func _on_lobby_state(_state: Dictionary) -> void:
	var now: Dictionary = presence()
	if now != _last_presence:
		_last_presence = now
		presence_changed.emit(now)
