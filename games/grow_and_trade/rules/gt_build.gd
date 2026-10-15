class_name GtBuild
extends RefCounted
## Building during the main phase: build_path, build_village, build_town. Also holds the placement
## checks that GtFounding reuses (is the id on the board, is the corner free).
##
## Draws no random numbers. Works on a copy of the state; on error the input is untouched.

const ACTIONS: Array[String] = ["build_path", "build_village", "build_town"]


## {ok, state, events} or a failure. The dispatcher has already checked that the game is not over and
## that `player_id` is an active player of this game.
static func apply(state: Dictionary, board: GtBoard, player_id: String, action: Dictionary) -> Dictionary:
	var type: String = str(action.get("type", ""))
	if not ACTIONS.has(type):
		return CoreResult.failure(ErrorCodes.UNKNOWN_ACTION, "Unknown action %s." % type)
	var field: String = "edge" if type == "build_path" else "corner"
	var shape: Dictionary = check_shape(action, field)
	if not CoreResult.is_ok(shape):
		return shape
	var allowed: Dictionary = _check_turn(state, player_id)
	if not CoreResult.is_ok(allowed):
		return allowed
	var at: String = action[field]
	var next: Dictionary = state.duplicate(true)
	var events: Array = []
	var built: Dictionary
	match type:
		"build_path":
			built = _build_path(next, board, player_id, at)
		"build_village":
			built = _build_village(next, board, player_id, at)
		_:
			built = _build_town(next, player_id, at)
	if not CoreResult.is_ok(built):
		return built
	events.append({"type": "built", "player_id": player_id, "kind": type.trim_prefix("build_"), "at": at})
	GtScore.refresh_bonuses(next, events)
	GtScore.finish_if_won(next, player_id, events)
	return CoreResult.success({"state": next, "events": events})


# --- checks shared with GtFounding ---------------------------------------------------------------

## The action must be exactly {type, <field>} with `field` a string.
static func check_shape(action: Dictionary, field: String) -> Dictionary:
	if action.size() != 2 or typeof(action.get(field)) != TYPE_STRING:
		return CoreResult.failure(ErrorCodes.BAD_ACTION, "This action takes exactly one field, '%s', as text." % field)
	return CoreResult.success()


## True if `id` is a well-formed corner id of this board (at least one land hex around it).
static func is_board_corner(board: GtBoard, id: String) -> bool:
	var hex: Variant = _first_hex(id, 3)
	if hex == null:
		return false
	for k: int in 6:
		if GtBoard.corner_id(hex, k) == id:
			return not board.hexes_of_corner(id).is_empty()
	return false


## True if `id` is a well-formed edge id of this board.
static func is_board_edge(board: GtBoard, id: String) -> bool:
	var hex: Variant = _first_hex(id, 2)
	if hex == null:
		return false
	for side: int in 6:
		if GtBoard.edge_id(hex, side) == id:
			return not board.hexes_of_edge(id).is_empty()
	return false


## Why a village may not stand on this corner, or "" if it may: it must be on the board, empty and
## not next to any building (the one-gap rule).
static func corner_problem(state: Dictionary, board: GtBoard, corner: String) -> String:
	if not is_board_corner(board, corner):
		return "That corner is not on the board."
	if state["buildings"].has(corner):
		return "That corner is already taken."
	for other: String in board.adjacent_corners(corner):
		if state["buildings"].has(other):
			return "That corner is next to another building."
	return ""


## Failure NO_PIECES if the player has none of this kind left, otherwise success.
static func check_pieces(state: Dictionary, player_id: String, kind: String) -> Dictionary:
	if GtState.pieces_left(state, player_id, kind) <= 0:
		return CoreResult.failure(GtErrors.NO_PIECES, "You have no %s pieces left." % kind)
	return CoreResult.success()


# --- the three builds ----------------------------------------------------------------------------

static func _build_path(next: Dictionary, board: GtBoard, player_id: String, edge: String) -> Dictionary:
	if not is_board_edge(board, edge):
		return _bad_place("That edge is not on the board.")
	if next["paths"].has(edge):
		return _bad_place("That edge already has a path.")
	if not _path_connects(next, board, player_id, edge):
		return _bad_place("A path must continue from one of your buildings or paths.")
	var pieces: Dictionary = check_pieces(next, player_id, "path")
	if not CoreResult.is_ok(pieces):
		return pieces
	if int(next["turn"]["free_paths"]) > 0:
		next["turn"]["free_paths"] = int(next["turn"]["free_paths"]) - 1
	else:
		var paid: Dictionary = _pay(next, player_id, "path")
		if not CoreResult.is_ok(paid):
			return paid
	next["paths"][edge] = player_id
	return CoreResult.success()


