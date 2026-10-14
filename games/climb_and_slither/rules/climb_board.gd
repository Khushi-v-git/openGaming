class_name ClimbBoard
extends RefCounted
## Board data for Climb and Slither: loading and validation. Pure logic, no nodes.
##
## File format (JSON, see data/classic_board.json):
##   { "name": "Classic", "size": 100, "columns": 10,
##     "snakes":  [ {"from": 99, "to": 61}, ... ],     # head -> tail, tail is lower
##     "ladders": [ {"from": 5,  "to": 27}, ... ] }    # foot -> top, top is higher
## Squares are numbered 1..size. Position 0 (not on the board yet) is never a jump square.
## `columns` is only a layout hint for the UI; the rules ignore it.
##
## Rules a board must satisfy (CLAUDE.md):
##   - every start square is unique, so no square is both a snake and a ladder start,
##     and no square starts two jumps;
##   - no jump starts on square 1 or on the last square;
##   - snakes go down and ladders go up;
##   - a jump's end is never another jump's start: no chains, hence no loops, and a
##     landing triggers at most one jump;
##   - shared end squares are allowed;
##   - the last square can be reached: a search from square 0 over dice rolls 1 to 6 plus the
##     board's jumps must get there. Otherwise nobody could ever win (for example six snake
##     heads in a row, which cannot be crossed, or a trap near the start). The search uses the
##     strictest house rule (an overshooting roll does not move), so a board that passes is
##     winnable under every allowed combination of house rules.

const MIN_SIZE: int = 10
const MAX_SIZE: int = 400
const DEFAULT_PATH: String = "res://games/climb_and_slither/data/classic_board.json"

const KIND_SNAKE: String = "snake"
const KIND_LADDER: String = "ladder"


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


## Checks board data and returns {ok, board} with a cleaned, canonical copy (ints, jumps
## sorted by start square), or INVALID_BOARD with a message naming the offending square.
## The input is never modified.
static func validate(data: Dictionary) -> Dictionary:
	var input: Dictionary = Envelope.normalize(data)
	var size: Variant = input.get("size")
	var columns: Variant = input.get("columns")
	if typeof(size) != TYPE_INT or size < MIN_SIZE or size > MAX_SIZE:
		return _bad("'size' must be a whole number from %d to %d." % [MIN_SIZE, MAX_SIZE])
	if typeof(columns) != TYPE_INT or columns < 2 or columns > size or size % columns != 0:
		return _bad("'columns' must be a whole number from 2 that divides the size (%d)." % size)
	var board_name: Variant = input.get("name", "Board")
	if typeof(board_name) != TYPE_STRING:
		return _bad("'name' must be text.")

	var starts: Dictionary = {}  # square -> kind
	var jump_ends: Dictionary = {}  # start square -> end square
	var clean: Dictionary = {KIND_SNAKE: [], KIND_LADDER: []}
	for kind: String in [KIND_SNAKE, KIND_LADDER]:
		var list_key: String = "snakes" if kind == KIND_SNAKE else "ladders"
		var raw_list: Variant = input.get(list_key)
		if typeof(raw_list) != TYPE_ARRAY:
			return _bad("'%s' must be a list." % list_key)
		for entry: Variant in raw_list:
			var checked: Dictionary = _check_jump(entry, kind, size, starts)
			if not CoreResult.is_ok(checked):
				return checked
			starts[checked["from"]] = kind
			jump_ends[checked["from"]] = checked["to"]
			(clean[kind] as Array).append({"from": checked["from"], "to": checked["to"]})

	for kind: String in [KIND_SNAKE, KIND_LADDER]:
		for jump: Dictionary in clean[kind]:
			if starts.has(jump["to"]):
				return _bad("The %s from %d ends on square %d, which starts a %s: jumps may not chain." % [kind, jump["from"], jump["to"], starts[jump["to"]]])

	var reachable: Dictionary = _reachable(size, jump_ends)
	if not reachable.has(size):
		var furthest: int = 0
		for square: int in reachable:
			furthest = maxi(furthest, square)
		return _bad("The last square (%d) can never be reached: whatever is rolled, nobody gets further than square %d. Look for six or more snake heads in a row, or a trap near the start." % [size, furthest])

	var snakes: Array = clean[KIND_SNAKE]
	var ladders: Array = clean[KIND_LADDER]
	snakes.sort_custom(_by_start)
	ladders.sort_custom(_by_start)
	return CoreResult.success({"board": {
		"name": board_name,
		"size": size,
		"columns": columns,
		"snakes": snakes,
		"ladders": ladders,
	}})


