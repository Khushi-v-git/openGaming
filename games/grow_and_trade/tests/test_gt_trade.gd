extends GutTest
## Bank trades and the turn owner's offers (GtTrade).

const PLAYERS: Array = ["a", "b", "c", "d"]


## A playing-phase state, a to move and past the roll, with every hand empty.
func _state(settings: Dictionary = {}) -> Dictionary:
	var r: Dictionary = GtSetup.new_game(PLAYERS, GtBoard.load_file()["board"], settings, 11)
	var state: Dictionary = r["state"]
	state["phase"] = "playing"
	state["founding"] = {}
	state["turn"]["rolled"] = true
	return state


func _board(state: Dictionary) -> GtBoard:
	return GtBoard.new(state["board"])


func _act(state: Dictionary, player: String, action: Dictionary) -> Dictionary:
	return GtTrade.apply(state, _board(state), player, action)


func _give(state: Dictionary, player: String, gain: Dictionary) -> void:
	state["hands"][player] = GtBank.add(state["hands"][player], gain)


func _total(state: Dictionary) -> int:
	var total: int = GtBank.hand_count(state["supply"])
	for id: String in PLAYERS:
		total += GtBank.hand_count(state["hands"][id])
	return total


func _fails(state: Dictionary, player: String, action: Dictionary, code: String) -> void:
	var before: Dictionary = state.duplicate(true)
	var r: Dictionary = _act(state, player, action)
	assert_false(CoreResult.is_ok(r), "%s should fail" % str(action))
	assert_eq(CoreResult.error_code(r), code, str(action))
	assert_eq(state, before, "a refused action leaves the state unchanged")


func _offer(state: Dictionary, give: Dictionary, want: Dictionary, to: Array = []) -> Dictionary:
	var action: Dictionary = {"type": "offer_trade", "give": give, "want": want}
	if not to.is_empty():
		action["to"] = to
	var r: Dictionary = _act(state, "a", action)
	assert_true(CoreResult.is_ok(r), "offer should succeed")
	return r["state"]


# --- bank trades ---------------------------------------------------------------------------------------

func test_bank_trade_at_the_default_rate() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"timber": 5})
	var r: Dictionary = _act(state, "a", {"type": "bank_trade", "give": "timber", "get": "stone"})
	assert_true(CoreResult.is_ok(r))
	assert_eq(r["state"]["hands"]["a"]["timber"], 1)
	assert_eq(r["state"]["hands"]["a"]["stone"], 1)
	assert_eq(r["state"]["supply"]["timber"], state["supply"]["timber"] + 4)
	assert_eq(r["state"]["supply"]["stone"], state["supply"]["stone"] - 1)
	assert_eq(r["events"], [{"type": "bank_traded", "player_id": "a", "give": "timber", "get": "stone", "rate": 4}])
	assert_eq(state["hands"]["a"]["timber"], 5, "the input is not changed")


func test_bank_rate_setting_three_and_harbors() -> void:
	var state: Dictionary = _state({"bank_rate": 3})
	_give(state, "a", {"clay": 3})
	assert_eq(_act(state, "a", {"type": "bank_trade", "give": "clay", "get": "wheat"})["events"][0]["rate"], 3)
	# a generic harbor with a building of a on one of its corners keeps 3; a clay harbor gives 2
	var harbors: Array = state["layout"]["harbors"]
	state["layout"]["harbors"][0]["kind"] = "clay"
	state["layout"]["harbors"][0]["ratio"] = 2
	state["buildings"][harbors[0]["corners"][0]] = {"owner": "a", "kind": "village"}
	var r: Dictionary = _act(state, "a", {"type": "bank_trade", "give": "clay", "get": "wheat"})
	assert_eq(r["events"][0]["rate"], 2)
	assert_eq(r["state"]["hands"]["a"]["clay"], 1)
	var other: Dictionary = _act(state, "a", {"type": "bank_trade", "give": "timber", "get": "wheat"})
	assert_eq(CoreResult.error_code(other), GtBank.CANNOT_AFFORD)


func test_generic_harbor_gives_three_for_one() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"stone": 3})
	state["layout"]["harbors"][0]["kind"] = "generic"
	state["buildings"][state["layout"]["harbors"][0]["corners"][1]] = {"owner": "a", "kind": "town"}
	var r: Dictionary = _act(state, "a", {"type": "bank_trade", "give": "stone", "get": "clay"})
	assert_true(CoreResult.is_ok(r))
	assert_eq(r["events"][0]["rate"], 3)


