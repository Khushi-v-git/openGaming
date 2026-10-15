extends GutTest
## Costs, bank supply, payouts with shortages, discards and bank trades. Headless, no scene, no network.

var config: Dictionary


func before_each() -> void:
	var loaded: Dictionary = GtBank.load_config()
	assert_true(CoreResult.is_ok(loaded), str(loaded))
	config = loaded["config"]


func _hand(timber: int = 0, clay: int = 0, fleece: int = 0, wheat: int = 0, stone: int = 0) -> Dictionary:
	return {"timber": timber, "clay": clay, "fleece": fleece, "wheat": wheat, "stone": stone}


func _total(supply: Dictionary, gains: Dictionary) -> int:
	var sum: int = GtBank.hand_count(supply)
	for player_id: Variant in gains:
		sum += GtBank.hand_count(gains[player_id])
	return sum


# --- config -----------------------------------------------------------------------------------------

func test_the_shipped_config_loads_with_the_documented_numbers() -> void:
	assert_eq(config["costs"]["path"], {"timber": 1, "clay": 1})
	assert_eq(config["costs"]["village"], {"timber": 1, "clay": 1, "fleece": 1, "wheat": 1})
	assert_eq(config["costs"]["town"], {"stone": 3, "wheat": 2})
	assert_eq(config["costs"]["card"], {"fleece": 1, "wheat": 1, "stone": 1})
	assert_eq(config["pieces"], {"path": 15, "village": 5, "town": 4})
	var deck_total: int = 0
	for entry: Dictionary in config["deck"]:
		deck_total += int(entry["count"])
	assert_eq(deck_total, 25)


func test_bank_supply_depends_on_the_player_count() -> void:
	for n: int in [3, 4]:
		assert_eq(GtBank.supply_for(config, n)["supply"], _hand(24, 24, 24, 24, 24), "%d players" % n)
	for n: int in [5, 6]:
		assert_eq(GtBank.supply_for(config, n)["supply"], _hand(30, 30, 30, 30, 30), "%d players" % n)


func test_unsupported_player_counts_are_refused() -> void:
	for n: int in [0, 1, 2, 7]:
		assert_eq(CoreResult.error_code(GtBank.supply_for(config, n)), GtBank.UNSUPPORTED_PLAYER_COUNT, "%d players" % n)


func _raw() -> Dictionary:
	var file: FileAccess = FileAccess.open(GtBank.DEFAULT_PATH, FileAccess.READ)
	return JSON.parse_string(file.get_as_text())


func test_bad_config_is_refused_with_a_clear_code() -> void:
	var mutations: Array[Callable] = [
		func(d: Dictionary) -> void: d["costs"].erase("town"),
		func(d: Dictionary) -> void: d["costs"]["path"] = {"gold": 1},
		func(d: Dictionary) -> void: d["costs"]["path"] = {"timber": 0},
		func(d: Dictionary) -> void: d["pieces"]["village"] = 0,
		func(d: Dictionary) -> void: d["bank_supply"].pop_back(),
		func(d: Dictionary) -> void: d["bank_supply"].append({"min_players": 4, "max_players": 4, "per_resource": 9}),
		func(d: Dictionary) -> void: d["deck"][0]["type"] = "jester",
		func(d: Dictionary) -> void: d["deck"][1]["type"] = "guard",
		func(d: Dictionary) -> void: d["deck"][0]["count"] = 0,
		func(d: Dictionary) -> void: d["deck"] = [],
	]
	for i: int in mutations.size():
		var data: Dictionary = _raw()
		mutations[i].call(data)
		assert_eq(CoreResult.error_code(GtBank.validate_config(data)), GtBank.INVALID_CONFIG, "mutation %d" % i)


func test_validating_does_not_change_its_input() -> void:
	var data: Dictionary = _raw()
	var before: Dictionary = data.duplicate(true)
	GtBank.validate_config(data)
	assert_eq(data, before)


func test_a_missing_file_is_refused() -> void:
	assert_eq(CoreResult.error_code(GtBank.load_config("res://games/grow_and_trade/data/nope.json")), GtBank.INVALID_CONFIG)


# --- affording and paying -----------------------------------------------------------------------------

