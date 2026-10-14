extends GutTest
## A game saved through core's SessionSnapshot, written as text (and as a file), loaded back
## and continued must play out exactly like the original: same dice, same events, same end.

const ROLL: Dictionary = {"type": "roll"}
const APP: String = "0.1.0"
const SAVE_PATH: String = "user://test_saves/climb_save.json"

var rules: ClimbAndSlitherRules


func before_each() -> void:
	rules = ClimbAndSlitherRules.new()


func after_each() -> void:
	for path: String in [SAVE_PATH, SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://test_saves")


## A lobby (the part of a save that core owns) for the same players as the game.
func _lobby_and_registry(player_ids: Array) -> Array:
	var registry: PlayerRegistry = PlayerRegistry.new()
	var lobby: Dictionary = LobbyLogic.create(ClimbAndSlitherRules.GAME_ID, 2, 4, "p1", "Player 1", 2)
	registry.create("Player 1")
	for i: int in range(1, player_ids.size()):
		registry.create("Player %d" % (i + 1))
		lobby = LobbyLogic.apply(lobby, player_ids[i], {"type": "join", "name": "Player %d" % (i + 1)})["state"]
		lobby = LobbyLogic.apply(lobby, player_ids[i], {"type": "set_ready", "ready": true})["state"]
	lobby = LobbyLogic.apply(lobby, "p1", {"type": "start"})["state"]
	return [lobby, registry]


func _save_text(state: Dictionary, player_ids: Array) -> String:
	var parts: Array = _lobby_and_registry(player_ids)
	return SessionSnapshot.to_text(SessionSnapshot.capture(APP, ClimbAndSlitherRules.GAME_ID, parts[0], parts[1], state))


func _load_state(text: String) -> Dictionary:
	var parsed: Dictionary = SessionSnapshot.from_text(text)
	assert_true(CoreResult.is_ok(parsed), str(parsed))
	var snapshot: Dictionary = parsed["snapshot"]
	var checked: Dictionary = SessionSnapshot.validate(snapshot, ClimbAndSlitherRules.GAME_ID)
	assert_true(CoreResult.is_ok(checked), str(checked))
	return snapshot["game_state"]


func _play(state: Dictionary, rolls: int) -> Dictionary:
	var events: Array = []
	var current: Dictionary = state
	for _i: int in rolls:
		if current["phase"] == "finished":
			break
		var result: Dictionary = rules.apply(current, current["current_player"], ROLL)
		assert_true(CoreResult.is_ok(result), str(result))
		current = result["state"]
		events.append_array(result["events"])
	return {"state": current, "events": events}


# --- the round trip ----------------------------------------------------------------------------

func test_a_saved_game_loads_back_identical_and_valid() -> void:
	var players: Array = ["p1", "p2", "p3"]
	var state: Dictionary = _play(rules.new_game(players, ClimbRig.classic(), {"extra_turn_on_six": true}, 31337)["state"], 17)["state"]
	var loaded: Dictionary = _load_state(_save_text(state, players))
	assert_eq(loaded, state)
	assert_true(CoreResult.is_ok(rules.validate_state(loaded)))


func test_a_loaded_game_continues_exactly_like_the_original() -> void:
	var players: Array = ["p1", "p2", "p3", "p4"]
	for checkpoint: int in [0, 1, 2, 5, 17, 40]:
		var original: Dictionary = _play(rules.new_game(players, ClimbRig.classic(), {"extra_turn_on_six": true, "dice_count": 2}, 2024)["state"], checkpoint)["state"]
		var loaded: Dictionary = _load_state(_save_text(original, players))
		var from_original: Dictionary = _play(original, 80)
		var from_loaded: Dictionary = _play(loaded, 80)
		assert_eq(from_loaded["events"], from_original["events"], "same events after loading at roll %d" % checkpoint)
		assert_eq(from_loaded["state"], from_original["state"], "same state after loading at roll %d" % checkpoint)


func test_saving_loading_and_saving_again_gives_the_same_text() -> void:
	var players: Array = ["p1", "p2"]
	var state: Dictionary = _play(rules.new_game(players, ClimbRig.classic(), {}, 8)["state"], 11)["state"]
	var first: Dictionary = SessionSnapshot.from_text(_save_text(state, players))["snapshot"]
	var again: String = SessionSnapshot.to_text(first)
	assert_eq(SessionSnapshot.from_text(again)["snapshot"], first)


func test_the_game_state_inside_a_save_carries_the_generator_so_the_dice_continue() -> void:
	var players: Array = ["p1", "p2"]
	var state: Dictionary = _play(rules.new_game(players, ClimbRig.classic(), {}, 99)["state"], 6)["state"]
	var text: String = _save_text(state, players)
	assert_true(text.contains(state["rng"]["state"]), "host-side saves keep the generator state")
	var loaded: Dictionary = _load_state(text)
	assert_eq(loaded["rng"], state["rng"])


func test_huge_seeds_survive_save_and_load() -> void:
	var players: Array = ["p1", "p2"]
	for seed_value: int in [9007199254740993, 4611686018427387904, -9007199254740993]:
		var state: Dictionary = _play(rules.new_game(players, ClimbRig.classic(), {}, seed_value)["state"], 9)["state"]
		var loaded: Dictionary = _load_state(_save_text(state, players))
		assert_eq(loaded["rng"]["seed"], str(seed_value))
		assert_eq(_play(loaded, 30)["state"], _play(state, 30)["state"], "seed %d" % seed_value)


func test_numbers_come_back_as_ints_after_json() -> void:
	var players: Array = ["p1", "p2"]
	var state: Dictionary = _play(rules.new_game(players, ClimbRig.classic(), {"dice_count": 2}, 5)["state"], 4)["state"]
	var loaded: Dictionary = _load_state(_save_text(state, players))
	for id: String in loaded["positions"]:
		assert_eq(typeof(loaded["positions"][id]), TYPE_INT)
	assert_eq(typeof(loaded["turn_number"]), TYPE_INT)
	assert_eq(typeof(loaded["last_roll"]["dice"][0]), TYPE_INT)
	assert_eq(typeof(loaded["board"]["snakes"][0]["from"]), TYPE_INT)


# --- special moments ------------------------------------------------------------------------------

func test_a_save_with_a_pending_extra_turn_keeps_it() -> void:
	var players: Array = ["p1", "p2"]
	var state: Dictionary = ClimbRig.game([6, 3], players, {"extra_turn_on_six": true}, {}, ClimbRig.board())
	state = rules.apply(state, "p1", ROLL)["state"]
	assert_true(state["extra_turn"])
	var loaded: Dictionary = _load_state(_save_text(state, players))
	assert_true(loaded["extra_turn"])
	assert_eq(loaded["current_player"], "p1")
	var next: Dictionary = rules.apply(loaded, "p1", ROLL)
	assert_eq(next["state"]["last_roll"]["dice"], [3])
	assert_eq(next["state"]["current_player"], "p2")


func test_a_save_taken_after_a_skipped_turn_loads_with_the_skip_applied() -> void:
	var players: Array = ["p1", "p2", "p3"]
	var state: Dictionary = rules.new_game(players, ClimbRig.classic(), {}, 3)["state"]
	state = rules.settle(state, ["p2", "p3"])["state"]
	var loaded: Dictionary = _load_state(_save_text(state, players))
	assert_eq(loaded["current_player"], "p2")
	assert_eq(loaded["turn_number"], 2)


func test_a_finished_game_loads_as_finished_and_stays_locked() -> void:
	var players: Array = ["p1", "p2"]
	var state: Dictionary = ClimbRig.game([4], players, {}, {"p1": 96})
	state = rules.apply(state, "p1", ROLL)["state"]
	var loaded: Dictionary = _load_state(_save_text(state, players))
	assert_eq(loaded["phase"], "finished")
	assert_eq(loaded["winner"], "p1")
	assert_eq(CoreResult.error_code(rules.apply(loaded, "p2", ROLL)), ClimbErrors.GAME_OVER)


func test_a_brand_new_game_can_be_saved_and_resumed() -> void:
	var players: Array = ["p1", "p2", "p3"]
	var state: Dictionary = rules.new_game(players, ClimbRig.classic(), {}, 123)["state"]
	assert_eq(_load_state(_save_text(state, players)), state)


# --- files --------------------------------------------------------------------------------------------

func test_a_save_file_round_trips() -> void:
	var players: Array = ["p1", "p2"]
	var state: Dictionary = _play(rules.new_game(players, ClimbRig.classic(), {"exact_finish": true}, 64)["state"], 13)["state"]
	var parts: Array = _lobby_and_registry(players)
	var snapshot: Dictionary = SessionSnapshot.capture(APP, ClimbAndSlitherRules.GAME_ID, parts[0], parts[1], state)
	assert_true(CoreResult.is_ok(SessionSnapshot.save_file(SAVE_PATH, snapshot)))
	var loaded: Dictionary = SessionSnapshot.load_file(SAVE_PATH)
	assert_true(CoreResult.is_ok(loaded))
	var game_state: Dictionary = loaded["snapshot"]["game_state"]
	assert_eq(game_state, state)
	assert_eq(_play(game_state, 50)["state"], _play(state, 50)["state"])


# --- damaged or tampered saves are caught by validate_state ---------------------------------------------------

func _tampered(mutate: Callable) -> Dictionary:
	var players: Array = ["p1", "p2"]
	var state: Dictionary = _play(rules.new_game(players, ClimbRig.classic(), {}, 21)["state"], 8)["state"]
	var loaded: Dictionary = _load_state(_save_text(state, players))
	mutate.call(loaded)
	return loaded


func test_a_save_edited_to_cheat_is_refused_by_validation() -> void:
	var cheats: Dictionary = {
		"teleport past the board": func(s: Dictionary) -> void: s["positions"]["p1"] = 150,
		"negative square": func(s: Dictionary) -> void: s["positions"]["p1"] = -3,
		"win without being on the last square": func(s: Dictionary) -> void:
			s["phase"] = "finished"
			s["winner"] = "p1",
		"two winners": func(s: Dictionary) -> void:
			s["phase"] = "finished"
			s["winner"] = "p1"
			s["positions"]["p1"] = 100
			s["positions"]["p2"] = 100,
		"someone already on the last square in a running game": func(s: Dictionary) -> void: s["positions"]["p2"] = 100,
		"corrupted generator": func(s: Dictionary) -> void: s["rng"]["state"] = "0,0,0,0",
		"generator replaced by numbers": func(s: Dictionary) -> void: s["rng"] = {"seed": 1, "state": 2},
		"unknown player's turn": func(s: Dictionary) -> void: s["current_player"] = "p9",
		"snake removed from the embedded board but board no longer canonical": func(s: Dictionary) -> void: s["board"]["ladders"].reverse(),
		"a chain sneaked into the board": func(s: Dictionary) -> void: s["board"]["snakes"].append({"from": 27, "to": 9}),
		"impossible dice": func(s: Dictionary) -> void: s["last_roll"] = {"player_id": "p1", "dice": [9], "total": 9},
	}
	for label: String in cheats:
		var tampered: Dictionary = _tampered(cheats[label])
		assert_eq(CoreResult.error_code(rules.validate_state(tampered)), ClimbErrors.INVALID_STATE, label)


func test_apply_refuses_a_save_whose_generator_was_wrecked() -> void:
	var tampered: Dictionary = _tampered(func(s: Dictionary) -> void: s["rng"]["state"] = "nonsense")
	assert_eq(CoreResult.error_code(rules.apply(tampered, tampered["current_player"], ROLL)), ClimbErrors.INVALID_STATE)
