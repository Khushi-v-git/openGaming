extends GutTest
## view_for: what a player is allowed to see. The host broadcasts views, never raw state.

const ROLL: Dictionary = {"type": "roll"}

var rules: ClimbAndSlitherRules


func before_each() -> void:
	rules = ClimbAndSlitherRules.new()


## Collects every key and every string value anywhere inside `value`.
func _flatten(value: Variant, keys: Array[String], strings: Array[String]) -> void:
	if value is Dictionary:
		for key: Variant in value:
			keys.append(str(key))
			_flatten(value[key], keys, strings)
	elif value is Array:
		for item: Variant in value:
			_flatten(item, keys, strings)
	elif value is String:
		strings.append(value)


func _game_after(rolls: int, seed_value: int = 77) -> Dictionary:
	var state: Dictionary = rules.new_game(["p1", "p2", "p3"], ClimbRig.classic(), {"extra_turn_on_six": true}, seed_value)["state"]
	for _i: int in rolls:
		if state["phase"] == "finished":
			break  # some seeds win early
		state = rules.apply(state, state["current_player"], ROLL)["state"]
	return state


# --- the rng never leaks --------------------------------------------------------------------

func test_the_random_generator_never_appears_in_a_view() -> void:
	for seed_value: int in [1, 77, 9007199254740993, -5, 4611686018427387904]:
		for rolls: int in [0, 1, 7, 40]:
			var state: Dictionary = _game_after(rolls, seed_value)
			for player: String in ["p1", "p2", "p3", "stranger", ""]:
				var view: Dictionary = rules.view_for(state, player)
				var keys: Array[String] = []
				var strings: Array[String] = []
				_flatten(view, keys, strings)
				assert_false(view.has("rng"), "no rng key (seed %d, %d rolls, %s)" % [seed_value, rolls, player])
				assert_false(keys.has("rng"), "no rng key anywhere")
				assert_false(keys.has("seed"), "no seed key anywhere")
				assert_false(strings.has(state["rng"]["seed"]), "the seed string is not in the view")
				assert_false(strings.has(state["rng"]["state"]), "the generator state string is not in the view")
				var text: String = JSON.stringify(view)
				assert_false(text.contains(state["rng"]["state"]), "not even inside the JSON text")
				assert_false(text.contains("rng"))


func test_the_view_never_contains_a_host_only_key_whatever_the_state_holds() -> void:
	var state: Dictionary = _game_after(3)
	for key: String in ClimbAndSlitherRules.HOST_ONLY_KEYS:
		assert_false(rules.view_for(state, "p1").has(key), key)
	# a field someone adds to the state later is private until it is whitelisted
	state["debug_secret"] = "do not send"
	assert_false(rules.view_for(state, "p1").has("debug_secret"))
	assert_false(JSON.stringify(rules.view_for(state, "p1")).contains("do not send"))


func test_public_and_host_only_keys_cover_the_whole_state_exactly() -> void:
	var state: Dictionary = _game_after(0)
	var all_keys: Array[String] = []
	for key: Variant in state.keys():
		all_keys.append(str(key))
	var covered: Array[String] = []
	covered.append_array(ClimbAndSlitherRules.PUBLIC_KEYS)
	covered.append_array(ClimbAndSlitherRules.HOST_ONLY_KEYS)
	all_keys.sort()
	covered.sort()
	assert_eq(covered, all_keys, "every state field is either public or host-only, so none is forgotten")


# --- what the view does contain ----------------------------------------------------------------

func test_a_view_is_the_public_state_plus_you() -> void:
	var state: Dictionary = _game_after(5)
	var view: Dictionary = rules.view_for(state, "p2")
	assert_eq(view["you"], "p2")
	for key: String in ClimbAndSlitherRules.PUBLIC_KEYS:
		assert_eq(view[key], state[key], key)
	assert_eq(view.size(), ClimbAndSlitherRules.PUBLIC_KEYS.size() + 1)


func test_every_player_sees_the_same_game() -> void:
	var state: Dictionary = _game_after(9)
	var one: Dictionary = rules.view_for(state, "p1")
	var two: Dictionary = rules.view_for(state, "p3")
	one.erase("you")
	two.erase("you")
	assert_eq(one, two, "no hidden information: views differ only in who 'you' is")


func test_positions_are_fully_visible_to_everyone() -> void:
	var state: Dictionary = _game_after(6)
	assert_eq(rules.view_for(state, "p3")["positions"], state["positions"])


func test_a_view_is_a_copy_not_a_window_onto_the_state() -> void:
	var state: Dictionary = _game_after(2)
	var snapshot: Dictionary = state.duplicate(true)
	var view: Dictionary = rules.view_for(state, "p1")
	view["positions"]["p1"] = 99
	view["board"]["snakes"].clear()
	view["players"].clear()
	view["last_roll"]["total"] = 100
	assert_eq(state, snapshot)


func test_a_view_is_plain_json_safe_data() -> void:
	var view: Dictionary = rules.view_for(_game_after(10), "p1")
	assert_true(Envelope.is_plain_data(view))
	assert_eq(Envelope.normalize(JSON.parse_string(JSON.stringify(view))), view)


func test_a_spectator_or_unknown_id_still_gets_a_view() -> void:
	var view: Dictionary = rules.view_for(_game_after(1), "someone-watching")
	assert_eq(view["you"], "someone-watching")
	assert_false(view.has("rng"))


func test_views_of_a_finished_game_show_the_winner_and_still_hide_the_rng() -> void:
	var state: Dictionary = ClimbRig.game([4], ["p1", "p2"], {}, {"p1": 96})
	var finished: Dictionary = rules.apply(state, "p1", ROLL)["state"]
	var view: Dictionary = rules.view_for(finished, "p2")
	assert_eq(view["phase"], "finished")
	assert_eq(view["winner"], "p1")
	assert_false(view.has("rng"))


func test_view_of_a_state_missing_fields_does_not_crash() -> void:
	var view: Dictionary = rules.view_for({"phase": "in_progress"}, "p1")
	assert_eq(view, {"phase": "in_progress", "you": "p1"})


func test_a_view_is_not_a_valid_game_state_so_it_cannot_be_applied_by_mistake() -> void:
	var view: Dictionary = rules.view_for(_game_after(1), "p1")
	assert_eq(CoreResult.error_code(rules.validate_state(view)), ClimbErrors.INVALID_STATE)
	assert_eq(CoreResult.error_code(rules.apply(view, "p1", ROLL)), ClimbErrors.INVALID_STATE)
