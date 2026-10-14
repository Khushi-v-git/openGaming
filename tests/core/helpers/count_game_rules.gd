class_name CountGameRules
extends GameRules
## A tiny test-only game ("count to N") that exists to prove core/game has no Climb and
## Slither code in it: players take turns adding 1 to 3 to a shared total, and whoever reaches
## the target wins. It has a host-only field so view_for has something to hide.
##
## State: {game_id, phase, target, total, players [ids], current_player, winner, secret}
## Action: {"type": "add", "n": 1..3}
## Events: added {player_id, n, total}, turn_changed {player_id}, won {player_id}

const GAME_ID: String = "count_to"
const PUBLIC_KEYS: Array[String] = ["game_id", "phase", "target", "total", "players", "current_player", "winner"]


func new_game(player_ids: Array, setup: Dictionary, _settings: Dictionary, seed_value: int) -> Dictionary:
	if player_ids.size() < 2:
		return CoreResult.failure("BAD_PLAYERS", "Needs two players.")
	var target: int = int(setup.get("target", 10))
	var state: Dictionary = {
		"game_id": GAME_ID, "phase": "in_progress", "target": target, "total": 0,
		"players": player_ids.duplicate(), "current_player": player_ids[0], "winner": "",
		"secret": "seed-%d" % seed_value,
	}
	return CoreResult.success({"state": state, "events": []})


func apply(state: Dictionary, player_id: String, action: Dictionary, active_players: Array = []) -> Dictionary:
	if state["phase"] == "finished":
		return CoreResult.failure("GAME_OVER", "The game is over.")
	if not (state["players"] as Array).has(player_id):
		return CoreResult.failure(ErrorCodes.UNKNOWN_PLAYER, "Not playing.")
	if state["current_player"] != player_id:
		return CoreResult.failure("NOT_YOUR_TURN", "Not your turn.")
	var n: int = int(action.get("n", 0))
	if action.get("type") != "add" or n < 1 or n > 3:
		return CoreResult.failure(ErrorCodes.BAD_ACTION, "Add 1 to 3.")
	var next: Dictionary = state.duplicate(true)
	next["total"] = int(next["total"]) + n
	var events: Array = [{"type": "added", "player_id": player_id, "n": n, "total": next["total"]}]
	if int(next["total"]) >= int(next["target"]):
		next["phase"] = "finished"
		next["winner"] = player_id
		events.append({"type": "won", "player_id": player_id})
	else:
		var order: Array[String] = []
		for id: Variant in next["players"]:
			order.append(id)
		var active: Array[String] = []
		for id: Variant in (active_players if not active_players.is_empty() else order):
			active.append(id)
		next["current_player"] = TurnOrder.next_active(order, player_id, active)
		events.append({"type": "turn_changed", "player_id": next["current_player"]})
	return CoreResult.success({"state": next, "events": events})


func view_for(state: Dictionary, player_id: String) -> Dictionary:
	var view: Dictionary = {}
	for key: String in PUBLIC_KEYS:
		view[key] = state[key].duplicate(true) if state[key] is Array or state[key] is Dictionary else state[key]
	view["you"] = player_id
	return view


func validate_state(state: Dictionary) -> Dictionary:
	for key: String in PUBLIC_KEYS + ["secret"]:
		if not state.has(key):
			return CoreResult.failure("INVALID_STATE", "Missing %s." % key)
	return CoreResult.success()


func is_finished(state_or_view: Dictionary) -> bool:
	return state_or_view["phase"] == "finished"


func current_player(state_or_view: Dictionary) -> String:
	return "" if is_finished(state_or_view) else String(state_or_view["current_player"])


func winner(state_or_view: Dictionary) -> String:
	return String(state_or_view["winner"])
