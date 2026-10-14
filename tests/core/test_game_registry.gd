extends GutTest

const FIXTURES: String = "res://tests/fixtures/games"
const ALPHA_DIR: String = FIXTURES + "/alpha"


func _alpha() -> Dictionary:
	var f: FileAccess = FileAccess.open(ALPHA_DIR + "/manifest.json", FileAccess.READ)
	return Envelope.normalize(JSON.parse_string(f.get_as_text()))


func _error_of(data: Dictionary) -> String:
	return CoreResult.error_code(GameManifest.validate(data, ALPHA_DIR))


# --- manifest validation ---------------------------------------------------------

func test_valid_manifest_is_accepted_and_cleaned() -> void:
	var data: Dictionary = _alpha()
	data["display_name"] = "  Zebra Race  "
	var r: Dictionary = GameManifest.validate(data, ALPHA_DIR)
	assert_true(CoreResult.is_ok(r), str(r))
	assert_eq(r["manifest"]["display_name"], "Zebra Race")
	assert_eq(r["manifest"]["id"], "alpha")
	assert_eq(r["manifest"]["min_players"], 2)


func test_description_is_optional() -> void:
	var data: Dictionary = _alpha()
	data.erase("description")
	var r: Dictionary = GameManifest.validate(data, ALPHA_DIR)
	assert_true(CoreResult.is_ok(r))
	assert_eq(r["manifest"]["description"], "")


func test_bad_ids_are_refused() -> void:
	for bad: Variant in ["", "A", "Alpha", "1alpha", "al pha", "al-pha", "x".repeat(33), 5, null]:
		var data: Dictionary = _alpha()
		data["id"] = bad
		assert_eq(_error_of(data), GameManifest.INVALID_MANIFEST, "id %s" % str(bad))


func test_bad_names_are_refused() -> void:
	for bad: Variant in ["", "   ", "x".repeat(41), 5]:
		var data: Dictionary = _alpha()
		data["display_name"] = bad
		assert_eq(_error_of(data), GameManifest.INVALID_MANIFEST, "name %s" % str(bad))


func test_bad_player_counts_are_refused() -> void:
	var cases: Array = [[0, 2], [3, 2], [2, 17], ["2", 4], [2, 4.5], [-1, 2]]
	for pair: Array in cases:
		var data: Dictionary = _alpha()
		data["min_players"] = pair[0]
		data["max_players"] = pair[1]
		assert_eq(_error_of(data), GameManifest.INVALID_MANIFEST, "counts %s" % str(pair))


func test_missing_fields_are_refused() -> void:
	for field: String in ["id", "display_name", "icon", "min_players", "max_players", "rules_class"]:
		var data: Dictionary = _alpha()
		data.erase(field)
		assert_eq(_error_of(data), GameManifest.INVALID_MANIFEST, "missing %s" % field)


func test_paths_must_stay_inside_the_game_folder() -> void:
	for field: String in ["icon", "rules_class", "ui_scene"]:
		var other: Dictionary = _alpha()
		other[field] = other[field].replace("/alpha/", "/beta/")
		assert_eq(_error_of(other), GameManifest.INVALID_MANIFEST, "%s into another game" % field)
		var sneaky: Dictionary = _alpha()
		sneaky[field] = ALPHA_DIR + "/../beta/" + sneaky[field].get_file()
		assert_eq(_error_of(sneaky), GameManifest.INVALID_MANIFEST, "%s with .." % field)
		var core: Dictionary = _alpha()
		core[field] = "res://core/net/protocol.gd"
		assert_eq(_error_of(core), GameManifest.INVALID_MANIFEST, "%s into core" % field)


func test_paths_must_exist_and_have_the_right_type() -> void:
	var missing: Dictionary = _alpha()
	missing["icon"] = ALPHA_DIR + "/nope.svg"
	assert_eq(_error_of(missing), GameManifest.INVALID_MANIFEST)
	var wrong_rules: Dictionary = _alpha()
	wrong_rules["rules_class"] = ALPHA_DIR + "/ui.tscn"
	assert_eq(_error_of(wrong_rules), GameManifest.INVALID_MANIFEST)
	var wrong_scene: Dictionary = _alpha()
	wrong_scene["ui_scene"] = ALPHA_DIR + "/rules.gd"
	assert_eq(_error_of(wrong_scene), GameManifest.INVALID_MANIFEST)


func test_rules_class_must_extend_refcounted() -> void:
	var data: Dictionary = _alpha()
	var dir: String = FIXTURES + "/not_refcounted"
	data["id"] = "not_refcounted"
	for field: String in ["icon", "rules_class", "ui_scene"]:
		data[field] = dir + "/" + (data[field] as String).get_file()
	var r: Dictionary = GameManifest.validate(data, dir)
	assert_eq(CoreResult.error_code(r), GameManifest.INVALID_MANIFEST)
	assert_string_contains(str(r["error"]["message"]), "RefCounted")