func test_can_afford_checks_every_resource() -> void:
	var village: Dictionary = config["costs"]["village"]
	assert_true(GtBank.can_afford(_hand(1, 1, 1, 1), village))
	assert_true(GtBank.can_afford(_hand(3, 3, 3, 3, 3), village))
	assert_false(GtBank.can_afford(_hand(1, 1, 1, 0), village))
	assert_false(GtBank.can_afford({}, village))
	assert_true(GtBank.can_afford({}, {}), "free is always affordable")


func test_pay_returns_a_new_hand_and_leaves_the_input_alone() -> void:
	var hand: Dictionary = _hand(2, 2, 1, 1, 0)
	var before: Dictionary = hand.duplicate(true)
	var result: Dictionary = GtBank.pay(hand, config["costs"]["village"])
	assert_true(CoreResult.is_ok(result))
	assert_eq(result["hand"], _hand(1, 1, 0, 0, 0))
	assert_eq(hand, before)


func test_pay_refuses_what_the_hand_cannot_cover() -> void:
	var hand: Dictionary = _hand(1, 1, 0, 1, 0)
	var result: Dictionary = GtBank.pay(hand, config["costs"]["village"])
	assert_eq(CoreResult.error_code(result), GtBank.CANNOT_AFFORD)
	assert_eq(hand, _hand(1, 1, 0, 1, 0))


func test_pay_fills_in_missing_keys() -> void:
	var result: Dictionary = GtBank.pay({"timber": 1, "clay": 1}, config["costs"]["path"])
	assert_eq(result["hand"], _hand())


func test_add_and_hand_count() -> void:
	var hand: Dictionary = GtBank.add(_hand(1), {"stone": 2, "clay": 1})
	assert_eq(hand, _hand(1, 1, 0, 0, 2))
	assert_eq(GtBank.hand_count(hand), 4)
	assert_eq(GtBank.hand_count({}), 0)


# --- paying out a roll --------------------------------------------------------------------------------

func test_a_payout_with_enough_in_the_bank_pays_everyone_in_full() -> void:
	var supply: Dictionary = _hand(5, 5, 5, 5, 5)
	var result: Dictionary = GtBank.payout(supply, {"b": {"timber": 2, "wheat": 1}, "a": {"timber": 1}})
	assert_eq(result["gains"]["a"], {"timber": 1})
	assert_eq(result["gains"]["b"], {"timber": 2, "wheat": 1})
	assert_eq(result["supply"], _hand(2, 5, 5, 4, 5))
	assert_eq(result["shortages"], [])


func test_a_single_claimant_gets_what_is_left_when_the_bank_runs_short() -> void:
	var result: Dictionary = GtBank.payout(_hand(0, 3), {"a": {"clay": 5}})
	assert_eq(result["gains"]["a"], {"clay": 3})
	assert_eq(result["supply"]["clay"], 0)
	assert_eq(result["shortages"].size(), 1)
	var event: Dictionary = result["shortages"][0]
	assert_eq(event["type"], "shortage")
	assert_eq(event["resource"], "clay")
	assert_eq(event["owed"], 5)
	assert_eq(event["available"], 3)
	assert_eq(event["claimants"], ["a"])
	assert_eq(event["paid"], 3)


func test_several_claimants_get_none_of_a_short_resource() -> void:
	var result: Dictionary = GtBank.payout(_hand(3), {"a": {"timber": 2}, "b": {"timber": 2}})
	assert_eq(result["gains"]["a"], {})
	assert_eq(result["gains"]["b"], {})
	assert_eq(result["supply"]["timber"], 3, "the bank keeps what it has")
	assert_eq(result["shortages"][0]["claimants"], ["a", "b"])
	assert_eq(result["shortages"][0]["paid"], 0)


func test_exactly_enough_is_not_a_shortage() -> void:
	var result: Dictionary = GtBank.payout(_hand(4), {"a": {"timber": 2}, "b": {"timber": 2}})
	assert_eq(result["gains"]["a"], {"timber": 2})
	assert_eq(result["gains"]["b"], {"timber": 2})
	assert_eq(result["supply"]["timber"], 0)
	assert_eq(result["shortages"], [])


