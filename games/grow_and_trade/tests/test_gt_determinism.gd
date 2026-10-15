extends GutTest
## The same seed gives the same game, a different seed a different one, and the random draws happen in
## exactly the documented order (docs/grow-and-trade-design.md, "Random draws"): changing it breaks saves.

var rules: GrowAndTradeRules


func before_each() -> void:
	rules = GrowAndTradeRules.new()


func _owner(state: Dictionary) -> String:
	return state["current_player"]


func _apply(state: Dictionary, player: String, action: Dictionary, active: Array = []) -> Dictionary:
	var result: Dictionary = rules.apply(state, player, action, active)
	assert_true(CoreResult.is_ok(result), str(result))
	return result


func _restore(state: Dictionary) -> Prng:
	return Prng.restore(state["rng"]["seed"], state["rng"]["state"])


# --- new_game --------------------------------------------------------------------------------------

func test_the_same_seed_gives_the_same_game() -> void:
	assert_eq(GtRig.new_state(5, {}, 77), GtRig.new_state(5, {}, 77))
	assert_eq(GtRig.new_state(3, {}, -5), GtRig.new_state(3, {}, -5), "negative seeds work")
	assert_eq(GtRig.new_state(4, {}, 9007199254740993), GtRig.new_state(4, {}, 9007199254740993), "so do seeds beyond 2^53")


func test_different_seeds_give_different_layouts_and_decks() -> void:
	var a: Dictionary = GtRig.new_state(4, {}, 1)
	var b: Dictionary = GtRig.new_state(4, {}, 2)
	assert_ne(a["layout"], b["layout"])
	assert_ne(a["deck"], b["deck"])
	assert_ne(a["rng"], b["rng"])


func test_new_game_draws_the_layout_first_and_then_the_deck() -> void:
	var state: Dictionary = GtRig.new_state(5, {}, 424242)
	var prng: Prng = Prng.new(424242)
	var layout: Dictionary = GtBoard.layout(GtBoard.validate(GtRig.board())["board"], prng)["layout"]
	var deck: Array = GtDeck.new_deck(GtBank.load_config()["config"], prng)
	assert_eq(state["layout"]["tiles"], layout["tiles"])
	assert_eq(state["layout"]["harbors"], layout["harbors"])
	assert_eq(state["blocker"], layout["blocker"])
	assert_eq(state["deck"], deck)
	assert_eq(state["rng"]["state"], prng.state_text(), "and nothing else was drawn")


# --- the game itself is deterministic ------------------------------------------------------------------

func _play_bot(state: Dictionary, bot_seed: int, actions: int) -> Dictionary:
	var bot: GtBot = GtBot.new(bot_seed)
	var events: Array = []
	var current: Dictionary = state
	for _i: int in actions:
		if current["phase"] == "finished":
			break
		var picked: Dictionary = bot.pick(current)
		var result: Dictionary = _apply(current, picked["player_id"], picked["action"])
		current = result["state"]
		events.append_array(result["events"])
	return {"state": current, "events": events}


func test_the_same_seed_and_actions_give_the_same_game_and_events() -> void:
	var first: Dictionary = _play_bot(GtRig.new_state(4, {}, 31), 5, 260)
	var second: Dictionary = _play_bot(GtRig.new_state(4, {}, 31), 5, 260)
	assert_eq(first["state"], second["state"])
	assert_eq(first["events"], second["events"])
	assert_eq(JSON.stringify(first["state"]), JSON.stringify(second["state"]), "byte for byte")


func test_another_seed_plays_out_differently() -> void:
	var first: Dictionary = _play_bot(GtRig.new_state(4, {}, 31), 5, 200)
	var second: Dictionary = _play_bot(GtRig.new_state(4, {}, 32), 5, 200)
	assert_ne(first["state"]["rng"], second["state"]["rng"])
	assert_ne(first["state"]["hands"], second["state"]["hands"])


# --- the draw order ---------------------------------------------------------------------------------------

func test_a_roll_draws_exactly_two_dice_in_order() -> void:
	var state: Dictionary = GtRig.playing(4, {}, 12)
	var prng: Prng = _restore(state)
	var first: int = prng.range_int(1, 6)
	var second: int = prng.range_int(1, 6)
	var result: Dictionary = _apply(state, _owner(state), {"type": "roll"})
	assert_eq(result["state"]["turn"]["dice"], [first, second])
	assert_eq(result["events"][0], {"type": "rolled", "player_id": _owner(state), "dice": [first, second], "total": first + second})
	assert_eq(result["state"]["rng"]["state"], prng.state_text(), "exactly two draws")
	assert_eq(result["state"]["rng"]["seed"], state["rng"]["seed"], "the seed never changes")