func test_supports_player_count() -> void:
	var m: Dictionary = GameManifest.validate(_alpha(), ALPHA_DIR)["manifest"]
	assert_false(GameManifest.supports_player_count(m, 1))
	assert_true(GameManifest.supports_player_count(m, 2))
	assert_true(GameManifest.supports_player_count(m, 4))
	assert_false(GameManifest.supports_player_count(m, 5))


# --- loader ----------------------------------------------------------------------

func test_scan_finds_good_games_and_reports_broken_ones_separately() -> void:
	var scanned: Dictionary = ManifestLoader.scan(FIXTURES)
	var ids: Array[String] = []
	for m: Dictionary in scanned["manifests"]:
		ids.append(m["id"])
	assert_eq(ids, ["alpha", "beta", "no_ui"] as Array[String])
	var bad_paths: Array[String] = []
	for e: Dictionary in scanned["errors"]:
		bad_paths.append((e["path"] as String).get_base_dir().get_file())
		assert_eq(e["code"], GameManifest.INVALID_MANIFEST)
	bad_paths.sort()
	assert_eq(bad_paths, ["broken_json", "missing_files", "not_refcounted", "wrong_id"] as Array[String])


func test_scan_skips_folders_without_a_manifest_quietly() -> void:
	for e: Dictionary in ManifestLoader.scan(FIXTURES)["errors"]:
		assert_false((e["path"] as String).contains("no_manifest"))


func test_scan_of_a_missing_folder_is_empty_not_an_error() -> void:
	var scanned: Dictionary = ManifestLoader.scan("res://does_not_exist")
	assert_eq(scanned["manifests"].size(), 0)
	assert_eq(scanned["errors"].size(), 0)


func test_the_real_games_folder_scans_without_errors() -> void:
	var scanned: Dictionary = ManifestLoader.scan("res://games")
	assert_eq(scanned["errors"], [], "no shipped game has a broken manifest")


func test_id_must_equal_folder_name() -> void:
	var scanned: Dictionary = ManifestLoader.scan(FIXTURES)
	var found: bool = false
	for e: Dictionary in scanned["errors"]:
		if (e["path"] as String).contains("wrong_id"):
			found = true
			assert_string_contains(e["message"], "folder name")
	assert_true(found)


# --- registry --------------------------------------------------------------------

func _loaded() -> GameRegistry:
	var registry: GameRegistry = GameRegistry.new()
	registry.load_from(FIXTURES)
	return registry


func test_load_from_registers_valid_games() -> void:
	var registry: GameRegistry = GameRegistry.new()
	var result: Dictionary = registry.load_from(FIXTURES)
	assert_eq(result["registered"], ["alpha", "beta", "no_ui"] as Array[String])
	assert_eq(result["errors"].size(), 4)
	assert_eq(registry.count(), 3)


func test_has_and_get_manifest() -> void:
	var registry: GameRegistry = _loaded()
	assert_true(registry.has("alpha"))
	assert_false(registry.has("climb_and_slither"))
	assert_false(registry.has(""))
	assert_eq(registry.get_manifest("alpha")["display_name"], "Zebra Race")
	assert_eq(registry.get_manifest("nope"), {})
	assert_eq(registry.display_name("alpha"), "Zebra Race")
	assert_eq(registry.display_name("nope"), "nope", "unknown games show their id")


func test_all_is_sorted_by_display_name() -> void:
	var registry: GameRegistry = _loaded()
	var names: Array[String] = []
	for m: Dictionary in registry.all():
		names.append(m["display_name"])
	assert_eq(names, ["Apple Cards", "Mango Draft", "Zebra Race"] as Array[String])
	assert_eq(registry.ids(), ["beta", "no_ui", "alpha"] as Array[String])


func test_returned_manifests_are_copies() -> void:
	var registry: GameRegistry = _loaded()
	var copy: Dictionary = registry.get_manifest("alpha")
	copy["display_name"] = "Hacked"
	assert_eq(registry.get_manifest("alpha")["display_name"], "Zebra Race")


func test_duplicate_ids_are_refused() -> void:
	var registry: GameRegistry = _loaded()
	var again: Dictionary = registry.register(registry.get_manifest("alpha"))
	assert_eq(CoreResult.error_code(again), GameManifest.DUPLICATE_GAME)
	assert_eq(registry.count(), 3)
	var second_load: Dictionary = registry.load_from(FIXTURES)
	assert_eq(second_load["registered"].size(), 0)
	var codes: Array[String] = []
	for e: Dictionary in second_load["errors"]:
		codes.append(e["code"])
	assert_true(codes.has(GameManifest.DUPLICATE_GAME))


func test_register_needs_an_id() -> void:
	assert_eq(CoreResult.error_code(GameRegistry.new().register({})), GameManifest.INVALID_MANIFEST)


func test_supports_player_count_by_game_id() -> void:
	var registry: GameRegistry = _loaded()
	assert_true(registry.supports_player_count("alpha", 3))
	assert_false(registry.supports_player_count("alpha", 5))
	assert_false(registry.supports_player_count("nope", 2))