func test_bank_trade_refusals() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"timber": 3})
	_fails(state, "a", {"type": "bank_trade", "give": "timber", "get": "stone"}, GtBank.CANNOT_AFFORD)
	_give(state, "a", {"timber": 1})
	_fails(state, "a", {"type": "bank_trade", "give": "timber", "get": "timber"}, GtBank.SAME_RESOURCE)
	_fails(state, "a", {"type": "bank_trade", "give": "gold", "get": "stone"}, GtBank.UNKNOWN_RESOURCE)
	_fails(state, "b", {"type": "bank_trade", "give": "timber", "get": "stone"}, GtErrors.NOT_YOUR_TURN)
	_fails(state, "a", {"type": "bank_trade", "give": "timber"}, ErrorCodes.BAD_ACTION)
	_fails(state, "a", {"type": "bank_trade", "give": 1, "get": "stone"}, ErrorCodes.BAD_ACTION)
	_fails(state, "a", {"type": "bank_trade", "give": "timber", "get": "stone", "extra": 1}, ErrorCodes.BAD_ACTION)
	state["supply"]["stone"] = 0
	_fails(state, "a", {"type": "bank_trade", "give": "timber", "get": "stone"}, GtBank.BANK_EMPTY)


func test_trading_needs_the_roll_the_playing_phase_and_no_pending_step() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"timber": 4})
	var action: Dictionary = {"type": "bank_trade", "give": "timber", "get": "stone"}
	state["turn"]["rolled"] = false
	_fails(state, "a", action, GtErrors.NOT_ROLLED)
	_fails(state, "a", {"type": "offer_trade", "give": {"timber": 1}, "want": {"clay": 1}}, GtErrors.NOT_ROLLED)
	state["turn"]["rolled"] = true
	state["turn"]["pending"] = "move_blocker"
	_fails(state, "a", action, GtErrors.WRONG_PHASE)
	state["turn"]["pending"] = ""
	state["phase"] = "founding"
	_fails(state, "a", action, GtErrors.WRONG_PHASE)


func test_unknown_and_foreign_types() -> void:
	var state: Dictionary = _state()
	_fails(state, "a", {"type": "roll"}, ErrorCodes.UNKNOWN_ACTION)
	_fails(state, "a", {}, ErrorCodes.BAD_ACTION)


# --- offers --------------------------------------------------------------------------------------------

func test_an_offer_is_stored_and_does_not_move_cards() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"timber": 2})
	var r: Dictionary = _act(state, "a", {"type": "offer_trade", "give": {"timber": 2}, "want": {"clay": 1}})
	assert_true(CoreResult.is_ok(r))
	assert_eq(r["state"]["offer"], {"from": "a", "give": {"timber": 2}, "want": {"clay": 1}, "to": [], "accepted": [], "declined": []})
	assert_eq(r["events"][0]["type"], "offer_made")
	assert_eq(r["state"]["hands"], state["hands"])


func test_offer_refusals() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"timber": 2})
	var ok_give: Dictionary = {"timber": 1}
	var ok_want: Dictionary = {"clay": 1}
	_fails(state, "b", {"type": "offer_trade", "give": ok_give, "want": ok_want}, GtErrors.NOT_YOUR_TURN)
	_fails(state, "a", {"type": "offer_trade", "give": {"timber": 3}, "want": ok_want}, GtErrors.OFFER_INVALID)
	_fails(state, "a", {"type": "offer_trade", "give": {}, "want": ok_want}, GtErrors.OFFER_INVALID)
	_fails(state, "a", {"type": "offer_trade", "give": ok_give, "want": {}}, GtErrors.OFFER_INVALID)
	_fails(state, "a", {"type": "offer_trade", "give": {"timber": 0}, "want": ok_want}, GtErrors.OFFER_INVALID)
	_fails(state, "a", {"type": "offer_trade", "give": {"timber": -1}, "want": ok_want}, GtErrors.OFFER_INVALID)
	_fails(state, "a", {"type": "offer_trade", "give": {"gold": 1}, "want": ok_want}, GtErrors.OFFER_INVALID)
	_fails(state, "a", {"type": "offer_trade", "give": {"timber": 1}, "want": {"timber": 1}}, GtErrors.OFFER_INVALID)
	_fails(state, "a", {"type": "offer_trade", "give": ok_give, "want": ok_want, "to": ["a"]}, GtErrors.OFFER_INVALID)
	_fails(state, "a", {"type": "offer_trade", "give": ok_give, "want": ok_want, "to": ["zed"]}, GtErrors.OFFER_INVALID)
	_fails(state, "a", {"type": "offer_trade", "give": ok_give, "want": ok_want, "to": ["b", "b"]}, GtErrors.OFFER_INVALID)
	_fails(state, "a", {"type": "offer_trade", "give": ok_give, "want": ok_want, "to": "b"}, ErrorCodes.BAD_ACTION)
	_fails(state, "a", {"type": "offer_trade", "give": ok_give}, ErrorCodes.BAD_ACTION)
	_fails(state, "a", {"type": "offer_trade", "give": "timber", "want": ok_want}, GtErrors.OFFER_INVALID)