## Every square a player can ever stand on, found by searching from square 0 with dice rolls
## 1 to 6 and the board's jumps (an overshooting roll does not move). The last square is in the
## result exactly when the board is winnable. Takes a validated board. Returns {square: true}.
static func reachable_squares(board: Dictionary) -> Dictionary:
	var jump_ends: Dictionary = {}
	for kind_list: Array in [board["snakes"], board["ladders"]]:
		for jump: Dictionary in kind_list:
			jump_ends[jump["from"]] = jump["to"]
	return _reachable(board["size"], jump_ends)


## The jump that starts on `square`, as {kind, from, to}, or {} if there is none.
static func jump_at(board: Dictionary, square: int) -> Dictionary:
	for jump: Dictionary in board["snakes"]:
		if jump["from"] == square:
			return {"kind": KIND_SNAKE, "from": square, "to": jump["to"]}
	for jump: Dictionary in board["ladders"]:
		if jump["from"] == square:
			return {"kind": KIND_LADDER, "from": square, "to": jump["to"]}
	return {}


static func _reachable(size: int, jump_ends: Dictionary) -> Dictionary:
	var seen: Dictionary = {0: true}
	var queue: Array[int] = [0]
	var head: int = 0
	while head < queue.size():
		var at: int = queue[head]
		head += 1
		if at == size:
			continue
		for roll: int in range(1, 7):
			var target: int = at + roll
			if target > size:
				break  # overshooting does not move (the strictest house rule)
			var landing: int = jump_ends.get(target, target)
			if not seen.has(landing):
				seen[landing] = true
				queue.append(landing)
	return seen


static func _check_jump(entry: Variant, kind: String, size: int, starts: Dictionary) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		return _bad("Every %s must be an object with 'from' and 'to'." % kind)
	var from: Variant = entry.get("from")
	var to: Variant = entry.get("to")
	if typeof(from) != TYPE_INT or typeof(to) != TYPE_INT:
		return _bad("A %s needs whole-number 'from' and 'to' squares." % kind)
	if from == 1:
		return _bad("A %s cannot start on square 1." % kind)
	if from == size:
		return _bad("A %s cannot start on the last square (%d)." % [kind, size])
	if from < 1 or from > size:
		return _bad("A %s starts on square %d, which is off the board (1 to %d)." % [kind, from, size])
	if to < 1 or to > size:
		return _bad("The %s from %d ends on square %d, which is off the board (1 to %d)." % [kind, from, to, size])
	if kind == KIND_SNAKE and to >= from:
		return _bad("The snake from %d must go down, but it ends on %d." % [from, to])
	if kind == KIND_LADDER and to <= from:
		return _bad("The ladder from %d must go up, but it ends on %d." % [from, to])
	if starts.has(from):
		if starts[from] != kind:
			return _bad("Square %d starts both a snake and a ladder." % from)
		return _bad("Square %d starts two %ss." % [from, kind])
	return CoreResult.success({"from": from, "to": to})


static func _by_start(a: Dictionary, b: Dictionary) -> bool:
	return a["from"] < b["from"]


static func _bad(message: String) -> Dictionary:
	return CoreResult.failure(ClimbErrors.INVALID_BOARD, message)
