extends GutTest
## Grow & Trade fulfils the shared GameRules contract: inputs are never changed, refusals carry a code and
## a message and leave the state alone, views are whitelists, damaged states are caught, and a game saved
## through core's SessionSnapshot resumes exactly.

const APP: String = "0.1.0"

var rules: GrowAndTradeRules


func before_each() -> void:
	rules = GrowAndTradeRules.new()


func _mid_game(actions: int = 160, count: int = 4, seed_value: int = 77) -> Dictionary:
	var state: Dictionary = GtRig.new_state(count, {}, seed_value)
	var bot: GtBot = GtBot.new(seed_value + 5)
	for _i: int in actions:
		if state["phase"] == "finished":
			break
		var picked: Dictionary = bot.pick(state)
		state = rules.apply(state, picked["player_id"], picked["action"])["state"]
	return state


func _code(result: Dictionary) -> String:
	return CoreResult.error_code(result)


# --- the contract -----------------------------------------------------------------------------------

func test_it_is_a_game_rules() -> void:
	assert_true(rules is GameRules)
	assert_true(rules is RefCounted)


func test_default_setup_is_a_valid_board_and_settings_have_defaults() -> void:
	var setup: Dictionary = rules.default_setup()
	assert_true(CoreResult.is_ok(GtBoard.validate(setup)))
	assert_true(CoreResult.is_ok(rules.new_game(GtRig.players(4), setup, {}, 1)))
	assert_true(CoreResult.is_ok(rules.validate_settings({})))
	assert_true(CoreResult.is_ok(rules.validate_settings({"target_points": 12})))
	assert_eq(_code(rules.validate_settings({"target_points": 99})), GtErrors.INVALID_SETTINGS)
	assert_eq(rules.describe_settings({})[0], "First to 10 points")
	assert_eq(rules.describe_settings({"target_points": 8, "bank_rate": 3})[0], "First to 8 points")


func test_new_game_does_not_change_what_it_is_given() -> void:
	var players: Array = GtRig.players(5)
	var board: Dictionary = GtRig.board()
	var settings: Dictionary = {"target_points": 9, "friendly_blocker": true}
	var hashes: Array = [players.hash(), board.hash(), settings.hash()]
	var created: Dictionary = rules.new_game(players, board, settings, 5)
	assert_true(CoreResult.is_ok(created))
	assert_eq([players.hash(), board.hash(), settings.hash()], hashes)
	created["state"]["board"]["tiles"]["desert"] = 99
	assert_eq(board.hash(), hashes[1], "the state holds its own copy of the board")


func test_new_game_refuses_bad_setups_with_a_code_and_a_message() -> void:
	var cases: Array = [
		[["p1", "p2"], {}, GtErrors.BAD_PLAYERS],
		[GtRig.players(6) + ["p7"], {}, GtErrors.BAD_PLAYERS],
		[["p1", "p1", "p2"], {}, GtErrors.BAD_PLAYERS],
		[["p1", "", "p2"], {}, GtErrors.BAD_PLAYERS],
		[GtRig.players(3), {"hand_limit": 2}, GtErrors.INVALID_SETTINGS],
		[GtRig.players(3), {"cheat": true}, GtErrors.INVALID_SETTINGS],
	]
	for case: Array in cases:
		var result: Dictionary = rules.new_game(case[0], GtRig.board(), case[1], 1)
		assert_false(result["ok"])
		assert_eq(_code(result), case[2], str(case))
		assert_false(str(result["error"]["message"]).is_empty())
	var bad_board: Dictionary = GtRig.board().duplicate(true)
	bad_board["tokens"].append(7)
	assert_eq(_code(rules.new_game(GtRig.players(3), bad_board, {}, 1)), GtBoard.INVALID_BOARD)


