extends GutTest

const APP: String = "1.0.0"
const GAME: String = "g"


func _valid() -> Dictionary:
	return Handshake.hello(APP, GAME, "Asha")


func test_valid_hello() -> void:
	var r: Dictionary = Handshake.validate_hello(_valid(), APP, GAME)
	assert_true(CoreResult.is_ok(r))
	assert_eq(r["player_name"], "Asha")
	assert_eq(r["player_id"], "")
	assert_eq(r["rejoin_token"], "")


func test_rejoin_fields_are_passed_through() -> void:
	var r: Dictionary = Handshake.validate_hello(Handshake.hello(APP, GAME, "A", "p3", "tok"), APP, GAME)
	assert_eq(r["player_id"], "p3")
	assert_eq(r["rejoin_token"], "tok")


func test_protocol_mismatch() -> void:
	var m: Dictionary = _valid()
	m["protocol_version"] = Protocol.PROTOCOL_VERSION + 1
	assert_eq(CoreResult.error_code(Handshake.validate_hello(m, APP, GAME)), ErrorCodes.PROTOCOL_MISMATCH)


func test_game_mismatch() -> void:
	assert_eq(CoreResult.error_code(Handshake.validate_hello(_valid(), APP, "other")), ErrorCodes.WRONG_GAME)


func test_app_version_must_match_exactly() -> void:
	assert_eq(CoreResult.error_code(Handshake.validate_hello(_valid(), "1.0.1", GAME)), ErrorCodes.APP_VERSION_MISMATCH)
	assert_eq(CoreResult.error_code(Handshake.validate_hello(_valid(), "1.0", GAME)), ErrorCodes.APP_VERSION_MISMATCH)


func test_protocol_beats_game_beats_version() -> void:
	var m: Dictionary = Handshake.hello("9", "x", "A")
	assert_eq(CoreResult.error_code(Handshake.validate_hello(m, APP, GAME)), ErrorCodes.WRONG_GAME)
	m["protocol_version"] = 77
	assert_eq(CoreResult.error_code(Handshake.validate_hello(m, APP, GAME)), ErrorCodes.PROTOCOL_MISMATCH)


func test_game_id_is_optional_in_hello() -> void:
	var m: Dictionary = Handshake.hello(APP, "", "Asha")
	assert_false(m["payload"].has("game_id"), "an empty game_id is left out")
	assert_true(CoreResult.is_ok(Handshake.validate_hello(m, APP, GAME)))
	m["payload"]["game_id"] = ""
	assert_true(CoreResult.is_ok(Handshake.validate_hello(m, APP, GAME)), "an explicitly empty one means any game")


func test_a_supplied_game_id_must_still_match_and_be_text() -> void:
	assert_eq(CoreResult.error_code(Handshake.validate_hello(Handshake.hello(APP, "other", "A"), APP, GAME)), ErrorCodes.WRONG_GAME)
	var m: Dictionary = Handshake.hello(APP, GAME, "A")
	m["payload"]["game_id"] = 7
	assert_eq(CoreResult.error_code(Handshake.validate_hello(m, APP, GAME)), ErrorCodes.MALFORMED)


func test_welcome_and_reject_carry_the_hosts_game_and_version() -> void:
	var w: Dictionary = Handshake.welcome("p1", "tok", "ludo", "1.2.0")
	assert_eq(w["payload"]["game_id"], "ludo")
	assert_eq(w["payload"]["app_version"], "1.2.0")
	var r: Dictionary = Handshake.reject("ROOM_FULL", "full", "ludo", "1.2.0")
	assert_eq(r["payload"]["game_id"], "ludo")
	assert_eq(r["payload"]["app_version"], "1.2.0")
	assert_eq(r["payload"]["code"], "ROOM_FULL")


func test_missing_or_wrong_typed_fields_are_malformed() -> void:
	for field: String in ["app_version", "player_name"]:
		var m: Dictionary = _valid()
		m["payload"].erase(field)
		assert_eq(CoreResult.error_code(Handshake.validate_hello(m, APP, GAME)), ErrorCodes.MALFORMED, field)
		m["payload"][field] = 5
		assert_eq(CoreResult.error_code(Handshake.validate_hello(m, APP, GAME)), ErrorCodes.MALFORMED, field)
	var m2: Dictionary = _valid()
	m2["payload"]["player_id"] = 7
	assert_eq(CoreResult.error_code(Handshake.validate_hello(m2, APP, GAME)), ErrorCodes.MALFORMED)


func test_clean_name() -> void:
	assert_eq(Handshake.clean_name("  Zed  ")["name"], "Zed")
	assert_eq(Handshake.clean_name("x".repeat(24))["name"], "x".repeat(24))
	assert_eq(CoreResult.error_code(Handshake.clean_name("x".repeat(25))), ErrorCodes.NAME_INVALID)
	assert_eq(CoreResult.error_code(Handshake.clean_name("")), ErrorCodes.NAME_INVALID)
	assert_eq(CoreResult.error_code(Handshake.clean_name("a\tb")), ErrorCodes.NAME_INVALID)
	assert_true(CoreResult.is_ok(Handshake.clean_name("Zoë 李")))


func test_builders_make_valid_envelopes() -> void:
	for m: Dictionary in [Handshake.hello(APP, GAME, "A"), Handshake.welcome("p1", "tok", GAME, APP), Handshake.reject("X", "y", GAME, APP)]:
		assert_true(CoreResult.is_ok(Envelope.validate(m)))
		assert_true(Envelope.is_plain_data(m))
	assert_eq(Handshake.welcome("p1", "tok", GAME, APP, {"extra": 1})["payload"], {"extra": 1, "player_id": "p1", "rejoin_token": "tok", "game_id": GAME, "app_version": APP})
