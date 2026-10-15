extends GutTest
## The command-line options used by manual and scripted tests.

const TEST_SETTINGS: String = "user://test_launch_settings.cfg"

var _saved_path: String


func before_each() -> void:
	_saved_path = AppSettings.path
	AppSettings.path = TEST_SETTINGS
	DirAccess.remove_absolute(TEST_SETTINGS)


func after_each() -> void:
	AppSettings.path = _saved_path
	DirAccess.remove_absolute(TEST_SETTINGS)


func _parse(args: Array) -> Dictionary:
	return LaunchOptions.parse(PackedStringArray(args))


func test_no_options_is_an_empty_set() -> void:
	var parsed: Dictionary = _parse([])
	assert_true(CoreResult.is_ok(parsed))
	assert_eq(parsed["options"], {})


func test_every_option_is_read() -> void:
	var parsed: Dictionary = _parse([
		"--name=Asha", "--relay_url=ws://127.0.0.1:8787", "--via=direct", "--port=24681", "--auto=host",
		"--game=climb_and_slither", "--share_file=C:/tmp/code.txt", "--auto_ready",
	])
	assert_true(CoreResult.is_ok(parsed), str(parsed))
	var options: Dictionary = parsed["options"]
	assert_eq(options["name"], "Asha")
	assert_eq(options["relay_url"], "ws://127.0.0.1:8787", "a value may contain = and :")
	assert_eq(options["via"], "direct")
	assert_eq(options["port"], 24681)
	assert_eq(options["auto"], "host")
	assert_eq(options["game"], "climb_and_slither")
	assert_eq(options["share_file"], "C:/tmp/code.txt")
	assert_true(options["auto_ready"])


func test_a_guest_can_join_by_code_or_wait_for_a_file() -> void:
	assert_eq(_parse(["--auto=join", "--join=ABCDE2"])["options"]["join"], "ABCDE2")
	assert_eq(_parse(["--auto=join", "--join_from_file=C:/tmp/code.txt"])["options"]["join_from_file"], "C:/tmp/code.txt")
	assert_false(CoreResult.is_ok(_parse(["--auto=join"])), "joining needs something to join")


func test_values_that_contain_an_equals_sign_survive() -> void:
	assert_eq(_parse(["--name=A=B"])["options"]["name"], "A=B")


func test_bad_options_are_refused_with_a_message_that_names_them() -> void:
	for args: Array in [["--via=carrier_pigeon"], ["--auto=spectate"], ["--port=0"], ["--port=70000"], ["--port=abc"], ["--name"], ["--name="], ["--nonsense=1"]]:
		var parsed: Dictionary = _parse(args)
		assert_false(CoreResult.is_ok(parsed), str(args))
		assert_eq(CoreResult.error_code(parsed), LaunchOptions.BAD_OPTION)
		assert_ne(str(parsed["error"]["message"]), "")


func test_arguments_that_are_not_ours_are_ignored() -> void:
	var parsed: Dictionary = _parse(["somefile.tscn", "-v", "--name=Asha"])
	assert_true(CoreResult.is_ok(parsed))
	assert_eq(parsed["options"], {"name": "Asha"})


func test_a_run_that_sets_its_own_choices_never_touches_the_players_saved_settings() -> void:
	AppSettings.path = _saved_path  # pretend this is the player's real file
	var real: String = AppSettings.path
	LaunchOptions.isolate_settings({"name": "Test Guest", "relay_url": "ws://127.0.0.1:8787"})
	assert_ne(AppSettings.path, real)
	assert_true(AppSettings.path.begins_with("user://settings_"))
	assert_false(AppSettings.path.contains(" "), "a safe file name")
	DirAccess.remove_absolute(AppSettings.path)
	LaunchOptions.apply_to_settings({"name": "Test Guest", "relay_url": "127.0.0.1:8787", "via": "direct"})
	assert_eq(AppSettings.player_name(), "Test Guest")
	assert_eq(AppSettings.relay_url(), "ws://127.0.0.1:8787", "normalized like the box does")
	assert_eq(AppSettings.host_via(), "direct")
	DirAccess.remove_absolute(AppSettings.path)


func test_options_that_change_nothing_leave_the_settings_path_alone() -> void:
	var before: String = AppSettings.path
	LaunchOptions.isolate_settings({"port": 24680, "via": "direct"})
	assert_eq(AppSettings.path, before)


func test_the_players_name_is_remembered() -> void:
	assert_eq(AppSettings.player_name(), "")
	AppSettings.set_player_name("  Mira ")
	assert_eq(AppSettings.player_name(), "Mira")
