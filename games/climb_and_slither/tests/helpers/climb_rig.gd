class_name ClimbRig
extends RefCounted
## Test helper: builds games whose first dice are exactly what a test wants, by searching for
## a seed whose Prng produces that sequence. The rules draw dice with
## ClimbAndSlitherRules.draw_dice (one range_int(1, 6) per die, in order), and this helper uses
## the same draws, so "rolls: [6, 3]" really means the first player rolls a 6 and then a 3.
##
## Keep sequences short (about 6 dice or fewer): the search tries seeds one by one.

const SEARCH_LIMIT: int = 3000000

static var _seeds: Dictionary = {}


## `rolls` has one entry per roll: a die value, or an Array of dice for two-dice games.
static func seed_for(rolls: Array) -> int:
	var key: String = var_to_str(rolls)
	if _seeds.has(key):
		return _seeds[key]
	var wanted: Array[int] = []
	for roll: Variant in rolls:
		if roll is Array:
			for die: Variant in roll:
				wanted.append(int(die))
		else:
			wanted.append(int(roll))
	for candidate: int in range(1, SEARCH_LIMIT):
		var prng: Prng = Prng.new(candidate)
		var matches: bool = true
		for die: int in wanted:
			if prng.range_int(1, ClimbSettings.DIE_SIDES) != die:
				matches = false
				break
		if matches:
			_seeds[key] = candidate
			return candidate
	push_error("ClimbRig: no seed found for %s" % key)
	return -1


static func jump(from: int, to: int) -> Dictionary:
	return {"from": from, "to": to}


## A validated board; the default has no jumps at all.
static func board(snakes: Array = [], ladders: Array = [], size: int = 100, columns: int = 10) -> Dictionary:
	var result: Dictionary = ClimbBoard.validate({"name": "Rig", "size": size, "columns": columns, "snakes": snakes, "ladders": ladders})
	assert(CoreResult.is_ok(result), "rig board is invalid: %s" % str(result))
	return result["board"]


static func classic() -> Dictionary:
	return ClimbBoard.load_file()["board"]


## A started game. `rolls` are the first dice (see seed_for); `positions` overrides where
## players stand (player id -> square); `board_data` defaults to the classic board.
static func game(rolls: Array, players: Array = ["p1", "p2"], settings: Dictionary = {}, positions: Dictionary = {}, board_data: Dictionary = {}) -> Dictionary:
	var rules: ClimbAndSlitherRules = ClimbAndSlitherRules.new()
	var chosen_board: Dictionary = board_data if not board_data.is_empty() else classic()
	var created: Dictionary = rules.new_game(players, chosen_board, settings, seed_for(rolls))
	assert(CoreResult.is_ok(created), "rig game failed: %s" % str(created))
	var state: Dictionary = created["state"]
	for id: String in positions:
		state["positions"][id] = positions[id]
	return state


static func event_types(events: Array) -> Array[String]:
	var out: Array[String] = []
	for event: Dictionary in events:
		out.append(event["type"])
	return out


## A random but valid board, for fuzzing: sizes 15 to 140, random snakes and ladders that obey
## every board rule (unique starts, none on square 1 or the last square, right direction, no
## jump ending on another's start). Shared end squares happen naturally.
static func random_board(prng: Prng) -> Dictionary:
	var columns: int = [5, 6, 8, 10][prng.range_int(0, 3)]
	var rows: int = prng.range_int(3, 14)
	var size: int = columns * rows
	var starts: Dictionary = {}
	var jumps: Array[Dictionary] = []  # {kind, from, to}
	var attempts: int = prng.range_int(0, maxi(1, size / 5))
	for _i: int in attempts:
		var from: int = prng.range_int(2, size - 1)
		if starts.has(from):
			continue
		var snake: bool = prng.range_int(0, 1) == 0
		var to: int = prng.range_int(1, from - 1) if snake else prng.range_int(from + 1, size)
		starts[from] = true
		jumps.append({"snake": snake, "from": from, "to": to})
	var snakes: Array = []
	var ladders: Array = []
	for jump: Dictionary in jumps:
		if starts.has(jump["to"]):
			continue  # would chain: drop it
		(snakes if jump["snake"] else ladders).append({"from": jump["from"], "to": jump["to"]})
	return board(snakes, ladders, size, columns)
