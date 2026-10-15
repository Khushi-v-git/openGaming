class_name GtValidate
extends RefCounted
## Checks every invariant of a Grow & Trade state (docs/grow-and-trade-design.md, "State"). Used by
## tests and by the host before it trusts a loaded save. Returns {ok} or INVALID_STATE naming what
## is wrong. Floats are refused anywhere: a state loaded from JSON must have had its whole numbers
## turned back into ints first (core does that on load, Envelope.normalize).

const _KEYS: Array[String] = [
	"state_version", "game_id", "phase", "settings", "config", "board", "layout", "blocker",
	"players", "hands", "supply", "buildings", "paths", "cards", "guards_played", "deck", "bonuses",
	"founding", "turn", "offer", "current_player", "turn_number", "winner", "rng",
]
const _TURN_KEYS: Array[String] = ["rolled", "dice", "card_played", "free_paths", "pending", "owed", "source"]
const _OFFER_KEYS: Array[String] = ["from", "give", "want", "to", "accepted", "declined"]
const _FOUNDING_KEYS: Array[String] = ["order", "index", "expect", "last_village"]
const _TILE_KEYS: Array[String] = ["q", "r", "type", "token"]
const _HARBOR_KEYS: Array[String] = ["q", "r", "side", "edge", "kind", "ratio", "corners"]
const _MAX_FREE_PATHS: int = 2


static func validate_state(state: Dictionary) -> Dictionary:
	for key: String in _KEYS:
		if not state.has(key):
			return _invalid("The state has no '%s'." % key)
	if state.size() != _KEYS.size():
		return _invalid("The state has unexpected extra fields.")
	var plain: String = _plain_data(state, "state")
	if plain != "":
		return _invalid(plain)
	if typeof(state["state_version"]) != TYPE_INT or state["state_version"] != GtState.STATE_VERSION:
		return _invalid("Unsupported state version.")
	if typeof(state["game_id"]) != TYPE_STRING or state["game_id"] != GtState.GAME_ID:
		return _invalid("This state belongs to another game.")
	var phase: Variant = state["phase"]
	if typeof(phase) != TYPE_STRING or not [GtState.PHASE_FOUNDING, GtState.PHASE_PLAYING, GtState.PHASE_FINISHED].has(phase):
		return _invalid("Unknown phase.")

	var settings_problem: String = _check_settings_config_board(state)
	if settings_problem != "":
		return _invalid(settings_problem)
	var board: GtBoard = GtBoard.new(state["board"])
	var layout_problem: String = _check_layout(state, board)
	if layout_problem != "":
		return _invalid(layout_problem)

	var ids: Array[String] = []
	var players_problem: String = _check_players(state["players"], ids)
	if players_problem != "":
		return _invalid(players_problem)
	var holdings_problem: String = _check_holdings(state, ids)
	if holdings_problem != "":
		return _invalid(holdings_problem)
	var pieces_problem: String = _check_pieces(state, board, ids)
	if pieces_problem != "":
		return _invalid(pieces_problem)

	var flow_problem: String = _check_flow(state, ids)
	if flow_problem != "":
		return _invalid(flow_problem)
	var bonus_problem: String = _check_bonuses(state, ids)
	if bonus_problem != "":
		return _invalid(bonus_problem)
	var end_problem: String = _check_end(state, ids)
	if end_problem != "":
		return _invalid(end_problem)
	var rng: Variant = state["rng"]
	if typeof(rng) != TYPE_DICTIONARY or rng.size() != 2 or typeof(rng.get("seed")) != TYPE_STRING or typeof(rng.get("state")) != TYPE_STRING:
		return _invalid("The random generator state is damaged.")
	if Prng.restore(rng["seed"], rng["state"]) == null:
		return _invalid("The random generator state is not valid.")
	return CoreResult.success()


# --- shape ----------------------------------------------------------------------------------------

