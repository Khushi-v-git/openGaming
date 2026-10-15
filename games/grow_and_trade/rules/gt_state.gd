class_name GtState
extends RefCounted
## Read helpers over a Grow & Trade state (see docs/grow-and-trade-design.md). Pure functions,
## no mutation of their inputs.

const STATE_VERSION: int = 1
const GAME_ID: String = "grow_and_trade"

const PHASE_FOUNDING: String = "founding"
const PHASE_PLAYING: String = "playing"
const PHASE_FINISHED: String = "finished"

const PENDING_NONE: String = ""
const PENDING_DISCARD: String = "discard"
const PENDING_BLOCKER: String = "move_blocker"

const COLORS: Array[String] = ["red", "blue", "green", "yellow", "orange", "purple"]


static func seat_order(state: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for entry: Variant in state["players"]:
		ids.append(str(entry["player_id"]))
	return ids


## `active_players` as strings; empty means everybody in seat order.
static func active_or_all(state: Dictionary, active_players: Array) -> Array[String]:
	var out: Array[String] = []
	for value: Variant in active_players:
		out.append(str(value))
	return seat_order(state) if out.is_empty() else out


static func hand(state: Dictionary, player_id: String) -> Dictionary:
	return state["hands"][player_id]


static func hand_count(state: Dictionary, player_id: String) -> int:
	return GtBank.hand_count(state["hands"][player_id])


## Buildings of one kind ("village" or "town") owned by a player.
static func building_count(state: Dictionary, player_id: String, kind: String) -> int:
	var count: int = 0
	for corner: Variant in state["buildings"]:
		var building: Dictionary = state["buildings"][corner]
		if building["owner"] == player_id and building["kind"] == kind:
			count += 1
	return count


static func path_count(state: Dictionary, player_id: String) -> int:
	var count: int = 0
	for edge: Variant in state["paths"]:
		if state["paths"][edge] == player_id:
			count += 1
	return count


## Pieces still in the player's supply: "path", "village" or "town".
static func pieces_left(state: Dictionary, player_id: String, kind: String) -> int:
	var limit: int = int(state["config"]["pieces"][kind])
	var used: int = path_count(state, player_id) if kind == "path" else building_count(state, player_id, kind)
	return limit - used


## Harbor kinds the player can use: "any" for a generic harbor, a resource name for a resource harbor.
static func ports(state: Dictionary, player_id: String) -> Array:
	var found: Array = []
	for harbor: Variant in state["layout"]["harbors"]:
		var owned: bool = false
		for corner: Variant in harbor["corners"]:
			if state["buildings"].has(corner) and state["buildings"][corner]["owner"] == player_id:
				owned = true
		if not owned:
			continue
		var kind: String = GtBank.PORT_ANY if harbor["kind"] == GtBoard.GENERIC else str(harbor["kind"])
		if not found.has(kind):
			found.append(kind)
	return found


## corner -> owner id, for the Longest Path blocking rule.
static func building_owners(state: Dictionary) -> Dictionary:
	var owners: Dictionary = {}
	for corner: Variant in state["buildings"]:
		owners[corner] = state["buildings"][corner]["owner"]
	return owners


## player_id -> Array of [corner_a, corner_b], for every seat (possibly empty).
static func paths_by_player(state: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id: String in seat_order(state):
		out[id] = []
	for edge: Variant in state["paths"]:
		out[state["paths"][edge]].append(GtBoard.edge_corners(edge))
	return out


## The tile at (q, r) in the layout, or {} if there is none.
static func tile_at(state: Dictionary, q: int, r: int) -> Dictionary:
	for tile: Variant in state["layout"]["tiles"]:
		if int(tile["q"]) == q and int(tile["r"]) == r:
			return tile
	return {}


static func is_finished(state: Dictionary) -> bool:
	return state["phase"] == PHASE_FINISHED