func test_apply_never_changes_the_state_it_is_given() -> void:
	var state: Dictionary = _mid_game()
	var bot: GtBot = GtBot.new(9)
	for _i: int in 60:
		if state["phase"] == "finished":
			break
		var before: Dictionary = state.duplicate(true)
		var picked: Dictionary = bot.pick(state)
		var result: Dictionary = rules.apply(state, picked["player_id"], picked["action"])
		assert_eq(state, before, "input of %s" % str(picked["action"]))
		state = result["state"]
		var junk: Dictionary = bot.junk(state)
		var snapshot: Dictionary = state.duplicate(true)
		assert_false(rules.apply(state, junk["player_id"], junk["action"])["ok"])
		assert_eq(state, snapshot, "a refused action leaves the state as it was")


func test_a_result_never_shares_data_with_the_input() -> void:
	var state: Dictionary = _mid_game()
	var picked: Dictionary = GtBot.new(2).pick(state)
	var result: Dictionary = rules.apply(state, picked["player_id"], picked["action"])
	result["state"]["hands"][picked["player_id"]]["timber"] = 99
	result["state"]["paths"]["x"] = "p1"
	assert_ne(state["hands"][picked["player_id"]]["timber"], 99)
	assert_false(state["paths"].has("x"))


func test_refusals_carry_ok_false_a_code_and_a_message() -> void:
	var state: Dictionary = _mid_game(80)
	var cases: Array = [
		[state["current_player"], {"type": "fly"}, ErrorCodes.UNKNOWN_ACTION],
		[state["current_player"], {"nothing": 1}, ErrorCodes.BAD_ACTION],
		[state["current_player"], {"type": 5}, ErrorCodes.BAD_ACTION],
		["stranger", {"type": "roll"}, ErrorCodes.UNKNOWN_PLAYER],
		[state["current_player"], {"type": "roll", "extra": 1}, ErrorCodes.BAD_ACTION],
	]
	for case: Array in cases:
		var result: Dictionary = rules.apply(state, case[0], case[1])
		assert_false(result["ok"], str(case))
		assert_eq(_code(result), case[2], str(case))
		assert_false(str(result["error"]["message"]).is_empty(), str(case))
		assert_false(result.has("state"), "a refusal has no state")


func test_the_wrong_player_cannot_act() -> void:
	var state: Dictionary = GtRig.playing(4, {}, 3)
	assert_eq(_code(rules.apply(state, "p2", {"type": "roll"})), GtErrors.NOT_YOUR_TURN)
	assert_eq(_code(rules.apply(state, "p1", {"type": "end_turn"})), GtErrors.NOT_ROLLED)
	var founding: Dictionary = GtRig.new_state(4, {}, 3)
	assert_eq(_code(rules.apply(founding, "p1", {"type": "roll"})), GtErrors.WRONG_PHASE)
	var corner: String = GtBoard.new(founding["board"]).corners()[0]
	assert_eq(_code(rules.apply(founding, "p2", {"type": "place_village", "corner": corner})), GtErrors.NOT_YOUR_TURN)


func test_a_finished_game_refuses_everything() -> void:
	var state: Dictionary = GtRig.playing(4, {}, 3)
	state["phase"] = "finished"
	state["winner"] = "p1"
	for id: String in GtRig.players(4):
		for action: Dictionary in [{"type": "roll"}, {"type": "end_turn"}, {"type": "accept_trade"}, {"type": "buy_card"}]:
			assert_eq(_code(rules.apply(state, id, action)), GtErrors.GAME_OVER, "%s %s" % [id, action["type"]])
	assert_eq(_code(rules.apply(state, "p1", {"type": "fly"})), ErrorCodes.UNKNOWN_ACTION, "an unknown action is still unknown")
	assert_true(CoreResult.is_ok(rules.settle(state, ["p2"])), "settle just does nothing")