## "" if `value` is JSON-safe plain data without floats; otherwise what is wrong.
static func _plain_data(value: Variant, path: String) -> String:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return ""
		TYPE_FLOAT:
			return "%s is a decimal number; whole numbers must be ints." % path
		TYPE_ARRAY:
			for i: int in (value as Array).size():
				var problem: String = _plain_data(value[i], "%s[%d]" % [path, i])
				if problem != "":
					return problem
			return ""
		TYPE_DICTIONARY:
			for key: Variant in value:
				if typeof(key) != TYPE_STRING:
					return "%s has a key that is not text." % path
				var problem: String = _plain_data(value[key], "%s.%s" % [path, key])
				if problem != "":
					return problem
			return ""
	return "%s holds data that is not plain." % path


static func _has_exactly(value: Variant, keys: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY or (value as Dictionary).size() != keys.size():
		return false
	for key: String in keys:
		if not (value as Dictionary).has(key):
			return false
	return true


static func _is_count(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0


## A {resource: int >= 0} map with all five resources and nothing else.
static func _is_full_hand(value: Variant) -> bool:
	if not _has_exactly(value, GtBank.RESOURCES):
		return false
	for resource: String in GtBank.RESOURCES:
		if not _is_count(value[resource]):
			return false
	return true


## A non-empty {resource: int >= 1} map over known resources only.
static func _is_resource_map(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or (value as Dictionary).is_empty():
		return false
	for resource: Variant in value:
		if typeof(resource) != TYPE_STRING or not GtBank.RESOURCES.has(resource):
			return false
		if typeof(value[resource]) != TYPE_INT or value[resource] < 1:
			return false
	return true


static func _string_list(value: Variant) -> Array[String]:
	var out: Array[String] = []
	for item: Variant in value:
		out.append(str(item))
	return out


static func _all_strings(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for item: Variant in value:
		if typeof(item) != TYPE_STRING:
			return false
	return true


# --- settings, config, board, layout --------------------------------------------------------------

static func _check_settings_config_board(state: Dictionary) -> String:
	if typeof(state["settings"]) != TYPE_DICTIONARY:
		return "The settings are damaged."
	var settings: Dictionary = GtSetup.normalize(state["settings"])
	if not CoreResult.is_ok(settings) or settings["settings"] != state["settings"]:
		return "The settings are not valid."
	if typeof(state["config"]) != TYPE_DICTIONARY:
		return "The config is damaged."
	var config: Dictionary = GtBank.validate_config(state["config"])
	if not CoreResult.is_ok(config) or config["config"] != state["config"]:
		return "The config is not valid."
	if typeof(state["board"]) != TYPE_DICTIONARY:
		return "The board is damaged."
	var board: Dictionary = GtBoard.validate(state["board"])
	if not CoreResult.is_ok(board) or board["board"] != state["board"]:
		return "The board is not valid."
	return ""


static func _check_layout(state: Dictionary, board: GtBoard) -> String:
	var clean: Dictionary = state["board"]
	var layout: Variant = state["layout"]
	if not _has_exactly(layout, ["tiles", "harbors"]):
		return "The layout is damaged."
	var tiles: Variant = layout["tiles"]
	if typeof(tiles) != TYPE_ARRAY or (tiles as Array).size() != board.hexes.size():
		return "The layout does not cover the board."
	var type_counts: Dictionary = {}
	var tokens: Array = []
	var token_at: Dictionary = {}
	for i: int in board.hexes.size():
		var tile: Variant = tiles[i]
		if not _has_exactly(tile, _TILE_KEYS):
			return "A tile is damaged."
		if typeof(tile["q"]) != TYPE_INT or typeof(tile["r"]) != TYPE_INT or Vector2i(tile["q"], tile["r"]) != board.hexes[i]:
			return "The tiles are not in board order."
		var type: Variant = tile["type"]
		if typeof(type) != TYPE_STRING or not (GtBoard.RESOURCES.has(type) or type == GtBoard.DESERT):
			return "A tile has an unknown type."
		if typeof(tile["token"]) != TYPE_INT:
			return "A tile token is not a whole number."
		if type == GtBoard.DESERT:
			if tile["token"] != 0:
				return "A desert has a number token."
		else:
			if tile["token"] < 2 or tile["token"] > 12 or tile["token"] == 7:
				return "A tile has an impossible number token."
			tokens.append(tile["token"])
			token_at[board.hexes[i]] = tile["token"]
		type_counts[type] = int(type_counts.get(type, 0)) + 1
	for type: String in clean["tiles"]:
		if int(type_counts.get(type, 0)) != int(clean["tiles"][type]):
			return "The tile types do not match the board."
	tokens.sort()
	var expected_tokens: Array = (clean["tokens"] as Array).duplicate()
	expected_tokens.sort()
	if tokens != expected_tokens:
		return "The number tokens do not match the board."
	for hex: Vector2i in token_at:
		if not GtBoard.HOT_TOKENS.has(token_at[hex]):
			continue
		for other: Vector2i in board.land_neighbors(hex):
			if token_at.has(other) and GtBoard.HOT_TOKENS.has(token_at[other]):
				return "A 6 or 8 touches another 6 or 8."

	var harbors: Variant = layout["harbors"]
	var slots: Array = clean["harbor_slots"]
	if typeof(harbors) != TYPE_ARRAY or (harbors as Array).size() != slots.size():
		return "The harbors do not match the board."
	var kinds: Array = []
	for i: int in slots.size():
		var harbor: Variant = harbors[i]
		if not _has_exactly(harbor, _HARBOR_KEYS):
			return "A harbor is damaged."
		var slot: Dictionary = slots[i]
		var hex: Vector2i = Vector2i(slot["hex"][0], slot["hex"][1])
		if harbor["q"] != hex.x or harbor["r"] != hex.y or harbor["side"] != slot["side"]:
			return "A harbor is not on its slot."
		var edge: String = GtBoard.edge_id(hex, slot["side"])
		if harbor["edge"] != edge or harbor["corners"] != GtBoard.edge_corners(edge):
			return "A harbor is not on its edge."
		if typeof(harbor["kind"]) != TYPE_STRING or not (harbor["kind"] == GtBoard.GENERIC or GtBoard.RESOURCES.has(harbor["kind"])):
			return "A harbor has an unknown kind."
		if harbor["ratio"] != GtBoard.harbor_ratio(harbor["kind"]):
			return "A harbor has the wrong ratio."
		kinds.append(harbor["kind"])
	kinds.sort()
	var pool: Array = (clean["harbor_pool"] as Array).duplicate()
	pool.sort()
	if kinds != pool:
		return "The harbor kinds do not match the board."

	var blocker: Variant = state["blocker"]
	if not _has_exactly(blocker, ["q", "r"]) or typeof(blocker["q"]) != TYPE_INT or typeof(blocker["r"]) != TYPE_INT:
		return "The blocker is damaged."
	if not board.has_hex(Vector2i(blocker["q"], blocker["r"])):
		return "The blocker is not on the island."
	return ""


# --- players, hands, cards --------------------------------------------------------------------------

static func _check_players(players: Variant, ids: Array[String]) -> String:
	if typeof(players) != TYPE_ARRAY or players.size() < GtSetup.MIN_PLAYERS or players.size() > GtSetup.MAX_PLAYERS:
		return "The player list is not valid."
	for i: int in players.size():
		var entry: Variant = players[i]
		if not _has_exactly(entry, ["player_id", "color"]):
			return "A player entry is damaged."
		if typeof(entry["player_id"]) != TYPE_STRING or (entry["player_id"] as String).is_empty():
			return "A player id is not valid."
		if ids.has(entry["player_id"]):
			return "A player appears twice."
		if entry["color"] != GtState.COLORS[i]:
			return "Player colors must follow seat order."
		ids.append(entry["player_id"])
	return ""


static func _same_keys(value: Variant, ids: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY or (value as Dictionary).size() != ids.size():
		return false
	for id: String in ids:
		if not (value as Dictionary).has(id):
			return false
	return true


static func _check_holdings(state: Dictionary, ids: Array[String]) -> String:
	if not _same_keys(state["hands"], ids) or not _same_keys(state["cards"], ids) or not _same_keys(state["guards_played"], ids):
		return "The hands, cards or played guards do not match the players."
	if not _is_full_hand(state["supply"]):
		return "The bank is damaged."
	for id: String in ids:
		if not _is_full_hand(state["hands"][id]):
			return "A hand is damaged."
		if not _is_count(state["guards_played"][id]):
			return "A played guard count is not valid."
		if not _has_exactly(state["cards"][id], ["held", "fresh"]):
			return "A card record is damaged."
		for list: String in ["held", "fresh"]:
			if typeof(state["cards"][id][list]) != TYPE_ARRAY:
				return "A card list is damaged."
			for card: Variant in state["cards"][id][list]:
				if typeof(card) != TYPE_STRING or not GtDeck.CARD_TYPES.has(card):
					return "A player holds an unknown card."

	var supplied: Dictionary = GtBank.supply_for(state["config"], ids.size())
	if not CoreResult.is_ok(supplied):
		return "There is no bank for this many players."
	for resource: String in GtBank.RESOURCES:
		var total: int = int(state["supply"][resource])
		for id: String in ids:
			total += int(state["hands"][id][resource])
		if total != int(supplied["supply"][resource]):
			return "The %s in the game does not add up to the bank's start." % resource

	if typeof(state["deck"]) != TYPE_ARRAY:
		return "The deck is damaged."
	var counts: Dictionary = {}
	for card: Variant in state["deck"]:
		if typeof(card) != TYPE_STRING or not GtDeck.CARD_TYPES.has(card):
			return "The deck has an unknown card."
		counts[card] = int(counts.get(card, 0)) + 1
	var played_guards: int = 0
	for id: String in ids:
		for list: String in ["held", "fresh"]:
			for card: String in state["cards"][id][list]:
				counts[card] = int(counts.get(card, 0)) + 1
		played_guards += int(state["guards_played"][id])
	counts[GtDeck.GUARD] = int(counts.get(GtDeck.GUARD, 0)) + played_guards
	var limits: Dictionary = {}
	for entry: Dictionary in state["config"]["deck"]:
		limits[entry["type"]] = int(entry["count"])
	for card: Variant in counts:
		if int(counts[card]) > int(limits.get(card, 0)):
			return "There are more '%s' cards than the deck holds." % str(card)
	return ""


# --- the board pieces ---------------------------------------------------------------------------------

static func _check_pieces(state: Dictionary, board: GtBoard, ids: Array[String]) -> String:
	if typeof(state["buildings"]) != TYPE_DICTIONARY or typeof(state["paths"]) != TYPE_DICTIONARY:
		return "The buildings or paths are damaged."
	var corners: Dictionary = {}
	for corner: String in board.corners():
		corners[corner] = true
	var edges: Dictionary = {}
	for edge: String in board.edges():
		edges[edge] = true
	var villages: Dictionary = {}
	var towns: Dictionary = {}
	var paths: Dictionary = {}
	for id: String in ids:
		villages[id] = 0
		towns[id] = 0
		paths[id] = 0
	for corner: String in state["buildings"]:
		var building: Variant = state["buildings"][corner]
		if not corners.has(corner):
			return "A building is not on a corner of the board."
		if not _has_exactly(building, ["owner", "kind"]) or typeof(building["owner"]) != TYPE_STRING or not ids.has(building["owner"]):
			return "A building is damaged."
		if building["kind"] == "village":
			villages[building["owner"]] += 1
		elif building["kind"] == "town":
			towns[building["owner"]] += 1
		else:
			return "A building has an unknown kind."
		for near: String in board.adjacent_corners(corner):
			if state["buildings"].has(near):
				return "Two buildings are next to each other."
	for edge: String in state["paths"]:
		var owner: Variant = state["paths"][edge]
		if not edges.has(edge):
			return "A path is not on an edge of the board."
		if typeof(owner) != TYPE_STRING or not ids.has(owner):
			return "A path has an unknown owner."
		paths[owner] += 1
	var limits: Dictionary = state["config"]["pieces"]
	for id: String in ids:
		if villages[id] > int(limits["village"]) or towns[id] > int(limits["town"]) or paths[id] > int(limits["path"]):
			return "A player has more pieces than exist."
	return ""


static func _check_bonuses(state: Dictionary, ids: Array[String]) -> String:
	var bonuses: Variant = state["bonuses"]
	if not _has_exactly(bonuses, ["longest_path", "largest_guard"]):
		return "The bonuses are damaged."
	for key: String in ["longest_path", "largest_guard"]:
		if typeof(bonuses[key]) != TYPE_STRING or not (bonuses[key] == "" or ids.has(bonuses[key])):
			return "A bonus is held by someone who is not playing."
	var copy: Dictionary = state.duplicate(true)
	GtScore.refresh_bonuses(copy, [])
	if copy["bonuses"] != state["bonuses"]:
		return "The bonuses do not match the board."
	return ""


# --- turn flow, offers, end --------------------------------------------------------------------------------

static func _check_flow(state: Dictionary, ids: Array[String]) -> String:
	var phase: String = state["phase"]
	var current: Variant = state["current_player"]
	if typeof(current) != TYPE_STRING or not ids.has(current):
		return "The current player is not in the game."
	if typeof(state["turn_number"]) != TYPE_INT or state["turn_number"] < 1:
		return "'turn_number' is not valid."

	var founding: Variant = state["founding"]
	if phase == GtState.PHASE_FOUNDING:
		var problem: String = _check_founding(state, ids)
		if problem != "":
			return problem
	elif typeof(founding) != TYPE_DICTIONARY or not (founding as Dictionary).is_empty():
		return "Founding is over, but its record is still there."

	var turn_problem: String = _check_turn(state, ids)
	if turn_problem != "":
		return turn_problem
	return _check_offer(state, ids)


static func _check_founding(state: Dictionary, ids: Array[String]) -> String:
	var founding: Variant = state["founding"]
	if not _has_exactly(founding, _FOUNDING_KEYS):
		return "The founding record is damaged."
	var expected_order: Array[String] = ids.duplicate()
	var backwards: Array[String] = ids.duplicate()
	backwards.reverse()
	expected_order.append_array(backwards)
	if not _all_strings(founding["order"]) or _string_list(founding["order"]) != expected_order:
		return "The founding order is wrong."
	var index: Variant = founding["index"]
	if typeof(index) != TYPE_INT or index < 0 or index >= expected_order.size():
		return "The founding step is out of range."
	var placer: String = expected_order[index]
	if state["current_player"] != placer:
		return "The current player is not the one who places next."
	var expect: Variant = founding["expect"]
	var last: Variant = founding["last_village"]
	if typeof(last) != TYPE_STRING:
		return "The founding record is damaged."
	var buildings: Dictionary = state["buildings"]
	if expect == "village":
		if last != "" and not buildings.has(last):
			return "The last founded village is not on the board."
		# "at most": settle() skips a placer who is away, so a step can have fewer pieces than its index
		if buildings.size() > index or state["paths"].size() > index:
			return "The founding step does not match what has been placed."
	elif expect == "path":
		if last == "" or not buildings.has(last) or buildings[last]["owner"] != placer:
			return "A path is due, but there is no village of the placer to put it by."
		if buildings.size() > index + 1 or state["paths"].size() > index:
			return "The founding step does not match what has been placed."
	else:
		return "The founding step is unknown."
	return ""


static func _check_turn(state: Dictionary, ids: Array[String]) -> String:
	var turn: Variant = state["turn"]
	if not _has_exactly(turn, _TURN_KEYS):
		return "The turn record is damaged."
	if typeof(turn["rolled"]) != TYPE_BOOL or typeof(turn["card_played"]) != TYPE_BOOL:
		return "The turn record is damaged."
	if typeof(turn["dice"]) != TYPE_ARRAY:
		return "The dice are damaged."
	if (turn["dice"] as Array).size() != (2 if turn["rolled"] else 0):
		return "The dice do not match whether they were rolled."
	for die: Variant in turn["dice"]:
		if typeof(die) != TYPE_INT or die < 1 or die > 6:
			return "A die shows an impossible number."
	if typeof(turn["free_paths"]) != TYPE_INT or turn["free_paths"] < 0 or turn["free_paths"] > _MAX_FREE_PATHS:
		return "The free path count is not valid."
	if typeof(turn["pending"]) != TYPE_STRING or not [GtState.PENDING_NONE, GtState.PENDING_DISCARD, GtState.PENDING_BLOCKER].has(turn["pending"]):
		return "The pending step is unknown."
	if typeof(turn["source"]) != TYPE_STRING or not ["", "seven", "guard"].has(turn["source"]):
		return "The pending source is unknown."
	if typeof(turn["owed"]) != TYPE_DICTIONARY:
		return "The owed discards are damaged."
	if state["phase"] == GtState.PHASE_FOUNDING and (turn["rolled"] or turn["card_played"] or turn["free_paths"] != 0 or turn["pending"] != ""):
		return "The turn has begun during founding."
	var pending: String = turn["pending"]
	if pending == GtState.PENDING_DISCARD:
		if turn["source"] != "seven":
			return "Discards are only owed after a 7."
		if (turn["owed"] as Dictionary).is_empty():
			return "Discarding is pending but nobody owes anything."
		for id: Variant in turn["owed"]:
			if not ids.has(id) or typeof(turn["owed"][id]) != TYPE_INT or turn["owed"][id] < 1:
				return "An owed discard is not valid."
			if turn["owed"][id] > GtState.hand_count(state, id):
				return "A player owes more cards than they hold."
	else:
		if not (turn["owed"] as Dictionary).is_empty():
			return "Discards are owed but none is pending."
		if pending == GtState.PENDING_BLOCKER and turn["source"] == "":
			return "A blocker move is pending without a reason."
		if pending == GtState.PENDING_NONE and turn["source"] != "":
			return "A pending reason is left over."
	return ""


static func _check_offer(state: Dictionary, ids: Array[String]) -> String:
	var offer: Variant = state["offer"]
	if typeof(offer) != TYPE_DICTIONARY:
		return "The offer is damaged."
	if (offer as Dictionary).is_empty():
		return ""
	if state["phase"] != GtState.PHASE_PLAYING:
		return "There is an offer outside of play."
	if not _has_exactly(offer, _OFFER_KEYS):
		return "The offer is damaged."
	if offer["from"] != state["current_player"]:
		return "Only the player whose turn it is can have an offer open."
	if not _is_resource_map(offer["give"]) or not _is_resource_map(offer["want"]):
		return "The offer's cards are not valid."
	for list: String in ["to", "accepted", "declined"]:
		if not _all_strings(offer[list]):
			return "The offer's player lists are damaged."
		var seen: Array[String] = []
		for id: String in offer[list]:
			if not ids.has(id) or id == offer["from"] or seen.has(id):
				return "The offer's player lists are not valid."
			seen.append(id)
	var addressed: Array[String] = _string_list(offer["to"])
	if addressed.is_empty():
		for id: String in ids:
			if id != offer["from"]:
				addressed.append(id)
	for id: String in _string_list(offer["accepted"]) + _string_list(offer["declined"]):
		if not addressed.has(id):
			return "Someone answered an offer that was not for them."
	for id: String in offer["accepted"]:
		if (offer["declined"] as Array).has(id):
			return "Someone both accepted and declined."
	return ""


static func _check_end(state: Dictionary, ids: Array[String]) -> String:
	var winner: Variant = state["winner"]
	if typeof(winner) != TYPE_STRING:
		return "'winner' must be text."
	if state["phase"] != GtState.PHASE_FINISHED:
		return "" if winner == "" else "Nobody can have won before the game is finished."
	if not ids.has(winner):
		return "A finished game has a winner who is playing."
	if state["current_player"] != winner:
		return "The winner must be the player whose turn it was."
	if not (state["offer"] as Dictionary).is_empty() or state["turn"]["pending"] != "":
		return "A finished game has nothing left to do."
	if GtScore.points(state, winner, true) < int(state["settings"]["target_points"]):
		return "The winner has not reached the target."
	return ""


static func _invalid(message: String) -> Dictionary:
	return CoreResult.failure(GtErrors.INVALID_STATE, message)
