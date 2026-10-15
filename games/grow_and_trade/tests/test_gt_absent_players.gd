extends GutTest
## Players who are away (active_players) and settle(): turn rotation skips them, absent players cannot act,
## discards they owe are made for them, placements and offers do not wait for them forever.

var rules: GrowAndTradeRules


func before_each() -> void:
	rules = GrowAndTradeRules.new()


## Four players, p1's turn, rolled, nothing in anybody's hand.
func _turn(settings: Dictionary = {}) -> Dictionary:
	return GtRig.rolled(GtRig.playing(4, settings, 5))


func _end(state: Dictionary, active: Array = []) -> Dictionary:
	var result: Dictionary = rules.apply(state, state["current_player"], {"type": "end_turn"}, active)
	assert_true(CoreResult.is_ok(result), str(result))
	return result


func _settle(state: Dictionary, active: Array) -> Dictionary:
	var result: Dictionary = rules.settle(state, active)
	assert_true(CoreResult.is_ok(result), str(result))
	return result


func _totals(state: Dictionary) -> Dictionary:
	var totals: Dictionary = {}
	for resource: String in GtBank.RESOURCES:
		var sum: int = int(state["supply"][resource])
		for id: String in GtState.seat_order(state):
			sum += int(state["hands"][id][resource])
		totals[resource] = sum
	return totals


func _types(events: Array) -> Array:
	var types: Array = []
	for event: Dictionary in events:
		types.append(event["type"])
	return types


# --- apply: who may act, who gets the turn ----------------------------------------------------------------

func test_a_player_who_is_away_cannot_act() -> void:
	var state: Dictionary = GtRig.playing(4, {}, 5)
	var result: Dictionary = rules.apply(state, "p1", {"type": "roll"}, ["p2", "p3", "p4"])
	assert_eq(CoreResult.error_code(result), GtErrors.PLAYER_INACTIVE)
	assert_true(CoreResult.is_ok(rules.apply(state, "p1", {"type": "roll"}, ["p1", "p2"])))


func test_an_empty_active_list_means_everybody() -> void:
	assert_true(CoreResult.is_ok(rules.apply(GtRig.playing(4, {}, 5), "p1", {"type": "roll"}, [])))


func test_a_player_who_is_away_cannot_answer_an_offer_or_discard() -> void:
	var state: Dictionary = _turn()
	GtRig.give(state, "p1", {"timber": 1})
	GtRig.give(state, "p2", {"clay": 1})
	var offered: Dictionary = rules.apply(state, "p1", {"type": "offer_trade", "give": {"timber": 1}, "want": {"clay": 1}})["state"]
	assert_eq(CoreResult.error_code(rules.apply(offered, "p2", {"type": "accept_trade"}, ["p1", "p3", "p4"])), GtErrors.PLAYER_INACTIVE)
	assert_true(CoreResult.is_ok(rules.apply(offered, "p2", {"type": "accept_trade"}, ["p1", "p2"])))
	GtRig.give(state, "p2", {"timber": 3, "stone": 4})
	state["turn"]["pending"] = "discard"
	state["turn"]["source"] = "seven"
	state["turn"]["owed"] = {"p2": 4}
	assert_eq(CoreResult.error_code(rules.apply(state, "p2", {"type": "discard", "resources": {"timber": 3, "stone": 1}}, ["p1", "p3"])), GtErrors.PLAYER_INACTIVE)


func test_the_turn_skips_players_who_are_away() -> void:
	var result: Dictionary = _end(_turn(), ["p1", "p3", "p4"])
	assert_eq(result["state"]["current_player"], "p3", "p2 is away")
	assert_eq(result["events"].back(), {"type": "turn_changed", "player_id": "p3"})
	assert_eq(result["state"]["turn_number"], 2)


func test_several_absent_players_in_a_row_are_all_skipped() -> void:
	assert_eq(_end(_turn(), ["p1", "p4"])["state"]["current_player"], "p4")


