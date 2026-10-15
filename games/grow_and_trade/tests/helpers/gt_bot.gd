class_name GtBot
extends RefCounted
## A random player for tests. `pick(state, active)` returns the next action somebody legally takes,
## `{player_id, action}`, worked out from the board geometry and the state alone (it never asks the rules
## whether an action is legal, so a refusal of what it picked is a bug in the rules or in the bot).
## `junk(state)` returns an action that must ALWAYS be refused. Deterministic from its own seed.
##
## Weighted to finish games: it builds eagerly, trades with the bank towards what it lacks, ends its turn
## more and more often the longer it has dithered, and answers offers.

const RESOURCES: Array[String] = ["timber", "clay", "fleece", "wheat", "stone"]
const MAX_OFFERS_PER_TURN: int = 2

var _prng: Prng
var _board: GtBoard = null
var _turn_key: String = ""
var _actions_this_turn: int = 0
var _offers_this_turn: int = 0


func _init(seed_value: int) -> void:
	_prng = Prng.new(seed_value)


## The next legal action by somebody present: {player_id, action}, or {} if nobody present can act
## (the caller should settle) or the game is over. `active` empty = everybody.
func pick(state: Dictionary, active: Array = []) -> Dictionary:
	if _board == null:
		_board = GtBoard.new(state["board"])
	if state["phase"] == GtState.PHASE_FINISHED:
		return {}
	var present: Array[String] = GtState.active_or_all(state, active)
	if state["phase"] == GtState.PHASE_FOUNDING:
		return _founding(state, present)
	return _playing(state, present)


## An action that is never legal: unknown type, stranger, extra fields, garbage ids, a non-owner's owner action.
func junk(state: Dictionary) -> Dictionary:
	var ids: Array[String] = GtState.seat_order(state)
	var owner: String = state["current_player"]
	var others: Array[String] = []
	for id: String in ids:
		if id != owner:
			others.append(id)
	match _prng.range_int(0, 6):
		0:
			return {"player_id": owner, "action": {"type": "fly"}}
		1:
			return {"player_id": "stranger", "action": {"type": "roll"}}
		2:
			return {"player_id": owner, "action": {"type": "roll", "cheat": 1}}
		3:
			return {"player_id": owner, "action": {"type": "build_path", "edge": "9,9|9,10"}}
		4:
			return {"player_id": others[_prng.range_int(0, others.size() - 1)], "action": {"type": "end_turn"}}
		5:
			return {"player_id": owner, "action": {"type": "place_village", "corner": "nowhere"}}
		_:
			return {"player_id": owner, "action": {"type": "bank_trade", "give": "timber", "get": "timber"}}


# --- founding ------------------------------------------------------------------------------------------

func _founding(state: Dictionary, present: Array[String]) -> Dictionary:
	var placer: String = state["current_player"]
	if not present.has(placer):
		return {}
	var founding: Dictionary = state["founding"]
	if founding["expect"] == "village":
		var corners: Array[String] = []
		for corner: String in _board.corners():
			if _free_for_village(state, corner):
				corners.append(corner)
		return _act(placer, {"type": "place_village", "corner": _random_of(corners)})
	var edges: Array[String] = []
	for edge: String in _board.edges_of_corner(founding["last_village"]):
		if not state["paths"].has(edge):
			edges.append(edge)
	return _act(placer, {"type": "place_path", "edge": _random_of(edges)})


# --- playing -------------------------------------------------------------------------------------------

func _playing(state: Dictionary, present: Array[String]) -> Dictionary:
	var owner: String = state["current_player"]
	var turn: Dictionary = state["turn"]
	var key: String = "%d" % int(state["turn_number"])
	if key != _turn_key:
		_turn_key = key
		_actions_this_turn = 0
		_offers_this_turn = 0
	_actions_this_turn += 1
	if turn["pending"] == "discard":
		return _a_discard(state, present)
	if not present.has(owner):
		return {}
	if turn["pending"] == "move_blocker":
		return _a_blocker(state, owner)
	if not (state["offer"] as Dictionary).is_empty() and _prng.range_int(0, 2) != 0:
		var answer: Dictionary = _an_answer(state, present)
		if not answer.is_empty():
			return answer
	if not turn["rolled"]:
		return _before_roll(state, owner)
	return _main_phase(state, owner)