func test_a_damaged_state_is_refused_not_crashed_on() -> void:
	var state: Dictionary = GtRig.playing(4, {}, 3)
	for key: String in ["hands", "rng", "turn", "players", "supply", "founding", "offer", "layout"]:
		var damaged: Dictionary = state.duplicate(true)
		damaged.erase(key)
		assert_eq(_code(rules.apply(damaged, "p1", {"type": "roll"})), GtErrors.INVALID_STATE, "without %s" % key)
		assert_eq(_code(rules.settle(damaged, ["p1"])), GtErrors.INVALID_STATE, "settle without %s" % key)
	var no_rng: Dictionary = state.duplicate(true)
	no_rng["rng"]["state"] = "nonsense"
	assert_eq(_code(rules.apply(no_rng, "p1", {"type": "roll"})), GtErrors.INVALID_STATE)


## Regression (found by the fuzz test): a Guard card sets a blocker move pending and the Largest Guard bonus
## can win the game on the spot, which used to leave the finished game with the move still pending.
func test_winning_by_playing_a_guard_leaves_nothing_pending() -> void:
	var state: Dictionary = GtRig.playing(4, {"target_points": 10}, 8)
	var owner: String = state["current_player"]
	var geometry: GtBoard = GtBoard.new(state["board"])
	var added: int = 0
	for corner: String in geometry.corners():
		if added == 3:
			break
		var free: bool = not state["buildings"].has(corner)
		for other: String in geometry.adjacent_corners(corner):
			free = free and not state["buildings"].has(other)
		if free:
			state["buildings"][corner] = {"owner": owner, "kind": "town"}
			added += 1
	state["guards_played"][owner] = 2
	for _i: int in 3:  # the card in hand and the two already played all came out of the 14 guards
		state["deck"].remove_at(state["deck"].find("guard"))
	state["cards"][owner]["held"] = ["guard"]
	var result: Dictionary = rules.apply(state, owner, {"type": "play_card", "card": "guard"})
	assert_true(CoreResult.is_ok(result), str(result))
	var next: Dictionary = result["state"]
	assert_eq(next["phase"], "finished", "2 villages + 3 towns + Largest Guard is 10 points")
	assert_eq(next["winner"], owner)
	assert_eq(next["turn"]["pending"], "")
	assert_eq(next["turn"]["source"], "")
	assert_true(CoreResult.is_ok(rules.validate_state(next)), str(rules.validate_state(next)))


# --- queries and views ---------------------------------------------------------------------------------------

func test_the_queries_work_on_a_state_and_on_a_view() -> void:
	var state: Dictionary = GtRig.new_state(4, {}, 1)
	for source: Dictionary in [state, rules.view_for(state, "p2")]:
		assert_eq(rules.current_player(source), "p1")
		assert_false(rules.is_finished(source))
		assert_eq(rules.winner(source), "")
	state["phase"] = "finished"
	state["winner"] = "p3"
	for source: Dictionary in [state, rules.view_for(state, "p1")]:
		assert_true(rules.is_finished(source))
		assert_eq(rules.winner(source), "p3")
		assert_eq(rules.current_player(source), "", "nobody is to move once it is over")


func test_a_view_is_a_whitelist_with_the_viewers_own_cards_only() -> void:
	var state: Dictionary = _mid_game(220)
	state["cards"]["p2"]["held"] = ["guard"]
	for id: String in GtRig.players(4):
		var view: Dictionary = rules.view_for(state, id)
		var allowed: Array = GtView.PUBLIC_KEYS + ["you", "hand", "my_cards", "hand_counts", "card_counts", "deck_remaining", "points"]
		for key: String in view:
			assert_true(allowed.has(key), "unexpected key %s in the view of %s" % [key, id])
		for hidden: String in ["hands", "cards", "deck", "rng"]:
			assert_false(view.has(hidden), hidden)
		assert_eq(view["you"], id)
		assert_eq(view["hand"], state["hands"][id])
		assert_eq(view["my_cards"], state["cards"][id])
	var other: Dictionary = rules.view_for(state, "p1")
	assert_eq(other["card_counts"]["p2"], 1, "others' fortune cards are only counted")
	assert_false(JSON.stringify(other).contains(state["rng"]["state"]))


