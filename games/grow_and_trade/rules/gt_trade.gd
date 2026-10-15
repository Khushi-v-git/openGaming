class_name GtTrade
extends RefCounted
## Trading: bank trades and the turn owner's offers to the other players (docs/grow-and-trade-rules.md,
## "Trading"). Static functions that work on a copy of the state and never touch their input.
##
## Offer flow: the owner posts an offer (after rolling), addressed players accept or decline, and the
## owner picks one accepter with choose_trade_partner. Hands change only at that last step.
##
## Actions handled: bank_trade {give, get}, offer_trade {give, want, to?}, accept_trade {},
## decline_trade {}, choose_trade_partner {player}, withdraw_offer {}. The dispatcher has already
## checked that the game is not finished and that the player exists and is present.

const ACTIONS: Array[String] = [
	"bank_trade", "offer_trade", "accept_trade", "decline_trade", "choose_trade_partner", "withdraw_offer",
]


static func apply(state: Dictionary, _board: GtBoard, player_id: String, action: Dictionary) -> Dictionary:
	var type: Variant = action.get("type")
	if typeof(type) != TYPE_STRING:
		return CoreResult.failure(ErrorCodes.BAD_ACTION, "An action needs a text type.")
	if not ACTIONS.has(type):
		return CoreResult.failure(ErrorCodes.UNKNOWN_ACTION, "Unknown action %s." % type)
	match type:
		"bank_trade":
			return _bank_trade(state, player_id, action)
		"offer_trade":
			return _offer_trade(state, player_id, action)
		"accept_trade":
			return _answer(state, player_id, action, true)
		"decline_trade":
			return _answer(state, player_id, action, false)
		"choose_trade_partner":
			return _choose(state, player_id, action)
		_:
			return _withdraw(state, player_id, action)


## Clears an open offer on a state the caller already copied, with an `offer_cancelled` event.
## Does nothing if no offer is open.
static func cancel_offer(state: Dictionary, reason: String, events: Array) -> void:
	if (state["offer"] as Dictionary).is_empty():
		return
	state["offer"] = {}
	events.append({"type": "offer_cancelled", "reason": reason})


# --- actions -------------------------------------------------------------------------------------------

static func _bank_trade(state: Dictionary, player_id: String, action: Dictionary) -> Dictionary:
	var shape: Dictionary = _shape(action, ["give", "get"], [])
	if not CoreResult.is_ok(shape):
		return shape
	if typeof(action["give"]) != TYPE_STRING or typeof(action["get"]) != TYPE_STRING:
		return _bad_action("A bank trade names the resource to give and the one to get.")
	var gate: Dictionary = _owner_gate(state, player_id)
	if not CoreResult.is_ok(gate):
		return gate
	var give: String = action["give"]
	var get_resource: String = action["get"]
	var rate: int = GtBank.bank_rate(GtState.ports(state, player_id), give, int(state["settings"]["bank_rate"]))
	var traded: Dictionary = GtBank.bank_trade(state["hands"][player_id], state["supply"], give, get_resource, rate)
	if not CoreResult.is_ok(traded):
		return traded
	var next: Dictionary = state.duplicate(true)
	next["hands"][player_id] = traded["hand"]
	next["supply"] = traded["supply"]
	var events: Array = [{"type": "bank_traded", "player_id": player_id, "give": give, "get": get_resource, "rate": rate}]
	return _done(next, events)


