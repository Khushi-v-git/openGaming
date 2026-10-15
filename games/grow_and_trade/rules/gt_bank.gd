class_name GtBank
extends RefCounted
## Resources, costs and the bank for Grow & Trade. Pure logic, no nodes. Every function is static and
## never changes its inputs; "a hand" and "a supply" are plain dicts {resource: count} that hold all five
## resources (missing keys read as 0), so they are JSON-safe and can live in the game state.
##
## Numbers (costs, piece limits, bank supply by player count, deck mix) come from data/costs.json and are
## checked by validate_config(); nothing here hard-codes them except the five resource names.
##
## Functions that can refuse return {ok, ...fields} or {ok: false, error: {code, message}} (CoreResult).

const DEFAULT_PATH: String = "res://games/grow_and_trade/data/costs.json"

const TIMBER: String = "timber"
const CLAY: String = "clay"
const FLEECE: String = "fleece"
const WHEAT: String = "wheat"
const STONE: String = "stone"
const RESOURCES: Array[String] = [TIMBER, CLAY, FLEECE, WHEAT, STONE]

## What can be bought; each has a cost entry in the config.
const COST_KEYS: Array[String] = ["path", "village", "town", "card"]
const PIECE_KEYS: Array[String] = ["path", "village", "town"]

## Harbor kinds a player can own: "any" (3 for 1) or a resource name (2 for 1 on that resource).
const PORT_ANY: String = "any"
const GENERIC_RATE: int = 3
const RESOURCE_RATE: int = 2

const INVALID_CONFIG: String = "INVALID_CONFIG"
const UNSUPPORTED_PLAYER_COUNT: String = "UNSUPPORTED_PLAYER_COUNT"
const CANNOT_AFFORD: String = "CANNOT_AFFORD"
const UNKNOWN_RESOURCE: String = "UNKNOWN_RESOURCE"
const SAME_RESOURCE: String = "SAME_RESOURCE"
const BANK_EMPTY: String = "BANK_EMPTY"
const BAD_DISCARD: String = "BAD_DISCARD"

const MIN_SUPPORTED_PLAYERS: int = 3
const MAX_SUPPORTED_PLAYERS: int = 6


# --- config -------------------------------------------------------------------------------------------

