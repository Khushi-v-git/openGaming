class_name GtBoard
extends RefCounted
## The island board of Grow & Trade: hex geometry, data validation and the random layout.
## Pure logic, no nodes.
##
## Hexes use axial coordinates (q, r) as Vector2i(q, r), pointy-top, with six sides numbered
## 0 east, 1 north-east, 2 north-west, 3 west, 4 south-west, 5 south-east (DIRECTIONS).
## Corners and edges have deterministic string ids made of the hex coordinates around them, so
## they work as JSON keys and need no lookup table:
##   corner id: its three hexes, sorted by (r, q), "q,r|q,r|q,r" (hexes may be water);
##   edge id:   its two hexes, same form, "q,r|q,r".
## A corner or edge belongs to the board when at least one of its hexes is land.
##
## File format (JSON, see data/board_large.json); all numbers are whole numbers:
##   { "name": "Large",
##     "hexes": [[q, r], ...],                       # the land hexes
##     "tiles": {"timber": 6, "clay": 5, "fleece": 6, "wheat": 6, "stone": 5, "desert": 2},
##     "tokens": [2, 3, 3, ...],                     # one per non-desert hex, 2..12, never 7
##     "harbor_slots": [{"hex": [q, r], "side": 0}, ...],     # coastal edges
##     "harbor_pool": ["generic", "timber", ...] }   # one per slot: 3:1 "generic" or 2:1 resource
##
## Layout draws from the Prng, in this order (changing it breaks saves and replays): per attempt
## shuffle the tile list, then shuffle the token list; on the first attempt that keeps every 6 and 8
## off touching hexes, shuffle the harbor pool. A shuffle is Fisher-Yates from the end:
## for i from n-1 down to 1, j = range_int(0, i), swap items i and j.

const INVALID_BOARD: String = "INVALID_BOARD"
const DEFAULT_PATH: String = "res://games/grow_and_trade/data/board_large.json"

const MIN_HEXES: int = 7
const MAX_HEXES: int = 61
## Only about 1 random shuffle in 28 keeps the six 6s and 8s apart on the large board, so the cap is
## generous: 2000 attempts fail with odds below 1e-30.
const MAX_LAYOUT_ATTEMPTS: int = 2000
const _PROOF_SEED: int = 20240601  # validate() proves a layout exists by making one with this seed

const RESOURCES: Array[String] = ["timber", "clay", "fleece", "wheat", "stone"]
const DESERT: String = "desert"
const GENERIC: String = "generic"
const GENERIC_RATIO: int = 3
const RESOURCE_RATIO: int = 2
const HOT_TOKENS: Array[int] = [6, 8]

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

## The land hexes in canonical (r, then q) order.
var hexes: Array[Vector2i] = []
var _land: Dictionary = {}  # Vector2i -> true


## `clean` is the board returned by validate(); it is not checked again here.
func _init(clean: Dictionary = {}) -> void:
	for pair: Variant in clean.get("hexes", []):
		var hex: Vector2i = Vector2i(int(pair[0]), int(pair[1]))
		hexes.append(hex)
		_land[hex] = true


# --- geometry that does not depend on the board ------------------------------------------

static func neighbor(hex: Vector2i, side: int) -> Vector2i:
	return hex + DIRECTIONS[posmod(side, 6)]


## The corner between sides `k` and `k + 1` of a hex.
static func corner_id(hex: Vector2i, k: int) -> String:
	return _key([hex, neighbor(hex, k), neighbor(hex, k + 1)])


static func edge_id(hex: Vector2i, side: int) -> String:
	return _key([hex, neighbor(hex, side)])


