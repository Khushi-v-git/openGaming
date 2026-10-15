class_name GtTurn
extends RefCounted
## The turn flow of Grow & Trade: roll and pay out, the 7 (discard, move the blocker), fortune cards,
## ending the turn, and `settle` for absent players. Pure functions over a state; every function works
## on a copy and never changes its input (see docs/grow-and-trade-design.md).
##
## Decisions where the docs were silent:
##  - `apply` takes an optional fifth argument `active_players` (empty = everybody); end_turn needs it
##    to skip absent seats.
##  - While a discard is pending, anything but `discard` is MUST_DISCARD (for the owner) or NOT_YOUR_TURN
##    (for others); while the blocker move is pending the owner's other actions are WRONG_PHASE.
##  - `turn.owed` loses a player's entry once they discard; when it is empty the blocker move is pending.
##  - Point cards (and unknown names) cannot be played: NO_SUCH_CARD. A card still in `fresh` is
##    CARD_NOT_AVAILABLE. A played card simply leaves the hand (only guards are counted, in guards_played).
##  - A victim must be named when some other player with cards has a building on the new tile; it is
##    BAD_VICTIM to name one otherwise. `friendly_blocker` forbids a tile whose neighbours all have 2 or
##    fewer public points, unless every other tile would be forbidden too.
##  - Winning is checked after buy_card, after a guard (the bonus may complete the target) and at end_turn.
##  - settle in founding: an absent placer is skipped (they get no pieces); when nobody later in the
##    founding order is present, the game moves on to the playing phase.

const ACTIONS: Array[String] = ["roll", "buy_card", "play_card", "move_blocker", "discard", "end_turn"]
const FREE_PATHS: int = 2
const FRIENDLY_POINTS: int = 2
const SEVEN: int = 7
const DIE_SIDES: int = 6


## One action of the turn flow. `active_players` (empty = everybody) decides who the turn passes to.
static func apply(state: Dictionary, board: GtBoard, player_id: String, action: Dictionary, active_players: Array = []) -> Dictionary:
	var type: Variant = action.get("type")
	if typeof(type) != TYPE_STRING:
		return CoreResult.failure(ErrorCodes.BAD_ACTION, "An action needs a text type.")
	if not ACTIONS.has(type):
		return CoreResult.failure(ErrorCodes.UNKNOWN_ACTION, "Unknown action %s." % type)
	var shape: Dictionary = _check_shape(type, action)
	if not CoreResult.is_ok(shape):
		return shape
	if state["phase"] == GtState.PHASE_FINISHED:
		return CoreResult.failure(GtErrors.GAME_OVER, "The game is over.")
	if state["phase"] != GtState.PHASE_PLAYING:
		return CoreResult.failure(GtErrors.WRONG_PHASE, "The game has not started yet: finish founding first.")
	var next: Dictionary = state.duplicate(true)
	var events: Array = []
	if type == "discard":
		return _discard(next, player_id, action, events)
	if player_id != next["current_player"]:
		return CoreResult.failure(GtErrors.NOT_YOUR_TURN, "It is not your turn.")
	var pending: String = next["turn"]["pending"]
	if pending == GtState.PENDING_DISCARD:
		return CoreResult.failure(GtErrors.MUST_DISCARD, "Everyone who owes a discard must discard first.")
	if pending == GtState.PENDING_BLOCKER and type != "move_blocker":
		return CoreResult.failure(GtErrors.WRONG_PHASE, "Move the blocker first.")
	match type:
		"roll":
			return _roll(next, board, player_id, events)
		"buy_card":
			return _buy_card(next, player_id, events)
		"play_card":
			return _play_card(next, player_id, action, events)
		"move_blocker":
			return _move_blocker(next, board, player_id, action, events)
	return _end_turn(next, player_id, active_players, events)