func test_the_turn_wraps_past_absent_players_back_to_the_start() -> void:
	var state: Dictionary = _turn()
	state["current_player"] = "p4"
	assert_eq(_end(state, ["p1", "p2", "p4"])["state"]["current_player"], "p1")
	var wrap: Dictionary = _turn()
	wrap["current_player"] = "p3"
	assert_eq(_end(wrap, ["p2", "p3"])["state"]["current_player"], "p2", "p4 and p1 are away")


func test_one_present_player_keeps_getting_the_turn() -> void:
	var result: Dictionary = _end(_turn(), ["p1"])
	assert_eq(result["state"]["current_player"], "p1")
	assert_false(result["state"]["turn"]["rolled"], "but it is a fresh turn")


func test_unknown_ids_in_the_active_list_are_ignored_and_order_does_not_matter() -> void:
	assert_eq(_end(_turn(), ["p1", "ghost", "p3"])["state"]["current_player"], "p3")
	assert_eq(_end(_turn(), ["p4", "p3", "p1"])["state"]["current_player"], "p3", "seat order decides, not list order")


func test_a_returning_player_gets_their_turn_in_their_own_seat() -> void:
	var state: Dictionary = _end(_turn(), ["p1", "p3", "p4"])["state"]  # p2 skipped
	assert_eq(state["current_player"], "p3")
	state = GtRig.rolled(state)
	state = _end(state)["state"]  # p2 is back
	assert_eq(state["current_player"], "p4")
	state = _end(GtRig.rolled(state))["state"]
	assert_eq(state["current_player"], "p1")
	state = _end(GtRig.rolled(state))["state"]
	assert_eq(state["current_player"], "p2", "p2 plays in their own seat again")


func test_ending_a_turn_with_an_open_offer_cancels_it_even_when_others_are_away() -> void:
	var state: Dictionary = _turn()
	GtRig.give(state, "p1", {"timber": 1})
	state = rules.apply(state, "p1", {"type": "offer_trade", "give": {"timber": 1}, "want": {"clay": 1}})["state"]
	var result: Dictionary = _end(state, ["p1", "p3"])
	assert_eq(result["state"]["offer"], {})
	assert_true(_types(result["events"]).has("offer_cancelled"))


# --- settle: the turn owner is away -----------------------------------------------------------------------------

func test_settle_hands_the_turn_on_when_the_owner_is_away() -> void:
	var state: Dictionary = _turn()
	state["turn"]["free_paths"] = 1
	state["turn"]["card_played"] = true
	state["cards"]["p1"]["fresh"] = ["point"]
	state["deck"].remove_at(state["deck"].find("point"))  # the card p1 bought came from the deck
	var result: Dictionary = _settle(state, ["p2", "p3", "p4"])
	var next: Dictionary = result["state"]
	assert_eq(next["current_player"], "p2")
	assert_eq(_types(result["events"]), ["turn_skipped", "turn_changed"])
	assert_eq(result["events"][0]["player_id"], "p1")
	assert_eq(next["turn"], GtSetup.new_turn(), "the next player starts a clean turn")
	assert_eq(next["cards"]["p1"]["held"], ["point"], "what p1 bought this turn is playable from now on")
	assert_eq(next["cards"]["p1"]["fresh"], [])
	assert_eq(next["turn_number"], state["turn_number"] + 1)
	assert_true(CoreResult.is_ok(rules.validate_state(next)), str(rules.validate_state(next)))


func test_settle_drops_a_pending_blocker_move_and_an_open_offer_with_the_turn() -> void:
	var state: Dictionary = _turn()
	GtRig.give(state, "p1", {"timber": 1})
	state = rules.apply(state, "p1", {"type": "offer_trade", "give": {"timber": 1}, "want": {"clay": 1}})["state"]
	state["turn"]["pending"] = "move_blocker"
	state["turn"]["source"] = "seven"
	var result: Dictionary = _settle(state, ["p3", "p4"])
	assert_eq(result["state"]["current_player"], "p3")
	assert_eq(result["state"]["turn"]["pending"], "")
	assert_eq(result["state"]["offer"], {})
	assert_true(_types(result["events"]).has("offer_cancelled"))


