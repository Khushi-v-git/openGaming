extends GutTest
## The game registers itself through its manifest, with no change to core/.

const GAME_DIR: String = "res://games/climb_and_slither"
const MANIFEST: String = GAME_DIR + "/manifest.json"


func _registry() -> GameRegistry:
	var registry: GameRegistry = GameRegistry.new()
	registry.load_from("res://games")
	return registry


func test_the_manifest_is_valid() -> void:
	var loaded: Dictionary = ManifestLoader.load_manifest(MANIFEST, GAME_DIR)
	assert_true(CoreResult.is_ok(loaded), str(loaded))
	var manifest: Dictionary = loaded["manifest"]
	assert_eq(manifest["id"], "climb_and_slither")
	assert_eq(manifest["display_name"], "Climb and Slither")
	assert_eq(manifest["min_players"], 2)
	assert_eq(manifest["max_players"], 4)


func test_scanning_the_games_folder_registers_it_without_errors() -> void:
	var registry: GameRegistry = GameRegistry.new()
	var result: Dictionary = registry.load_from("res://games")
	assert_eq(result["errors"], [], "no broken manifests under games/")
	assert_true(registry.has("climb_and_slither"))
	assert_true("climb_and_slither" in result["registered"])


func test_the_id_matches_the_folder_the_rules_and_the_name_rules() -> void:
	var manifest: Dictionary = _registry().get_manifest("climb_and_slither")
	assert_eq(manifest["id"], GAME_DIR.get_file())
	assert_eq(manifest["id"], ClimbAndSlitherRules.GAME_ID)


func test_the_icon_exists_inside_the_game_folder() -> void:
	var manifest: Dictionary = _registry().get_manifest("climb_and_slither")
	assert_true(manifest["icon"].begins_with(GAME_DIR + "/"))
	assert_true(FileAccess.file_exists(manifest["icon"]), "icon file %s exists" % manifest["icon"])
	assert_gt(FileAccess.get_file_as_string(manifest["icon"]).length(), 100, "it is a real image, not an empty placeholder")


func test_player_counts_agree_between_the_manifest_and_the_rules() -> void:
	var manifest: Dictionary = _registry().get_manifest("climb_and_slither")
	assert_eq(manifest["min_players"], ClimbAndSlitherRules.MIN_PLAYERS)
	assert_eq(manifest["max_players"], ClimbAndSlitherRules.MAX_PLAYERS)
	assert_eq(manifest["max_players"], ClimbAndSlitherRules.COLORS.size(), "one player color per seat")


func test_the_registry_knows_which_player_counts_are_allowed() -> void:
	var registry: GameRegistry = _registry()
	for count: int in [2, 3, 4]:
		assert_true(registry.supports_player_count("climb_and_slither", count), "%d players" % count)
	for count: int in [0, 1, 5, 8]:
		assert_false(registry.supports_player_count("climb_and_slither", count), "%d players" % count)


func test_the_game_can_carry_on_with_two_players_present() -> void:
	var manifest: Dictionary = _registry().get_manifest("climb_and_slither")
	assert_eq(manifest["min_active_players"], 2)
	assert_lte(manifest["min_active_players"], manifest["min_players"])


func test_the_game_has_a_ui_and_a_settings_scene_and_is_listed_on_the_home_screen() -> void:
	var registry: GameRegistry = _registry()
	assert_true(registry.has_ui("climb_and_slither"))
	assert_not_null(registry.load_ui_scene("climb_and_slither"))
	assert_not_null(registry.load_settings_scene("climb_and_slither"))
	var listed: Array[String] = []
	for manifest: Dictionary in registry.playable():
		listed.append(manifest["id"])
	assert_true(listed.has("climb_and_slither"))


func test_the_registry_creates_working_rules_from_the_manifest() -> void:
	var rules: RefCounted = _registry().create_rules("climb_and_slither")
	assert_not_null(rules)
	assert_true(rules is ClimbAndSlitherRules)
	for method: String in ["new_game", "apply", "view_for", "settle", "validate_state"]:
		assert_true(rules.has_method(method), method)
	var created: Dictionary = rules.call("new_game", ["a", "b"], ClimbBoard.load_file()["board"], {}, 5)
	assert_true(CoreResult.is_ok(created))


func test_two_rules_objects_from_the_registry_are_independent() -> void:
	var registry: GameRegistry = _registry()
	assert_ne(registry.create_rules("climb_and_slither"), registry.create_rules("climb_and_slither"))


func test_a_game_played_through_registry_made_rules_finishes() -> void:
	var rules: RefCounted = _registry().create_rules("climb_and_slither")
	var state: Dictionary = rules.call("new_game", ["a", "b", "c"], ClimbBoard.load_file()["board"], {}, 2025)["state"]
	var guard: int = 0
	while state["phase"] == "in_progress" and guard < 5000:
		guard += 1
		state = rules.call("apply", state, state["current_player"], {"type": "roll"})["state"]
	assert_eq(state["phase"], "finished")


func test_a_client_whose_app_has_this_game_accepts_a_host_playing_it() -> void:
	var validator: Callable = _registry().validator()
	assert_true(validator.call("climb_and_slither"))
	assert_false(validator.call("some_other_game"))


func test_the_game_folder_follows_the_layout_in_claude_md() -> void:
	for sub: String in ["data", "rules", "tests", "assets"]:
		assert_true(DirAccess.dir_exists_absolute(GAME_DIR + "/" + sub), sub)
	assert_true(FileAccess.file_exists(GAME_DIR + "/data/classic_board.json"))
