extends GutTest


func _lobby(min_players: int = 2, max_players: int = 4) -> Dictionary:
	return LobbyLogic.create("g", min_players, max_players, "p1", "Host")


func _apply_ok(state: Dictionary, player_id: String, action: Dictionary) -> Dictionary:
	var r: Dictionary = LobbyLogic.apply(state, player_id, action)
	assert_true(CoreResult.is_ok(r), "expected ok for %s: %s" % [str(action), str(r)])
	return r["state"]


func _join(state: Dictionary, player_id: String, player_name: String) -> Dictionary:
	return _apply_ok(state, player_id, {"type": "join", "name": player_name})


func _ready_lobby() -> Dictionary:
	var s: Dictionary = _join(_lobby(), "p2", "Bo")
	return _apply_ok(s, "p2", {"type": "set_ready", "ready": true})


func _code(state: Dictionary, player_id: String, action: Dictionary) -> String:
	return CoreResult.error_code(LobbyLogic.apply(state, player_id, action))


# --- creation and join -----------------------------------------------------------

func test_create_has_ready_host_slot() -> void:
	var s: Dictionary = _lobby()
	assert_eq(s["phase"], LobbyLogic.PHASE_OPEN)
	assert_eq(s["slots"].size(), 1)
	assert_eq(s["slots"][0], {"player_id": "p1", "name": "Host", "ready": true, "connected": true, "left": false})
	assert_eq(s["revision"], 0)


func test_join_adds_unready_slot() -> void:
	var s: Dictionary = _join(_lobby(), "p2", "  Bo ")
	assert_eq(s["slots"].size(), 2)
	assert_eq(s["slots"][1]["name"], "Bo")
	assert_false(s["slots"][1]["ready"])
	assert_true(s["slots"][1]["connected"])


func test_join_rejects_full_room() -> void:
	var s: Dictionary = _lobby(2, 2)
	s = _join(s, "p2", "Bo")
	assert_eq(_code(s, "p3", {"type": "join", "name": "Cy"}), ErrorCodes.ROOM_FULL)
	assert_eq(CoreResult.error_code(LobbyLogic.can_join(s, "Cy")), ErrorCodes.ROOM_FULL)


func test_join_rejects_duplicate_name_case_insensitively() -> void:
	var s: Dictionary = _join(_lobby(), "p2", "Bo")
	assert_eq(_code(s, "p3", {"type": "join", "name": "bO"}), ErrorCodes.NAME_TAKEN)
	assert_eq(_code(s, "p3", {"type": "join", "name": "HOST"}), ErrorCodes.NAME_TAKEN)


func test_join_rejects_invalid_name() -> void:
	assert_eq(_code(_lobby(), "p2", {"type": "join", "name": "  "}), ErrorCodes.NAME_INVALID)


func test_join_rejects_same_player_twice() -> void:
	var s: Dictionary = _join(_lobby(), "p2", "Bo")
	assert_eq(_code(s, "p2", {"type": "join", "name": "Other"}), ErrorCodes.ALREADY_JOINED)


func test_join_rejected_once_game_started() -> void:
	var s: Dictionary = _apply_ok(_ready_lobby(), "p1", {"type": "start"})
	assert_eq(_code(s, "p3", {"type": "join", "name": "Cy"}), ErrorCodes.GAME_IN_PROGRESS)


# --- ready and names -------------------------------------------------------------

func test_set_ready_toggles() -> void:
	var s: Dictionary = _join(_lobby(), "p2", "Bo")
	s = _apply_ok(s, "p2", {"type": "set_ready", "ready": true})
	assert_true(s["slots"][1]["ready"])
	s = _apply_ok(s, "p2", {"type": "set_ready", "ready": false})
	assert_false(s["slots"][1]["ready"])


func test_host_stays_ready() -> void:
	var s: Dictionary = _apply_ok(_lobby(), "p1", {"type": "set_ready", "ready": false})
	assert_true(s["slots"][0]["ready"])


func test_set_ready_needs_boolean() -> void:
	var s: Dictionary = _join(_lobby(), "p2", "Bo")
	assert_eq(_code(s, "p2", {"type": "set_ready", "ready": "yes"}), ErrorCodes.BAD_ACTION)
	assert_eq(_code(s, "p2", {"type": "set_ready"}), ErrorCodes.BAD_ACTION)