func test_settle_skips_over_several_absent_seats_and_wraps() -> void:
	assert_eq(_settle(_turn(), ["p4"])["state"]["current_player"], "p4")
	var state: Dictionary = _turn()
	state["current_player"] = "p3"
	assert_eq(_settle(state, ["p2", "p1"])["state"]["current_player"], "p1", "p3 is away, p4 is away, so on to p1")


func test_settle_does_nothing_when_the_owner_is_present() -> void:
	var state: Dictionary = _turn()
	var result: Dictionary = _settle(state, ["p1", "p3"])
	assert_eq(result["state"], state)
	assert_eq(result["events"], [])


func test_settle_with_an_empty_list_means_everybody_and_changes_nothing() -> void:
	var state: Dictionary = _turn()
	var result: Dictionary = _settle(state, [])
	assert_eq(result["state"], state)
	assert_eq(result["events"], [])


func test_settle_does_nothing_after_the_game_is_over() -> void:
	var state: Dictionary = _turn()
	state["phase"] = "finished"
	state["winner"] = "p1"
	var result: Dictionary = _settle(state, ["p3"])
	assert_eq(result["state"], state)
	assert_eq(result["events"], [])


func test_settle_fails_if_nobody_from_this_game_is_present() -> void:
	var result: Dictionary = rules.settle(_turn(), ["ghost", "nobody"])
	assert_eq(CoreResult.error_code(result), GtErrors.NO_ACTIVE_PLAYERS)
	assert_false(str(result["error"]["message"]).is_empty())


func test_settle_does_not_change_its_input() -> void:
	var state: Dictionary = _turn()
	var before: Dictionary = state.duplicate(true)
	rules.settle(state, ["p3", "p4"])
	assert_eq(state, before)


func test_after_settle_the_absent_player_returns_and_rotation_includes_them_again() -> void:
	var state: Dictionary = _settle(_turn(), ["p2", "p3", "p4"])["state"]  # p1 away: p2's turn
	state = _end(GtRig.rolled(state))["state"]
	assert_eq(state["current_player"], "p3")
	state = _end(GtRig.rolled(state))["state"]
	state = _end(GtRig.rolled(state))["state"]
	assert_eq(state["current_player"], "p1", "p1 is back in their seat")


# --- settle: discards owed by people who are away --------------------------------------------------------------------

func _discarding() -> Dictionary:
	var state: Dictionary = _turn()
	GtRig.give(state, "p2", {"timber": 4, "stone": 4})
	GtRig.give(state, "p3", {"clay": 5, "wheat": 4})
	state["turn"]["pending"] = "discard"
	state["turn"]["source"] = "seven"
	state["turn"]["owed"] = {"p2": 4, "p3": 4}
	return state


func test_settle_discards_for_an_absent_player_and_keeps_waiting_for_a_present_one() -> void:
	var state: Dictionary = _discarding()
	var result: Dictionary = _settle(state, ["p1", "p3", "p4"])
	var next: Dictionary = result["state"]
	assert_eq(GtBank.hand_count(next["hands"]["p2"]), 4, "half of 8 was discarded")
	assert_eq(next["turn"]["owed"], {"p3": 4}, "the present player still has to choose")
	assert_eq(next["turn"]["pending"], "discard")
	assert_eq(next["hands"]["p3"], state["hands"]["p3"])
	assert_eq(result["events"], [{"type": "discarded", "player_id": "p2", "count": 4}])
	assert_eq(_totals(next), _totals(state), "the cards went back to the bank")
	assert_true(CoreResult.is_ok(rules.validate_state(next)), str(rules.validate_state(next)))


func test_when_only_absent_players_owe_the_blocker_move_comes_next() -> void:
	var state: Dictionary = _discarding()
	state["turn"]["owed"] = {"p2": 4}
	var next: Dictionary = _settle(state, ["p1", "p3", "p4"])["state"]
	assert_eq(next["turn"]["owed"], {})
	assert_eq(next["turn"]["pending"], "move_blocker")
	assert_eq(next["turn"]["source"], "seven")