func _a_discard(state: Dictionary, present: Array[String]) -> Dictionary:
	var candidates: Array[String] = []
	for id: Variant in state["turn"]["owed"]:
		if present.has(str(id)):
			candidates.append(str(id))
	if candidates.is_empty():
		return {}
	var who: String = _random_of(candidates)
	var cards: Array[String] = _expand(state["hands"][who])
	var chosen: Dictionary = {}
	for _i: int in int(state["turn"]["owed"][who]):
		var index: int = _prng.range_int(0, cards.size() - 1)
		chosen[cards[index]] = int(chosen.get(cards[index], 0)) + 1
		cards.remove_at(index)
	return _act(who, {"type": "discard", "resources": chosen})


func _a_blocker(state: Dictionary, owner: String) -> Dictionary:
	var spared_any_other: bool = false
	var tiles: Array = []
	for tile: Variant in state["layout"]["tiles"]:
		var hex: Vector2i = Vector2i(int(tile["q"]), int(tile["r"]))
		if hex.x == int(state["blocker"]["q"]) and hex.y == int(state["blocker"]["r"]):
			continue
		tiles.append(hex)
		if not _spares(state, owner, hex):
			spared_any_other = true
	var allowed: Array = []
	for hex: Vector2i in tiles:
		if not state["settings"]["friendly_blocker"] or not _spares(state, owner, hex) or not spared_any_other:
			allowed.append(hex)
	var target: Vector2i = _random_of(allowed)
	var action: Dictionary = {"type": "move_blocker", "q": target.x, "r": target.y}
	var victims: Array[String] = []
	for id: String in _neighbours(state, owner, target):
		if _hand_count(state, id) > 0:
			victims.append(id)
	if not victims.is_empty():
		action["victim"] = _random_of(victims)
	return _act(owner, action)


func _an_answer(state: Dictionary, present: Array[String]) -> Dictionary:
	var offer: Dictionary = state["offer"]
	var waiting: Array[String] = []
	for id: String in _addressees(state):
		if present.has(id) and not (offer["accepted"] as Array).has(id) and not (offer["declined"] as Array).has(id):
			waiting.append(id)
	if waiting.is_empty():
		return {}
	var who: String = _random_of(waiting)
	if _can_afford(state["hands"][who], offer["want"]) and _prng.range_int(0, 9) < 6:
		return _act(who, {"type": "accept_trade"})
	return _act(who, {"type": "decline_trade"})


func _before_roll(state: Dictionary, owner: String) -> Dictionary:
	var turn: Dictionary = state["turn"]
	if not turn["card_played"] and (state["cards"][owner]["held"] as Array).has("guard") and _prng.range_int(0, 3) == 0:
		return _act(owner, {"type": "play_card", "card": "guard"})
	return _act(owner, {"type": "roll"})


## A weighted random pick among the things the turn owner can do now. End turn is always possible.
func _main_phase(state: Dictionary, owner: String) -> Dictionary:
	var options: Array = []  # [weight, action]
	var hand: Dictionary = state["hands"][owner]
	var costs: Dictionary = state["config"]["costs"]
	var turn: Dictionary = state["turn"]

	for corner: String in _own_corners(state, owner, "village"):
		if _pieces_left(state, owner, "town") > 0 and _can_afford(hand, costs["town"]):
			options.append([10, {"type": "build_town", "corner": corner}])
	if _pieces_left(state, owner, "village") > 0 and _can_afford(hand, costs["village"]):
		var spots: Array[String] = []
		for corner: String in _board.corners():
			if _free_for_village(state, corner) and _touches_own_path(state, owner, corner):
				spots.append(corner)
		if not spots.is_empty():
			options.append([9, {"type": "build_village", "corner": _random_of(spots)}])
	var free: bool = int(turn["free_paths"]) > 0
	if _pieces_left(state, owner, "path") > 0 and (free or _can_afford(hand, costs["path"])):
		var edges: Array[String] = []
		for edge: String in _board.edges():
			if not state["paths"].has(edge) and _path_connects(state, owner, edge):
				edges.append(edge)
		if not edges.is_empty():
			options.append([8 if free else 4, {"type": "build_path", "edge": _random_of(edges)}])
	if not (state["deck"] as Array).is_empty() and _can_afford(hand, costs["card"]):
		options.append([4, {"type": "buy_card"}])
	_add_card_options(state, owner, options)
	_add_bank_options(state, owner, options)
	_add_trade_options(state, owner, options)
	options.append([3 + 2 * _actions_this_turn, {"type": "end_turn"}])
	return _act(owner, _weighted(options))