static func _offer_trade(state: Dictionary, player_id: String, action: Dictionary) -> Dictionary:
	var shape: Dictionary = _shape(action, ["give", "want"], ["to"])
	if not CoreResult.is_ok(shape):
		return shape
	var gate: Dictionary = _owner_gate(state, player_id)
	if not CoreResult.is_ok(gate):
		return gate
	var give: Dictionary = _clean_map(action["give"])
	var want: Dictionary = _clean_map(action["want"])
	if give.is_empty() or want.is_empty():
		return _offer_invalid("An offer names what you give and what you want, as positive whole numbers.")
	for resource: Variant in give:
		if want.has(resource):
			return _offer_invalid("An offer cannot give and ask for the same resource.")
	if not GtBank.can_afford(state["hands"][player_id], give):
		return _offer_invalid("You do not hold what you are offering.")
	var to: Array = []
	if action.has("to"):
		if typeof(action["to"]) != TYPE_ARRAY:
			return _bad_action("'to' must be a list of players.")
		var seats: Array[String] = GtState.seat_order(state)
		for entry: Variant in action["to"]:
			if typeof(entry) != TYPE_STRING:
				return _bad_action("'to' must be a list of player ids.")
			if entry == player_id or not seats.has(entry) or to.has(entry):
				return _offer_invalid("An offer goes to other players in the game, each named once.")
			to.append(entry)
	var next: Dictionary = state.duplicate(true)
	var events: Array = []
	cancel_offer(next, "replaced", events)
	next["offer"] = {"from": player_id, "give": give, "want": want, "to": to, "accepted": [], "declined": []}
	events.append({"type": "offer_made", "from": player_id, "give": give.duplicate(), "want": want.duplicate(), "to": to.duplicate()})
	return _done(next, events)


static func _answer(state: Dictionary, player_id: String, action: Dictionary, accept: bool) -> Dictionary:
	var shape: Dictionary = _shape(action, [], [])
	if not CoreResult.is_ok(shape):
		return shape
	var gate: Dictionary = _phase_gate(state)
	if not CoreResult.is_ok(gate):
		return gate
	var offer: Dictionary = state["offer"]
	if offer.is_empty():
		return CoreResult.failure(GtErrors.NO_OFFER, "There is no offer to answer.")
	if not _addressed(state, player_id):
		return CoreResult.failure(GtErrors.NOT_ADDRESSED, "That offer is not for you.")
	if (offer["accepted"] as Array).has(player_id) or (offer["declined"] as Array).has(player_id):
		return CoreResult.failure(GtErrors.ALREADY_ANSWERED, "You have already answered this offer.")
	if accept and not GtBank.can_afford(state["hands"][player_id], offer["want"]):
		return CoreResult.failure(GtErrors.CANNOT_AFFORD, "You do not hold what the offer asks for.")
	var next: Dictionary = state.duplicate(true)
	var events: Array = []
	if accept:
		next["offer"]["accepted"].append(player_id)
		events.append({"type": "offer_accepted", "player_id": player_id})
	else:
		next["offer"]["declined"].append(player_id)
		events.append({"type": "offer_declined", "player_id": player_id})
		if (next["offer"]["declined"] as Array).size() == _addressees(next).size():
			cancel_offer(next, "all_declined", events)
	return _done(next, events)


static func _choose(state: Dictionary, player_id: String, action: Dictionary) -> Dictionary:
	var shape: Dictionary = _shape(action, ["player"], [])
	if not CoreResult.is_ok(shape):
		return shape
	if typeof(action["player"]) != TYPE_STRING:
		return _bad_action("'player' must be a player id.")
	var gate: Dictionary = _owner_gate(state, player_id, false)
	if not CoreResult.is_ok(gate):
		return gate
	var offer: Dictionary = state["offer"]
	if offer.is_empty():
		return CoreResult.failure(GtErrors.NO_OFFER, "There is no offer open.")
	var partner: String = action["player"]
	if not (offer["accepted"] as Array).has(partner):
		return CoreResult.failure(GtErrors.NOT_AN_ACCEPTER, "That player has not accepted the offer.")
	if not GtBank.can_afford(state["hands"][player_id], offer["give"]):
		return CoreResult.failure(GtErrors.CANNOT_AFFORD, "You no longer hold what you offered.")
	if not GtBank.can_afford(state["hands"][partner], offer["want"]):
		return CoreResult.failure(GtErrors.CANNOT_AFFORD, "That player no longer holds what you asked for.")
	var next: Dictionary = state.duplicate(true)
	var give: Dictionary = offer["give"]
	var want: Dictionary = offer["want"]
	var owner_hand: Dictionary = GtBank.add(GtBank.pay(next["hands"][player_id], give)["hand"], want)
	var partner_hand: Dictionary = GtBank.add(GtBank.pay(next["hands"][partner], want)["hand"], give)
	next["hands"][player_id] = owner_hand
	next["hands"][partner] = partner_hand
	next["offer"] = {}
	var events: Array = [{"type": "trade_done", "from": player_id, "with": partner, "give": give.duplicate(), "want": want.duplicate()}]
	return _done(next, events)


