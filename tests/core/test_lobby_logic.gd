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


func test_leave_in_game_keeps_the_seat_and_pauses_for_the_host_to_decide() -> void:
	var s: Dictionary = _apply_ok(_ready_lobby(), "p1", {"type": "start"})
	s = _apply_ok(s, "p2", {"type": "leave"})
	assert_eq(s["slots"].size(), 2)
	assert_false(s["slots"][1]["left"], "not gone for good: the host decides")
	assert_false(s["slots"][1]["connected"])
	assert_true(s["paused"])


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


func test_removed_player_cannot_reconnect() -> void:
	var s: Dictionary = _apply_ok(_ready_lobby(), "p1", {"type": "start"})
	s = _apply_ok(s, "p1", {"type": "kick", "player_id": "p2"})
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


# --- resume (loading a save) -----------------------------------------------------

func _in_game_lobby() -> Dictionary:
	var s: Dictionary = _join(_ready_lobby(), "p3", "Cy")
	s = _apply_ok(s, "p3", {"type": "set_ready", "ready": true})
	return _apply_ok(s, "p1", {"type": "start"})


func test_resume_keeps_host_and_puts_everyone_else_offline() -> void:
	var s: Dictionary = _in_game_lobby()
	var r: Dictionary = LobbyLogic.resume(s, "p1")
	assert_true(CoreResult.is_ok(r))
	var resumed: Dictionary = r["state"]
	assert_eq(resumed["host_player_id"], "p1")
	assert_true(resumed["slots"][0]["connected"])
	assert_false(resumed["slots"][1]["connected"])
	assert_false(resumed["slots"][2]["connected"])
	assert_eq(resumed["phase"], LobbyLogic.PHASE_IN_GAME)
	assert_eq(resumed["revision"], s["revision"] + 1)


func test_resume_as_another_player_hands_them_the_host_role() -> void:
	var resumed: Dictionary = LobbyLogic.resume(_in_game_lobby(), "p2")["state"]
	assert_eq(resumed["host_player_id"], "p2")
	assert_true(resumed["slots"][1]["connected"])
	assert_false(resumed["slots"][0]["connected"], "the old host is offline until they rejoin")
	assert_true(resumed["slots"][1]["ready"])
	# the new host has host powers, the old one does not
	assert_eq(_code(resumed, "p1", {"type": "kick", "player_id": "p3"}), ErrorCodes.NOT_HOST)
	assert_true(CoreResult.is_ok(LobbyLogic.apply(resumed, "p2", {"type": "kick", "player_id": "p3"})))


func test_resume_rejects_unknown_or_departed_players_and_leaves_state_alone() -> void:
	var s: Dictionary = _apply_ok(_in_game_lobby(), "p1", {"type": "kick", "player_id": "p3"})
	var snapshot: Dictionary = s.duplicate(true)
	assert_eq(CoreResult.error_code(LobbyLogic.resume(s, "p9")), ErrorCodes.UNKNOWN_PLAYER)
	assert_eq(CoreResult.error_code(LobbyLogic.resume(s, "p3")), ErrorCodes.PLAYER_LEFT)
	assert_eq(s, snapshot)


func test_resumed_players_can_reconnect() -> void:
	var resumed: Dictionary = LobbyLogic.resume(_in_game_lobby(), "p1")["state"]
	var back: Dictionary = _apply_ok(resumed, "p2", {"type": "reconnected"})
	assert_true(back["slots"][1]["connected"])


# --- the host decides: wait, continue, or remove ----------------------------------

func test_a_new_game_is_not_paused() -> void:
	assert_false(_in_game_lobby()["paused"])
	assert_false(LobbyLogic.is_paused(_in_game_lobby()))
	assert_false(LobbyLogic.is_paused(_lobby()), "an open lobby is never paused")


func test_a_drop_in_game_pauses_and_keeps_the_seat() -> void:
	var s: Dictionary = _apply_ok(_in_game_lobby(), "p2", {"type": "disconnected"})
	assert_true(s["paused"])
	assert_true(LobbyLogic.is_paused(s))
	assert_eq(LobbyLogic.away_players(s).size(), 1)
	assert_eq(LobbyLogic.away_players(s)[0]["player_id"], "p2")