## Hands things on for players who are away: the turn, a pending discard, a founding placement, and
## (with cancel_offers_on_absence) an open offer. Returns {ok, state, events}; nothing to do is ok with
## no events. NO_ACTIVE_PLAYERS if `active_players` names no seat of this game.
static func settle(state: Dictionary, board: GtBoard, active_players: Array = []) -> Dictionary:
	var seats: Array[String] = GtState.seat_order(state)
	var named: Array[String] = []
	for value: Variant in active_players:
		if seats.has(str(value)):
			named.append(str(value))
	if not active_players.is_empty() and named.is_empty():
		return CoreResult.failure(GtErrors.NO_ACTIVE_PLAYERS, "None of the players in this game is present.")
	var next: Dictionary = state.duplicate(true)
	var events: Array = []
	if not named.is_empty() and next["phase"] == GtState.PHASE_FOUNDING:
		_settle_founding(next, seats, named, events)
	elif not named.is_empty() and next["phase"] == GtState.PHASE_PLAYING:
		if not named.has(next["current_player"]):
			_pass_turn(next, seats, named, true, events)
		else:
			_settle_discards(next, seats, named, events)
			_settle_offer(next, named, events)
	return CoreResult.success({"state": next, "events": events})


# --- shape ---------------------------------------------------------------------------------------------

static func _check_shape(type: String, action: Dictionary) -> Dictionary:
	var required: Array = []
	var optional: Array = []
	match type:
		"discard":
			required = ["resources"]
		"move_blocker":
			required = ["q", "r"]
			optional = ["victim"]
		"play_card":
			required = ["card"]
			if action.get("card") == GtDeck.HARVEST:
				required.append("resources")
			elif action.get("card") == GtDeck.SWEEP:
				required.append("resource")
	for key: Variant in action:
		if key != "type" and not required.has(key) and not optional.has(key):
			return _bad_action("An action %s has no field '%s'." % [type, str(key)])
	for key: String in required:
		if not action.has(key):
			return _bad_action("The action %s needs '%s'." % [type, key])
	match type:
		"discard":
			if _clean_map(action["resources"]) == null:
				return _bad_action("'resources' must map resource names to whole numbers.")
		"move_blocker":
			if _whole(action["q"]) == null or _whole(action["r"]) == null:
				return _bad_action("'q' and 'r' must be whole numbers.")
			if action.has("victim") and typeof(action["victim"]) != TYPE_STRING:
				return _bad_action("'victim' must be a player id.")
		"play_card":
			if typeof(action["card"]) != TYPE_STRING:
				return _bad_action("'card' must be text.")
			if action.has("resource") and not GtBank.RESOURCES.has(action["resource"]):
				return _bad_action("'resource' must be a resource name.")
			if action.has("resources") and not _two_resources(action["resources"]):
				return _bad_action("'resources' must list exactly two resource names.")
	return CoreResult.success()


