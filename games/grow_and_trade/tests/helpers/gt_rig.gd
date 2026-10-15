class_name GtRig
extends RefCounted
## Test helpers: quick Grow & Trade states without writing out every placement.

const IDS: Array = ["p1", "p2", "p3", "p4", "p5", "p6"]


static func board() -> Dictionary:
	return GtBoard.load_file()["board"]


static func players(count: int) -> Array:
	return IDS.slice(0, count)


## A fresh game in the founding phase.
static func new_state(count: int = 4, settings: Dictionary = {}, seed_value: int = 1) -> Dictionary:
	var created: Dictionary = GrowAndTradeRules.new().new_game(players(count), board(), settings, seed_value)
	assert(CoreResult.is_ok(created), str(created))
	return created["state"]


## A game whose founding rounds are over (played by a bot), so it is player one's turn, nothing rolled.
static func playing(count: int = 4, settings: Dictionary = {}, seed_value: int = 1) -> Dictionary:
	var rules: GrowAndTradeRules = GrowAndTradeRules.new()
	var state: Dictionary = new_state(count, settings, seed_value)
	var bot: GtBot = GtBot.new(seed_value + 1000)
	while state["phase"] == "founding":
		var picked: Dictionary = bot.pick(state)
		var result: Dictionary = rules.apply(state, picked["player_id"], picked["action"])
		assert(CoreResult.is_ok(result), str(result))
		state = result["state"]
	return state


## Moves resources from the bank into a player's hand (nothing is created).
static func give(state: Dictionary, player_id: String, resources: Dictionary) -> void:
	for resource: Variant in resources:
		state["hands"][player_id][resource] = int(state["hands"][player_id][resource]) + int(resources[resource])
		state["supply"][resource] = int(state["supply"][resource]) - int(resources[resource])


## Returns a player's whole hand to the bank.
static func empty_hand(state: Dictionary, player_id: String) -> void:
	for resource: String in GtBank.RESOURCES:
		state["supply"][resource] = int(state["supply"][resource]) + int(state["hands"][player_id][resource])
		state["hands"][player_id][resource] = 0


## The owner's turn after the roll, nothing pending, empty hands for everybody.
static func rolled(state: Dictionary) -> Dictionary:
	var next: Dictionary = state.duplicate(true)
	for id: String in GtState.seat_order(next):
		empty_hand(next, id)
	next["turn"]["rolled"] = true
	next["turn"]["dice"] = [3, 4]
	return next


## The id of a building owned by somebody other than `owner`, with a tile (q, r) it touches that is not
## under the blocker. {} if there is none.
static func rival_tile(state: Dictionary, owner: String) -> Dictionary:
	var board_geometry: GtBoard = GtBoard.new(state["board"])
	for corner: Variant in state["buildings"]:
		var building: Dictionary = state["buildings"][corner]
		if building["owner"] == owner:
			continue
		for hex: Vector2i in board_geometry.hexes_of_corner(str(corner)):
			if hex.x != int(state["blocker"]["q"]) or hex.y != int(state["blocker"]["r"]):
				return {"q": hex.x, "r": hex.y, "victim": building["owner"], "corner": str(corner)}
	return {}