func test_set_ready_by_stranger_is_rejected() -> void:
	assert_eq(_code(_lobby(), "p9", {"type": "set_ready", "ready": true}), ErrorCodes.NOT_IN_LOBBY)


func test_set_name() -> void:
	var s: Dictionary = _join(_lobby(), "p2", "Bo")
	s = _apply_ok(s, "p2", {"type": "set_name", "name": "Bobby"})
	assert_eq(s["slots"][1]["name"], "Bobby")
	s = _apply_ok(s, "p2", {"type": "set_name", "name": "bobby"})  # own name, different case
	assert_eq(_code(s, "p2", {"type": "set_name", "name": "host"}), ErrorCodes.NAME_TAKEN)
	assert_eq(_code(s, "p2", {"type": "set_name", "name": ""}), ErrorCodes.NAME_INVALID)


# --- start -----------------------------------------------------------------------

func test_start_requires_host() -> void:
	var s: Dictionary = _ready_lobby()
	assert_eq(_code(s, "p2", {"type": "start"}), ErrorCodes.NOT_HOST)


func test_start_requires_min_players() -> void:
	assert_eq(_code(_lobby(2, 4), "p1", {"type": "start"}), ErrorCodes.NOT_ENOUGH_PLAYERS)


func test_start_requires_everyone_ready() -> void:
	var s: Dictionary = _join(_lobby(), "p2", "Bo")
	assert_eq(_code(s, "p1", {"type": "start"}), ErrorCodes.NOT_ALL_READY)
	s = _apply_ok(s, "p2", {"type": "set_ready", "ready": true})
	s = _join(s, "p3", "Cy")
	assert_eq(_code(s, "p1", {"type": "start"}), ErrorCodes.NOT_ALL_READY)


func test_start_moves_to_in_game_and_locks_lobby() -> void:
	var s: Dictionary = _apply_ok(_ready_lobby(), "p1", {"type": "start"})
	assert_eq(s["phase"], LobbyLogic.PHASE_IN_GAME)
	assert_eq(_code(s, "p1", {"type": "start"}), ErrorCodes.WRONG_PHASE)
	assert_eq(_code(s, "p2", {"type": "set_ready", "ready": false}), ErrorCodes.WRONG_PHASE)
	assert_eq(_code(s, "p2", {"type": "set_name", "name": "Z"}), ErrorCodes.WRONG_PHASE)


func test_ready_to_start_helper() -> void:
	assert_false(LobbyLogic.ready_to_start(_lobby()))
	assert_true(LobbyLogic.ready_to_start(_ready_lobby()))


# --- leave, kick, disconnect -----------------------------------------------------

func test_leave_in_open_lobby_removes_slot() -> void:
	var s: Dictionary = _apply_ok(_ready_lobby(), "p2", {"type": "leave"})
	assert_eq(s["slots"].size(), 1)


func test_leave_in_game_keeps_slot_marked_left() -> void:
	var s: Dictionary = _apply_ok(_ready_lobby(), "p1", {"type": "start"})
	s = _apply_ok(s, "p2", {"type": "leave"})
	assert_eq(s["slots"].size(), 2)
	assert_true(s["slots"][1]["left"])
	assert_false(s["slots"][1]["connected"])


func test_host_cannot_leave() -> void:
	assert_eq(_code(_ready_lobby(), "p1", {"type": "leave"}), ErrorCodes.HOST_CANNOT_LEAVE)


func test_kick() -> void:
	var s: Dictionary = _apply_ok(_ready_lobby(), "p1", {"type": "kick", "player_id": "p2"})
	assert_eq(s["slots"].size(), 1)


func test_kick_rules() -> void:
	var s: Dictionary = _ready_lobby()
	assert_eq(_code(s, "p2", {"type": "kick", "player_id": "p1"}), ErrorCodes.NOT_HOST)
	assert_eq(_code(s, "p1", {"type": "kick", "player_id": "nobody"}), ErrorCodes.UNKNOWN_PLAYER)
	assert_eq(_code(s, "p1", {"type": "kick", "player_id": "p1"}), ErrorCodes.HOST_CANNOT_LEAVE)


func test_kick_in_game_marks_left() -> void:
	var s: Dictionary = _apply_ok(_ready_lobby(), "p1", {"type": "start"})
	s = _apply_ok(s, "p1", {"type": "kick", "player_id": "p2"})
	assert_true(s["slots"][1]["left"])