static func _two_resources(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		return false
	for item: Variant in value:
		if typeof(item) != TYPE_STRING or not GtBank.RESOURCES.has(item):
			return false
	return true


static func _whole(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and value == floorf(value):
		return int(value)
	return null


## {resource: count} with whole, non-negative counts and text keys, or null.
static func _clean_map(value: Variant) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		return null
	var out: Dictionary = {}
	for key: Variant in value:
		var count: Variant = _whole(value[key])
		if typeof(key) != TYPE_STRING or count == null or count < 0:
			return null
		out[key] = count
	return out


static func _bad_action(message: String) -> Dictionary:
	return CoreResult.failure(ErrorCodes.BAD_ACTION, message)


# --- roll ----------------------------------------------------------------------------------------------

static func _roll(state: Dictionary, board: GtBoard, player_id: String, events: Array) -> Dictionary:
	if state["turn"]["rolled"]:
		return CoreResult.failure(GtErrors.ALREADY_ROLLED, "You have already rolled this turn.")
	var prng: Prng = Prng.restore(state["rng"]["seed"], state["rng"]["state"])
	if prng == null:
		return CoreResult.failure(GtErrors.INVALID_STATE, "The random generator state is not valid.")
	var dice: Array = [prng.range_int(1, DIE_SIDES), prng.range_int(1, DIE_SIDES)]
	var total: int = int(dice[0]) + int(dice[1])
	_save_prng(state, prng)
	state["turn"]["rolled"] = true
	state["turn"]["dice"] = dice
	events.append({"type": "rolled", "player_id": player_id, "dice": dice.duplicate(), "total": total})
	if total == SEVEN:
		_start_seven(state, events)
	else:
		_pay_roll(state, board, total, events)
	return _ok(state, events)


## Nobody collects. Players over the hand limit owe a discard; then the blocker moves.
static func _start_seven(state: Dictionary, events: Array) -> void:
	var owed: Dictionary = {}
	for id: String in GtState.seat_order(state):
		var count: int = GtBank.discard_count(GtState.hand_count(state, id), int(state["settings"]["hand_limit"]))
		if count > 0:
			owed[id] = count
	state["turn"]["owed"] = owed
	state["turn"]["source"] = "seven"
	if owed.is_empty():
		state["turn"]["pending"] = GtState.PENDING_BLOCKER
	else:
		state["turn"]["pending"] = GtState.PENDING_DISCARD
		events.append({"type": "discard_required", "owed": owed.duplicate()})


static func _pay_roll(state: Dictionary, board: GtBoard, total: int, events: Array) -> void:
	var owed: Dictionary = {}
	var paying: Array = []
	for tile: Variant in state["layout"]["tiles"]:
		if int(tile["token"]) != total or tile["type"] == GtBoard.DESERT:
			continue
		if int(tile["q"]) == int(state["blocker"]["q"]) and int(tile["r"]) == int(state["blocker"]["r"]):
			continue
		var paid: bool = false
		for corner: String in board.corners_of_hex(Vector2i(int(tile["q"]), int(tile["r"]))):
			if state["buildings"].has(corner):
				var building: Dictionary = state["buildings"][corner]
				if not owed.has(building["owner"]):
					owed[building["owner"]] = {}
				var amount: int = 2 if building["kind"] == "town" else 1
				owed[building["owner"]][tile["type"]] = int(owed[building["owner"]].get(tile["type"], 0)) + amount
				paid = true
		if paid:
			paying.append({"q": int(tile["q"]), "r": int(tile["r"]), "token": int(tile["token"])})
	if owed.is_empty():
		events.append({"type": "nothing_produced"})
		return
	var result: Dictionary = GtBank.payout(state["supply"], owed)
	state["supply"] = result["supply"]
	for id: Variant in result["gains"]:
		state["hands"][id] = GtBank.add(state["hands"][id], result["gains"][id])
	events.append({"type": "produced", "gains": result["gains"], "tiles": paying})
	for shortage: Variant in result["shortages"]:
		events.append(shortage)


# --- discard and the blocker -------------------------------------------------------------------------

static func _discard(state: Dictionary, player_id: String, action: Dictionary, events: Array) -> Dictionary:
	if state["turn"]["pending"] != GtState.PENDING_DISCARD:
		return CoreResult.failure(GtErrors.WRONG_PHASE, "Nobody has to discard right now.")
	if not state["turn"]["owed"].has(player_id):
		return CoreResult.failure(GtErrors.NOT_YOUR_TURN, "You do not owe a discard.")
	var chosen: Dictionary = _clean_map(action["resources"])
	var checked: Dictionary = GtBank.apply_discard(state["hands"][player_id], chosen, int(state["settings"]["hand_limit"]))
	if not CoreResult.is_ok(checked):
		return checked
	state["hands"][player_id] = checked["hand"]
	state["supply"] = GtBank.add(state["supply"], chosen)
	var count: int = int(state["turn"]["owed"][player_id])
	state["turn"]["owed"].erase(player_id)
	events.append({"type": "discarded", "player_id": player_id, "count": count})
	_after_discards(state)
	return _ok(state, events)


static func _after_discards(state: Dictionary) -> void:
	if state["turn"]["owed"].is_empty():
		state["turn"]["pending"] = GtState.PENDING_BLOCKER


static func _move_blocker(state: Dictionary, board: GtBoard, player_id: String, action: Dictionary, events: Array) -> Dictionary:
	if state["turn"]["pending"] != GtState.PENDING_BLOCKER:
		return CoreResult.failure(GtErrors.WRONG_PHASE, "There is no blocker to move right now.")
	var hex: Vector2i = Vector2i(int(_whole(action["q"])), int(_whole(action["r"])))
	if GtState.tile_at(state, hex.x, hex.y).is_empty():
		return CoreResult.failure(GtErrors.BAD_BLOCKER_MOVE, "That tile is not on the island.")
	if hex.x == int(state["blocker"]["q"]) and hex.y == int(state["blocker"]["r"]):
		return CoreResult.failure(GtErrors.BAD_BLOCKER_MOVE, "The blocker must move to a different tile.")
	if state["settings"]["friendly_blocker"] and _spares(state, board, player_id, hex) and _has_unspared_tile(state, board, player_id):
		return CoreResult.failure(GtErrors.BAD_BLOCKER_MOVE, "That tile only has players with 2 points or fewer.")
	var eligible: Array[String] = []
	for id: String in _neighbours(state, board, player_id, hex):
		if GtState.hand_count(state, id) > 0:
			eligible.append(id)
	var victim: String = str(action.get("victim", ""))
	if eligible.is_empty() and action.has("victim"):
		return CoreResult.failure(GtErrors.BAD_VICTIM, "Nobody on that tile has cards to steal.")
	if not eligible.is_empty() and not eligible.has(victim):
		return CoreResult.failure(GtErrors.BAD_VICTIM, "Name a player with a building on that tile and cards in hand.")
	state["blocker"] = {"q": hex.x, "r": hex.y}
	events.append({"type": "blocker_moved", "player_id": player_id, "q": hex.x, "r": hex.y})
	if not eligible.is_empty():
		var prng: Prng = Prng.restore(state["rng"]["seed"], state["rng"]["state"])
		if prng == null:
			return CoreResult.failure(GtErrors.INVALID_STATE, "The random generator state is not valid.")
		var card: String = _take_random(state, prng, victim)
		state["hands"][player_id] = GtBank.add(state["hands"][player_id], {card: 1})
		_save_prng(state, prng)
		events.append({"type": "stole", "player_id": player_id, "victim": victim})
	state["turn"]["pending"] = GtState.PENDING_NONE
	state["turn"]["source"] = ""
	return _ok(state, events)


## Players other than `owner` with a building on a corner of `hex`, in seat order.
static func _neighbours(state: Dictionary, board: GtBoard, owner: String, hex: Vector2i) -> Array[String]:
	var present: Dictionary = {}
	for corner: String in board.corners_of_hex(hex):
		if state["buildings"].has(corner):
			present[state["buildings"][corner]["owner"]] = true
	var out: Array[String] = []
	for id: String in GtState.seat_order(state):
		if id != owner and present.has(id):
			out.append(id)
	return out


## friendly_blocker: the tile has neighbours and every one has 2 public points or fewer.
static func _spares(state: Dictionary, board: GtBoard, owner: String, hex: Vector2i) -> bool:
	var neighbours: Array[String] = _neighbours(state, board, owner, hex)
	if neighbours.is_empty():
		return false
	for id: String in neighbours:
		if GtScore.points(state, id, false) > FRIENDLY_POINTS:
			return false
	return true


static func _has_unspared_tile(state: Dictionary, board: GtBoard, owner: String) -> bool:
	for tile: Variant in state["layout"]["tiles"]:
		var hex: Vector2i = Vector2i(int(tile["q"]), int(tile["r"]))
		var here: bool = hex.x == int(state["blocker"]["q"]) and hex.y == int(state["blocker"]["r"])
		if not here and not _spares(state, board, owner, hex):
			return true
	return false


## Removes one random card from a player's hand (draw: range_int over the hand in resource order).
static func _take_random(state: Dictionary, prng: Prng, player_id: String) -> String:
	var cards: Array[String] = []
	for resource: String in GtBank.RESOURCES:
		for i: int in int(state["hands"][player_id][resource]):
			cards.append(resource)
	var card: String = cards[prng.range_int(0, cards.size() - 1)]
	state["hands"][player_id][card] = int(state["hands"][player_id][card]) - 1
	return card


# --- fortune cards -------------------------------------------------------------------------------------

static func _buy_card(state: Dictionary, player_id: String, events: Array) -> Dictionary:
	if not state["turn"]["rolled"]:
		return CoreResult.failure(GtErrors.NOT_ROLLED, "Roll first.")
	if (state["deck"] as Array).is_empty():
		return CoreResult.failure(GtErrors.CARD_NOT_AVAILABLE, "There are no fortune cards left.")
	var cost: Dictionary = state["config"]["costs"]["card"]
	var paid: Dictionary = GtBank.pay(state["hands"][player_id], cost)
	if not CoreResult.is_ok(paid):
		return CoreResult.failure(GtErrors.CANNOT_AFFORD, "A fortune card costs fleece, wheat and stone.")
	var drawn: Dictionary = GtDeck.draw(state["deck"])
	state["hands"][player_id] = paid["hand"]
	state["supply"] = GtBank.add(state["supply"], cost)
	state["deck"] = drawn["deck"]
	state["cards"][player_id]["fresh"].append(drawn["card"])
	events.append({"type": "card_bought", "player_id": player_id})
	GtScore.finish_if_won(state, player_id, events)
	return _ok(state, events)


static func _play_card(state: Dictionary, player_id: String, action: Dictionary, events: Array) -> Dictionary:
	var card: String = action["card"]
	if not GtDeck.CARD_TYPES.has(card) or card == GtDeck.POINT:
		return CoreResult.failure(GtErrors.NO_SUCH_CARD, "That card cannot be played.")
	if state["turn"]["card_played"]:
		return CoreResult.failure(GtErrors.CARD_ALREADY_PLAYED, "You may play one card per turn.")
	var held: Array = state["cards"][player_id]["held"]
	if not held.has(card):
		return CoreResult.failure(GtErrors.CARD_NOT_AVAILABLE, "You have no %s card you can play now." % card)
	if card != GtDeck.GUARD and not state["turn"]["rolled"]:
		return CoreResult.failure(GtErrors.NOT_ROLLED, "Roll before playing that card.")
	var played: Dictionary = _card_effect(state, player_id, card, action, events)
	if not CoreResult.is_ok(played):
		return played
	held.erase(card)  # Array.erase removes the first match only
	state["turn"]["card_played"] = true
	events.insert(0, {"type": "card_played", "player_id": player_id, "card": card})
	return _ok(state, events)


## Applies one card's effect; fails (changing nothing that matters, the caller discards the copy) if illegal.
static func _card_effect(state: Dictionary, player_id: String, card: String, action: Dictionary, events: Array) -> Dictionary:
	match card:
		GtDeck.GUARD:
			state["guards_played"][player_id] = int(state["guards_played"][player_id]) + 1
			state["turn"]["pending"] = GtState.PENDING_BLOCKER
			state["turn"]["source"] = "guard"
			GtScore.refresh_bonuses(state, events)
			GtScore.finish_if_won(state, player_id, events)
		GtDeck.TWO_PATHS:
			state["turn"]["free_paths"] = FREE_PATHS
		GtDeck.HARVEST:
			var take: Dictionary = {}
			for resource: String in action["resources"]:
				take[resource] = int(take.get(resource, 0)) + 1
			var paid: Dictionary = GtBank.pay(state["supply"], take)
			if not CoreResult.is_ok(paid):
				return CoreResult.failure(GtErrors.CANNOT_AFFORD, "The bank does not have those resources.")
			state["supply"] = paid["hand"]
			state["hands"][player_id] = GtBank.add(state["hands"][player_id], take)
			events.append({"type": "harvest_taken", "player_id": player_id, "resources": take})
		GtDeck.SWEEP:
			var resource: String = action["resource"]
			var total: int = 0
			for id: String in GtState.seat_order(state):
				if id != player_id:
					total += int(state["hands"][id][resource])
					state["hands"][id][resource] = 0
			state["hands"][player_id][resource] = int(state["hands"][player_id][resource]) + total
			events.append({"type": "swept", "player_id": player_id, "resource": resource, "total": total})
	return CoreResult.success()


# --- ending the turn -------------------------------------------------------------------------------------

static func _end_turn(state: Dictionary, player_id: String, active_players: Array, events: Array) -> Dictionary:
	if not state["turn"]["rolled"]:
		return CoreResult.failure(GtErrors.NOT_ROLLED, "Roll before ending your turn.")
	GtScore.finish_if_won(state, player_id, events)
	if state["phase"] == GtState.PHASE_FINISHED:
		return _ok(state, events)
	var active: Array[String] = GtState.active_or_all(state, active_players)
	_pass_turn(state, GtState.seat_order(state), active, false, events)
	return _ok(state, events)


## Cancels the offer, makes fresh cards playable, resets the turn record and moves to the next present
## player. `skipped` says the owner was away (adds a turn_skipped event and drops everything pending).
static func _pass_turn(state: Dictionary, seats: Array[String], active: Array[String], skipped: bool, events: Array) -> void:
	var owner: String = state["current_player"]
	if not (state["offer"] as Dictionary).is_empty():
		events.append({"type": "offer_cancelled", "reason": "owner_away" if skipped else "turn_ended"})
		state["offer"] = {}
	var cards: Dictionary = state["cards"][owner]
	cards["held"].append_array(cards["fresh"])
	cards["fresh"] = []
	state["turn"] = GtSetup.new_turn()
	var following: String = TurnOrder.next_active(seats, owner, active)
	state["current_player"] = following
	state["turn_number"] = int(state["turn_number"]) + 1
	if skipped:
		events.append({"type": "turn_skipped", "player_id": owner})
	events.append({"type": "turn_changed", "player_id": following})


# --- settle ------------------------------------------------------------------------------------------------

## Absent players who owe a discard lose random cards (design doc, draw 4) so the game can go on.
static func _settle_discards(state: Dictionary, seats: Array[String], active: Array[String], events: Array) -> void:
	if state["turn"]["pending"] != GtState.PENDING_DISCARD:
		return
	var prng: Prng = Prng.restore(state["rng"]["seed"], state["rng"]["state"])
	if prng == null:
		return
	for id: String in seats:
		if active.has(id) or not state["turn"]["owed"].has(id):
			continue
		var count: int = int(state["turn"]["owed"][id])
		for i: int in count:
			var card: String = _take_random(state, prng, id)
			state["supply"][card] = int(state["supply"][card]) + 1
		state["turn"]["owed"].erase(id)
		events.append({"type": "discarded", "player_id": id, "count": count})
	_save_prng(state, prng)
	_after_discards(state)


static func _settle_offer(state: Dictionary, active: Array[String], events: Array) -> void:
	var offer: Dictionary = state["offer"]
	if offer.is_empty() or not state["settings"]["cancel_offers_on_absence"]:
		return
	var involved: Array = [offer["from"]]
	involved.append_array(offer["to"])
	involved.append_array(offer["accepted"])
	for id: Variant in involved:
		if not active.has(str(id)):
			state["offer"] = {}
			events.append({"type": "offer_cancelled", "reason": "player_away"})
			return


static func _settle_founding(state: Dictionary, seats: Array[String], active: Array[String], events: Array) -> void:
	var founding: Dictionary = state["founding"]
	var order: Array = founding["order"]
	var index: int = int(founding["index"])
	if active.has(str(order[index])):
		return
	var skipped: String = str(order[index])
	var next_index: int = index + 1
	while next_index < order.size() and not active.has(str(order[next_index])):
		next_index += 1
	events.append({"type": "turn_skipped", "player_id": skipped})
	if next_index >= order.size():
		state["phase"] = GtState.PHASE_PLAYING
		state["founding"] = {}
		state["turn"] = GtSetup.new_turn()
		state["current_player"] = TurnOrder.first_active(seats, active, 0)
	else:
		founding["index"] = next_index
		founding["expect"] = "village"
		founding["last_village"] = ""
		state["current_player"] = str(order[next_index])
	events.append({"type": "turn_changed", "player_id": state["current_player"]})


# --- shared --------------------------------------------------------------------------------------------------

static func _save_prng(state: Dictionary, prng: Prng) -> void:
	state["rng"]["state"] = prng.state_text()


static func _ok(state: Dictionary, events: Array) -> Dictionary:
	return CoreResult.success({"state": state, "events": events})