func test_extra_state_fields_stay_private_until_the_view_lists_them() -> void:
	var state: Dictionary = GtRig.playing(4, {}, 3)
	state["secret_plan"] = "swap the deck"
	assert_false(rules.view_for(state, "p1").has("secret_plan"))


func test_views_are_deep_copies() -> void:
	var state: Dictionary = GtRig.playing(4, {}, 3)
	var view: Dictionary = rules.view_for(state, "p1")
	view["supply"]["timber"] = 0
	view["layout"]["tiles"].clear()
	view["hand"]["clay"] = 50
	assert_ne(state["supply"]["timber"], 0)
	assert_eq(state["layout"]["tiles"].size(), 30)
	assert_ne(state["hands"]["p1"]["clay"], 50)


# --- validate_state ---------------------------------------------------------------------------------------------

func test_valid_states_validate_and_corrupted_ones_do_not() -> void:
	var state: Dictionary = _mid_game(180)
	assert_true(CoreResult.is_ok(rules.validate_state(state)), str(rules.validate_state(state)))
	assert_true(CoreResult.is_ok(rules.validate_state(GtRig.new_state(6, {}, 2))))
	var corruptions: Dictionary = {
		"a resource created": func(s: Dictionary) -> void: s["hands"]["p1"]["timber"] += 1,
		"a negative hand": func(s: Dictionary) -> void: s["hands"]["p1"]["clay"] = -1,
		"the bank short": func(s: Dictionary) -> void: s["supply"]["wheat"] -= 1,
		"a fortune card created": func(s: Dictionary) -> void: s["deck"].append("guard"),
		"an unknown card": func(s: Dictionary) -> void: s["cards"]["p2"]["held"].append("dragon"),
		"a stranger's turn": func(s: Dictionary) -> void: s["current_player"] = "p9",
		"a building on no corner": func(s: Dictionary) -> void: s["buildings"]["nowhere"] = {"owner": "p1", "kind": "village"},
		"a path on no edge": func(s: Dictionary) -> void: s["paths"]["nowhere"] = "p1",
		"a winner in a running game": func(s: Dictionary) -> void: s["winner"] = "p1",
		"a wrecked generator": func(s: Dictionary) -> void: s["rng"]["state"] = "0,0,0,0",
		"another game's id": func(s: Dictionary) -> void: s["game_id"] = "climb_and_slither",
		"a future version": func(s: Dictionary) -> void: s["state_version"] = 2,
		"an unknown phase": func(s: Dictionary) -> void: s["phase"] = "lunch",
		"an extra field": func(s: Dictionary) -> void: s["extra"] = 1,
		"a missing hand": func(s: Dictionary) -> void: s["hands"].erase("p3"),
		"invalid settings": func(s: Dictionary) -> void: s["settings"]["target_points"] = 99,
		"the blocker in the sea": func(s: Dictionary) -> void: s["blocker"] = {"q": 99, "r": 99},
		"a bonus held by nobody who earned it": func(s: Dictionary) -> void: s["bonuses"]["longest_path"] = "p1" if s["bonuses"]["longest_path"] != "p1" else "p2",
		"a stranger in the offer": func(s: Dictionary) -> void:
			s["turn"]["rolled"] = true
			s["offer"] = {"from": s["current_player"], "give": {"timber": 1}, "want": {"clay": 1}, "to": ["p9"], "accepted": [], "declined": []},
	}
	for label: String in corruptions:
		var damaged: Dictionary = state.duplicate(true)
		corruptions[label].call(damaged)
		var checked: Dictionary = rules.validate_state(damaged)
		assert_false(checked["ok"], label)
		assert_eq(_code(checked), GtErrors.INVALID_STATE, label)


