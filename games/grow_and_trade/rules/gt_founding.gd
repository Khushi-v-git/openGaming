class_name GtFounding
extends RefCounted
## The two founding rounds: each player places a village and a path touching it, in seat order, then
## again in reverse seat order. A second-round village pays one resource per adjacent producing tile.
##
## Draws no random numbers. Works on a copy of the state; on error the input is untouched.

const ACTIONS: Array[String] = ["place_village", "place_path"]


## {ok, state, events} or a failure. The dispatcher has already checked that the game is not over and
## that `player_id` is an active player of this game.
static func apply(state: Dictionary, board: GtBoard, player_id: String, action: Dictionary) -> Dictionary:
	var type: String = str(action.get("type", ""))
	if not ACTIONS.has(type):
		return CoreResult.failure(ErrorCodes.UNKNOWN_ACTION, "Unknown action %s." % type)
	var field: String = "corner" if type == "place_village" else "edge"
	var shape: Dictionary = GtBuild.check_shape(action, field)
	if not CoreResult.is_ok(shape):
		return shape
	var allowed: Dictionary = _check_turn(state, player_id, "village" if type == "place_village" else "path")
	if not CoreResult.is_ok(allowed):
		return allowed
	var next: Dictionary = state.duplicate(true)
	var events: Array = []
	var placed: Dictionary
	if type == "place_village":
		placed = _place_village(next, board, player_id, action["corner"], events)
	else:
		placed = _place_path(next, board, player_id, action["edge"], events)
	if not CoreResult.is_ok(placed):
		return placed
	return CoreResult.success({"state": next, "events": events})


static func _check_turn(state: Dictionary, player_id: String, expect: String) -> Dictionary:
	if state["phase"] == GtState.PHASE_FINISHED:
		return CoreResult.failure(GtErrors.GAME_OVER, "The game is over.")
	if state["phase"] != GtState.PHASE_FOUNDING:
		return CoreResult.failure(GtErrors.WRONG_PHASE, "The founding rounds are over.")
	var founding: Dictionary = state["founding"]
	if founding["order"][int(founding["index"])] != player_id:
		return CoreResult.failure(GtErrors.NOT_YOUR_TURN, "It is not your turn to place.")
	if founding["expect"] != expect:
		return CoreResult.failure(GtErrors.WRONG_PHASE, "Place a %s now." % founding["expect"])
	return CoreResult.success()


static func _place_village(next: Dictionary, board: GtBoard, player_id: String, corner: String, events: Array) -> Dictionary:
	var problem: String = GtBuild.corner_problem(next, board, corner)
	if problem != "":
		return CoreResult.failure(GtErrors.BAD_PLACEMENT, problem)
	var pieces: Dictionary = GtBuild.check_pieces(next, player_id, "village")
	if not CoreResult.is_ok(pieces):
		return pieces
	next["buildings"][corner] = {"owner": player_id, "kind": "village"}
	next["founding"]["expect"] = "path"
	next["founding"]["last_village"] = corner
	events.append({"type": "founding_placed", "player_id": player_id, "kind": "village", "at": corner})
	if int(next["founding"]["index"]) >= next["players"].size():
		_pay_second_village(next, board, player_id, corner, events)
	return CoreResult.success()


static func _place_path(next: Dictionary, board: GtBoard, player_id: String, edge: String, events: Array) -> Dictionary:
	if not GtBuild.is_board_edge(board, edge):
		return CoreResult.failure(GtErrors.BAD_PLACEMENT, "That edge is not on the board.")
	if next["paths"].has(edge):
		return CoreResult.failure(GtErrors.BAD_PLACEMENT, "That edge already has a path.")
	if not board.corners_of_edge(edge).has(next["founding"]["last_village"]):
		return CoreResult.failure(GtErrors.BAD_PLACEMENT, "The path must touch the village you just placed.")
	var pieces: Dictionary = GtBuild.check_pieces(next, player_id, "path")
	if not CoreResult.is_ok(pieces):
		return pieces
	next["paths"][edge] = player_id
	events.append({"type": "founding_placed", "player_id": player_id, "kind": "path", "at": edge})
	_advance(next, events)
	return CoreResult.success()


## Moves to the next placement, or into the playing phase after the very last path.
static func _advance(next: Dictionary, events: Array) -> void:
	var founding: Dictionary = next["founding"]
	var before: String = next["current_player"]
	var index: int = int(founding["index"]) + 1
	if index >= founding["order"].size():
		next["phase"] = GtState.PHASE_PLAYING
		next["founding"] = {}
		next["turn"] = GtSetup.new_turn()
		next["current_player"] = next["players"][0]["player_id"]
		events.append({"type": "turn_changed", "player_id": next["current_player"]})
		return
	founding["index"] = index
	founding["expect"] = "village"
	founding["last_village"] = ""
	next["current_player"] = founding["order"][index]
	if next["current_player"] != before:
		events.append({"type": "turn_changed", "player_id": next["current_player"]})


## One resource per adjacent producing tile, from the bank (shortage rule applies).
static func _pay_second_village(next: Dictionary, board: GtBoard, player_id: String, corner: String, events: Array) -> void:
	var owed: Dictionary = {}
	var tiles: Array = []
	for hex: Vector2i in board.hexes_of_corner(corner):
		var tile: Dictionary = GtState.tile_at(next, hex.x, hex.y)
		if tile.is_empty() or tile["type"] == GtBoard.DESERT:
			continue
		owed[tile["type"]] = int(owed.get(tile["type"], 0)) + 1
		tiles.append({"q": hex.x, "r": hex.y, "token": int(tile["token"])})
	var paid: Dictionary = GtBank.payout(next["supply"], {player_id: owed})
	var gain: Dictionary = paid["gains"][player_id]
	next["supply"] = paid["supply"]
	next["hands"][player_id] = GtBank.add(next["hands"][player_id], gain)
	if gain.is_empty():
		events.append({"type": "nothing_produced"})
	else:
		events.append({"type": "produced", "gains": {player_id: gain}, "tiles": tiles})
	events.append_array(paid["shortages"])