## Reads and validates the config file. Returns {ok, config} or INVALID_CONFIG.
static func load_config(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _bad("There is no config file at %s." % path)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _bad("The config file %s cannot be read." % path)
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return _bad("%s is not valid JSON (line %d: %s)." % [path, json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _bad("%s must contain a JSON object." % path)
	return validate_config(json.data)


## Checks config data and returns {ok, config}: a cleaned copy (ints, every cost and supply with all five
## resource keys where relevant) or INVALID_CONFIG naming the problem. The input is never modified.
static func validate_config(data: Dictionary) -> Dictionary:
	var input: Dictionary = Envelope.normalize(data)
	var costs_in: Variant = input.get("costs")
	if typeof(costs_in) != TYPE_DICTIONARY:
		return _bad("'costs' must be an object.")
	var costs: Dictionary = {}
	for key: String in COST_KEYS:
		var cost: Variant = (costs_in as Dictionary).get(key)
		if typeof(cost) != TYPE_DICTIONARY or (cost as Dictionary).is_empty():
			return _bad("The cost of '%s' is missing." % key)
		var clean: Dictionary = {}
		for resource: Variant in cost:
			if typeof(resource) != TYPE_STRING or not RESOURCES.has(resource):
				return _bad("The cost of '%s' names an unknown resource: %s." % [key, str(resource)])
			if typeof(cost[resource]) != TYPE_INT or cost[resource] < 1:
				return _bad("The cost of '%s' needs whole numbers of at least 1." % key)
			clean[resource] = cost[resource]
		costs[key] = clean

	var pieces_in: Variant = input.get("pieces")
	if typeof(pieces_in) != TYPE_DICTIONARY:
		return _bad("'pieces' must be an object.")
	var pieces: Dictionary = {}
	for key: String in PIECE_KEYS:
		var count: Variant = (pieces_in as Dictionary).get(key)
		if typeof(count) != TYPE_INT or count < 1:
			return _bad("The piece limit for '%s' must be a whole number of at least 1." % key)
		pieces[key] = count

	var supply_in: Variant = input.get("bank_supply")
	if typeof(supply_in) != TYPE_ARRAY:
		return _bad("'bank_supply' must be a list.")
	var supply_rows: Array = []
	var covered: Dictionary = {}
	for row: Variant in supply_in:
		if typeof(row) != TYPE_DICTIONARY:
			return _bad("Each 'bank_supply' entry must be an object.")
		var low: Variant = row.get("min_players")
		var high: Variant = row.get("max_players")
		var each: Variant = row.get("per_resource")
		if typeof(low) != TYPE_INT or typeof(high) != TYPE_INT or typeof(each) != TYPE_INT:
			return _bad("A 'bank_supply' entry needs whole numbers min_players, max_players and per_resource.")
		if low < MIN_SUPPORTED_PLAYERS or high < low or high > MAX_SUPPORTED_PLAYERS or each < 1:
			return _bad("A 'bank_supply' entry must satisfy %d <= min_players <= max_players <= %d and per_resource >= 1." % [MIN_SUPPORTED_PLAYERS, MAX_SUPPORTED_PLAYERS])
		for n: int in range(low, high + 1):
			if covered.has(n):
				return _bad("The bank supply for %d players is given twice." % n)
			covered[n] = true
		supply_rows.append({"min_players": low, "max_players": high, "per_resource": each})
	for n: int in range(MIN_SUPPORTED_PLAYERS, MAX_SUPPORTED_PLAYERS + 1):
		if not covered.has(n):
			return _bad("The bank supply for %d players is missing." % n)

	var deck_in: Variant = input.get("deck")
	if typeof(deck_in) != TYPE_ARRAY or (deck_in as Array).is_empty():
		return _bad("'deck' must be a non-empty list.")
	var deck: Array = []
	var seen: Dictionary = {}
	for entry: Variant in deck_in:
		if typeof(entry) != TYPE_DICTIONARY:
			return _bad("Each 'deck' entry must be an object.")
		var card_type: Variant = entry.get("type")
		var card_count: Variant = entry.get("count")
		if typeof(card_type) != TYPE_STRING or not GtDeck.CARD_TYPES.has(card_type):
			return _bad("The deck names an unknown card type: %s." % str(card_type))
		if seen.has(card_type):
			return _bad("The deck lists '%s' twice." % card_type)
		if typeof(card_count) != TYPE_INT or card_count < 1:
			return _bad("The deck count for '%s' must be a whole number of at least 1." % card_type)
		seen[card_type] = true
		deck.append({"type": card_type, "count": card_count})

	return CoreResult.success({"config": {
		"costs": costs,
		"pieces": pieces,
		"bank_supply": supply_rows,
		"deck": deck,
	}})


## The starting bank for a table: {resource: count}, or UNSUPPORTED_PLAYER_COUNT.
static func supply_for(config: Dictionary, player_count: int) -> Dictionary:
	for row: Dictionary in config["bank_supply"]:
		if player_count >= int(row["min_players"]) and player_count <= int(row["max_players"]):
			var supply: Dictionary = {}
			for resource: String in RESOURCES:
				supply[resource] = int(row["per_resource"])
			return CoreResult.success({"supply": supply})
	return CoreResult.failure(UNSUPPORTED_PLAYER_COUNT, "Grow & Trade has no bank for %d players." % player_count)


# --- hands ---------------------------------------------------------------------------------------------

## A hand or supply with every resource at 0.
static func empty_hand() -> Dictionary:
	var hand: Dictionary = {}
	for resource: String in RESOURCES:
		hand[resource] = 0
	return hand


## A copy of a hand with all five keys present (missing = 0).
static func clean_hand(hand: Dictionary) -> Dictionary:
	var out: Dictionary = empty_hand()
	for resource: String in RESOURCES:
		out[resource] = int(hand.get(resource, 0))
	return out


static func hand_count(hand: Dictionary) -> int:
	var total: int = 0
	for resource: String in RESOURCES:
		total += int(hand.get(resource, 0))
	return total


static func can_afford(hand: Dictionary, cost: Dictionary) -> bool:
	for resource: Variant in cost:
		if int(hand.get(resource, 0)) < int(cost[resource]):
			return false
	return true


## The hand after paying `cost`: {ok, hand}, or CANNOT_AFFORD (the input is unchanged either way).
static func pay(hand: Dictionary, cost: Dictionary) -> Dictionary:
	if not can_afford(hand, cost):
		return CoreResult.failure(CANNOT_AFFORD, "That costs more than the hand holds.")
	var out: Dictionary = clean_hand(hand)
	for resource: Variant in cost:
		out[resource] = int(out[resource]) - int(cost[resource])
	return CoreResult.success({"hand": out})


## A hand plus `gain` ({resource: count}), as a new hand.
static func add(hand: Dictionary, gain: Dictionary) -> Dictionary:
	var out: Dictionary = clean_hand(hand)
	for resource: Variant in gain:
		if RESOURCES.has(resource):
			out[resource] = int(out[resource]) + int(gain[resource])
	return out


# --- paying out a roll -----------------------------------------------------------------------------------

## Pays what a dice roll gives. `owed` is {player_id: {resource: count}}. For each resource:
##   - if the supply covers everyone, everyone is paid in full;
##   - if it falls short and only one player is owed it, that player gets what is left;
##   - if it falls short and several players are owed it, nobody gets any of it.
## Other resources are paid normally. Returns {supply, gains, shortages}: the new supply,
## {player_id: {resource: count}} with only positive entries (a player owed nothing paid still appears,
## with {}), and one event {type: "shortage", resource, owed, available, claimants, paid} per short resource.
## Players and resources are handled in sorted order, so the result never depends on dict order.
static func payout(supply: Dictionary, owed: Dictionary) -> Dictionary:
	var new_supply: Dictionary = clean_hand(supply)
	var gains: Dictionary = {}
	var player_ids: Array = owed.keys()
	player_ids.sort()
	for player_id: Variant in player_ids:
		gains[player_id] = {}
	var shortages: Array = []
	for resource: String in RESOURCES:
		var claimants: Array = []
		var total: int = 0
		for player_id: Variant in player_ids:
			var amount: int = int((owed[player_id] as Dictionary).get(resource, 0))
			if amount > 0:
				claimants.append(player_id)
				total += amount
		if claimants.is_empty():
			continue
		var available: int = int(new_supply[resource])
		var paid: int = 0
		if total <= available:
			for player_id: Variant in claimants:
				var amount: int = int(owed[player_id][resource])
				gains[player_id][resource] = amount
				paid += amount
		else:
			if claimants.size() == 1:
				paid = available
				if paid > 0:
					gains[claimants[0]][resource] = paid
			shortages.append({
				"type": "shortage", "resource": resource, "owed": total,
				"available": available, "claimants": claimants, "paid": paid,
			})
		new_supply[resource] = available - paid
	return {"supply": new_supply, "gains": gains, "shortages": shortages}


# --- the 7: discarding ----------------------------------------------------------------------------------

## How many cards a player must discard after a 7: half their hand (rounded down) if they hold more than
## `limit`, otherwise none. A hand of exactly the limit keeps everything.
static func discard_count(hand_total: int, limit: int) -> int:
	if hand_total <= limit:
		return 0
	return floori(hand_total / 2.0)


## Checks a chosen discard against the hand: all resources known, counts not negative, available in the
## hand, and exactly discard_count(...) cards. Returns {ok, hand} (the hand after discarding) or BAD_DISCARD.
static func apply_discard(hand: Dictionary, discard: Dictionary, limit: int) -> Dictionary:
	var required: int = discard_count(hand_count(hand), limit)
	var taken: int = 0
	for resource: Variant in discard:
		if typeof(resource) != TYPE_STRING or not RESOURCES.has(resource):
			return CoreResult.failure(BAD_DISCARD, "That discard names an unknown resource.")
		var amount: int = int(discard[resource])
		if amount < 0 or amount > int(hand.get(resource, 0)):
			return CoreResult.failure(BAD_DISCARD, "That discard holds cards the player does not have.")
		taken += amount
	if taken != required:
		return CoreResult.failure(BAD_DISCARD, "The discard must be exactly %d cards." % required)
	return CoreResult.success({"hand": pay(hand, discard)["hand"]})


# --- bank trades -----------------------------------------------------------------------------------------

## The best bank rate for `resource` (the one being given) with these harbors. `default_rate` is the
## setting (4, or 3 when no harbor is needed). "any" harbor gives 3, the matching resource harbor 2.
static func bank_rate(player_ports: Array, resource: String, default_rate: int) -> int:
	var rate: int = default_rate
	if player_ports.has(PORT_ANY):
		rate = mini(rate, GENERIC_RATE)
	if player_ports.has(resource):
		rate = mini(rate, RESOURCE_RATE)
	return rate


## One bank trade: give `rate` of one resource, get 1 of another. Returns {ok, hand, supply} with both
## updated, or UNKNOWN_RESOURCE, SAME_RESOURCE, CANNOT_AFFORD, BANK_EMPTY (inputs unchanged).
static func bank_trade(hand: Dictionary, supply: Dictionary, give: String, get_resource: String, rate: int) -> Dictionary:
	if not RESOURCES.has(give) or not RESOURCES.has(get_resource):
		return CoreResult.failure(UNKNOWN_RESOURCE, "That is not a resource.")
	if give == get_resource:
		return CoreResult.failure(SAME_RESOURCE, "Trading a resource for itself does nothing.")
	if int(hand.get(give, 0)) < rate:
		return CoreResult.failure(CANNOT_AFFORD, "That trade needs %d %s." % [rate, give])
	if int(supply.get(get_resource, 0)) < 1:
		return CoreResult.failure(BANK_EMPTY, "The bank has no %s left." % get_resource)
	var new_hand: Dictionary = clean_hand(hand)
	var new_supply: Dictionary = clean_hand(supply)
	new_hand[give] = int(new_hand[give]) - rate
	new_hand[get_resource] = int(new_hand[get_resource]) + 1
	new_supply[give] = int(new_supply[give]) + rate
	new_supply[get_resource] = int(new_supply[get_resource]) - 1
	return CoreResult.success({"hand": new_hand, "supply": new_supply})


static func _bad(message: String) -> Dictionary:
	return CoreResult.failure(INVALID_CONFIG, message)