func test_a_state_with_floats_is_refused_until_it_is_normalised() -> void:
	var state: Dictionary = _mid_game(120)
	var raw: Variant = JSON.parse_string(JSON.stringify(state))
	assert_false(CoreResult.is_ok(rules.validate_state(raw)), "a raw JSON state has floats")
	var fixed: Dictionary = Envelope.normalize(raw)
	assert_eq(fixed, state)
	assert_true(CoreResult.is_ok(rules.validate_state(fixed)))


# --- save and load through core's snapshot ---------------------------------------------------------------------------

func _lobby_and_registry(player_ids: Array) -> Array:
	var registry: PlayerRegistry = PlayerRegistry.new()
	var lobby: Dictionary = LobbyLogic.create(GtState.GAME_ID, 3, 6, "p1", "Player 1", 3)
	registry.create("Player 1")
	for i: int in range(1, player_ids.size()):
		registry.create("Player %d" % (i + 1))
		lobby = LobbyLogic.apply(lobby, player_ids[i], {"type": "join", "name": "Player %d" % (i + 1)})["state"]
		lobby = LobbyLogic.apply(lobby, player_ids[i], {"type": "set_ready", "ready": true})["state"]
	lobby = LobbyLogic.apply(lobby, "p1", {"type": "start"})["state"]
	return [lobby, registry]


func _save_text(state: Dictionary, player_ids: Array) -> String:
	var parts: Array = _lobby_and_registry(player_ids)
	return SessionSnapshot.to_text(SessionSnapshot.capture(APP, GtState.GAME_ID, parts[0], parts[1], state))


func _load_state(text: String) -> Dictionary:
	var parsed: Dictionary = SessionSnapshot.from_text(text)
	assert_true(CoreResult.is_ok(parsed), str(parsed))
	var snapshot: Dictionary = parsed["snapshot"]
	var checked: Dictionary = SessionSnapshot.validate(snapshot, GtState.GAME_ID)
	assert_true(CoreResult.is_ok(checked), str(checked))
	return snapshot["game_state"]


func _play(state: Dictionary, bot_seed: int, actions: int) -> Dictionary:
	var bot: GtBot = GtBot.new(bot_seed)
	var events: Array = []
	var current: Dictionary = state
	for _i: int in actions:
		if current["phase"] == "finished":
			break
		var picked: Dictionary = bot.pick(current)
		var result: Dictionary = rules.apply(current, picked["player_id"], picked["action"])
		assert_true(CoreResult.is_ok(result), str(result))
		current = result["state"]
		events.append_array(result["events"])
	return {"state": current, "events": events}


func test_a_saved_game_loads_back_identical_and_valid() -> void:
	var players: Array = GtRig.players(5)
	var state: Dictionary = _mid_game(210, 5, 31337)
	var loaded: Dictionary = _load_state(_save_text(state, players))
	assert_eq(loaded, state)
	assert_true(CoreResult.is_ok(rules.validate_state(loaded)))


func test_a_loaded_game_continues_exactly_like_the_original() -> void:
	var players: Array = GtRig.players(4)
	for checkpoint: int in [0, 9, 60, 200]:
		var original: Dictionary = _mid_game(checkpoint, 4, 2024)
		var loaded: Dictionary = _load_state(_save_text(original, players))
		var from_original: Dictionary = _play(original, 8, 120)
		var from_loaded: Dictionary = _play(loaded, 8, 120)
		assert_eq(from_loaded["events"], from_original["events"], "same events after loading at action %d" % checkpoint)
		assert_eq(from_loaded["state"], from_original["state"], "same state after loading at action %d" % checkpoint)


func test_the_save_keeps_the_hidden_state_so_the_game_can_be_resumed() -> void:
	var players: Array = GtRig.players(3)
	var state: Dictionary = _mid_game(90, 3, 99)
	var text: String = _save_text(state, players)
	assert_true(text.contains(state["rng"]["state"]), "the generator is saved")
	var loaded: Dictionary = _load_state(text)
	assert_eq(loaded["deck"], state["deck"])
	assert_eq(loaded["hands"], state["hands"])
	assert_eq(loaded["cards"], state["cards"])


