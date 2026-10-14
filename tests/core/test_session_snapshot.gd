extends GutTest

const APP: String = "1.0.0"
const GAME: String = "g"
const SAVE_DIR: String = "user://test_saves"


func after_each() -> void:
	for name: String in ["snap.json", "snap.json.tmp", "corrupt.json", "list.json"]:
		var path: String = "%s/%s" % [SAVE_DIR, name]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(SAVE_DIR)


func _sample() -> Dictionary:
	var registry: PlayerRegistry = PlayerRegistry.new()
	registry.create("Hosty")
	registry.create("Asha")
	registry.create("Bo")
	var lobby: Dictionary = LobbyLogic.create(GAME, 2, 4, "p1", "Hosty")
	for entry: Array in [["p2", "Asha"], ["p3", "Bo"]]:
		lobby = LobbyLogic.apply(lobby, entry[0], {"type": "join", "name": entry[1]})["state"]
		lobby = LobbyLogic.apply(lobby, entry[0], {"type": "set_ready", "ready": true})["state"]
	lobby = LobbyLogic.apply(lobby, "p1", {"type": "start"})["state"]
	registry.bind_peer("p2", 7)  # a live connection must never leak into a save
	return SessionSnapshot.capture(APP, GAME, lobby, registry, {"turn": 3, "positions": {"p1": 5, "p2": 12}})


func _error_of(snapshot: Dictionary) -> String:
	return CoreResult.error_code(SessionSnapshot.validate(snapshot, GAME))


# --- capture ---------------------------------------------------------------------

func test_capture_is_plain_data_with_everything_needed_to_resume() -> void:
	var snap: Dictionary = _sample()
	assert_true(Envelope.is_plain_data(snap))
	assert_eq(snap["save_version"], SessionSnapshot.SAVE_VERSION)
	assert_eq(snap["saved_by_app_version"], APP)
	assert_eq(snap["game_id"], GAME)
	assert_eq(snap["lobby"]["phase"], LobbyLogic.PHASE_IN_GAME)
	assert_eq(snap["players"]["players"].size(), 3)
	assert_eq(snap["game_state"], {"turn": 3, "positions": {"p1": 5, "p2": 12}})
	for entry: Dictionary in snap["players"]["players"]:
		assert_eq(str(entry["token"]).length(), 32, "tokens are saved so players can rejoin")


func test_capture_has_no_connection_info() -> void:
	var text: String = SessionSnapshot.to_text(_sample())
	assert_false(text.contains("peer"))


func test_capture_is_a_deep_copy() -> void:
	var registry: PlayerRegistry = PlayerRegistry.new()
	registry.create("Hosty")
	var lobby: Dictionary = LobbyLogic.create(GAME, 2, 4, "p1", "Hosty")
	var game_state: Dictionary = {"turn": 1}
	var snap: Dictionary = SessionSnapshot.capture(APP, GAME, lobby, registry, game_state)
	lobby["slots"][0]["name"] = "Changed"
	game_state["turn"] = 99
	assert_eq(snap["lobby"]["slots"][0]["name"], "Hosty")
	assert_eq(snap["game_state"]["turn"], 1)


func test_identity_of() -> void:
	var snap: Dictionary = _sample()
	var identity: Dictionary = SessionSnapshot.identity_of(snap, "p2")
	assert_eq(identity["player_id"], "p2")
	assert_eq(identity["rejoin_token"], snap["players"]["players"][1]["token"])
	assert_eq(SessionSnapshot.identity_of(snap, "p9"), {})


# --- text and files --------------------------------------------------------------

func test_text_round_trip_validates_and_matches() -> void:
	var snap: Dictionary = _sample()
	var parsed: Dictionary = SessionSnapshot.from_text(SessionSnapshot.to_text(snap))
	assert_true(CoreResult.is_ok(parsed))
	assert_eq(parsed["snapshot"], snap)
	assert_true(CoreResult.is_ok(SessionSnapshot.validate(parsed["snapshot"], GAME)))


func test_from_text_rejects_garbage() -> void:
	assert_eq(CoreResult.error_code(SessionSnapshot.from_text("not json")), ErrorCodes.MALFORMED)
	assert_eq(CoreResult.error_code(SessionSnapshot.from_text("[1, 2]")), ErrorCodes.MALFORMED)


func test_file_round_trip() -> void:
	var snap: Dictionary = _sample()
	var path: String = SAVE_DIR + "/snap.json"
	assert_true(CoreResult.is_ok(SessionSnapshot.save_file(path, snap)))
	assert_false(FileAccess.file_exists(path + ".tmp"), "temporary file is renamed away")
	var loaded: Dictionary = SessionSnapshot.load_file(path)
	assert_true(CoreResult.is_ok(loaded))
	assert_eq(loaded["snapshot"], snap)


