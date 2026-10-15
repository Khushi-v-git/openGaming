extends GutTest
## GtTurn: roll and payout, the 7, the blocker, fortune cards, end_turn and settle.

const PLAYERS: Array = ["a", "b", "c", "d"]

var _data: Dictionary = {}
var _board: GtBoard = null


func before_all() -> void:
	_data = GtBoard.load_file()["board"]
	_board = GtBoard.new(_data)


# --- helpers -------------------------------------------------------------------------------------------

func _state(seed_value: int = 3, settings: Dictionary = {}, ids: Array = PLAYERS) -> Dictionary:
	var state: Dictionary = GtSetup.new_game(ids, _data, settings, seed_value)["state"]
	state["phase"] = "playing"
	state["founding"] = {}
	return state


func _turn(state: Dictionary, player: String, action: Dictionary, active: Array = []) -> Dictionary:
	return GtTurn.apply(state, _board, player, action, active)


## Moves cards from the bank into a hand.
func _give(state: Dictionary, player: String, cards: Dictionary) -> void:
	state["hands"][player] = GtBank.add(state["hands"][player], cards)
	for resource: String in cards:
		state["supply"][resource] = int(state["supply"][resource]) - int(cards[resource])


func _tile(state: Dictionary, token: int) -> Dictionary:
	for tile: Dictionary in state["layout"]["tiles"]:
		if int(tile["token"]) == token:
			return tile
	return {}


## A building on corner `k` of the first tile with this token. Returns the tile.
func _build(state: Dictionary, player: String, token: int, k: int, kind: String = "village") -> Dictionary:
	var tile: Dictionary = _tile(state, token)
	var corner: String = _board.corners_of_hex(Vector2i(int(tile["q"]), int(tile["r"])))[k]
	state["buildings"][corner] = {"owner": player, "kind": kind}
	return tile


## Makes the next roll come out as `total` by choosing the generator state.
func _rig(state: Dictionary, total: int) -> void:
	for s: int in range(1, 5000):
		var prng: Prng = Prng.new(s)
		if prng.range_int(1, 6) + prng.range_int(1, 6) == total:
			var fresh: Prng = Prng.new(s)
			state["rng"] = {"seed": fresh.seed_text(), "state": fresh.state_text()}
			return
	fail_test("no seed gives %d" % total)


func _total(state: Dictionary) -> Dictionary:
	var sums: Dictionary = state["supply"].duplicate()
	for id: String in GtState.seat_order(state):
		sums = GtBank.add(sums, state["hands"][id])
	return sums


func _rolled(state: Dictionary) -> Dictionary:
	state["turn"]["rolled"] = true
	return state


func _types(result: Dictionary) -> Array:
	var out: Array = []
	for event: Dictionary in result["events"]:
		out.append(event["type"])
	return out


func _refused(state: Dictionary, player: String, action: Dictionary, code: String, active: Array = []) -> void:
	var before: Dictionary = state.duplicate(true)
	var result: Dictionary = _turn(state, player, action, active)
	assert_eq(CoreResult.error_code(result), code, "%s by %s" % [str(action), player])
	assert_eq(state, before, "a refused action leaves the state alone")