func test_a_present_player_can_finish_the_discards_after_settle() -> void:
	var settled: Dictionary = _settle(_discarding(), ["p1", "p3", "p4"])["state"]
	var result: Dictionary = rules.apply(settled, "p3", {"type": "discard", "resources": {"clay": 4}}, ["p1", "p3", "p4"])
	assert_true(CoreResult.is_ok(result), str(result))
	assert_eq(result["state"]["turn"]["pending"], "move_blocker")


func test_an_absent_owner_with_discards_pending_just_loses_the_turn() -> void:
	var state: Dictionary = _discarding()
	var next: Dictionary = _settle(state, ["p2", "p3", "p4"])["state"]
	assert_eq(next["current_player"], "p2")
	assert_eq(next["turn"], GtSetup.new_turn())
	assert_eq(next["hands"]["p3"], state["hands"]["p3"], "nobody is made to discard for a turn that was dropped")


# --- settle: founding with an absent placer ----------------------------------------------------------------------------

func test_an_absent_placer_cannot_place_and_is_skipped_by_settle() -> void:
	var state: Dictionary = GtRig.new_state(4, {}, 3)
	var corner: String = GtBoard.new(state["board"]).corners()[0]
	assert_eq(CoreResult.error_code(rules.apply(state, "p1", {"type": "place_village", "corner": corner}, ["p2", "p3", "p4"])), GtErrors.PLAYER_INACTIVE)
	var result: Dictionary = _settle(state, ["p2", "p3", "p4"])
	assert_eq(result["state"]["current_player"], "p2")
	assert_eq(result["state"]["founding"]["index"], 1)
	assert_eq(result["state"]["founding"]["expect"], "village")
	assert_eq(_types(result["events"]), ["turn_skipped", "turn_changed"])
	assert_true(CoreResult.is_ok(rules.validate_state(result["state"])), str(rules.validate_state(result["state"])))


func test_settle_goes_on_to_the_next_present_placer_across_several_absent_ones() -> void:
	var next: Dictionary = _settle(GtRig.new_state(4, {}, 3), ["p3"])["state"]
	assert_eq(next["current_player"], "p3")
	assert_eq(next["founding"]["index"], 2)


func test_a_placer_who_leaves_between_village_and_path_is_skipped_too() -> void:
	var state: Dictionary = GtRig.new_state(4, {}, 3)
	var corner: String = GtBoard.new(state["board"]).corners()[0]
	state = rules.apply(state, "p1", {"type": "place_village", "corner": corner})["state"]
	assert_eq(state["founding"]["expect"], "path")
	var next: Dictionary = _settle(state, ["p2", "p3", "p4"])["state"]
	assert_eq(next["current_player"], "p2")
	assert_eq(next["founding"]["expect"], "village", "p2 starts with a village")
	assert_eq(next["founding"]["last_village"], "")
	assert_true(next["buildings"].has(corner), "p1 keeps the village they placed")


func test_settle_ends_the_founding_rounds_when_nobody_later_is_present() -> void:
	var state: Dictionary = GtRig.new_state(4, {}, 3)
	state["founding"]["index"] = 7  # the very last placement, p1's
	var next: Dictionary = _settle(state, ["p2"])["state"]
	assert_eq(next["phase"], "playing")
	assert_eq(next["founding"], {})
	assert_eq(next["current_player"], "p2", "the first present player in seat order starts")
	assert_eq(next["turn"], GtSetup.new_turn())


func test_settle_leaves_a_present_placer_alone() -> void:
	var state: Dictionary = GtRig.new_state(4, {}, 3)
	var result: Dictionary = _settle(state, ["p1", "p3"])
	assert_eq(result["state"], state)
	assert_eq(result["events"], [])


# --- offers and people who are away ------------------------------------------------------------------------------------------