func test_saving_over_an_existing_save_replaces_it() -> void:
	var path: String = SAVE_DIR + "/snap.json"
	var first: Dictionary = _sample()
	SessionSnapshot.save_file(path, first)
	var second: Dictionary = first.duplicate(true)
	second["game_state"] = {"turn": 4}
	assert_true(CoreResult.is_ok(SessionSnapshot.save_file(path, second)))
	assert_eq(SessionSnapshot.load_file(path)["snapshot"]["game_state"], {"turn": 4})


func test_missing_and_corrupt_files() -> void:
	assert_eq(CoreResult.error_code(SessionSnapshot.load_file(SAVE_DIR + "/nope.json")), SessionSnapshot.FILE_NOT_FOUND)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file: FileAccess = FileAccess.open(SAVE_DIR + "/corrupt.json", FileAccess.WRITE)
	file.store_string("{ half a save")
	file.close()
	assert_eq(CoreResult.error_code(SessionSnapshot.load_file(SAVE_DIR + "/corrupt.json")), ErrorCodes.MALFORMED)


# --- validation ------------------------------------------------------------------

func test_valid_snapshot_passes() -> void:
	assert_true(CoreResult.is_ok(SessionSnapshot.validate(_sample(), GAME)))


func test_other_game_is_refused() -> void:
	assert_eq(CoreResult.error_code(SessionSnapshot.validate(_sample(), "other")), ErrorCodes.WRONG_GAME)


func test_the_app_version_does_not_matter_only_the_save_version() -> void:
	var snap: Dictionary = _sample()
	snap["saved_by_app_version"] = "0.0.1-ancient"
	assert_true(CoreResult.is_ok(SessionSnapshot.validate(snap, GAME)), "app upgrades must not orphan saves")


func test_newer_or_older_save_formats_are_refused_clearly_without_migration() -> void:
	var newer: Dictionary = _sample()
	newer["save_version"] = SessionSnapshot.SAVE_VERSION + 1
	var r: Dictionary = SessionSnapshot.validate(newer, GAME)
	assert_eq(CoreResult.error_code(r), ErrorCodes.UNSUPPORTED_SAVE)
	assert_string_contains(str(r["error"]["message"]), "newer")
	var older: Dictionary = _sample()
	older["save_version"] = 0
	var r2: Dictionary = SessionSnapshot.validate(older, GAME)
	assert_eq(CoreResult.error_code(r2), ErrorCodes.UNSUPPORTED_SAVE)
	assert_string_contains(str(r2["error"]["message"]), "old format")


func test_missing_or_non_numeric_save_version_is_malformed() -> void:
	var missing: Dictionary = _sample()
	missing.erase("save_version")
	assert_eq(_error_of(missing), ErrorCodes.MALFORMED)
	var text: Dictionary = _sample()
	text["save_version"] = "1"
	assert_eq(_error_of(text), ErrorCodes.MALFORMED)


func test_damaged_snapshots_are_refused_not_crashed_on() -> void:
	var mutations: Dictionary = {
		"no lobby": func(s: Dictionary) -> void: s.erase("lobby"),
		"no players": func(s: Dictionary) -> void: s.erase("players"),
		"no game_state": func(s: Dictionary) -> void: s.erase("game_state"),
		"player list wrong type": func(s: Dictionary) -> void: s["players"]["players"] = "x",
		"empty token": func(s: Dictionary) -> void: s["players"]["players"][0]["token"] = "",
		"duplicate player": func(s: Dictionary) -> void: s["players"]["players"][1]["player_id"] = "p1",
		"slot without player": func(s: Dictionary) -> void: s["lobby"]["slots"][1]["player_id"] = "p9",
		"duplicate slot": func(s: Dictionary) -> void: s["lobby"]["slots"][2]["player_id"] = "p2",
		"host not in lobby": func(s: Dictionary) -> void: s["lobby"]["host_player_id"] = "p9",
		"bad phase": func(s: Dictionary) -> void: s["lobby"]["phase"] = "bogus",
		"flag wrong type": func(s: Dictionary) -> void: s["lobby"]["slots"][0]["ready"] = "yes",
		"too many players": func(s: Dictionary) -> void: s["lobby"]["max_players"] = 2,
		"lobby of another game": func(s: Dictionary) -> void: s["lobby"]["game_id"] = "other",
		"revision missing": func(s: Dictionary) -> void: s["lobby"].erase("revision"),
		"slot not a dict": func(s: Dictionary) -> void: s["lobby"]["slots"][0] = 5,
	}
	for label: String in mutations:
		var snap: Dictionary = _sample()
		(mutations[label] as Callable).call(snap)
		assert_eq(_error_of(snap), ErrorCodes.MALFORMED, label)