func _is_plain(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for item: Variant in value:
				if not _is_plain(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if typeof(key) != TYPE_STRING or not _is_plain(value[key]):
					return false
			return true
	return false


# --- action shapes and phases ----------------------------------------------------------------------------

func test_unknown_and_malformed_actions() -> void:
	var state: Dictionary = _state()
	_refused(state, "a", {"type": "build_path"}, ErrorCodes.UNKNOWN_ACTION)
	_refused(state, "a", {}, ErrorCodes.BAD_ACTION)
	_refused(state, "a", {"type": 5}, ErrorCodes.BAD_ACTION)
	_refused(state, "a", {"type": "roll", "dice": [6, 6]}, ErrorCodes.BAD_ACTION)
	_refused(state, "a", {"type": "end_turn", "x": 1}, ErrorCodes.BAD_ACTION)
	_refused(state, "a", {"type": "discard"}, ErrorCodes.BAD_ACTION)
	_refused(state, "a", {"type": "discard", "resources": {"timber": "x"}}, ErrorCodes.BAD_ACTION)
	_refused(state, "a", {"type": "move_blocker", "q": 0}, ErrorCodes.BAD_ACTION)
	_refused(state, "a", {"type": "move_blocker", "q": 0, "r": 0, "victim": 4}, ErrorCodes.BAD_ACTION)


func test_nothing_works_in_founding_or_after_the_end() -> void:
	var state: Dictionary = _state()
	state["phase"] = "founding"
	_refused(state, "a", {"type": "roll"}, GtErrors.WRONG_PHASE)
	state["phase"] = "finished"
	_refused(state, "a", {"type": "roll"}, GtErrors.GAME_OVER)


func test_only_the_turn_owner_rolls_and_only_once() -> void:
	var state: Dictionary = _state()
	_refused(state, "b", {"type": "roll"}, GtErrors.NOT_YOUR_TURN)
	var rolled: Dictionary = _turn(state, "a", {"type": "roll"})
	assert_true(CoreResult.is_ok(rolled))
	assert_true(rolled["state"]["turn"]["rolled"])
	assert_eq(rolled["state"]["turn"]["dice"].size(), 2)
	assert_eq(state["turn"]["rolled"], false, "the input is not changed")
	_refused(rolled["state"], "a", {"type": "roll"}, GtErrors.ALREADY_ROLLED)


# --- roll and payout ---------------------------------------------------------------------------------------

func test_roll_pays_villages_one_and_towns_two() -> void:
	var state: Dictionary = _state()
	var tile: Dictionary = _build(state, "a", 6, 0)
	_build(state, "b", 6, 3, "town")
	_rig(state, 6)
	var before: Dictionary = _total(state)
	var result: Dictionary = _turn(state, "a", {"type": "roll"})
	var next: Dictionary = result["state"]
	assert_eq(next["hands"]["a"][tile["type"]], 1)
	assert_eq(next["hands"]["b"][tile["type"]], 2)
	assert_eq(next["supply"][tile["type"]], int(state["supply"][tile["type"]]) - 3)
	assert_eq(_types(result), ["rolled", "produced"])
	assert_eq(result["events"][0]["total"], 6)
	assert_eq(result["events"][1]["tiles"], [{"q": tile["q"], "r": tile["r"], "token": 6}])
	assert_eq(_total(next), before)


func test_one_player_with_two_corners_on_a_tile_collects_for_each() -> void:
	var state: Dictionary = _state()
	var tile: Dictionary = _build(state, "a", 8, 0)
	_build(state, "a", 8, 2)
	_rig(state, 8)
	var next: Dictionary = _turn(state, "a", {"type": "roll"})["state"]
	assert_eq(next["hands"]["a"][tile["type"]], 2)


func test_the_blocked_tile_pays_nothing() -> void:
	var state: Dictionary = _state()
	var tile: Dictionary = _build(state, "a", 6, 0)
	state["blocker"] = {"q": tile["q"], "r": tile["r"]}
	_rig(state, 6)
	var result: Dictionary = _turn(state, "a", {"type": "roll"})
	assert_eq(_types(result), ["rolled", "nothing_produced"])
	assert_eq(GtBank.hand_count(result["state"]["hands"]["a"]), 0)


func test_a_roll_nobody_matches_produces_nothing() -> void:
	var state: Dictionary = _state()
	_rig(state, 12)
	assert_eq(_types(_turn(state, "a", {"type": "roll"})), ["rolled", "nothing_produced"])


func test_shortage_with_two_claimants_pays_none_and_one_claimant_gets_what_is_left() -> void:
	var state: Dictionary = _state()
	var tile: Dictionary = _build(state, "a", 6, 0)
	_build(state, "b", 6, 3)
	_rig(state, 6)
	state["supply"][tile["type"]] = 1
	var result: Dictionary = _turn(state, "a", {"type": "roll"})
	assert_eq(result["state"]["supply"][tile["type"]], 1, "two claimants, one card: nobody is paid")
	assert_true(_types(result).has("shortage"))
	var solo: Dictionary = _state()
	_build(solo, "a", 6, 0, "town")
	_rig(solo, 6)
	solo["supply"][tile["type"]] = 1
	var paid: Dictionary = _turn(solo, "a", {"type": "roll"})["state"]
	assert_eq(paid["hands"]["a"][_tile(solo, 6)["type"]], 1)
	assert_eq(paid["supply"][_tile(solo, 6)["type"]], 0)


func test_rolls_are_deterministic_and_change_the_generator() -> void:
	var state: Dictionary = _state(9)
	var one: Dictionary = _turn(state, "a", {"type": "roll"})
	var two: Dictionary = _turn(state, "a", {"type": "roll"})
	assert_eq(one["state"], two["state"])
	assert_ne(one["state"]["rng"]["state"], state["rng"]["state"])
	var dice_seen: Dictionary = {}
	for s: int in 40:
		dice_seen[str(_turn(_state(s), "a", {"type": "roll"})["state"]["turn"]["dice"])] = true
	assert_gt(dice_seen.size(), 10)


# --- the 7 ---------------------------------------------------------------------------------------------------

func test_a_seven_with_nobody_over_the_limit_goes_straight_to_the_blocker() -> void:
	var state: Dictionary = _state()
	_give(state, "b", {"timber": 7})  # exactly the limit keeps everything
	_rig(state, 7)
	var result: Dictionary = _turn(state, "a", {"type": "roll"})
	assert_eq(result["state"]["turn"]["pending"], "move_blocker")
	assert_eq(result["state"]["turn"]["source"], "seven")
	assert_eq(_types(result), ["rolled"])


func test_a_seven_makes_big_hands_discard_half_before_the_blocker_moves() -> void:
	var state: Dictionary = _state()
	_give(state, "b", {"timber": 5, "clay": 3})
	_give(state, "c", {"wheat": 9})
	_rig(state, 7)
	var result: Dictionary = _turn(state, "a", {"type": "roll"})
	var next: Dictionary = result["state"]
	assert_eq(next["turn"]["pending"], "discard")
	assert_eq(next["turn"]["owed"], {"b": 4, "c": 4})
	assert_eq(_types(result), ["rolled", "discard_required"])
	_refused(next, "a", {"type": "end_turn"}, GtErrors.MUST_DISCARD)
	_refused(next, "d", {"type": "discard", "resources": {}}, GtErrors.NOT_YOUR_TURN)
	_refused(next, "b", {"type": "discard", "resources": {"timber": 3}}, GtErrors.BAD_DISCARD)
	_refused(next, "b", {"type": "discard", "resources": {"stone": 4}}, GtErrors.BAD_DISCARD)
	_refused(next, "b", {"type": "discard", "resources": {"wheat": -4, "timber": 8}}, ErrorCodes.BAD_ACTION)
	var before: Dictionary = _total(next)
	var first: Dictionary = _turn(next, "b", {"type": "discard", "resources": {"timber": 4}})
	assert_true(CoreResult.is_ok(first))
	assert_eq(first["state"]["hands"]["b"]["timber"], 1)
	assert_eq(first["state"]["turn"]["pending"], "discard", "c still owes")
	_refused(first["state"], "b", {"type": "discard", "resources": {"timber": 1}}, GtErrors.NOT_YOUR_TURN)
	var second: Dictionary = _turn(first["state"], "c", {"type": "discard", "resources": {"wheat": 4}})
	assert_eq(second["state"]["turn"]["pending"], "move_blocker")
	assert_eq(second["state"]["turn"]["owed"], {})
	assert_eq(_total(second["state"]), before)


func test_discard_outside_a_discard_is_wrong_phase() -> void:
	_refused(_state(), "a", {"type": "discard", "resources": {}}, GtErrors.WRONG_PHASE)


func _blocker_state() -> Dictionary:
	var state: Dictionary = _state()
	state["turn"]["rolled"] = true
	state["turn"]["pending"] = "move_blocker"
	state["turn"]["source"] = "seven"
	return state


func _other_tile(state: Dictionary, token: int) -> Dictionary:
	return _tile(state, token)


func test_move_blocker_steals_one_card_from_the_named_victim() -> void:
	var state: Dictionary = _blocker_state()
	var tile: Dictionary = _build(state, "b", 5, 0)
	_give(state, "b", {"clay": 2})
	var action: Dictionary = {"type": "move_blocker", "q": tile["q"], "r": tile["r"], "victim": "b"}
	_refused(state, "a", {"type": "end_turn"}, GtErrors.WRONG_PHASE)
	_refused(state, "b", action, GtErrors.NOT_YOUR_TURN)
	var no_victim: Dictionary = action.duplicate()
	no_victim.erase("victim")
	_refused(state, "a", no_victim, GtErrors.BAD_VICTIM)
	var self_victim: Dictionary = action.duplicate()
	self_victim["victim"] = "a"
	_refused(state, "a", self_victim, GtErrors.BAD_VICTIM)
	var result: Dictionary = _turn(state, "a", action)
	var next: Dictionary = result["state"]
	assert_eq(next["blocker"], {"q": tile["q"], "r": tile["r"]})
	assert_eq(next["hands"]["a"]["clay"], 1)
	assert_eq(next["hands"]["b"]["clay"], 1)
	assert_eq(next["turn"]["pending"], "")
	assert_eq(_types(result), ["blocker_moved", "stole"])
	assert_false(result["events"][1].has("resource"), "which card was taken is not public")


func test_move_blocker_without_a_victim_when_nobody_can_be_robbed() -> void:
	var state: Dictionary = _blocker_state()
	var tile: Dictionary = _build(state, "b", 5, 0)  # b has an empty hand
	var go: Dictionary = {"type": "move_blocker", "q": tile["q"], "r": tile["r"]}
	var result: Dictionary = _turn(state, "a", go)
	assert_eq(_types(result), ["blocker_moved"])
	_refused(state, "a", {"type": "move_blocker", "q": tile["q"], "r": tile["r"], "victim": "b"}, GtErrors.BAD_VICTIM)
	var empty: Dictionary = _turn(state, "a", {"type": "move_blocker", "q": 99, "r": 99})
	assert_eq(CoreResult.error_code(empty), GtErrors.BAD_BLOCKER_MOVE)


func test_the_blocker_must_move_to_a_different_tile() -> void:
	var state: Dictionary = _blocker_state()
	_refused(state, "a", {"type": "move_blocker", "q": state["blocker"]["q"], "r": state["blocker"]["r"]}, GtErrors.BAD_BLOCKER_MOVE)


func test_friendly_blocker_spares_players_with_two_points_or_fewer() -> void:
	var state: Dictionary = _state(3, {"friendly_blocker": true})
	state["turn"]["rolled"] = true
	state["turn"]["pending"] = "move_blocker"
	var tile: Dictionary = _build(state, "b", 5, 0)
	_give(state, "b", {"clay": 1})
	var go: Dictionary = {"type": "move_blocker", "q": tile["q"], "r": tile["r"], "victim": "b"}
	_refused(state, "a", go, GtErrors.BAD_BLOCKER_MOVE)
	state["bonuses"]["longest_path"] = "b"  # 1 + 2 points: no longer spared
	assert_true(CoreResult.is_ok(_turn(state, "a", go)))


func test_the_move_always_steals_a_card_b_has() -> void:
	var seen: Dictionary = {}
	for s: int in 30:
		var state: Dictionary = _state(s)
		state["turn"]["rolled"] = true
		state["turn"]["pending"] = "move_blocker"
		var tile: Dictionary = _build(state, "b", 5, 0)
		_give(state, "b", {"timber": 1, "clay": 1, "stone": 1})
		var next: Dictionary = _turn(state, "a", {"type": "move_blocker", "q": tile["q"], "r": tile["r"], "victim": "b"})["state"]
		assert_eq(GtBank.hand_count(next["hands"]["a"]), 1)
		for resource: String in GtBank.RESOURCES:
			if int(next["hands"]["a"][resource]) == 1:
				seen[resource] = true
	assert_eq(seen.size(), 3, "every card can be the one taken")


# --- fortune cards ---------------------------------------------------------------------------------------------

func test_buy_card_needs_a_roll_and_the_price() -> void:
	var state: Dictionary = _state()
	_give(state, "a", {"fleece": 1, "wheat": 1, "stone": 1})
	_refused(state, "a", {"type": "buy_card"}, GtErrors.NOT_ROLLED)
	_rolled(state)
	var before: Dictionary = _total(state)
	var result: Dictionary = _turn(state, "a", {"type": "buy_card"})
	var next: Dictionary = result["state"]
	assert_eq(next["cards"]["a"]["fresh"].size(), 1)
	assert_eq(next["cards"]["a"]["fresh"][0], state["deck"][0])
	assert_eq(next["deck"].size(), 24)
	assert_eq(GtBank.hand_count(next["hands"]["a"]), 0)
	assert_eq(_types(result), ["card_bought"])
	assert_eq(_total(next), before)
	_refused(next, "a", {"type": "buy_card"}, GtErrors.CANNOT_AFFORD)
	state["deck"] = []
	_refused(state, "a", {"type": "buy_card"}, GtErrors.CARD_NOT_AVAILABLE)


func test_a_bought_point_card_can_win_at_once() -> void:
	var state: Dictionary = _rolled(_state(3, {"target_points": 8}))
	for i: int in 7:
		state["buildings"]["x%d" % i] = {"owner": "a", "kind": "village"}
	state["deck"][0] = "point"
	_give(state, "a", {"fleece": 1, "wheat": 1, "stone": 1})
	var result: Dictionary = _turn(state, "a", {"type": "buy_card"})
	assert_eq(result["state"]["phase"], "finished")
	assert_eq(result["state"]["winner"], "a")
	assert_eq(_types(result), ["card_bought", "won"])


func _with_card(state: Dictionary, player: String, card: String) -> Dictionary:
	state["cards"][player]["held"].append(card)
	return state


func test_a_guard_card_moves_the_blocker_before_or_after_the_roll() -> void:
	var state: Dictionary = _with_card(_state(), "a", "guard")
	var result: Dictionary = _turn(state, "a", {"type": "play_card", "card": "guard"})
	var next: Dictionary = result["state"]
	assert_eq(_types(result), ["card_played"])
	assert_eq(next["guards_played"]["a"], 1)
	assert_eq(next["turn"]["pending"], "move_blocker")
	assert_eq(next["turn"]["source"], "guard")
	assert_true(next["turn"]["card_played"])
	assert_eq(next["cards"]["a"]["held"], [])
	assert_eq(state["cards"]["a"]["held"], ["guard"])
	_refused(next, "a", {"type": "roll"}, GtErrors.WRONG_PHASE)
	var tile: Dictionary = _tile(next, 9)
	var moved: Dictionary = _turn(next, "a", {"type": "move_blocker", "q": tile["q"], "r": tile["r"]})
	assert_eq(moved["state"]["turn"]["pending"], "")
	assert_true(CoreResult.is_ok(_turn(moved["state"], "a", {"type": "roll"})), "the roll still comes after")


func test_the_third_guard_takes_largest_guard() -> void:
	var state: Dictionary = _with_card(_state(), "a", "guard")
	state["guards_played"]["a"] = 2
	var result: Dictionary = _turn(state, "a", {"type": "play_card", "card": "guard"})
	assert_eq(result["state"]["bonuses"]["largest_guard"], "a")
	assert_eq(_types(result), ["card_played", "bonus_changed"])


func test_one_card_per_turn_and_only_held_cards() -> void:
	var state: Dictionary = _with_card(_with_card(_rolled(_state()), "a", "two_paths"), "a", "guard")
	var next: Dictionary = _turn(state, "a", {"type": "play_card", "card": "two_paths"})["state"]
	assert_eq(next["turn"]["free_paths"], 2)
	_refused(next, "a", {"type": "play_card", "card": "guard"}, GtErrors.CARD_ALREADY_PLAYED)
	var fresh: Dictionary = _rolled(_state())
	fresh["cards"]["a"]["fresh"].append("guard")
	_refused(fresh, "a", {"type": "play_card", "card": "guard"}, GtErrors.CARD_NOT_AVAILABLE)
	_refused(_state(), "a", {"type": "play_card", "card": "sweep", "resource": "clay"}, GtErrors.CARD_NOT_AVAILABLE)
	_refused(_with_card(_state(), "a", "point"), "a", {"type": "play_card", "card": "point"}, GtErrors.NO_SUCH_CARD)
	_refused(_state(), "a", {"type": "play_card", "card": "wand"}, GtErrors.NO_SUCH_CARD)
	_refused(_with_card(_state(), "a", "two_paths"), "a", {"type": "play_card", "card": "two_paths"}, GtErrors.NOT_ROLLED)
	_refused(_with_card(_state(), "b", "guard"), "b", {"type": "play_card", "card": "guard"}, GtErrors.NOT_YOUR_TURN)


func test_card_actions_check_their_fields() -> void:
	var state: Dictionary = _with_card(_with_card(_with_card(_rolled(_state()), "a", "harvest"), "a", "sweep"), "a", "guard")
	_refused(state, "a", {"type": "play_card"}, ErrorCodes.BAD_ACTION)
	_refused(state, "a", {"type": "play_card", "card": "guard", "q": 1}, ErrorCodes.BAD_ACTION)
	_refused(state, "a", {"type": "play_card", "card": "harvest"}, ErrorCodes.BAD_ACTION)
	_refused(state, "a", {"type": "play_card", "card": "harvest", "resources": ["clay"]}, ErrorCodes.BAD_ACTION)
	_refused(state, "a", {"type": "play_card", "card": "harvest", "resources": ["clay", "gold"]}, ErrorCodes.BAD_ACTION)
	_refused(state, "a", {"type": "play_card", "card": "sweep", "resource": "gold"}, ErrorCodes.BAD_ACTION)
	_refused(state, "a", {"type": "play_card", "card": "sweep"}, ErrorCodes.BAD_ACTION)


func test_harvest_takes_two_from_the_bank() -> void:
	var state: Dictionary = _with_card(_rolled(_state()), "a", "harvest")
	var before: Dictionary = _total(state)
	var result: Dictionary = _turn(state, "a", {"type": "play_card", "card": "harvest", "resources": ["clay", "clay"]})
	assert_eq(result["state"]["hands"]["a"]["clay"], 2)
	assert_eq(result["state"]["supply"]["clay"], int(state["supply"]["clay"]) - 2)
	assert_eq(_types(result), ["card_played", "harvest_taken"])
	assert_eq(_total(result["state"]), before)
	state["supply"]["clay"] = 1
	_refused(state, "a", {"type": "play_card", "card": "harvest", "resources": ["clay", "clay"]}, GtErrors.CANNOT_AFFORD)
	assert_true(CoreResult.is_ok(_turn(state, "a", {"type": "play_card", "card": "harvest", "resources": ["clay", "wheat"]})))


func test_sweep_collects_one_resource_from_everyone_else() -> void:
	var state: Dictionary = _with_card(_rolled(_state()), "a", "sweep")
	_give(state, "a", {"clay": 1})
	_give(state, "b", {"clay": 3, "wheat": 1})
	_give(state, "c", {"clay": 2})
	var before: Dictionary = _total(state)
	var result: Dictionary = _turn(state, "a", {"type": "play_card", "card": "sweep", "resource": "clay"})
	var next: Dictionary = result["state"]
	assert_eq(next["hands"]["a"]["clay"], 6)
	assert_eq(next["hands"]["b"]["clay"], 0)
	assert_eq(next["hands"]["b"]["wheat"], 1)
	assert_eq(result["events"][1], {"type": "swept", "player_id": "a", "resource": "clay", "total": 5})
	assert_eq(_total(next), before)


# --- end of turn -------------------------------------------------------------------------------------------------

func test_end_turn_needs_a_roll_and_passes_to_the_next_player() -> void:
	var state: Dictionary = _state()
	_refused(state, "a", {"type": "end_turn"}, GtErrors.NOT_ROLLED)
	_rolled(state)
	state["cards"]["a"]["fresh"] = ["guard"]
	state["turn"]["card_played"] = true
	state["offer"] = {"from": "a", "give": {"clay": 1}, "want": {"wheat": 1}, "to": [], "accepted": [], "declined": []}
	_refused(state, "b", {"type": "end_turn"}, GtErrors.NOT_YOUR_TURN)
	var result: Dictionary = _turn(state, "a", {"type": "end_turn"})
	var next: Dictionary = result["state"]
	assert_eq(next["current_player"], "b")
	assert_eq(next["turn_number"], 2)
	assert_eq(next["turn"], GtSetup.new_turn())
	assert_eq(next["cards"]["a"]["held"], ["guard"])
	assert_eq(next["cards"]["a"]["fresh"], [])
	assert_eq(next["offer"], {})
	assert_eq(_types(result), ["offer_cancelled", "turn_changed"])
	var wrap: Dictionary = _rolled(_state())
	wrap["current_player"] = "d"
	assert_eq(_turn(wrap, "d", {"type": "end_turn"})["state"]["current_player"], "a")


func test_end_turn_skips_absent_players() -> void:
	var state: Dictionary = _rolled(_state())
	assert_eq(_turn(state, "a", {"type": "end_turn"}, ["a", "c", "d"])["state"]["current_player"], "c")
	assert_eq(_turn(state, "a", {"type": "end_turn"}, ["a"])["state"]["current_player"], "a")


func test_end_turn_wins_with_hidden_point_cards() -> void:
	var state: Dictionary = _rolled(_state(3, {"target_points": 8}))
	for i: int in 6:
		state["buildings"]["x%d" % i] = {"owner": "a", "kind": "village"}
	state["cards"]["a"]["held"] = ["point", "point"]
	var result: Dictionary = _turn(state, "a", {"type": "end_turn"})
	assert_eq(result["state"]["phase"], "finished")
	assert_eq(result["state"]["current_player"], "a")
	assert_eq(_types(result), ["won"])


# --- settle ------------------------------------------------------------------------------------------------------------

func _settle(state: Dictionary, active: Array) -> Dictionary:
	return GtTurn.settle(state, _board, active)


func test_settle_does_nothing_when_everyone_is_present() -> void:
	var state: Dictionary = _state()
	var all: Dictionary = _settle(state, PLAYERS)
	assert_true(CoreResult.is_ok(all))
	assert_eq(all["state"], state)
	assert_eq(all["events"], [])
	assert_eq(_settle(state, [])["state"], state)
	state["phase"] = "finished"
	assert_eq(_settle(state, ["b"])["state"], state)


func test_settle_needs_somebody_present() -> void:
	assert_eq(CoreResult.error_code(_settle(_state(), ["zed"])), GtErrors.NO_ACTIVE_PLAYERS)


func test_settle_passes_the_turn_when_the_owner_is_away() -> void:
	var state: Dictionary = _rolled(_state())
	state["cards"]["a"]["fresh"] = ["sweep"]
	state["turn"]["pending"] = "move_blocker"
	state["offer"] = {"from": "a", "give": {"clay": 1}, "want": {"wheat": 1}, "to": [], "accepted": [], "declined": []}
	var result: Dictionary = _settle(state, ["b", "c", "d"])
	var next: Dictionary = result["state"]
	assert_eq(next["current_player"], "b")
	assert_eq(next["turn"], GtSetup.new_turn())
	assert_eq(next["cards"]["a"]["held"], ["sweep"])
	assert_eq(next["offer"], {})
	assert_eq(_types(result), ["offer_cancelled", "turn_skipped", "turn_changed"])
	assert_eq(_settle(state, ["c", "d"])["state"]["current_player"], "c", "b is away too")


func test_settle_discards_at_random_for_absent_players() -> void:
	var state: Dictionary = _state()
	_give(state, "b", {"timber": 4, "clay": 4})
	_give(state, "c", {"wheat": 9})
	_rig(state, 7)
	var rolled: Dictionary = _turn(state, "a", {"type": "roll"})["state"]
	var before: Dictionary = _total(rolled)
	var result: Dictionary = _settle(rolled, ["a", "c", "d"])
	var next: Dictionary = result["state"]
	assert_eq(GtBank.hand_count(next["hands"]["b"]), 4)
	assert_eq(next["turn"]["owed"], {"c": 4})
	assert_eq(next["turn"]["pending"], "discard")
	assert_eq(_total(next), before)
	assert_eq(result["events"], [{"type": "discarded", "player_id": "b", "count": 4}])
	assert_eq(_settle(rolled, ["a", "c", "d"])["state"], next, "the same state gives the same discards")
	var done: Dictionary = _settle(rolled, ["a", "d"])["state"]
	assert_eq(done["turn"]["pending"], "move_blocker")
	assert_eq(GtBank.hand_count(done["hands"]["c"]), 5)
	assert_eq(_total(done), before)


func test_settle_cancels_offers_only_when_the_setting_asks() -> void:
	var offer: Dictionary = {"from": "a", "give": {"clay": 1}, "want": {"wheat": 1}, "to": ["b"], "accepted": [], "declined": []}
	var keep: Dictionary = _state()
	keep["offer"] = offer
	assert_eq(_settle(keep, ["a", "c", "d"])["state"]["offer"], offer, "default: idle")
	var cancel: Dictionary = _state(3, {"cancel_offers_on_absence": true})
	cancel["offer"] = offer
	var result: Dictionary = _settle(cancel, ["a", "c", "d"])
	assert_eq(result["state"]["offer"], {})
	assert_eq(_types(result), ["offer_cancelled"])
	assert_eq(_settle(cancel, ["a", "b", "c"])["state"]["offer"], offer, "an uninvolved player is away")
	cancel["offer"] = {"from": "a", "give": {"clay": 1}, "want": {"wheat": 1}, "to": [], "accepted": ["d"], "declined": []}
	assert_eq(_settle(cancel, ["a", "b", "c"])["state"]["offer"], {}, "an accepter is away")


func test_settle_skips_an_absent_founder() -> void:
	var state: Dictionary = GtSetup.new_game(PLAYERS, _data, {}, 3)["state"]
	var result: Dictionary = _settle(state, ["b", "c", "d"])
	var next: Dictionary = result["state"]
	assert_eq(next["current_player"], "b")
	assert_eq(next["founding"]["index"], 1)
	assert_eq(_types(result), ["turn_skipped", "turn_changed"])
	var late: Dictionary = GtSetup.new_game(PLAYERS, _data, {}, 3)["state"]
	late["founding"]["index"] = 7  # "c" places; only "d" and "a" would follow in order, "a" is last
	late["current_player"] = "c"
	assert_eq(_settle(late, ["d", "c"])["state"]["current_player"], "c", "c is present: nothing to do")
	var last: Dictionary = GtSetup.new_game(PLAYERS, _data, {}, 3)["state"]
	last["founding"]["index"] = 7
	last["current_player"] = "c"
	var over: Dictionary = _settle(last, ["d", "b"])["state"]
	assert_eq(over["phase"], "playing", "nobody present is left to place")
	assert_eq(over["current_player"], "b")
	assert_eq(over["founding"], {})


# --- properties ----------------------------------------------------------------------------------------------------------

func _random_action(state: Dictionary, prng: Prng) -> Array:
	var turn: Dictionary = state["turn"]
	if turn["pending"] == "discard":
		var ids: Array = turn["owed"].keys()
		var id: String = ids[prng.range_int(0, ids.size() - 1)]
		var cards: Array = []
		for resource: String in GtBank.RESOURCES:
			for i: int in int(state["hands"][id][resource]):
				cards.append(resource)
		var chosen: Dictionary = {}
		for i: int in int(turn["owed"][id]):
			var pick: int = prng.range_int(0, cards.size() - 1)
			chosen[cards[pick]] = int(chosen.get(cards[pick], 0)) + 1
			cards.remove_at(pick)
		return [id, {"type": "discard", "resources": chosen}]
	var owner: String = state["current_player"]
	var tiles: Array = state["layout"]["tiles"]
	var tile: Dictionary = tiles[prng.range_int(0, tiles.size() - 1)]
	var victims: Array = GtState.seat_order(state)
	var choices: Array = [
		{"type": "roll"}, {"type": "roll"}, {"type": "buy_card"}, {"type": "end_turn"},
		{"type": "move_blocker", "q": tile["q"], "r": tile["r"], "victim": victims[prng.range_int(0, victims.size() - 1)]},
		{"type": "move_blocker", "q": tile["q"], "r": tile["r"]},
		{"type": "play_card", "card": "guard"},
		{"type": "play_card", "card": "two_paths"},
		{"type": "play_card", "card": "harvest", "resources": [GtBank.RESOURCES[prng.range_int(0, 4)], GtBank.RESOURCES[prng.range_int(0, 4)]]},
		{"type": "play_card", "card": "sweep", "resource": GtBank.RESOURCES[prng.range_int(0, 4)]},
	]
	return [owner, choices[prng.range_int(0, choices.size() - 1)]]


func _random_start(seed_value: int, prng: Prng) -> Dictionary:
	var state: Dictionary = _state(seed_value, {"hand_limit": 5})
	var corners: Array = _board.corners()
	for id: String in PLAYERS:
		for k: int in 3:
			state["buildings"][corners[prng.range_int(0, corners.size() - 1)]] = {"owner": id, "kind": "town" if k == 0 else "village"}
		var cards: Dictionary = {}
		for resource: String in GtBank.RESOURCES:
			cards[resource] = prng.range_int(0, 3)
		_give(state, id, cards)
		for card: String in GtDeck.CARD_TYPES:
			if prng.range_int(0, 2) == 0:
				state["cards"][id]["held"].append(card)
	return state


func test_resources_are_conserved_over_random_play() -> void:
	var applied: int = 0
	for s: int in 25:
		var prng: Prng = Prng.new(1000 + s)
		var state: Dictionary = _random_start(s, prng)
		var totals: Dictionary = _total(state)
		for step: int in 80:
			if state["phase"] == "finished":
				break
			var pick: Array = _random_action(state, prng)
			var before: Dictionary = state.duplicate(true)
			var result: Dictionary = _turn(state, pick[0], pick[1])
			if CoreResult.is_ok(result):
				state = result["state"]
				applied += 1
				assert_eq(_total(state), totals, "seed %d step %d %s" % [s, step, str(pick[1])])
				if step % 10 == 0:
					assert_true(_is_plain(state), "state stays plain data")
					assert_true(_is_plain(result["events"]), "events stay plain data")
				for resource: String in GtBank.RESOURCES:
					assert_gte(int(state["supply"][resource]), 0)
					for id: String in PLAYERS:
						assert_gte(int(state["hands"][id][resource]), 0)
			else:
				assert_eq(state, before, "a refusal changes nothing")
	assert_gt(applied, 250, "the random driver does real work")


func test_the_same_seed_and_actions_replay_identically() -> void:
	var finals: Array = []
	for run: int in 2:
		var prng: Prng = Prng.new(77)
		var state: Dictionary = _random_start(5, prng)
		for step: int in 60:
			if state["phase"] == "finished":
				break
			var pick: Array = _random_action(state, prng)
			var result: Dictionary = _turn(state, pick[0], pick[1])
			if CoreResult.is_ok(result):
				state = result["state"]
		finals.append(JSON.stringify(state))
	assert_eq(finals[0], finals[1])