func test_an_empty_to_list_means_everyone() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"timber": 1})
	var r: Dictionary = _act(state, "a", {"type": "offer_trade", "give": {"timber": 1}, "want": {"clay": 1}, "to": []})
	assert_true(CoreResult.is_ok(r))
	assert_eq(r["state"]["offer"]["to"], [])


func test_whole_floats_from_json_count_as_ints() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"timber": 2})
	var r: Dictionary = _act(state, "a", {"type": "offer_trade", "give": {"timber": 2.0}, "want": {"clay": 1.0}})
	assert_true(CoreResult.is_ok(r))
	assert_eq(typeof(r["state"]["offer"]["give"]["timber"]), TYPE_INT)
	_fails(state, "a", {"type": "offer_trade", "give": {"timber": 1.5}, "want": {"clay": 1}}, GtErrors.OFFER_INVALID)


func test_a_new_offer_replaces_the_open_one() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"timber": 2, "wheat": 1})
	state = _offer(state, {"timber": 1}, {"clay": 1})
	var r: Dictionary = _act(state, "a", {"type": "offer_trade", "give": {"wheat": 1}, "want": {"stone": 1}, "to": ["c"]})
	assert_true(CoreResult.is_ok(r))
	assert_eq(r["state"]["offer"]["give"], {"wheat": 1})
	assert_eq(r["state"]["offer"]["to"], ["c"])
	assert_eq(r["events"][0], {"type": "offer_cancelled", "reason": "replaced"})
	assert_eq(r["events"][1]["type"], "offer_made")


func test_accept_then_the_owner_chooses_among_several() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"timber": 2})
	_give(state, "b", {"clay": 1})
	_give(state, "c", {"clay": 2})
	state = _offer(state, {"timber": 2}, {"clay": 1})
	var rb: Dictionary = _act(state, "b", {"type": "accept_trade"})
	assert_true(CoreResult.is_ok(rb))
	assert_eq(rb["events"], [{"type": "offer_accepted", "player_id": "b"}])
	var rc: Dictionary = _act(rb["state"], "c", {"type": "accept_trade"})
	assert_eq(rc["state"]["offer"]["accepted"], ["b", "c"])
	assert_eq(rc["state"]["hands"]["a"]["timber"], 2, "nothing moves before the owner chooses")
	var chosen: Dictionary = _act(rc["state"], "a", {"type": "choose_trade_partner", "player": "c"})
	assert_true(CoreResult.is_ok(chosen))
	assert_eq(chosen["events"], [{"type": "trade_done", "from": "a", "with": "c", "give": {"timber": 2}, "want": {"clay": 1}}])
	var after: Dictionary = chosen["state"]
	assert_eq(after["hands"]["a"], GtBank.add(GtBank.empty_hand(), {"clay": 1}))
	assert_eq(after["hands"]["c"], GtBank.add(GtBank.empty_hand(), {"timber": 2, "clay": 1}))
	assert_eq(after["hands"]["b"]["clay"], 1)
	assert_true(after["offer"].is_empty())
	assert_eq(_total(after), _total(state))