func test_other_resources_are_paid_normally_during_a_shortage() -> void:
	var supply: Dictionary = _hand(1, 9, 9, 9, 9)
	var result: Dictionary = GtBank.payout(supply, {"a": {"timber": 2, "clay": 1}, "b": {"timber": 1, "wheat": 2}})
	assert_eq(result["gains"]["a"], {"clay": 1})
	assert_eq(result["gains"]["b"], {"wheat": 2})
	assert_eq(result["supply"], _hand(1, 8, 9, 7, 9))
	assert_eq(result["shortages"].size(), 1)


func test_an_empty_bank_pays_a_lone_claimant_nothing_but_reports_it() -> void:
	var result: Dictionary = GtBank.payout(_hand(), {"a": {"stone": 1}})
	assert_eq(result["gains"]["a"], {})
	assert_eq(result["shortages"][0]["paid"], 0)


func test_a_payout_never_changes_its_inputs() -> void:
	var supply: Dictionary = _hand(1, 2, 3, 4, 5)
	var owed: Dictionary = {"a": {"timber": 3}, "b": {"stone": 1}}
	var supply_before: Dictionary = supply.duplicate(true)
	var owed_before: Dictionary = owed.duplicate(true)
	GtBank.payout(supply, owed)
	assert_eq(supply, supply_before)
	assert_eq(owed, owed_before)


func test_payout_does_not_depend_on_dictionary_order() -> void:
	var one: Dictionary = GtBank.payout(_hand(3), {"a": {"timber": 2}, "b": {"timber": 2}, "c": {"timber": 1}})
	var two: Dictionary = GtBank.payout(_hand(3), {"c": {"timber": 1}, "b": {"timber": 2}, "a": {"timber": 2}})
	assert_eq(one["shortages"], two["shortages"])
	assert_eq(one["supply"], two["supply"])


func test_property_resources_are_never_created_or_destroyed_by_payouts() -> void:
	var prng: Prng = Prng.new(20260515)
	var players: Array[String] = ["p1", "p2", "p3", "p4", "p5", "p6"]
	var shortages_seen: int = 0
	for round_index: int in 600:
		var supply: Dictionary = {}
		for resource: String in GtBank.RESOURCES:
			supply[resource] = prng.range_int(0, 12)
		var owed: Dictionary = {}
		for player_id: String in players:
			if prng.range_int(0, 2) == 0:
				continue
			var entry: Dictionary = {}
			for resource: String in GtBank.RESOURCES:
				if prng.range_int(0, 2) == 0:
					entry[resource] = prng.range_int(1, 4)
			owed[player_id] = entry
		var before: int = GtBank.hand_count(supply)
		var result: Dictionary = GtBank.payout(supply, owed)
		assert_eq(_total(result["supply"], result["gains"]), before, "round %d conserves resources" % round_index)
		for resource: String in GtBank.RESOURCES:
			assert_true(int(result["supply"][resource]) >= 0, "round %d: %s never goes negative" % [round_index, resource])
		for player_id: Variant in result["gains"]:
			for resource: Variant in result["gains"][player_id]:
				assert_true(int(result["gains"][player_id][resource]) <= int(owed[player_id][resource]), "never pays more than owed")
		shortages_seen += result["shortages"].size()
	assert_gt(shortages_seen, 50, "the property run really exercised shortages")


# --- the 7: discarding --------------------------------------------------------------------------------

func test_discard_count_is_half_rounded_down_above_the_limit() -> void:
	assert_eq(GtBank.discard_count(7, 7), 0, "exactly the limit keeps everything")
	assert_eq(GtBank.discard_count(0, 7), 0)
	assert_eq(GtBank.discard_count(8, 7), 4)
	assert_eq(GtBank.discard_count(9, 7), 4)
	assert_eq(GtBank.discard_count(15, 7), 7)
	assert_eq(GtBank.discard_count(6, 5), 3)


func test_a_valid_discard_removes_exactly_the_required_cards() -> void:
	var hand: Dictionary = _hand(3, 2, 1, 2, 1)  # 9 cards, limit 7: discard 4
	var result: Dictionary = GtBank.apply_discard(hand, {"timber": 2, "wheat": 2}, 7)
	assert_true(CoreResult.is_ok(result), str(result))
	assert_eq(result["hand"], _hand(1, 2, 1, 0, 1))
	assert_eq(hand, _hand(3, 2, 1, 2, 1))


