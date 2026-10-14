extends GutTest


func test_defaults_are_the_agreed_house_rules() -> void:
	assert_eq(ClimbSettings.defaults(), {"exact_finish": false, "extra_turn_on_six": false, "dice_count": 1})


func test_no_settings_means_the_defaults() -> void:
	var r: Dictionary = ClimbSettings.normalize({})
	assert_true(CoreResult.is_ok(r))
	assert_eq(r["settings"], ClimbSettings.defaults())


func test_given_settings_override_the_defaults_and_the_rest_stay() -> void:
	var r: Dictionary = ClimbSettings.normalize({"exact_finish": true})
	assert_eq(r["settings"], {"exact_finish": true, "extra_turn_on_six": false, "dice_count": 1})
	r = ClimbSettings.normalize({"extra_turn_on_six": true, "dice_count": 2})
	assert_eq(r["settings"], {"exact_finish": false, "extra_turn_on_six": true, "dice_count": 2})


func test_all_settings_at_once() -> void:
	var all: Dictionary = {"exact_finish": true, "extra_turn_on_six": true, "dice_count": 1}
	assert_eq(ClimbSettings.normalize(all)["settings"], all)
	var two_dice: Dictionary = {"exact_finish": false, "extra_turn_on_six": true, "dice_count": 2}
	assert_eq(ClimbSettings.normalize(two_dice)["settings"], two_dice)


func test_exact_finish_with_two_dice_is_refused_because_it_can_never_end() -> void:
	var r: Dictionary = ClimbSettings.normalize({"exact_finish": true, "dice_count": 2})
	assert_eq(CoreResult.error_code(r), ClimbErrors.INVALID_SETTINGS)
	assert_string_contains(str(r["error"]["message"]), "single die")
	assert_eq(CoreResult.error_code(ClimbSettings.normalize({"exact_finish": true, "extra_turn_on_six": true, "dice_count": 2})), ClimbErrors.INVALID_SETTINGS)
	# each half on its own is fine
	assert_true(CoreResult.is_ok(ClimbSettings.normalize({"exact_finish": true})))
	assert_true(CoreResult.is_ok(ClimbSettings.normalize({"exact_finish": false, "dice_count": 2})))


func test_unknown_settings_are_refused() -> void:
	var r: Dictionary = ClimbSettings.normalize({"exact_finnish": true})
	assert_eq(CoreResult.error_code(r), ClimbErrors.INVALID_SETTINGS)
	assert_string_contains(str(r["error"]["message"]), "exact_finnish")
	assert_eq(CoreResult.error_code(ClimbSettings.normalize({"dice": 2})), ClimbErrors.INVALID_SETTINGS)


func test_wrong_types_are_refused() -> void:
	for bad: Dictionary in [
		{"exact_finish": 1}, {"exact_finish": "true"}, {"exact_finish": null},
		{"extra_turn_on_six": 0}, {"extra_turn_on_six": "yes"},
		{"dice_count": "2"}, {"dice_count": true}, {"dice_count": 1.5}, {"dice_count": null}, {"dice_count": [1]},
	]:
		assert_eq(CoreResult.error_code(ClimbSettings.normalize(bad)), ClimbErrors.INVALID_SETTINGS, str(bad))


func test_dice_count_must_be_one_or_two() -> void:
	for bad: int in [0, -1, 3, 10]:
		assert_eq(CoreResult.error_code(ClimbSettings.normalize({"dice_count": bad})), ClimbErrors.INVALID_SETTINGS, "dice %d" % bad)
	for ok: int in [1, 2]:
		assert_true(CoreResult.is_ok(ClimbSettings.normalize({"dice_count": ok})))


func test_integral_floats_from_json_become_ints() -> void:
	var r: Dictionary = ClimbSettings.normalize({"dice_count": 2.0})
	assert_true(CoreResult.is_ok(r))
	assert_eq(typeof(r["settings"]["dice_count"]), TYPE_INT)


func test_normalize_does_not_change_its_input_and_returns_a_fresh_copy() -> void:
	var input: Dictionary = {"exact_finish": true}
	var r: Dictionary = ClimbSettings.normalize(input)
	assert_eq(input, {"exact_finish": true})
	r["settings"]["dice_count"] = 2
	assert_eq(ClimbSettings.defaults()["dice_count"], 1, "defaults are not shared")


func test_settings_are_plain_data() -> void:
	assert_true(Envelope.is_plain_data(ClimbSettings.normalize({"dice_count": 2})["settings"]))


# --- what a settings screen should grey out ---------------------------------------------------

func test_with_the_defaults_both_options_are_available() -> void:
	var states: Dictionary = ClimbSettings.option_states(ClimbSettings.defaults())
	assert_true(states["exact_finish"]["enabled"])
	assert_true(states["two_dice"]["enabled"])
	assert_eq(states["exact_finish"]["tooltip"], "")
	assert_eq(states["two_dice"]["tooltip"], "")


func test_choosing_exact_finish_greys_out_two_dice_with_a_tooltip() -> void:
	var states: Dictionary = ClimbSettings.option_states({"exact_finish": true, "dice_count": 1})
	assert_false(states["two_dice"]["enabled"])
	assert_eq(states["two_dice"]["tooltip"], ClimbSettings.TWO_DICE_NEEDS_NO_EXACT_FINISH)
	assert_true(states["exact_finish"]["enabled"], "the chosen option stays enabled so it can be switched off")
	assert_eq(states["exact_finish"]["tooltip"], "")


func test_choosing_two_dice_greys_out_exact_finish_with_a_tooltip() -> void:
	var states: Dictionary = ClimbSettings.option_states({"exact_finish": false, "dice_count": 2})
	assert_false(states["exact_finish"]["enabled"])
	assert_eq(states["exact_finish"]["tooltip"], ClimbSettings.EXACT_FINISH_NEEDS_ONE_DIE)
	assert_true(states["two_dice"]["enabled"], "the chosen option stays enabled so it can be switched off")


func test_the_tooltips_are_short() -> void:
	assert_lt(ClimbSettings.EXACT_FINISH_NEEDS_ONE_DIE.length(), 60)
	assert_lt(ClimbSettings.TWO_DICE_NEEDS_NO_EXACT_FINISH.length(), 60)


func test_a_screen_that_follows_option_states_can_never_build_a_refused_combination() -> void:
	# Simulate a user clicking around: every click is only allowed if option_states enables it.
	var settings: Dictionary = ClimbSettings.defaults()
	var prng: Prng = Prng.new(5)
	for _i: int in 400:
		var states: Dictionary = ClimbSettings.option_states(settings)
		match prng.range_int(0, 3):
			0:  # toggle exact finish
				if states["exact_finish"]["enabled"]:
					settings["exact_finish"] = not settings["exact_finish"]
			1:  # pick two dice
				if states["two_dice"]["enabled"]:
					settings["dice_count"] = 2
			2:  # pick one die (always available)
				settings["dice_count"] = 1
			3:  # toggle extra turn on six (independent)
				settings["extra_turn_on_six"] = not settings["extra_turn_on_six"]
		assert_true(CoreResult.is_ok(ClimbSettings.normalize(settings)), "reached a refused combination: %s" % str(settings))


func test_option_states_copes_with_missing_or_odd_settings() -> void:
	assert_true(ClimbSettings.option_states({})["exact_finish"]["enabled"])
	assert_true(ClimbSettings.option_states({"dice_count": "2"})["exact_finish"]["enabled"], "junk is not treated as two dice")
	assert_true(ClimbSettings.option_states({"exact_finish": 1})["two_dice"]["enabled"], "junk is not treated as exact finish")