func test_answer_refusals() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"timber": 1})
	_give(state, "b", {"clay": 1})
	_fails(state, "b", {"type": "accept_trade"}, GtErrors.NO_OFFER)
	_fails(state, "b", {"type": "decline_trade"}, GtErrors.NO_OFFER)
	state = _offer(state, {"timber": 1}, {"clay": 1}, ["b", "c"])
	_fails(state, "a", {"type": "accept_trade"}, GtErrors.NOT_ADDRESSED)
	_fails(state, "d", {"type": "accept_trade"}, GtErrors.NOT_ADDRESSED)
	_fails(state, "c", {"type": "accept_trade"}, GtErrors.CANNOT_AFFORD)
	_fails(state, "b", {"type": "accept_trade", "extra": 1}, ErrorCodes.BAD_ACTION)
	var accepted: Dictionary = _act(state, "b", {"type": "accept_trade"})["state"]
	_fails(accepted, "b", {"type": "accept_trade"}, GtErrors.ALREADY_ANSWERED)
	_fails(accepted, "b", {"type": "decline_trade"}, GtErrors.ALREADY_ANSWERED)
	var declined: Dictionary = _act(state, "c", {"type": "decline_trade"})["state"]
	_fails(declined, "c", {"type": "accept_trade"}, GtErrors.ALREADY_ANSWERED)
	declined["turn"]["pending"] = "discard"
	_fails(declined, "b", {"type": "accept_trade"}, GtErrors.WRONG_PHASE)


func test_a_decline_is_recorded_and_everyone_declining_cancels() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"timber": 1})
	state = _offer(state, {"timber": 1}, {"clay": 1})
	var r: Dictionary = _act(state, "b", {"type": "decline_trade"})
	assert_eq(r["events"], [{"type": "offer_declined", "player_id": "b"}])
	assert_eq(r["state"]["offer"]["declined"], ["b"])
	r = _act(r["state"], "c", {"type": "decline_trade"})
	assert_false(r["state"]["offer"].is_empty())
	r = _act(r["state"], "d", {"type": "decline_trade"})
	assert_true(r["state"]["offer"].is_empty())
	assert_eq(r["events"], [{"type": "offer_declined", "player_id": "d"}, {"type": "offer_cancelled", "reason": "all_declined"}])


func test_an_offer_to_one_player_cancels_when_that_player_declines() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"timber": 1})
	state = _offer(state, {"timber": 1}, {"clay": 1}, ["c"])
	_fails(state, "b", {"type": "decline_trade"}, GtErrors.NOT_ADDRESSED)
	var r: Dictionary = _act(state, "c", {"type": "decline_trade"})
	assert_true(r["state"]["offer"].is_empty())


func test_choose_refusals() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"timber": 1})
	_give(state, "b", {"clay": 1})
	_fails(state, "a", {"type": "choose_trade_partner", "player": "b"}, GtErrors.NO_OFFER)
	state = _offer(state, {"timber": 1}, {"clay": 1})
	_fails(state, "a", {"type": "choose_trade_partner", "player": "b"}, GtErrors.NOT_AN_ACCEPTER)
	var accepted: Dictionary = _act(state, "b", {"type": "accept_trade"})["state"]
	_fails(accepted, "b", {"type": "choose_trade_partner", "player": "b"}, GtErrors.NOT_YOUR_TURN)
	_fails(accepted, "a", {"type": "choose_trade_partner", "player": "c"}, GtErrors.NOT_AN_ACCEPTER)
	_fails(accepted, "a", {"type": "choose_trade_partner"}, ErrorCodes.BAD_ACTION)
	_fails(accepted, "a", {"type": "choose_trade_partner", "player": 3}, ErrorCodes.BAD_ACTION)


func test_hands_that_changed_after_accepting_block_the_swap_and_keep_the_offer() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"timber": 1})
	_give(state, "b", {"clay": 1})
	state = _offer(state, {"timber": 1}, {"clay": 1})
	var accepted: Dictionary = _act(state, "b", {"type": "accept_trade"})["state"]
	var partner_spent: Dictionary = accepted.duplicate(true)
	partner_spent["hands"]["b"]["clay"] = 0
	_fails(partner_spent, "a", {"type": "choose_trade_partner", "player": "b"}, GtErrors.CANNOT_AFFORD)
	assert_false(partner_spent["offer"].is_empty())
	var owner_spent: Dictionary = accepted.duplicate(true)
	owner_spent["hands"]["a"]["timber"] = 0
	_fails(owner_spent, "a", {"type": "choose_trade_partner", "player": "b"}, GtErrors.CANNOT_AFFORD)