func test_huge_seeds_survive_save_and_load() -> void:
	var players: Array = GtRig.players(4)
	for seed_value: int in [9007199254740993, 4611686018427387904, -9007199254740993]:
		var state: Dictionary = _mid_game(70, 4, seed_value)
		var loaded: Dictionary = _load_state(_save_text(state, players))
		assert_eq(loaded["rng"]["seed"], str(seed_value))
		assert_eq(_play(loaded, 4, 50)["state"], _play(state, 4, 50)["state"], "seed %d" % seed_value)


func test_numbers_come_back_as_ints_after_json() -> void:
	var state: Dictionary = _mid_game(150, 4, 5)
	var loaded: Dictionary = _load_state(_save_text(state, GtRig.players(4)))
	assert_eq(typeof(loaded["turn_number"]), TYPE_INT)
	assert_eq(typeof(loaded["blocker"]["q"]), TYPE_INT)
	assert_eq(typeof(loaded["supply"]["timber"]), TYPE_INT)
	assert_eq(typeof(loaded["layout"]["tiles"][0]["token"]), TYPE_INT)
	assert_eq(typeof(loaded["hands"]["p1"]["clay"]), TYPE_INT)


func test_a_save_taken_mid_trade_or_mid_discard_resumes_there() -> void:
	var players: Array = GtRig.players(4)
	var state: Dictionary = GtRig.rolled(GtRig.playing(4, {}, 6))
	var owner: String = state["current_player"]
	GtRig.give(state, owner, {"timber": 2})
	GtRig.give(state, "p3" if owner != "p3" else "p4", {"clay": 1})
	state["offer"] = {"from": owner, "give": {"timber": 1}, "want": {"clay": 1}, "to": [], "accepted": [], "declined": []}
	var loaded: Dictionary = _load_state(_save_text(state, players))
	assert_eq(loaded["offer"], state["offer"])
	var seat: String = "p3" if owner != "p3" else "p4"
	var accepted: Dictionary = rules.apply(loaded, seat, {"type": "accept_trade"})
	assert_true(CoreResult.is_ok(accepted), str(accepted))
	var discarding: Dictionary = GtRig.rolled(GtRig.playing(4, {}, 6))
	GtRig.give(discarding, "p2", {"timber": 4, "stone": 4})
	discarding["turn"]["pending"] = "discard"
	discarding["turn"]["source"] = "seven"
	discarding["turn"]["owed"] = {"p2": 4}
	var reloaded: Dictionary = _load_state(_save_text(discarding, players))
	assert_eq(reloaded["turn"]["owed"], {"p2": 4})
	assert_true(CoreResult.is_ok(rules.apply(reloaded, "p2", {"type": "discard", "resources": {"timber": 4}})))


func test_a_save_edited_to_cheat_is_refused_by_validation() -> void:
	var players: Array = GtRig.players(4)
	var cheats: Dictionary = {
		"give yourself wheat": func(s: Dictionary) -> void: s["hands"]["p1"]["wheat"] += 5,
		"win without the points": func(s: Dictionary) -> void:
			s["phase"] = "finished"
			s["winner"] = "p1",
		"teleport a building": func(s: Dictionary) -> void: s["buildings"]["9,9|9,10|10,9"] = {"owner": "p1", "kind": "town"},
		"a sixth town": func(s: Dictionary) -> void:
			for i: int in 6:
				s["buildings"]["x%d" % i] = {"owner": "p1", "kind": "town"},
	}
	for label: String in cheats:
		var state: Dictionary = _mid_game(140, 4, 21)
		var loaded: Dictionary = _load_state(_save_text(state, players))
		cheats[label].call(loaded)
		assert_eq(_code(rules.validate_state(loaded)), GtErrors.INVALID_STATE, label)