## The hexes (land or not) named by a corner or edge id.
static func parse_id(id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for part: String in id.split("|"):
		var xy: PackedStringArray = part.split(",")
		out.append(Vector2i(xy[0].to_int(), xy[1].to_int()))
	return out


## The two corners at the ends of an edge. Empty if the id is not an edge.
static func edge_corners(edge: String) -> Array[String]:
	var out: Array[String] = []
	var pair: Array[Vector2i] = parse_id(edge)
	if pair.size() != 2:
		return out
	for side: int in 6:
		if neighbor(pair[0], side) == pair[1]:
			out.append(_key([pair[0], pair[1], neighbor(pair[0], side - 1)]))
			out.append(_key([pair[0], pair[1], neighbor(pair[0], side + 1)]))
			break
	return out


## The three edges that meet at a corner, whether or not they are on the board.
static func corner_edges(corner: String) -> Array[String]:
	var trio: Array[Vector2i] = parse_id(corner)
	return [_key([trio[0], trio[1]]), _key([trio[0], trio[2]]), _key([trio[1], trio[2]])]


static func harbor_ratio(kind: String) -> int:
	return GENERIC_RATIO if kind == GENERIC else RESOURCE_RATIO


# --- queries on this board ---------------------------------------------------------------

func has_hex(hex: Vector2i) -> bool:
	return _land.has(hex)


func land_neighbors(hex: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for side: int in 6:
		var other: Vector2i = neighbor(hex, side)
		if _land.has(other):
			out.append(other)
	return out


func corners_of_hex(hex: Vector2i) -> Array[String]:
	var out: Array[String] = []
	for k: int in 6:
		out.append(corner_id(hex, k))
	return out


func edges_of_hex(hex: Vector2i) -> Array[String]:
	var out: Array[String] = []
	for side: int in 6:
		out.append(edge_id(hex, side))
	return out


## Every corner of the board, each once, in a stable order.
func corners() -> Array[String]:
	var seen: Dictionary = {}
	for hex: Vector2i in hexes:
		for id: String in corners_of_hex(hex):
			seen[id] = true
	var out: Array[String] = []
	out.assign(seen.keys())
	return out


func edges() -> Array[String]:
	var seen: Dictionary = {}
	for hex: Vector2i in hexes:
		for id: String in edges_of_hex(hex):
			seen[id] = true
	var out: Array[String] = []
	out.assign(seen.keys())
	return out


## The land hexes touching a corner (one to three).
func hexes_of_corner(corner: String) -> Array[Vector2i]:
	return _land_among(parse_id(corner))


## The land hexes on either side of an edge (one on the coast, two inland).
func hexes_of_edge(edge: String) -> Array[Vector2i]:
	return _land_among(parse_id(edge))


func corners_of_edge(edge: String) -> Array[String]:
	return edge_corners(edge)


## The edges at a corner that are on the board (touch at least one land hex).
func edges_of_corner(corner: String) -> Array[String]:
	var out: Array[String] = []
	for edge: String in corner_edges(corner):
		if not hexes_of_edge(edge).is_empty():
			out.append(edge)
	return out


## The corners one edge away: the ones a village may not touch (the one-gap rule).
func adjacent_corners(corner: String) -> Array[String]:
	var out: Array[String] = []
	for edge: String in edges_of_corner(corner):
		for other: String in edge_corners(edge):
			if other != corner:
				out.append(other)
	return out


## Edges with water on one side.
func coastal_edges() -> Array[String]:
	var out: Array[String] = []
	for edge: String in edges():
		if is_coastal(edge):
			out.append(edge)
	return out


func is_coastal(edge: String) -> bool:
	return hexes_of_edge(edge).size() == 1


func _land_among(candidates: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for hex: Vector2i in candidates:
		if _land.has(hex):
			out.append(hex)
	return out


# --- loading and validation --------------------------------------------------------------

## Reads and validates a board file. Returns {ok, board} or INVALID_BOARD.
static func load_file(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _bad("There is no board file at %s." % path)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _bad("The board file %s cannot be read." % path)
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return _bad("%s is not valid JSON (line %d: %s)." % [path, json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _bad("%s must contain a JSON object." % path)
	return validate(json.data)


## Checks board data and returns {ok, board} with a cleaned, canonical copy (ints, hexes in
## (r, q) order, tokens and the harbor pool sorted), or INVALID_BOARD with a message.
## Beyond the shape of the data it checks: the land is one connected island, tile and token
## counts match the hex count, harbor slots are distinct coastal edges that share no corner, and
## a layout that keeps 6s and 8s apart exists. The input is never modified.
static func validate(data: Dictionary) -> Dictionary:
	var input: Dictionary = Envelope.normalize(data)
	var board_name: Variant = input.get("name", "Board")
	if typeof(board_name) != TYPE_STRING:
		return _bad("'name' must be text.")

	var hexes_checked: Dictionary = _check_hexes(input.get("hexes"))
	if not CoreResult.is_ok(hexes_checked):
		return hexes_checked
	var land: Array[Vector2i] = []
	land.assign(hexes_checked["hexes"])
	var tiles_checked: Dictionary = _check_tiles(input.get("tiles"), land.size())
	if not CoreResult.is_ok(tiles_checked):
		return tiles_checked
	var desert_count: int = tiles_checked["tiles"][DESERT]
	var tokens_checked: Dictionary = _check_tokens(input.get("tokens"), land.size() - desert_count)
	if not CoreResult.is_ok(tokens_checked):
		return tokens_checked

	var pairs: Array = []
	for hex: Vector2i in land:
		pairs.append([hex.x, hex.y])
	var clean: Dictionary = {
		"name": board_name,
		"hexes": pairs,
		"tiles": tiles_checked["tiles"],
		"tokens": tokens_checked["tokens"],
		"harbor_slots": [],
		"harbor_pool": [],
	}
	var board: GtBoard = GtBoard.new(clean)
	var harbors_checked: Dictionary = _check_harbors(input.get("harbor_slots"), input.get("harbor_pool"), board)
	if not CoreResult.is_ok(harbors_checked):
		return harbors_checked
	clean["harbor_slots"] = harbors_checked["slots"]
	clean["harbor_pool"] = harbors_checked["pool"]

	if not CoreResult.is_ok(_make_layout(board, clean, Prng.new(_PROOF_SEED))):
		return _bad("No layout keeps the 6 and 8 tokens off touching hexes; use fewer hot tokens or a bigger island.")
	return CoreResult.success({"board": clean})


static func _check_hexes(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_ARRAY:
		return _bad("'hexes' must be a list of [q, r] pairs.")
	var list: Array = raw
	if list.size() < MIN_HEXES or list.size() > MAX_HEXES:
		return _bad("The board needs %d to %d hexes, not %d." % [MIN_HEXES, MAX_HEXES, list.size()])
	var seen: Dictionary = {}
	var hexes: Array[Vector2i] = []
	for entry: Variant in list:
		if typeof(entry) != TYPE_ARRAY or (entry as Array).size() != 2 \
				or typeof(entry[0]) != TYPE_INT or typeof(entry[1]) != TYPE_INT:
			return _bad("Every hex must be a [q, r] pair of whole numbers.")
		var hex: Vector2i = Vector2i(entry[0], entry[1])
		if seen.has(hex):
			return _bad("Hex [%d, %d] is listed twice." % [hex.x, hex.y])
		seen[hex] = true
		hexes.append(hex)
	hexes.sort_custom(_hex_less)
	# One island: every hex reachable from the first through land neighbours.
	var reached: Dictionary = {hexes[0]: true}
	var queue: Array[Vector2i] = [hexes[0]]
	while not queue.is_empty():
		var here: Vector2i = queue.pop_back()
		for side: int in 6:
			var other: Vector2i = neighbor(here, side)
			if seen.has(other) and not reached.has(other):
				reached[other] = true
				queue.append(other)
	if reached.size() != hexes.size():
		return _bad("The land is not one connected island (%d of %d hexes reachable)." % [reached.size(), hexes.size()])
	return CoreResult.success({"hexes": hexes})


static func _check_tiles(raw: Variant, hex_count: int) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return _bad("'tiles' must say how many of each tile type there are.")
	var tiles: Dictionary = raw
	var wanted: Array[String] = RESOURCES.duplicate()
	wanted.append(DESERT)
	if tiles.size() != wanted.size():
		return _bad("'tiles' must list exactly: %s." % ", ".join(wanted))
	var clean: Dictionary = {}
	var total: int = 0
	for type: String in wanted:
		var count: Variant = tiles.get(type)
		if typeof(count) != TYPE_INT or count < 1:
			return _bad("Tile type '%s' needs a count of at least 1." % type)
		clean[type] = count
		total += count
	if total != hex_count:
		return _bad("The tile counts add up to %d but the board has %d hexes." % [total, hex_count])
	return CoreResult.success({"tiles": clean})


static func _check_tokens(raw: Variant, producing_hexes: int) -> Dictionary:
	if typeof(raw) != TYPE_ARRAY:
		return _bad("'tokens' must be a list of numbers.")
	var tokens: Array = []
	for value: Variant in raw:
		if typeof(value) != TYPE_INT or value < 2 or value > 12 or value == 7:
			return _bad("Every token must be a whole number from 2 to 12, never 7.")
		tokens.append(value)
	if tokens.size() != producing_hexes:
		return _bad("There are %d tokens for %d hexes that produce." % [tokens.size(), producing_hexes])
	tokens.sort()
	return CoreResult.success({"tokens": tokens})


static func _check_harbors(raw_slots: Variant, raw_pool: Variant, board: GtBoard) -> Dictionary:
	if typeof(raw_slots) != TYPE_ARRAY or typeof(raw_pool) != TYPE_ARRAY:
		return _bad("'harbor_slots' and 'harbor_pool' must be lists.")
	var slots: Array = []
	var used_edges: Dictionary = {}
	var used_corners: Dictionary = {}
	for entry: Variant in raw_slots:
		if typeof(entry) != TYPE_DICTIONARY:
			return _bad("Every harbor slot must be {\"hex\": [q, r], \"side\": 0-5}.")
		var hex_pair: Variant = entry.get("hex")
		var side: Variant = entry.get("side")
		if typeof(hex_pair) != TYPE_ARRAY or (hex_pair as Array).size() != 2 \
				or typeof(hex_pair[0]) != TYPE_INT or typeof(hex_pair[1]) != TYPE_INT \
				or typeof(side) != TYPE_INT or side < 0 or side > 5:
			return _bad("Every harbor slot must be {\"hex\": [q, r], \"side\": 0-5}.")
		var hex: Vector2i = Vector2i(hex_pair[0], hex_pair[1])
		if not board.has_hex(hex):
			return _bad("Harbor slot [%d, %d] side %d is not on a land hex." % [hex.x, hex.y, side])
		var edge: String = edge_id(hex, side)
		if not board.is_coastal(edge):
			return _bad("Harbor slot [%d, %d] side %d is not on the coast." % [hex.x, hex.y, side])
		if used_edges.has(edge):
			return _bad("Two harbor slots use the same edge (hex [%d, %d] side %d)." % [hex.x, hex.y, side])
		used_edges[edge] = true
		for corner: String in edge_corners(edge):
			if used_corners.has(corner):
				return _bad("Harbor slots touching at a corner (hex [%d, %d] side %d)." % [hex.x, hex.y, side])
			used_corners[corner] = true
		slots.append({"hex": [hex.x, hex.y], "side": side})
	var pool: Array = []
	for kind: Variant in raw_pool:
		if typeof(kind) != TYPE_STRING or not (kind == GENERIC or RESOURCES.has(kind)):
			return _bad("A harbor kind must be 'generic' or a resource name.")
		pool.append(kind)
	if pool.size() != slots.size():
		return _bad("There are %d harbors for %d slots." % [pool.size(), slots.size()])
	pool.sort()
	return CoreResult.success({"slots": slots, "pool": pool})


# --- layout ------------------------------------------------------------------------------

## Deals out tile types, number tokens and harbors with the seeded Prng. `clean` must come from
## validate(). Returns {ok, layout} (or INVALID_BOARD if no attempt keeps the 6s and 8s apart):
##   layout = { "tiles":   [{"q", "r", "type", "token"}, ...]   # board hex order; token 0 = none
##              "harbors": [{"q", "r", "side", "edge", "kind", "ratio", "corners": [id, id]}, ...],
##              "blocker": {"q", "r"} }                            # starts on the first desert
static func layout(clean: Dictionary, prng: Prng) -> Dictionary:
	return _make_layout(GtBoard.new(clean), clean, prng)


static func _make_layout(board: GtBoard, clean: Dictionary, prng: Prng) -> Dictionary:
	var types: Array[String] = []
	var tile_counts: Dictionary = clean["tiles"]
	var type_order: Array[String] = RESOURCES.duplicate()
	type_order.append(DESERT)
	for type: String in type_order:
		for i: int in int(tile_counts[type]):
			types.append(type)
	for attempt: int in MAX_LAYOUT_ATTEMPTS:
		_shuffle(types, prng)
		var tokens: Array = (clean["tokens"] as Array).duplicate()
		_shuffle(tokens, prng)
		var tiles: Array = []
		var token_at: Dictionary = {}  # Vector2i -> token, producing hexes only
		var next_token: int = 0
		var blocker: Dictionary = {}
		for i: int in board.hexes.size():
			var hex: Vector2i = board.hexes[i]
			var token: int = 0
			if types[i] == DESERT:
				if blocker.is_empty():
					blocker = {"q": hex.x, "r": hex.y}
			else:
				token = int(tokens[next_token])
				next_token += 1
				token_at[hex] = token
			tiles.append({"q": hex.x, "r": hex.y, "type": types[i], "token": token})
		if _hot_tokens_touch(board, token_at):
			continue
		var pool: Array = (clean["harbor_pool"] as Array).duplicate()
		_shuffle(pool, prng)
		var harbors: Array = []
		for i: int in (clean["harbor_slots"] as Array).size():
			var slot: Dictionary = clean["harbor_slots"][i]
			var hex: Vector2i = Vector2i(slot["hex"][0], slot["hex"][1])
			var edge: String = edge_id(hex, slot["side"])
			harbors.append({
				"q": hex.x, "r": hex.y, "side": slot["side"], "edge": edge,
				"kind": pool[i], "ratio": harbor_ratio(pool[i]), "corners": edge_corners(edge),
			})
		return CoreResult.success({"layout": {"tiles": tiles, "harbors": harbors, "blocker": blocker}})
	return _bad("No valid layout found in %d attempts." % MAX_LAYOUT_ATTEMPTS)


static func _hot_tokens_touch(board: GtBoard, token_at: Dictionary) -> bool:
	for hex: Vector2i in token_at:
		if not HOT_TOKENS.has(token_at[hex]):
			continue
		for other: Vector2i in board.land_neighbors(hex):
			if token_at.has(other) and HOT_TOKENS.has(token_at[other]):
				return true
	return false


static func _shuffle(items: Array, prng: Prng) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j: int = prng.range_int(0, i)
		var held: Variant = items[i]
		items[i] = items[j]
		items[j] = held


# --- helpers -----------------------------------------------------------------------------

static func _hex_less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


static func _key(list: Array[Vector2i]) -> String:
	var sorted: Array[Vector2i] = list.duplicate()
	sorted.sort_custom(_hex_less)
	var parts: PackedStringArray = []
	for hex: Vector2i in sorted:
		parts.append("%d,%d" % [hex.x, hex.y])
	return "|".join(parts)


static func _bad(message: String) -> Dictionary:
	return CoreResult.failure(INVALID_BOARD, message)