func test_bad_discards_are_refused() -> void:
	var hand: Dictionary = _hand(3, 2, 1, 2, 1)
	for bad: Dictionary in [{}, {"timber": 3}, {"timber": 5}, {"stone": 2, "timber": 2}, {"gold": 4}, {"timber": -1, "clay": 5}]:
		assert_eq(CoreResult.error_code(GtBank.apply_discard(hand, bad, 7)), GtBank.BAD_DISCARD, str(bad))
	assert_eq(CoreResult.error_code(GtBank.apply_discard(_hand(2, 2, 2, 1), {"timber": 1}, 7)), GtBank.BAD_DISCARD, "a hand within the limit discards nothing")
	assert_true(CoreResult.is_ok(GtBank.apply_discard(_hand(2, 2, 2, 1), {}, 7)))


# --- bank trades ------------------------------------------------------------------------------------------

func test_bank_rates() -> void:
	assert_eq(GtBank.bank_rate([], "timber", 4), 4)
	assert_eq(GtBank.bank_rate(["any"], "timber", 4), 3)
	assert_eq(GtBank.bank_rate(["clay"], "timber", 4), 4, "another resource's harbor does not help")
	assert_eq(GtBank.bank_rate(["clay"], "clay", 4), 2)
	assert_eq(GtBank.bank_rate(["any", "clay"], "clay", 4), 2)
	assert_eq(GtBank.bank_rate(["any", "clay"], "wheat", 4), 3)
	assert_eq(GtBank.bank_rate([], "timber", 3), 3, "the no-harbor-needed setting")
	assert_eq(GtBank.bank_rate(["any"], "timber", 3), 3)


func test_a_bank_trade_moves_cards_both_ways() -> void:
	var hand: Dictionary = _hand(4)
	var supply: Dictionary = _hand(5, 5, 5, 5, 5)
	var result: Dictionary = GtBank.bank_trade(hand, supply, "timber", "stone", 4)
	assert_true(CoreResult.is_ok(result), str(result))
	assert_eq(result["hand"], _hand(0, 0, 0, 0, 1))
	assert_eq(result["supply"], _hand(9, 5, 5, 5, 4))
	assert_eq(hand, _hand(4))
	assert_eq(supply, _hand(5, 5, 5, 5, 5))


func test_bank_trades_conserve_resources() -> void:
	var prng: Prng = Prng.new(77)
	var hand: Dictionary = _hand(6, 6, 6, 6, 6)
	var supply: Dictionary = _hand(10, 10, 10, 10, 10)
	var total: int = GtBank.hand_count(hand) + GtBank.hand_count(supply)
	for i: int in 400:
		var give: String = GtBank.RESOURCES[prng.range_int(0, 4)]
		var take: String = GtBank.RESOURCES[prng.range_int(0, 4)]
		var rate: int = [4, 3, 2][prng.range_int(0, 2)]
		var result: Dictionary = GtBank.bank_trade(hand, supply, give, take, rate)
		if CoreResult.is_ok(result):
			hand = result["hand"]
			supply = result["supply"]
		assert_eq(GtBank.hand_count(hand) + GtBank.hand_count(supply), total)
		for resource: String in GtBank.RESOURCES:
			assert_true(int(hand[resource]) >= 0 and int(supply[resource]) >= 0)


func test_bad_bank_trades_are_refused_and_change_nothing() -> void:
	var hand: Dictionary = _hand(4, 1)
	var supply: Dictionary = _hand(5, 5, 5, 5, 0)
	assert_eq(CoreResult.error_code(GtBank.bank_trade(hand, supply, "timber", "timber", 4)), GtBank.SAME_RESOURCE)
	assert_eq(CoreResult.error_code(GtBank.bank_trade(hand, supply, "gold", "timber", 4)), GtBank.UNKNOWN_RESOURCE)
	assert_eq(CoreResult.error_code(GtBank.bank_trade(hand, supply, "timber", "gold", 4)), GtBank.UNKNOWN_RESOURCE)
	assert_eq(CoreResult.error_code(GtBank.bank_trade(hand, supply, "clay", "timber", 4)), GtBank.CANNOT_AFFORD)
	assert_eq(CoreResult.error_code(GtBank.bank_trade(hand, supply, "timber", "stone", 4)), GtBank.BANK_EMPTY)
	assert_eq(hand, _hand(4, 1))
	assert_eq(supply, _hand(5, 5, 5, 5, 0))