func test_create_rules_returns_a_fresh_pure_logic_object() -> void:
	var registry: GameRegistry = _loaded()
	var a: RefCounted = registry.create_rules("alpha")
	var b: RefCounted = registry.create_rules("alpha")
	assert_not_null(a)
	assert_ne(a, b)
	assert_eq(a.call("game_name"), "alpha")
	assert_null(registry.create_rules("nope"))


func test_load_ui_scene() -> void:
	var registry: GameRegistry = _loaded()
	var scene: PackedScene = registry.load_ui_scene("alpha")
	assert_not_null(scene)
	var node: Node = autofree(scene.instantiate())
	assert_true(node is Control)
	assert_null(registry.load_ui_scene("nope"))


func test_validator_is_usable_by_the_lobby() -> void:
	var registry: GameRegistry = _loaded()
	var validator: Callable = registry.validator()
	assert_true(validator.call("alpha"))
	assert_false(validator.call("climb_and_slither"))


func test_games_with_five_or_more_players_are_fine() -> void:
	for pair: Array in [[2, 5], [5, 5], [3, 8], [2, 16]]:
		var data: Dictionary = _alpha()
		data["min_players"] = pair[0]
		data["max_players"] = pair[1]
		var r: Dictionary = GameManifest.validate(data, ALPHA_DIR)
		assert_true(CoreResult.is_ok(r), "counts %s" % str(pair))
		assert_true(GameManifest.supports_player_count(r["manifest"], 5) == (pair[0] <= 5 and pair[1] >= 5))


func test_min_active_players_defaults_to_min_players() -> void:
	var r: Dictionary = GameManifest.validate(_alpha(), ALPHA_DIR)
	assert_eq(r["manifest"]["min_active_players"], r["manifest"]["min_players"])


func test_min_active_players_can_be_lower_than_min_players() -> void:
	var data: Dictionary = _alpha()
	data["min_players"] = 4
	data["max_players"] = 6
	data["min_active_players"] = 2
	var r: Dictionary = GameManifest.validate(data, ALPHA_DIR)
	assert_true(CoreResult.is_ok(r))
	assert_eq(r["manifest"]["min_active_players"], 2)


func test_bad_min_active_players_are_refused() -> void:
	for bad: Variant in [0, -1, 3, "2", 1.5, null]:
		var data: Dictionary = _alpha()  # min_players 2
		data["min_active_players"] = bad
		assert_eq(_error_of(data), GameManifest.INVALID_MANIFEST, "min_active_players %s" % str(bad))


# --- ui_scene is optional while a game is in development ------------------------------

func test_a_manifest_without_ui_scene_is_valid_and_not_playable() -> void:
	var data: Dictionary = _alpha()
	data.erase("ui_scene")
	var r: Dictionary = GameManifest.validate(data, ALPHA_DIR)
	assert_true(CoreResult.is_ok(r), str(r))
	assert_eq(r["manifest"]["ui_scene"], "")
	assert_false(GameManifest.has_ui(r["manifest"]))


func test_an_empty_ui_scene_means_none() -> void:
	var data: Dictionary = _alpha()
	data["ui_scene"] = ""
	var r: Dictionary = GameManifest.validate(data, ALPHA_DIR)
	assert_true(CoreResult.is_ok(r))
	assert_eq(r["manifest"]["ui_scene"], "")


func test_a_ui_scene_that_is_given_is_still_checked() -> void:
	var missing: Dictionary = _alpha()
	missing["ui_scene"] = ALPHA_DIR + "/nope.tscn"
	assert_eq(_error_of(missing), GameManifest.INVALID_MANIFEST)
	var elsewhere: Dictionary = _alpha()
	elsewhere["ui_scene"] = "res://core/lobby/lobby_scene.tscn"
	assert_eq(_error_of(elsewhere), GameManifest.INVALID_MANIFEST)
	for bad: Variant in [5, true, ["a"], {}]:
		var data: Dictionary = _alpha()
		data["ui_scene"] = bad
		assert_eq(_error_of(data), GameManifest.INVALID_MANIFEST, "ui_scene %s" % str(bad))


func test_the_home_screen_list_only_has_games_with_a_ui() -> void:
	var registry: GameRegistry = _loaded()
	assert_eq(registry.count(), 3)
	var ids: Array[String] = []
	for manifest: Dictionary in registry.playable():
		ids.append(manifest["id"])
	assert_eq(ids, ["beta", "alpha"] as Array[String], "no_ui is registered but not listed")
	assert_true(registry.has("no_ui"))
	assert_false(registry.has_ui("no_ui"))
	assert_true(registry.has_ui("alpha"))
	assert_false(registry.has_ui("nope"))


func test_a_game_without_ui_still_has_rules_and_no_scene() -> void:
	var registry: GameRegistry = _loaded()
	assert_not_null(registry.create_rules("no_ui"))
	assert_null(registry.load_ui_scene("no_ui"))
	assert_true(registry.supports_player_count("no_ui", 3))
