extends GutTest
## Bugs found by the adversarial review of the Grow & Trade rules, each pinned by a test.

var rules: GrowAndTradeRules = GrowAndTradeRules.new()


func _new(count: int = 3) -> Dictionary:
	var ids: Array = []
	for i: int in count:
		ids.append(["a", "b", "c", "d", "e", "f"][i])
	return rules.new_game(ids, rules.default_setup(), {}, 11)["state"]


func _playing() -> Dictionary:
	var state: Dictionary = _new()
	state["phase"] = "playing"
	state["founding"] = {}
	state["turn"]["rolled"] = true
	state["turn"]["dice"] = [3, 4]
	return state


## play_card with a card that is not text used to be a script error (int == String), not BAD_ACTION.
func test_a_card_that_is_not_text_is_a_bad_action() -> void:
	var state: Dictionary = _playing()
	for card: Variant in [5, null, [], {}, 1.5, true]:
		var r: Dictionary = rules.apply(state, "a", {"type": "play_card", "card": card})
		assert_eq(CoreResult.error_code(r), ErrorCodes.BAD_ACTION, "card %s" % str(card))


func test_a_huge_number_in_an_id_is_just_not_on_the_board() -> void:
	var state: Dictionary = _new()
	var r: Dictionary = rules.apply(state, "a", {"type": "place_village", "corner": "99999999999999999999,0|0,0|1,1"})
	assert_eq(CoreResult.error_code(r), GtErrors.BAD_PLACEMENT)
	r = rules.apply(state, "a", {"type": "place_village", "corner": "-0,0|0,0|1,1"})
	assert_eq(CoreResult.error_code(r), GtErrors.BAD_PLACEMENT)


## settle() skips an absent placer during founding; the state it makes must still validate.
func test_settle_in_founding_gives_a_valid_state() -> void:
	var state: Dictionary = _new()
	var r: Dictionary = rules.settle(state, ["b", "c"])
	assert_true(CoreResult.is_ok(r))
	assert_eq(r["state"]["current_player"], "b")
	assert_true(CoreResult.is_ok(rules.validate_state(r["state"])), str(rules.validate_state(r["state"])))


func test_settle_between_a_village_and_its_path_gives_a_valid_state() -> void:
	var state: Dictionary = _new()
	var board: GtBoard = GtBoard.new(state["board"])
	var placed: Dictionary = rules.apply(state, "a", {"type": "place_village", "corner": board.corners()[0]})
	assert_true(CoreResult.is_ok(placed))
	var r: Dictionary = rules.settle(placed["state"], ["b", "c"])
	assert_true(CoreResult.is_ok(r))
	assert_eq(r["state"]["current_player"], "b")
	assert_true(CoreResult.is_ok(rules.validate_state(r["state"])), str(rules.validate_state(r["state"])))


func test_settle_late_in_founding_moves_on_or_starts_play_and_validates() -> void:
	# three players: the order is a b c c b a
	var state: Dictionary = _new()
	state["founding"]["index"] = 4
	state["current_player"] = "b"
	var moved: Dictionary = rules.settle(state, ["a", "c"])
	assert_true(CoreResult.is_ok(moved))
	assert_eq(moved["state"]["phase"], "founding")
	assert_eq(moved["state"]["current_player"], "a")
	assert_true(CoreResult.is_ok(rules.validate_state(moved["state"])))
	state["founding"]["index"] = 5
	state["current_player"] = "a"
	var started: Dictionary = rules.settle(state, ["b", "c"])
	assert_true(CoreResult.is_ok(started))
	assert_eq(started["state"]["phase"], "playing")
	assert_eq(started["state"]["current_player"], "b")
	assert_true(CoreResult.is_ok(rules.validate_state(started["state"])), str(rules.validate_state(started["state"])))


## A win in the middle of a trade drops the offer and says so.
func test_a_win_with_an_open_offer_cancels_it_with_an_event() -> void:
	var state: Dictionary = _playing()
	state["buildings"]["x"] = {"owner": "a", "kind": "town"}  # not a real corner; only points() reads it
	state["cards"]["a"]["held"] = ["point", "point", "point", "point", "point", "point", "point", "point"]
	state["offer"] = {"from": "a", "give": {"timber": 1}, "want": {"clay": 1}, "to": [], "accepted": [], "declined": []}
	var events: Array = []
	GtScore.finish_if_won(state, "a", events)
	assert_eq(state["phase"], "finished")
	assert_true(state["offer"].is_empty())
	var types: Array = events.map(func(e: Dictionary) -> String: return e["type"])
	assert_eq(types, ["offer_cancelled", "won"])
