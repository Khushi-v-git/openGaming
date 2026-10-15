extends GutTest
## GtView: each player sees their own hand and cards and nothing hidden of anybody else's.

const IDS: Array = ["a", "b", "c"]
const SEED: int = 987654321


func _new() -> Dictionary:
	return GtSetup.new_game(IDS, GtBoard.load_file()["board"], {}, SEED)["state"]


## Mid-game: distinctive hands and cards for a and b, c empty-handed.
func _mid_game() -> Dictionary:
	var state: Dictionary = _new()
	state["phase"] = "playing"
	state["founding"] = {}
	_give(state, "a", {"timber": 2, "wheat": 1})
	_give(state, "b", {"clay": 3, "stone": 4})
	_deal(state, "a", "held", "guard")
	_deal(state, "a", "fresh", "point")
	_deal(state, "b", "held", "point")
	_deal(state, "b", "held", "sweep")
	return state


func _give(state: Dictionary, player: String, hand: Dictionary) -> void:
	for resource: String in hand:
		state["hands"][player][resource] += hand[resource]
		state["supply"][resource] -= hand[resource]


func _deal(state: Dictionary, player: String, list: String, card: String) -> void:
	(state["deck"] as Array).erase(card)
	state["cards"][player][list].append(card)


func _keys_anywhere(value: Variant, found: Array) -> void:
	if value is Dictionary:
		for key: Variant in value:
			found.append(key)
			_keys_anywhere(value[key], found)
	elif value is Array:
		for item: Variant in value:
			_keys_anywhere(item, found)


# --- what a player sees ------------------------------------------------------------------------------------

func test_a_player_sees_their_own_hand_and_cards() -> void:
	var state: Dictionary = _mid_game()
	var view: Dictionary = GtView.view_for(state, "a")
	assert_eq(view["you"], "a")
	assert_eq(view["hand"], state["hands"]["a"])
	assert_eq(view["my_cards"], {"held": ["guard"], "fresh": ["point"]})
	assert_eq(view["hand_counts"], {"a": 3, "b": 7, "c": 0})
	assert_eq(view["card_counts"], {"a": 2, "b": 2, "c": 0})
	assert_eq(view["deck_remaining"], 21)


func test_nothing_hidden_leaks_into_any_view() -> void:
	var state: Dictionary = _mid_game()
	for id: String in IDS:
		var text: String = JSON.stringify(GtView.view_for(state, id))
		var keys: Array = []
		var parsed: Dictionary = JSON.parse_string(text)
		parsed.erase("config")  # config.deck is the public composition (type and count), not the shuffled order
		_keys_anywhere(parsed, keys)
		for hidden: String in ["hands", "cards", "deck", "rng"]:
			assert_false(keys.has(hidden), "%s's view has a '%s' key" % [id, hidden])
		assert_false(text.contains(state["rng"]["seed"]), "the seed")
		assert_false(text.contains(state["rng"]["state"]), "the generator state")
		assert_false(text.contains(JSON.stringify(state["deck"])), "the deck order")
		assert_eq(text.count("\"held\""), 1, "only the viewer's own card record (%s)" % id)


func test_others_hands_and_cards_are_only_counts() -> void:
	var state: Dictionary = _mid_game()
	var view_c: Dictionary = GtView.view_for(state, "c")
	assert_eq(view_c["hand"], GtBank.empty_hand())
	assert_eq(view_c["my_cards"], {"held": [], "fresh": []})
	assert_eq(view_c["hand_counts"]["b"], 7)
	assert_eq(view_c["card_counts"]["b"], 2)
	assert_false(view_c.has("revealed_cards"))


func test_points_hide_other_players_point_cards_until_the_end() -> void:
	var state: Dictionary = _mid_game()
	assert_eq(GtView.view_for(state, "a")["points"], {"a": 1, "b": 0, "c": 0}, "a counts their own fresh point card")
	assert_eq(GtView.view_for(state, "b")["points"], {"a": 0, "b": 1, "c": 0})
	assert_eq(GtView.view_for(state, "c")["points"], {"a": 0, "b": 0, "c": 0})


func test_a_finished_game_reveals_every_card_and_the_full_tally() -> void:
	var state: Dictionary = _mid_game()
	state["phase"] = "finished"
	state["winner"] = "a"
	var view: Dictionary = GtView.view_for(state, "c")
	assert_eq(view["points"], {"a": 1, "b": 1, "c": 0})
	assert_eq(view["revealed_cards"]["b"], {"held": ["point", "sweep"], "fresh": []})
	assert_eq(view["revealed_cards"]["a"], {"held": ["guard"], "fresh": ["point"]})
	assert_false(JSON.stringify(view).contains(JSON.stringify(state["deck"])), "the deck order stays secret even then")


func test_a_spectator_gets_the_public_part_only() -> void:
	var state: Dictionary = _mid_game()
	var view: Dictionary = GtView.view_for(state, "watcher")
	assert_eq(view["you"], "watcher")
	assert_false(view.has("hand"))
	assert_false(view.has("my_cards"))
	assert_eq(view["hand_counts"], {"a": 3, "b": 7, "c": 0})
	assert_eq(view["phase"], "playing")


# --- shape --------------------------------------------------------------------------------------------------

func test_the_public_keys_are_all_there() -> void:
	var view: Dictionary = GtView.view_for(_mid_game(), "a")
	for key: String in GtView.PUBLIC_KEYS:
		assert_true(view.has(key), key)


func test_a_view_does_not_share_anything_with_the_state() -> void:
	var state: Dictionary = _mid_game()
	var before: Dictionary = state.duplicate(true)
	var view: Dictionary = GtView.view_for(state, "a")
	view["hand"]["timber"] = 99
	view["my_cards"]["held"].append("bogus")
	view["supply"]["clay"] = 0
	view["players"].clear()
	view["layout"]["tiles"].clear()
	view["board"]["hexes"].clear()
	view["bonuses"]["longest_path"] = "zed"
	assert_eq(state, before)


func test_views_survive_json() -> void:
	var view: Dictionary = GtView.view_for(_mid_game(), "b")
	var round_trip: Variant = JSON.parse_string(JSON.stringify(view))
	assert_eq(round_trip["you"], "b")
	assert_eq(round_trip["my_cards"], view["my_cards"])
	assert_eq(round_trip["current_player"], "a")


func test_the_game_queries_can_be_answered_from_a_view() -> void:
	var state: Dictionary = _mid_game()
	state["current_player"] = "b"
	var view: Dictionary = GtView.view_for(state, "c")
	assert_eq(view["phase"], "playing")
	assert_eq(view["current_player"], "b")
	assert_eq(view["winner"], "")
	state["phase"] = "finished"
	state["winner"] = "b"
	var finished: Dictionary = GtView.view_for(state, "c")
	assert_eq(finished["phase"], "finished")
	assert_eq(finished["winner"], "b")


func test_the_offer_is_public() -> void:
	var state: Dictionary = _mid_game()
	state["offer"] = {"from": "a", "give": {"timber": 1}, "want": {"clay": 1}, "to": ["b"], "accepted": [], "declined": []}
	assert_eq(GtView.view_for(state, "c")["offer"], state["offer"])


func test_a_fresh_game_view_is_the_same_size_for_everyone() -> void:
	var state: Dictionary = _new()
	var sizes: Array = []
	for id: String in IDS:
		sizes.append(GtView.view_for(state, id).size())
	assert_eq(sizes[0], sizes[1])
	assert_eq(sizes[1], sizes[2])