static func _build_village(next: Dictionary, board: GtBoard, player_id: String, corner: String) -> Dictionary:
	var problem: String = corner_problem(next, board, corner)
	if problem != "":
		return _bad_place(problem)
	if not _touches_own_path(next, board, player_id, corner):
		return _bad_place("A village must touch one of your paths.")
	var pieces: Dictionary = check_pieces(next, player_id, "village")
	if not CoreResult.is_ok(pieces):
		return pieces
	var paid: Dictionary = _pay(next, player_id, "village")
	if not CoreResult.is_ok(paid):
		return paid
	next["buildings"][corner] = {"owner": player_id, "kind": "village"}
	return CoreResult.success()


static func _build_town(next: Dictionary, player_id: String, corner: String) -> Dictionary:
	var building: Variant = next["buildings"].get(corner)
	if building == null or building["owner"] != player_id or building["kind"] != "village":
		return _bad_place("A town replaces one of your own villages.")
	var pieces: Dictionary = check_pieces(next, player_id, "town")
	if not CoreResult.is_ok(pieces):
		return pieces
	var paid: Dictionary = _pay(next, player_id, "town")
	if not CoreResult.is_ok(paid):
		return paid
	next["buildings"][corner] = {"owner": player_id, "kind": "town"}
	return CoreResult.success()


# --- helpers -------------------------------------------------------------------------------------

## Phase, turn owner, rolled, nothing pending.
static func _check_turn(state: Dictionary, player_id: String) -> Dictionary:
	if state["phase"] == GtState.PHASE_FINISHED:
		return CoreResult.failure(GtErrors.GAME_OVER, "The game is over.")
	if state["phase"] != GtState.PHASE_PLAYING:
		return CoreResult.failure(GtErrors.WRONG_PHASE, "You cannot build until the founding rounds are over.")
	if state["current_player"] != player_id:
		return CoreResult.failure(GtErrors.NOT_YOUR_TURN, "It is not your turn.")
	var turn: Dictionary = state["turn"]
	if turn["pending"] == GtState.PENDING_DISCARD:
		return CoreResult.failure(GtErrors.MUST_DISCARD, "Players must discard first.")
	if turn["pending"] != GtState.PENDING_NONE:
		return CoreResult.failure(GtErrors.WRONG_PHASE, "Move the blocker first.")
	if not turn["rolled"]:
		return CoreResult.failure(GtErrors.NOT_ROLLED, "Roll the dice first.")
	return CoreResult.success()


## Takes the cost of `kind` from the player's hand and puts it back in the bank supply.
static func _pay(next: Dictionary, player_id: String, kind: String) -> Dictionary:
	var cost: Dictionary = next["config"]["costs"][kind]
	var paid: Dictionary = GtBank.pay(next["hands"][player_id], cost)
	if not CoreResult.is_ok(paid):
		return CoreResult.failure(GtErrors.CANNOT_AFFORD, "You cannot afford that.")
	next["hands"][player_id] = paid["hand"]
	next["supply"] = GtBank.add(next["supply"], cost)
	return CoreResult.success()


## A path may start at a corner holding the player's building, or continue a path of theirs through a
## corner no rival building stands on.
static func _path_connects(state: Dictionary, board: GtBoard, player_id: String, edge: String) -> bool:
	for corner: String in board.corners_of_edge(edge):
		var building: Variant = state["buildings"].get(corner)
		if building != null and building["owner"] == player_id:
			return true
		if building == null and _touches_own_path(state, board, player_id, corner):
			return true
	return false


static func _touches_own_path(state: Dictionary, board: GtBoard, player_id: String, corner: String) -> bool:
	for edge: String in board.edges_of_corner(corner):
		if state["paths"].get(edge) == player_id:
			return true
	return false


## The first hex of an id with `parts` hexes ("q,r|q,r..."), or null if it is not shaped like one.
static func _first_hex(id: String, parts: int) -> Variant:
	var pieces: PackedStringArray = id.split("|")
	if pieces.size() != parts:
		return null
	var first: Vector2i = Vector2i.ZERO
	for i: int in pieces.size():
		var xy: PackedStringArray = pieces[i].split(",")
		if xy.size() != 2 or not xy[0].is_valid_int() or not xy[1].is_valid_int():
			return null
		if xy[0].length() > 6 or xy[1].length() > 6:
			return null  # no board is that big, and to_int logs an engine error on huge numbers
		if i == 0:
			first = Vector2i(xy[0].to_int(), xy[1].to_int())
	return first


static func _bad_place(message: String) -> Dictionary:
	return CoreResult.failure(GtErrors.BAD_PLACEMENT, message)