func test_actions_that_are_not_random_leave_the_generator_alone() -> void:
	var state: Dictionary = GtRig.rolled(GtRig.playing(4, {}, 14))
	var owner: String = _owner(state)
	GtRig.give(state, owner, {"timber": 5, "clay": 5, "fleece": 5, "wheat": 5, "stone": 5})
	var before: Dictionary = state["rng"].duplicate()
	var bank: Dictionary = _apply(state, owner, {"type": "bank_trade", "give": "timber", "get": "stone"})
	assert_eq(bank["state"]["rng"], before, "a bank trade")
	var offer: Dictionary = _apply(state, owner, {"type": "offer_trade", "give": {"timber": 1}, "want": {"clay": 1}})
	assert_eq(offer["state"]["rng"], before, "an offer")
	var ended: Dictionary = _apply(state, owner, {"type": "end_turn"})
	assert_eq(ended["state"]["rng"], before, "ending the turn")
	var bought: Dictionary = _apply(state, owner, {"type": "buy_card"})
	assert_eq(bought["state"]["rng"], before, "buying a card takes the top of an already shuffled deck")


func test_a_steal_draws_one_card_over_the_victims_hand_in_resource_order() -> void:
	var state: Dictionary = GtRig.rolled(GtRig.playing(4, {}, 16))
	var owner: String = _owner(state)
	var target: Dictionary = GtRig.rival_tile(state, owner)
	assert_false(target.is_empty())
	var victim: String = target["victim"]
	GtRig.give(state, victim, {"timber": 2, "wheat": 1, "stone": 3})
	state["turn"]["pending"] = "move_blocker"
	state["turn"]["source"] = "guard"
	var prng: Prng = _restore(state)
	var expected: String = ["timber", "timber", "wheat", "stone", "stone", "stone"][prng.range_int(0, 5)]
	var result: Dictionary = _apply(state, owner, {"type": "move_blocker", "q": target["q"], "r": target["r"], "victim": victim})
	assert_eq(result["state"]["hands"][owner][expected], 1, "the thief got the card the documented draw picks")
	assert_eq(GtBank.hand_count(result["state"]["hands"][owner]), 1)
	assert_eq(int(result["state"]["hands"][victim][expected]), int(state["hands"][victim][expected]) - 1)
	assert_eq(result["state"]["rng"]["state"], prng.state_text(), "exactly one draw")


func test_moving_the_blocker_where_nobody_can_be_robbed_draws_nothing() -> void:
	var state: Dictionary = GtRig.rolled(GtRig.playing(4, {}, 16))
	var owner: String = _owner(state)
	state["turn"]["pending"] = "move_blocker"
	state["turn"]["source"] = "guard"
	var empty_tile: Dictionary = {}
	var geometry: GtBoard = GtBoard.new(state["board"])
	for tile: Variant in state["layout"]["tiles"]:
		var hex: Vector2i = Vector2i(int(tile["q"]), int(tile["r"]))
		var crowded: bool = false
		for corner: String in geometry.corners_of_hex(hex):
			crowded = crowded or state["buildings"].has(corner)
		if not crowded and (hex.x != int(state["blocker"]["q"]) or hex.y != int(state["blocker"]["r"])):
			empty_tile = {"q": hex.x, "r": hex.y}
			break
	assert_false(empty_tile.is_empty())
	var result: Dictionary = _apply(state, owner, {"type": "move_blocker", "q": empty_tile["q"], "r": empty_tile["r"]})
	assert_eq(result["state"]["rng"], state["rng"])


func test_the_discards_of_an_absent_player_draw_one_card_each_in_resource_order() -> void:
	var state: Dictionary = GtRig.rolled(GtRig.playing(4, {}, 18))
	var owner: String = _owner(state)
	var absent: String = "p3" if owner != "p3" else "p4"
	GtRig.give(state, absent, {"timber": 2, "clay": 1, "stone": 4})
	state["turn"]["pending"] = "discard"
	state["turn"]["source"] = "seven"
	state["turn"]["owed"] = {absent: 3}
	var present: Array = []
	for id: String in GtState.seat_order(state):
		if id != absent:
			present.append(id)
	var prng: Prng = _restore(state)
	var cards: Array = ["timber", "timber", "clay", "stone", "stone", "stone", "stone"]
	var lost: Dictionary = {}
	for _i: int in 3:
		var index: int = prng.range_int(0, cards.size() - 1)
		lost[cards[index]] = int(lost.get(cards[index], 0)) + 1
		cards.remove_at(index)
	var result: Dictionary = rules.settle(state, present)
	assert_true(CoreResult.is_ok(result), str(result))
	for resource: String in GtBank.RESOURCES:
		assert_eq(int(result["state"]["hands"][absent][resource]), int(state["hands"][absent][resource]) - int(lost.get(resource, 0)), resource)
	assert_eq(result["state"]["rng"]["state"], prng.state_text(), "one draw per card")