func test_disconnect_in_open_lobby_removes_slot() -> void:
	var s: Dictionary = _apply_ok(_ready_lobby(), "p2", {"type": "disconnected"})
	assert_eq(s["slots"].size(), 1)


func test_disconnect_in_game_keeps_slot_and_reconnect_restores() -> void:
	var s: Dictionary = _apply_ok(_ready_lobby(), "p1", {"type": "start"})
	s = _apply_ok(s, "p2", {"type": "disconnected"})
	assert_false(s["slots"][1]["connected"])
	assert_false(s["slots"][1]["left"])
	s = _apply_ok(s, "p2", {"type": "reconnected"})
	assert_true(s["slots"][1]["connected"])


func test_left_player_cannot_reconnect() -> void:
	var s: Dictionary = _apply_ok(_ready_lobby(), "p1", {"type": "start"})
	s = _apply_ok(s, "p2", {"type": "leave"})
	assert_eq(_code(s, "p2", {"type": "reconnected"}), ErrorCodes.PLAYER_LEFT)


func test_open_lobby_disconnect_drops_player_from_start_count() -> void:
	var s: Dictionary = _ready_lobby()
	s = _apply_ok(s, "p2", {"type": "disconnected"})
	assert_eq(_code(s, "p1", {"type": "start"}), ErrorCodes.NOT_ENOUGH_PLAYERS)


# --- invalid actions leave state unchanged ----------------------------------------

func test_invalid_actions_never_change_state() -> void:
	var s: Dictionary = _ready_lobby()
	var snapshot: Dictionary = s.duplicate(true)
	var bad: Array = [
		["p9", {"type": "set_ready", "ready": true}],
		["p2", {"type": "start"}],
		["p2", {"type": "kick", "player_id": "p1"}],
		["p1", {"type": "leave"}],
		["p2", {"type": "join", "name": "Again"}],
		["p3", {"type": "join", "name": "bo"}],
		["p2", {"type": "set_ready", "ready": 5}],
		["p2", {"type": "teleport"}],
		["p2", {"type": 7}],
		["p2", {}],
		["p9", {"type": "disconnected"}],
		["p9", {"type": "reconnected"}],
	]
	for entry: Array in bad:
		var r: Dictionary = LobbyLogic.apply(s, entry[0], entry[1])
		assert_false(CoreResult.is_ok(r), "should fail: %s" % str(entry))
		assert_eq(s, snapshot, "state changed by %s" % str(entry))


func test_apply_does_not_mutate_input_on_success() -> void:
	var s: Dictionary = _lobby()
	var snapshot: Dictionary = s.duplicate(true)
	LobbyLogic.apply(s, "p2", {"type": "join", "name": "Bo"})
	assert_eq(s, snapshot)


func test_revision_increases_only_on_success() -> void:
	var s: Dictionary = _lobby()
	s = _join(s, "p2", "Bo")
	assert_eq(s["revision"], 1)
	LobbyLogic.apply(s, "p9", {"type": "leave"})
	assert_eq(s["revision"], 1)
	s = _apply_ok(s, "p2", {"type": "set_ready", "ready": true})
	assert_eq(s["revision"], 2)


func test_player_actions_whitelist_excludes_system_actions() -> void:
	for system_action: String in ["join", "disconnected", "reconnected"]:
		assert_false(LobbyLogic.PLAYER_ACTIONS.has(system_action))


# --- serialization ---------------------------------------------------------------

func test_state_survives_json_round_trip() -> void:
	var s: Dictionary = _apply_ok(_ready_lobby(), "p1", {"type": "start"})
	var copy: Dictionary = Envelope.normalize(JSON.parse_string(JSON.stringify(s)))
	assert_eq(copy, s)
	assert_true(Envelope.is_plain_data(s))
	# and it keeps working after the round trip
	assert_eq(_code(copy, "p1", {"type": "start"}), ErrorCodes.WRONG_PHASE)


func test_view_for_adds_you_and_no_secrets() -> void:
	var view: Dictionary = LobbyLogic.view_for(_ready_lobby(), "p2")
	assert_eq(view["you"], "p2")
	assert_false(JSON.stringify(view).contains("token"))