func _add_card_options(state: Dictionary, owner: String, options: Array) -> void:
	if state["turn"]["card_played"]:
		return
	var held: Array = state["cards"][owner]["held"]
	if held.has("guard"):
		options.append([3, {"type": "play_card", "card": "guard"}])
	if held.has("two_paths"):
		options.append([4, {"type": "play_card", "card": "two_paths"}])
	if held.has("harvest"):
		var wanted: Array = [_random_of(RESOURCES), _random_of(RESOURCES)]
		var need: Dictionary = {}
		for resource: String in wanted:
			need[resource] = int(need.get(resource, 0)) + 1
		if _can_afford(state["supply"], need):
			options.append([4, {"type": "play_card", "card": "harvest", "resources": wanted}])
	if held.has("sweep"):
		options.append([3, {"type": "play_card", "card": "sweep", "resource": _random_of(RESOURCES)}])


func _add_bank_options(state: Dictionary, owner: String, options: Array) -> void:
	var hand: Dictionary = state["hands"][owner]
	var ports: Array = GtState.ports(state, owner)
	var gives: Array[String] = []
	for resource: String in RESOURCES:
		var rate: int = GtBank.bank_rate(ports, resource, int(state["settings"]["bank_rate"]))
		if int(hand[resource]) >= rate:
			gives.append(resource)
	if gives.is_empty():
		return
	var give: String = _random_of(gives)
	var lacking: Array[String] = []
	for resource: String in RESOURCES:
		if resource != give and int(hand[resource]) == 0 and int(state["supply"][resource]) > 0:
			lacking.append(resource)
	if lacking.is_empty():
		for resource: String in RESOURCES:
			if resource != give and int(state["supply"][resource]) > 0:
				lacking.append(resource)
	if lacking.is_empty():
		return
	options.append([5 if int(hand[give]) >= 5 else 2, {"type": "bank_trade", "give": give, "get": _random_of(lacking)}])


func _add_trade_options(state: Dictionary, owner: String, options: Array) -> void:
	var offer: Dictionary = state["offer"]
	if offer.is_empty():
		if _offers_this_turn < MAX_OFFERS_PER_TURN:
			var made: Dictionary = _an_offer(state, owner)
			if not made.is_empty():
				options.append([3, made])
		return
	var accepted: Array = offer["accepted"]
	var partners: Array[String] = []
	for id: Variant in accepted:
		if _can_afford(state["hands"][str(id)], offer["want"]) and _can_afford(state["hands"][owner], offer["give"]):
			partners.append(str(id))
	if not partners.is_empty():
		options.append([12, {"type": "choose_trade_partner", "player": _random_of(partners)}])
	options.append([1, {"type": "withdraw_offer"}])


func _an_offer(state: Dictionary, owner: String) -> Dictionary:
	var hand: Dictionary = state["hands"][owner]
	var giveable: Array[String] = []
	for resource: String in RESOURCES:
		if int(hand[resource]) > 0:
			giveable.append(resource)
	if giveable.is_empty():
		return {}
	var give_resource: String = _random_of(giveable)
	var wants: Array[String] = []
	for resource: String in RESOURCES:
		if resource != give_resource:
			wants.append(resource)
	var action: Dictionary = {
		"type": "offer_trade",
		"give": {give_resource: _prng.range_int(1, mini(3, int(hand[give_resource])))},
		"want": {_random_of(wants): _prng.range_int(1, 2)},
	}
	if _prng.range_int(0, 2) == 0:
		var to: Array = []
		for id: String in GtState.seat_order(state):
			if id != owner and _prng.range_int(0, 1) == 0:
				to.append(id)
		if not to.is_empty():
			action["to"] = to
	return action