func test_coming_back_unpauses_when_nobody_else_is_away() -> void:
	var s: Dictionary = _apply_ok(_in_game_lobby(), "p2", {"type": "disconnected"})
	s = _apply_ok(s, "p3", {"type": "disconnected"})
	s = _apply_ok(s, "p2", {"type": "reconnected"})
	assert_true(s["paused"], "p3 is still away")
	s = _apply_ok(s, "p3", {"type": "reconnected"})
	assert_false(s["paused"])
	assert_eq(LobbyLogic.away_players(s).size(), 0)


func test_host_can_continue_without_waiting_and_the_player_may_still_return() -> void:
	var s: Dictionary = _apply_ok(_in_game_lobby(), "p2", {"type": "disconnected"})
	s = _apply_ok(s, "p1", {"type": "set_paused", "paused": false})
	assert_false(s["paused"])
	assert_eq(LobbyLogic.away_players(s).size(), 1, "the seat is still theirs")
	s = _apply_ok(s, "p2", {"type": "reconnected"})
	assert_true(s["slots"][1]["connected"])


func test_another_drop_asks_the_host_again_even_after_continuing() -> void:
	var s: Dictionary = _apply_ok(_in_game_lobby(), "p2", {"type": "disconnected"})
	s = _apply_ok(s, "p1", {"type": "set_paused", "paused": false})
	s = _apply_ok(s, "p3", {"type": "disconnected"})
	assert_true(s["paused"])


func test_host_can_choose_to_wait_again() -> void:
	var s: Dictionary = _apply_ok(_in_game_lobby(), "p2", {"type": "disconnected"})
	s = _apply_ok(s, "p1", {"type": "set_paused", "paused": false})
	s = _apply_ok(s, "p1", {"type": "set_paused", "paused": true})
	assert_true(s["paused"])


func test_removing_the_last_away_player_unpauses() -> void:
	var s: Dictionary = _apply_ok(_in_game_lobby(), "p2", {"type": "disconnected"})
	s = _apply_ok(s, "p1", {"type": "kick", "player_id": "p2"})
	assert_false(s["paused"])
	assert_true(s["slots"][1]["left"])
	assert_eq(LobbyLogic.away_players(s).size(), 0)


func test_removing_one_of_two_away_players_keeps_waiting_for_the_other() -> void:
	var s: Dictionary = _apply_ok(_in_game_lobby(), "p2", {"type": "disconnected"})
	s = _apply_ok(s, "p3", {"type": "disconnected"})
	s = _apply_ok(s, "p1", {"type": "kick", "player_id": "p2"})
	assert_true(s["paused"])


func test_set_paused_rules() -> void:
	var s: Dictionary = _apply_ok(_in_game_lobby(), "p2", {"type": "disconnected"})
	assert_eq(_code(s, "p3", {"type": "set_paused", "paused": false}), ErrorCodes.NOT_HOST)
	assert_eq(_code(s, "p1", {"type": "set_paused", "paused": "no"}), ErrorCodes.BAD_ACTION)
	assert_eq(_code(s, "p1", {"type": "set_paused"}), ErrorCodes.BAD_ACTION)
	assert_eq(_code(_ready_lobby(), "p1", {"type": "set_paused", "paused": false}), ErrorCodes.WRONG_PHASE)
	assert_eq(_code(_in_game_lobby(), "p1", {"type": "set_paused", "paused": true}), ErrorCodes.NOTHING_TO_WAIT_FOR)


func test_set_paused_is_a_player_action_the_host_may_send_over_the_wire() -> void:
	assert_true(LobbyLogic.PLAYER_ACTIONS.has("set_paused"))


func test_open_lobby_drops_never_pause() -> void:
	var s: Dictionary = _apply_ok(_ready_lobby(), "p2", {"type": "disconnected"})
	assert_false(s["paused"])


func test_resuming_a_save_waits_for_everyone_who_is_offline() -> void:
	var resumed: Dictionary = LobbyLogic.resume(_in_game_lobby(), "p1")["state"]
	assert_true(resumed["paused"])
	var open_resumed: Dictionary = LobbyLogic.resume(_ready_lobby(), "p1")["state"]
	assert_false(open_resumed["paused"], "an open lobby has nothing to pause")


func test_older_saved_states_without_paused_still_work() -> void:
	var s: Dictionary = _in_game_lobby()
	s.erase("paused")
	assert_false(LobbyLogic.is_paused(s))
	var after: Dictionary = _apply_ok(s, "p2", {"type": "disconnected"})
	assert_true(after["paused"])