func test_withdraw() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"timber": 1})
	_fails(state, "a", {"type": "withdraw_offer"}, GtErrors.NO_OFFER)
	state = _offer(state, {"timber": 1}, {"clay": 1})
	_fails(state, "b", {"type": "withdraw_offer"}, GtErrors.NOT_YOUR_TURN)
	var r: Dictionary = _act(state, "a", {"type": "withdraw_offer"})
	assert_true(CoreResult.is_ok(r))
	assert_true(r["state"]["offer"].is_empty())
	assert_eq(r["events"], [{"type": "offer_cancelled", "reason": "withdrawn"}])


func test_cancel_offer_helper() -> void:
	var state: Dictionary = _state()
	var events: Array = []
	GtTrade.cancel_offer(state, "turn_ended", events)
	assert_eq(events, [], "no offer open: nothing happens")
	_give(state, "a", {"timber": 1})
	var open: Dictionary = _offer(state, {"timber": 1}, {"clay": 1})
	GtTrade.cancel_offer(open, "turn_ended", events)
	assert_true(open["offer"].is_empty())
	assert_eq(events, [{"type": "offer_cancelled", "reason": "turn_ended"}])


func test_the_bank_trade_works_while_an_offer_is_open_and_the_offer_stays() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"timber": 5})
	state = _offer(state, {"timber": 1}, {"clay": 1})
	var r: Dictionary = _act(state, "a", {"type": "bank_trade", "give": "timber", "get": "stone"})
	assert_true(CoreResult.is_ok(r))
	assert_false(r["state"]["offer"].is_empty())


func test_results_are_json_safe() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"timber": 2})
	_give(state, "b", {"clay": 1})
	state = _offer(state, {"timber": 2}, {"clay": 1}, ["b", "c"])
	var r: Dictionary = _act(state, "b", {"type": "accept_trade"})
	var text: String = JSON.stringify({"state": r["state"], "events": r["events"]})
	var back: Variant = JSON.parse_string(text)
	assert_eq(back["state"]["offer"]["accepted"], ["b"])
	assert_eq(back["events"][0]["type"], "offer_accepted")


# --- conservation ----------------------------------------------------------------------------------------

func test_random_trade_sequences_never_create_or_destroy_resources() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var kinds: Array[String] = ["timber", "clay", "fleece", "wheat", "stone"]
	for seed_value: int in 60:
		rng.seed = seed_value + 1
		var state: Dictionary = _state({"bank_rate": 3 if seed_value % 2 == 0 else 4})
		var prng: Prng = Prng.new(seed_value)
		for id: String in PLAYERS:
			var gain: Dictionary = {}
			for kind: String in kinds:
				gain[kind] = prng.range_int(0, 4)
			_give(state, id, gain)
			state["supply"] = _minus(state["supply"], gain)
		var expected: int = _total(state)
		for step: int in 40:
			var actor: String = PLAYERS[rng.randi_range(0, 3)]
			var action: Dictionary = _random_action(rng, kinds)
			var r: Dictionary = _act(state, actor, action)
			if CoreResult.is_ok(r):
				state = r["state"]
			assert_eq(_total(state), expected, "seed %d step %d" % [seed_value, step])
			for id: String in PLAYERS:
				for kind: String in kinds:
					assert_true(int(state["hands"][id][kind]) >= 0)
			for kind: String in kinds:
				assert_true(int(state["supply"][kind]) >= 0)


func _minus(supply: Dictionary, gain: Dictionary) -> Dictionary:
	var out: Dictionary = supply.duplicate()
	for kind: Variant in gain:
		out[kind] = maxi(0, int(out[kind]) - int(gain[kind]))
	return out


func _random_action(rng: RandomNumberGenerator, kinds: Array[String]) -> Dictionary:
	match rng.randi_range(0, 5):
		0:
			return {"type": "bank_trade", "give": kinds[rng.randi_range(0, 4)], "get": kinds[rng.randi_range(0, 4)]}
		1, 2:
			return {"type": "offer_trade", "give": {kinds[rng.randi_range(0, 4)]: rng.randi_range(1, 3)}, "want": {kinds[rng.randi_range(0, 4)]: rng.randi_range(1, 3)}}
		3:
			return {"type": "accept_trade"}
		4:
			return {"type": "choose_trade_partner", "player": PLAYERS[rng.randi_range(0, 3)]}
		_:
			return {"type": "decline_trade"} if rng.randi_range(0, 1) == 0 else {"type": "withdraw_offer"}