static func _withdraw(state: Dictionary, player_id: String, action: Dictionary) -> Dictionary:
	var shape: Dictionary = _shape(action, [], [])
	if not CoreResult.is_ok(shape):
		return shape
	var gate: Dictionary = _owner_gate(state, player_id, false)
	if not CoreResult.is_ok(gate):
		return gate
	if (state["offer"] as Dictionary).is_empty():
		return CoreResult.failure(GtErrors.NO_OFFER, "There is no offer open.")
	var next: Dictionary = state.duplicate(true)
	var events: Array = []
	cancel_offer(next, "withdrawn", events)
	return _done(next, events)


# --- gates and helpers -----------------------------------------------------------------------------------

## Playing phase and no pending discard or blocker move.
static func _phase_gate(state: Dictionary) -> Dictionary:
	if state["phase"] != GtState.PHASE_PLAYING:
		return CoreResult.failure(GtErrors.WRONG_PHASE, "Trading starts once the founding rounds are over.")
	if state["turn"]["pending"] != GtState.PENDING_NONE:
		return CoreResult.failure(GtErrors.WRONG_PHASE, "Finish the discard or the blocker move first.")
	return CoreResult.success()


## Only the turn owner, after the roll. `needs_roll` is false for choosing a partner and withdrawing, which
## can only follow an offer (made after the roll) anyway.
static func _owner_gate(state: Dictionary, player_id: String, needs_roll: bool = true) -> Dictionary:
	var phase: Dictionary = _phase_gate(state)
	if not CoreResult.is_ok(phase):
		return phase
	if state["current_player"] != player_id:
		return CoreResult.failure(GtErrors.NOT_YOUR_TURN, "Only the player whose turn it is can do that.")
	if needs_roll and not state["turn"]["rolled"]:
		return CoreResult.failure(GtErrors.NOT_ROLLED, "Roll the dice before trading.")
	return CoreResult.success()


## The players an open offer is addressed to: its `to` list, or every seat but the owner.
static func _addressees(state: Dictionary) -> Array:
	var offer: Dictionary = state["offer"]
	if not (offer["to"] as Array).is_empty():
		return offer["to"]
	var out: Array = []
	for id: String in GtState.seat_order(state):
		if id != offer["from"]:
			out.append(id)
	return out


static func _addressed(state: Dictionary, player_id: String) -> bool:
	return _addressees(state).has(player_id)


## The action must hold exactly `required` fields (plus any of `optional`) besides its type.
static func _shape(action: Dictionary, required: Array, optional: Array) -> Dictionary:
	for key: Variant in action:
		if key != "type" and not required.has(key) and not optional.has(key):
			return _bad_action("Unexpected field '%s'." % str(key))
	for key: Variant in required:
		if not action.has(key):
			return _bad_action("Missing field '%s'." % str(key))
	return CoreResult.success()


## {resource: positive int} -> a clean copy with int values, or {} if it is not one. Whole floats
## (what JSON gives for numbers) count as ints.
static func _clean_map(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = {}
	for resource: Variant in raw:
		if typeof(resource) != TYPE_STRING or not GtBank.RESOURCES.has(resource):
			return {}
		var amount: Variant = raw[resource]
		if typeof(amount) == TYPE_FLOAT and is_equal_approx(amount, roundf(amount)):
			amount = int(amount)
		if typeof(amount) != TYPE_INT or amount < 1:
			return {}
		out[resource] = amount
	return out


static func _done(next: Dictionary, events: Array) -> Dictionary:
	return CoreResult.success({"state": next, "events": events})


static func _bad_action(message: String) -> Dictionary:
	return CoreResult.failure(ErrorCodes.BAD_ACTION, message)


static func _offer_invalid(message: String) -> Dictionary:
	return CoreResult.failure(GtErrors.OFFER_INVALID, message)