# --- geometry and legality, worked out here -------------------------------------------------------------

func _free_for_village(state: Dictionary, corner: String) -> bool:
	if state["buildings"].has(corner):
		return false
	for other: String in _board.adjacent_corners(corner):
		if state["buildings"].has(other):
			return false
	return true


func _touches_own_path(state: Dictionary, owner: String, corner: String) -> bool:
	for edge: String in _board.edges_of_corner(corner):
		if state["paths"].get(edge) == owner:
			return true
	return false


## A path may start at the player's own building or continue their path through a corner no building stands on.
func _path_connects(state: Dictionary, owner: String, edge: String) -> bool:
	for corner: String in _board.corners_of_edge(edge):
		if state["buildings"].has(corner):
			if state["buildings"][corner]["owner"] == owner:
				return true
		elif _touches_own_path(state, owner, corner):
			return true
	return false


func _own_corners(state: Dictionary, owner: String, kind: String) -> Array[String]:
	var out: Array[String] = []
	for corner: Variant in state["buildings"]:
		var building: Dictionary = state["buildings"][corner]
		if building["owner"] == owner and building["kind"] == kind:
			out.append(str(corner))
	out.sort()
	return out


func _pieces_left(state: Dictionary, owner: String, kind: String) -> int:
	var used: int = 0
	if kind == "path":
		for edge: Variant in state["paths"]:
			if state["paths"][edge] == owner:
				used += 1
	else:
		used = _own_corners(state, owner, kind).size()
	return int(state["config"]["pieces"][kind]) - used


## Players other than `owner` with a building on a corner of `hex`, in seat order.
func _neighbours(state: Dictionary, owner: String, hex: Vector2i) -> Array[String]:
	var found: Dictionary = {}
	for corner: String in _board.corners_of_hex(hex):
		if state["buildings"].has(corner):
			found[state["buildings"][corner]["owner"]] = true
	var out: Array[String] = []
	for id: String in GtState.seat_order(state):
		if id != owner and found.has(id):
			out.append(id)
	return out


## friendly_blocker: the tile has neighbours and all of them have 2 public points or fewer.
func _spares(state: Dictionary, owner: String, hex: Vector2i) -> bool:
	var neighbours: Array[String] = _neighbours(state, owner, hex)
	if neighbours.is_empty():
		return false
	for id: String in neighbours:
		if GtScore.points(state, id, false) > 2:
			return false
	return true


func _addressees(state: Dictionary) -> Array[String]:
	var offer: Dictionary = state["offer"]
	var out: Array[String] = []
	if not (offer["to"] as Array).is_empty():
		for id: Variant in offer["to"]:
			out.append(str(id))
		return out
	for id: String in GtState.seat_order(state):
		if id != offer["from"]:
			out.append(id)
	return out


# --- small helpers -------------------------------------------------------------------------------------

func _can_afford(hand: Dictionary, cost: Dictionary) -> bool:
	for resource: Variant in cost:
		if int(hand.get(resource, 0)) < int(cost[resource]):
			return false
	return true


func _hand_count(state: Dictionary, player_id: String) -> int:
	var total: int = 0
	for resource: String in RESOURCES:
		total += int(state["hands"][player_id][resource])
	return total


func _expand(hand: Dictionary) -> Array[String]:
	var cards: Array[String] = []
	for resource: String in RESOURCES:
		for _i: int in int(hand[resource]):
			cards.append(resource)
	return cards


func _random_of(items: Array) -> Variant:
	return items[_prng.range_int(0, items.size() - 1)]


func _weighted(options: Array) -> Dictionary:
	var total: int = 0
	for option: Array in options:
		total += int(option[0])
	var roll: int = _prng.range_int(1, total)
	for option: Array in options:
		roll -= int(option[0])
		if roll <= 0:
			return option[1]
	return options[options.size() - 1][1]


func _act(player_id: String, action: Dictionary) -> Dictionary:
	if action.get("type") == "offer_trade":
		_offers_this_turn += 1
	return {"player_id": player_id, "action": action}