func _with_offer(settings: Dictionary, to: Array, accepted: Array = []) -> Dictionary:
	var state: Dictionary = _turn(settings)
	GtRig.give(state, "p1", {"timber": 2})
	GtRig.give(state, "p2", {"clay": 2})
	GtRig.give(state, "p3", {"clay": 2})
	var action: Dictionary = {"type": "offer_trade", "give": {"timber": 1}, "want": {"clay": 1}}
	if not to.is_empty():
		action["to"] = to
	state = rules.apply(state, "p1", action)["state"]
	for id: String in accepted:
		state = rules.apply(state, id, {"type": "accept_trade"})["state"]
	return state


func test_an_offer_to_someone_who_is_away_stays_open_by_default() -> void:
	var state: Dictionary = _with_offer({}, ["p2"])
	var result: Dictionary = _settle(state, ["p1", "p3", "p4"])
	assert_eq(result["state"]["offer"], state["offer"])
	assert_eq(result["events"], [])


func test_with_cancel_offers_on_absence_an_offer_to_someone_who_is_away_is_cancelled() -> void:
	var state: Dictionary = _with_offer({"cancel_offers_on_absence": true}, ["p2"])
	var result: Dictionary = _settle(state, ["p1", "p3", "p4"])
	assert_eq(result["state"]["offer"], {})
	assert_eq(result["events"], [{"type": "offer_cancelled", "reason": "player_away"}])


func test_an_accepter_who_goes_away_cancels_the_offer_when_the_rule_is_on() -> void:
	var state: Dictionary = _with_offer({"cancel_offers_on_absence": true}, [], ["p3"])
	assert_eq(_settle(state, ["p1", "p2", "p4"])["state"]["offer"], {})
	var kept: Dictionary = _with_offer({}, [], ["p3"])
	assert_eq(_settle(kept, ["p1", "p2", "p4"])["state"]["offer"], kept["offer"])


func test_an_offer_whose_players_are_all_present_is_never_cancelled() -> void:
	var state: Dictionary = _with_offer({"cancel_offers_on_absence": true}, ["p2", "p3"], ["p2"])
	var result: Dictionary = _settle(state, ["p1", "p2", "p3"])
	assert_eq(result["state"]["offer"], state["offer"])
	assert_eq(result["events"], [])


func test_an_offer_does_not_survive_its_owner_being_away() -> void:
	for settings: Dictionary in [{}, {"cancel_offers_on_absence": true}]:
		var state: Dictionary = _with_offer(settings, ["p2"])
		var next: Dictionary = _settle(state, ["p2", "p3", "p4"])["state"]
		assert_eq(next["offer"], {}, str(settings))
		assert_eq(next["current_player"], "p2")


func test_the_owner_can_still_trade_with_a_present_accepter_while_others_are_away() -> void:
	var state: Dictionary = _with_offer({}, [], ["p3"])
	var result: Dictionary = rules.apply(state, "p1", {"type": "choose_trade_partner", "player": "p3"}, ["p1", "p3"])
	assert_true(CoreResult.is_ok(result), str(result))
	assert_eq(result["state"]["hands"]["p3"]["timber"], 1)


# --- a longer wobble ----------------------------------------------------------------------------------------------------------

func test_states_stay_valid_through_many_skips_and_settles() -> void:
	var state: Dictionary = GtRig.new_state(4, {}, 41)
	var bot: GtBot = GtBot.new(41)
	var prng: Prng = Prng.new(41)
	var active: Array = GtRig.players(4)
	for step: int in 45:
		if state["phase"] == "finished":
			break
		if prng.range_int(0, 4) == 0:
			active = []
			for id: String in GtRig.players(4):
				if prng.range_int(0, 2) != 0:
					active.append(id)
			if active.is_empty():
				active.append("p1")
			state = _settle(state, active)["state"]
		var picked: Dictionary = bot.pick(state, active)
		if picked.is_empty():
			state = _settle(state, active)["state"]
			continue
		var result: Dictionary = rules.apply(state, picked["player_id"], picked["action"], active)
		assert_true(CoreResult.is_ok(result), "step %d: %s" % [step, str(result)])
		state = result["state"]
		assert_true(CoreResult.is_ok(rules.validate_state(state)), "step %d: %s" % [step, str(rules.validate_state(state))])
