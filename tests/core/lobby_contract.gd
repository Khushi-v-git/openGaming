extends NetTestCase
## Shared lobby tests (host + clients over a real session). Not collected itself;
## test_lobby_<transport>.gd extends this and overrides make_env().

class LobbyHostRig:
	extends RefCounted
	var lobby: LobbyHost
	var recorder: LobbyHostRecorder
	var address: String = ""

	func state() -> Dictionary:
		return lobby.state


class LobbyClientRig:
	extends RefCounted
	var client: LobbyClient
	var recorder: LobbyClientRecorder


func start_lobby(min_players: int = 2, max_players: int = 4, options: Dictionary = {}) -> LobbyHostRig:
	var rig: LobbyHostRig = LobbyHostRig.new()
	rig.lobby = LobbyHost.new(env.make_transport(), APP, GAME, "Hosty", min_players, max_players, options)
	rig.lobby.session.clock = clock.as_callable()
	rig.recorder = LobbyHostRecorder.new(rig.lobby)
	var info: Dictionary = rig.lobby.start(env.host_config())
	assert_true(CoreResult.is_ok(info), "host start failed: %s" % str(info))
	rig.address = str(info.get("address", ""))
	track(rig.lobby, rig.lobby.session.transport)
	return rig


func new_player(host: LobbyHostRig, player_name: String, identity: Dictionary = {}) -> LobbyClientRig:
	var rig: LobbyClientRig = LobbyClientRig.new()
	rig.client = LobbyClient.new(env.make_transport(), APP, GAME)
	rig.client.session.clock = clock.as_callable()
	rig.recorder = LobbyClientRecorder.new(rig.client)
	track(rig.client, rig.client.session.transport)
	rig.client.join(host.address, player_name, env.join_config(), identity)
	return rig


## Joins and waits until the client has an outcome and (if it joined) has seen a lobby state.
func join_player(host: LobbyHostRig, player_name: String, identity: Dictionary = {}) -> LobbyClientRig:
	var rig: LobbyClientRig = new_player(host, player_name, identity)
	var ok: bool = await pump(func() -> bool:
		return not rig.recorder.join_failures.is_empty() or (not rig.recorder.joined.is_empty() and not rig.recorder.states.is_empty()), 3000)
	assert_true(ok, "client got no outcome")
	return rig


## Waits until every client mirrors the host's current state revision.
func converge(host: LobbyHostRig, clients: Array) -> bool:
	return await pump(func() -> bool:
		for c: LobbyClientRig in clients:
			if c.client.state.is_empty() or c.client.state["revision"] != host.lobby.state["revision"]:
				return false
		return true)


func slot_names(state: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for slot: Dictionary in state["slots"]:
		names.append(slot["name"])
	return names


# --- joining ---------------------------------------------------------------------

func test_new_lobby_has_only_the_host() -> void:
	var host: LobbyHostRig = start_lobby()
	assert_eq(slot_names(host.state()), ["Hosty"] as Array[String])
	assert_eq(host.state()["host_player_id"], host.lobby.local_player_id)
	assert_true(host.state()["slots"][0]["connected"])


func test_players_join_and_everyone_sees_the_same_state() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	var b: LobbyClientRig = await join_player(host, "Bo")
	var c: LobbyClientRig = await join_player(host, "Cy")
	assert_true(await converge(host, [a, b, c]))
	assert_eq(slot_names(host.state()), ["Hosty", "Asha", "Bo", "Cy"] as Array[String])
	for rig: LobbyClientRig in [a, b, c]:
		assert_eq(rig.client.state, host.state())
		assert_false(rig.client.is_host())
	assert_eq(a.client.player_id, host.state()["slots"][1]["player_id"])


func test_full_room_is_rejected_with_room_full() -> void:
	var host: LobbyHostRig = start_lobby(2, 2)
	await join_player(host, "Asha")
	var late: LobbyClientRig = await join_player(host, "Late")
	assert_eq(late.recorder.join_failures.size(), 1)
	assert_eq(late.recorder.join_failures[0]["code"], ErrorCodes.ROOM_FULL)
	assert_eq(host.state()["slots"].size(), 2)


func test_duplicate_name_is_rejected() -> void:
	var host: LobbyHostRig = start_lobby()
	await join_player(host, "Asha")
	var dup: LobbyClientRig = await join_player(host, "asha")
	assert_eq(dup.recorder.join_failures[0]["code"], ErrorCodes.NAME_TAKEN)
	var as_host: LobbyClientRig = await join_player(host, "hosty")
	assert_eq(as_host.recorder.join_failures[0]["code"], ErrorCodes.NAME_TAKEN)


func test_joining_after_start_is_rejected() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	a.client.set_ready(true)
	await converge(host, [a])
	assert_true(CoreResult.is_ok(host.lobby.act({"type": "start"})))
	var late: LobbyClientRig = await join_player(host, "Late")
	assert_eq(late.recorder.join_failures[0]["code"], ErrorCodes.GAME_IN_PROGRESS)


# --- ready and start -------------------------------------------------------------

func test_ready_start_flow() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	var b: LobbyClientRig = await join_player(host, "Bo")
	assert_eq(CoreResult.error_code(host.lobby.act({"type": "start"})), ErrorCodes.NOT_ALL_READY)
	a.client.set_ready(true)
	b.client.set_ready(true)
	assert_true(await converge(host, [a, b]))
	assert_true(LobbyLogic.ready_to_start(host.state()))
	assert_true(CoreResult.is_ok(host.lobby.act({"type": "start"})))
	assert_true(await converge(host, [a, b]))
	assert_eq(host.state()["phase"], LobbyLogic.PHASE_IN_GAME)
	assert_eq(host.recorder.started, 1)
	assert_eq(a.recorder.started, 1)
	assert_eq(b.recorder.started, 1)


func test_player_can_unready() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	a.client.set_ready(true)
	assert_true(await converge(host, [a]))
	a.client.set_ready(false)
	assert_true(await converge(host, [a]))
	assert_false(host.state()["slots"][1]["ready"])


func test_only_host_can_start() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	a.client.set_ready(true)
	await converge(host, [a])
	a.client.start_game()
	assert_true(await pump(func() -> bool: return a.recorder.action_failures.size() >= 1))
	assert_eq(a.recorder.action_failures[0]["code"], ErrorCodes.NOT_HOST)
	assert_eq(a.recorder.action_failures[0]["action"], "start")
	assert_eq(host.state()["phase"], LobbyLogic.PHASE_OPEN)


func test_set_name_updates_everyone_and_the_registry() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	a.client.set_name("Ashley")
	assert_true(await pump(func() -> bool: return host.state()["slots"][1]["name"] == "Ashley"))
	assert_eq(host.lobby.session.registry.name_of(a.client.player_id), "Ashley")
	assert_true(await converge(host, [a]))


# --- leaving, kicking, dropping --------------------------------------------------

func test_client_leave_removes_slot_for_everyone() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	var b: LobbyClientRig = await join_player(host, "Bo")
	assert_true(await converge(host, [a, b]))
	a.client.leave()
	assert_true(await pump(func() -> bool: return host.state()["slots"].size() == 2))
	assert_true(await converge(host, [b]))
	assert_eq(slot_names(b.client.state), ["Hosty", "Bo"] as Array[String])


func test_dropped_connection_removes_slot_in_open_lobby() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	var b: LobbyClientRig = await join_player(host, "Bo")
	assert_true(await converge(host, [a, b]))
	a.client.session.transport.leave()  # abrupt: no goodbye
	assert_true(await pump(func() -> bool: return host.state()["slots"].size() == 2))
	assert_true(await converge(host, [b]))


func test_dropped_connection_keeps_slot_during_game() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	a.client.set_ready(true)
	await converge(host, [a])
	host.lobby.act({"type": "start"})
	await converge(host, [a])
	a.client.session.transport.leave()
	assert_true(await pump(func() -> bool: return not host.state()["slots"][1]["connected"]))
	assert_eq(host.state()["slots"].size(), 2, "slot is kept so the player can come back")
	assert_false(host.state()["slots"][1]["left"])


func test_host_can_kick_a_player() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	var b: LobbyClientRig = await join_player(host, "Bo")
	assert_true(await converge(host, [a, b]))
	assert_true(CoreResult.is_ok(host.lobby.act({"type": "kick", "player_id": a.client.player_id})))
	assert_true(await pump(func() -> bool: return a.recorder.left.size() >= 1))
	assert_eq(a.recorder.left[0]["code"], ErrorCodes.KICKED)
	assert_true(await converge(host, [b]))
	assert_eq(slot_names(host.state()), ["Hosty", "Bo"] as Array[String])


func test_player_cannot_kick() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	var b: LobbyClientRig = await join_player(host, "Bo")
	assert_true(await converge(host, [a, b]))
	a.client.kick(b.client.player_id)
	assert_true(await pump(func() -> bool: return a.recorder.action_failures.size() >= 1))
	assert_eq(a.recorder.action_failures[0]["code"], ErrorCodes.NOT_HOST)
	assert_eq(host.state()["slots"].size(), 3)


# --- host going away -------------------------------------------------------------

func test_host_close_tells_players_the_session_ended() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	var b: LobbyClientRig = await join_player(host, "Bo")
	assert_true(await converge(host, [a, b]))
	host.lobby.close("Thanks for playing")
	assert_true(await pump(func() -> bool: return a.recorder.left.size() >= 1 and b.recorder.left.size() >= 1 and host.recorder.closed == 1))
	assert_eq(a.recorder.left[0]["code"], "HOST_CLOSED")
	assert_eq(a.recorder.left[0]["message"], "Thanks for playing")


func test_host_disconnect_is_reported_to_players() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	var b: LobbyClientRig = await join_player(host, "Bo")
	assert_true(await converge(host, [a, b]))
	host.lobby.session.transport.leave()  # the host app died without saying goodbye
	assert_true(await pump(func() -> bool: return a.recorder.left.size() >= 1 and b.recorder.left.size() >= 1))
	assert_eq(a.recorder.left[0]["code"], ErrorCodes.HOST_LOST)
	assert_eq(b.recorder.left[0]["code"], ErrorCodes.HOST_LOST)


func test_host_survives_a_player_vanishing_mid_game() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	var b: LobbyClientRig = await join_player(host, "Bo")
	a.client.set_ready(true)
	b.client.set_ready(true)
	await converge(host, [a, b])
	host.lobby.act({"type": "start"})
	await converge(host, [a, b])
	a.client.session.transport.leave()
	assert_true(await pump(func() -> bool: return not host.state()["slots"][1]["connected"]))
	assert_eq(host.state()["phase"], LobbyLogic.PHASE_IN_GAME, "game continues")
	assert_true(b.client.session.is_active())


# --- abuse -----------------------------------------------------------------------

func test_system_actions_cannot_be_sent_by_clients() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	assert_true(await converge(host, [a]))
	var before: Dictionary = host.state().duplicate(true)
	for sneaky: String in ["join", "disconnected", "reconnected"]:
		a.client.act({"type": sneaky, "name": "Mallory"})
	assert_true(await pump(func() -> bool: return a.recorder.action_failures.size() >= 3))
	for failure: Dictionary in a.recorder.action_failures:
		assert_eq(failure["code"], ErrorCodes.UNKNOWN_ACTION)
	assert_eq(host.state(), before)


func test_malformed_lobby_action_is_answered_with_an_error() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	a.client.session.send(Envelope.make(Protocol.T_LOBBY_ACTION, {"action": 5}))
	assert_true(await pump(func() -> bool: return a.recorder.action_failures.size() >= 1))
	assert_eq(a.recorder.action_failures[0]["code"], ErrorCodes.MALFORMED)


func test_a_player_can_only_act_for_themselves() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	var b: LobbyClientRig = await join_player(host, "Bo")
	assert_true(await converge(host, [a, b]))
	a.client.act({"type": "set_ready", "ready": true, "player_id": b.client.player_id})
	assert_true(await converge(host, [a, b]))
	assert_true(host.state()["slots"][1]["ready"], "Asha is ready")
	assert_false(host.state()["slots"][2]["ready"], "Bo is not")


func test_game_traffic_is_passed_up_not_interpreted() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	a.client.session.send(Envelope.make(Protocol.T_GAME_ACTION, {"action": "roll"}))
	assert_true(await pump(func() -> bool: return host.recorder.game_messages.size() >= 1))
	assert_eq(host.recorder.game_messages[0]["player_id"], a.client.player_id)
	assert_eq(host.recorder.game_messages[0]["message"]["payload"], {"action": "roll"})


# --- polite leave ----------------------------------------------------------------

func test_polite_leave_is_recorded_by_the_host_even_mid_game() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	a.client.set_ready(true)
	await converge(host, [a])
	host.lobby.act({"type": "start"})
	await converge(host, [a])
	a.client.leave()
	assert_true(await pump(func() -> bool: return a.recorder.left.size() >= 1))
	assert_eq(a.recorder.left[0]["code"], ErrorCodes.LEFT)
	assert_true(await pump(func() -> bool: return host.state()["slots"][1]["left"]))
	assert_false(host.state()["slots"][1]["connected"])


func test_leave_gives_up_waiting_for_a_silent_host() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	_pollers.erase(host.lobby)  # host froze: never answers the leave
	a.client.leave()
	await frames(3)
	assert_eq(a.recorder.left.size(), 0)
	clock.now += 2000
	assert_true(await pump(func() -> bool: return a.recorder.left.size() >= 1))
	assert_eq(a.recorder.left[0]["code"], ErrorCodes.LEFT)


# --- reconnect / rejoin ----------------------------------------------------------

func _start_game_with(host: LobbyHostRig, players: Array) -> void:
	for p: LobbyClientRig in players:
		p.client.set_ready(true)
	await converge(host, players)
	assert_true(CoreResult.is_ok(host.lobby.act({"type": "start"})))
	await converge(host, players)


func test_dropped_player_rejoins_and_gets_full_state() -> void:
	var host: LobbyHostRig = start_lobby()
	host.lobby.game_view_provider = func(player_id: String) -> Dictionary: return {"you": player_id, "board": [1, 2, 3]}
	var a: LobbyClientRig = await join_player(host, "Asha")
	var b: LobbyClientRig = await join_player(host, "Bo")
	await _start_game_with(host, [a, b])
	var identity: Dictionary = a.client.identity()
	a.client.session.transport.leave()  # network loss
	assert_true(await pump(func() -> bool: return not host.state()["slots"][1]["connected"]))
	assert_eq(host.state()["phase"], LobbyLogic.PHASE_IN_GAME, "host keeps the game going")

	var a2: LobbyClientRig = await join_player(host, "Asha", identity)
	assert_eq(a2.recorder.joined, [identity["player_id"]] as Array[String], "same player_id")
	assert_true(await converge(host, [a2, b]))
	assert_true(host.state()["slots"][1]["connected"])
	assert_eq(host.state()["slots"].size(), 3)
	assert_eq(a2.client.state, host.state(), "full lobby state resent")
	assert_true(await pump(func() -> bool: return not a2.recorder.game_messages.is_empty()))
	var resent: Dictionary = a2.recorder.game_messages[0]
	assert_eq(resent["type"], Protocol.T_GAME_STATE)
	assert_eq(resent["payload"], {"rejoin": true, "view": {"you": identity["player_id"], "board": [1, 2, 3]}})
	assert_eq(host.lobby.session.registry.count(), 3, "no duplicate player was created")


func test_rejoin_rotates_the_token() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	await _start_game_with(host, [a])
	var old_identity: Dictionary = a.client.identity()
	a.client.session.transport.leave()
	await pump(func() -> bool: return not host.state()["slots"][1]["connected"])
	var a2: LobbyClientRig = await join_player(host, "Asha", old_identity)
	assert_ne(a2.client.identity()["rejoin_token"], old_identity["rejoin_token"])
	assert_eq(a2.client.identity()["rejoin_token"], host.lobby.session.registry.token_of(old_identity["player_id"]))


func test_old_token_works_until_the_new_one_is_confirmed() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	await _start_game_with(host, [a])
	var token_a: Dictionary = a.client.identity()
	a.client.session.transport.leave()
	await pump(func() -> bool: return not host.state()["slots"][1]["connected"])

	# Rejoin #1 gets token B, but the connection dies before the client ever speaks.
	var first: LobbyClientRig = await join_player(host, "Asha", token_a)
	assert_eq(first.recorder.joined.size(), 1)
	first.client.session.transport.leave()
	await pump(func() -> bool: return not host.state()["slots"][1]["connected"])

	# Token A is still good because B was never confirmed (the welcome may have been lost).
	var second: LobbyClientRig = await join_player(host, "Asha", token_a)
	assert_eq(second.recorder.joined.size(), 1, "old token still accepted")

	# The client speaks: that confirms the newest token and retires token A.
	second.client.session.send(Envelope.make(Protocol.T_GAME_ACTION, {"action": "hello again"}))
	assert_true(await pump(func() -> bool: return not host.recorder.game_messages.is_empty()))
	second.client.session.transport.leave()
	await pump(func() -> bool: return not host.state()["slots"][1]["connected"])
	var stale: LobbyClientRig = await join_player(host, "Asha", token_a)
	assert_eq(stale.recorder.join_failures[0]["code"], ErrorCodes.BAD_TOKEN)
	var current: LobbyClientRig = await join_player(host, "Asha", second.client.identity())
	assert_eq(current.recorder.joined.size(), 1)


func test_wrong_token_and_unknown_player_get_the_same_rejection() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	await _start_game_with(host, [a])
	var wrong_token: LobbyClientRig = await join_player(host, "Asha", {"player_id": a.client.player_id, "rejoin_token": "nope"})
	var unknown: LobbyClientRig = await join_player(host, "Asha", {"player_id": "p99", "rejoin_token": a.client.identity()["rejoin_token"]})
	assert_eq(wrong_token.recorder.join_failures[0]["code"], ErrorCodes.BAD_TOKEN)
	assert_eq(unknown.recorder.join_failures[0]["code"], ErrorCodes.BAD_TOKEN)
	assert_eq(wrong_token.recorder.join_failures[0]["message"], unknown.recorder.join_failures[0]["message"])
	assert_true(host.state()["slots"][1]["connected"], "the real player is unaffected")


func test_rejoin_replaces_a_connection_the_host_has_not_noticed_dying() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	await _start_game_with(host, [a])
	var seen_disconnected: Array[bool] = [false]
	host.lobby.state_changed.connect(func(state: Dictionary) -> void:
		if not state["slots"][1]["connected"]:
			seen_disconnected[0] = true)
	var a2: LobbyClientRig = await join_player(host, "Asha", a.client.identity())
	assert_eq(a2.recorder.joined.size(), 1)
	assert_true(await pump(func() -> bool: return a.recorder.left.size() >= 1))
	assert_eq(a.recorder.left[0]["code"], ErrorCodes.REPLACED)
	await frames(10)
	assert_false(seen_disconnected[0], "the swap must not flap the player to disconnected")
	assert_true(host.state()["slots"][1]["connected"])
	assert_eq(host.lobby.session.connected_player_ids().size(), 1)


func test_rejoin_in_open_lobby_takes_a_seat_again() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	a.client.set_ready(true)
	await converge(host, [a])
	var identity: Dictionary = a.client.identity()
	a.client.session.transport.leave()
	assert_true(await pump(func() -> bool: return host.state()["slots"].size() == 1))
	var a2: LobbyClientRig = await join_player(host, "Asha", identity)
	assert_eq(a2.recorder.joined, [identity["player_id"]] as Array[String])
	assert_true(await converge(host, [a2]))
	assert_eq(host.state()["slots"].size(), 2)
	assert_false(host.state()["slots"][1]["ready"], "ready is not remembered across a drop")
	assert_eq(a2.recorder.game_messages.size(), 0, "no game state exists yet in an open lobby")


func test_rejoin_is_refused_if_the_seat_was_taken() -> void:
	var host: LobbyHostRig = start_lobby(2, 2)
	var a: LobbyClientRig = await join_player(host, "Asha")
	var identity: Dictionary = a.client.identity()
	a.client.session.transport.leave()
	await pump(func() -> bool: return host.state()["slots"].size() == 1)
	var b: LobbyClientRig = await join_player(host, "Bo")
	assert_eq(b.recorder.joined.size(), 1)
	var a2: LobbyClientRig = await join_player(host, "Asha", identity)
	assert_eq(a2.recorder.join_failures[0]["code"], ErrorCodes.ROOM_FULL)


func test_kicked_player_cannot_come_back() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	var identity: Dictionary = a.client.identity()
	host.lobby.act({"type": "kick", "player_id": a.client.player_id})
	assert_true(await pump(func() -> bool: return a.recorder.left.size() >= 1))
	var again: LobbyClientRig = await join_player(host, "Asha", identity)
	assert_eq(again.recorder.join_failures[0]["code"], ErrorCodes.BAD_TOKEN)
	assert_eq(host.state()["slots"].size(), 1)


func test_player_who_left_the_open_lobby_cannot_use_the_old_identity() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	var identity: Dictionary = a.client.identity()
	a.client.leave()
	assert_true(await pump(func() -> bool: return a.recorder.left.size() >= 1))
	var again: LobbyClientRig = await join_player(host, "Asha", identity)
	assert_eq(again.recorder.join_failures[0]["code"], ErrorCodes.BAD_TOKEN)


func test_player_removed_or_gone_mid_game_cannot_rejoin() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	var b: LobbyClientRig = await join_player(host, "Bo")
	await _start_game_with(host, [a, b])
	var a_identity: Dictionary = a.client.identity()
	var b_identity: Dictionary = b.client.identity()
	host.lobby.act({"type": "kick", "player_id": a.client.player_id})
	b.client.leave()
	await pump(func() -> bool: return host.state()["slots"][1]["left"] and host.state()["slots"][2]["left"])
	var a2: LobbyClientRig = await join_player(host, "Asha", a_identity)
	var b2: LobbyClientRig = await join_player(host, "Bo", b_identity)
	assert_eq(a2.recorder.join_failures[0]["code"], ErrorCodes.PLAYER_LEFT)
	assert_eq(b2.recorder.join_failures[0]["code"], ErrorCodes.PLAYER_LEFT)


func test_players_who_dropped_before_start_have_no_identity_afterwards() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	var b: LobbyClientRig = await join_player(host, "Bo")
	var a_identity: Dictionary = a.client.identity()
	a.client.session.transport.leave()
	await pump(func() -> bool: return host.state()["slots"].size() == 2)
	b.client.set_ready(true)
	await converge(host, [b])
	host.lobby.act({"type": "start"})
	await converge(host, [b])
	assert_eq(host.lobby.session.registry.count(), 2, "host + Bo only")
	var late: LobbyClientRig = await join_player(host, "Asha", a_identity)
	assert_eq(late.recorder.join_failures[0]["code"], ErrorCodes.BAD_TOKEN)


func test_host_tolerates_every_player_dropping_and_they_can_all_come_back() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	var b: LobbyClientRig = await join_player(host, "Bo")
	await _start_game_with(host, [a, b])
	var ids: Array[Dictionary] = [a.client.identity(), b.client.identity()]
	a.client.session.transport.leave()
	b.client.session.transport.leave()
	assert_true(await pump(func() -> bool: return not host.state()["slots"][1]["connected"] and not host.state()["slots"][2]["connected"]))
	assert_eq(host.state()["phase"], LobbyLogic.PHASE_IN_GAME)
	assert_true(host.lobby.session.transport.is_active())
	var a2: LobbyClientRig = await join_player(host, "Asha", ids[0])
	var b2: LobbyClientRig = await join_player(host, "Bo", ids[1])
	assert_eq(a2.recorder.joined.size() + b2.recorder.joined.size(), 2)
	assert_true(await converge(host, [a2, b2]))
	assert_true(host.state()["slots"][1]["connected"] and host.state()["slots"][2]["connected"])


func test_rejoin_still_checks_the_app_version() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	var identity: Dictionary = a.client.identity()
	var wrong: LobbyClientRig = LobbyClientRig.new()
	wrong.client = LobbyClient.new(env.make_transport(), "9.9.9", GAME)
	wrong.recorder = LobbyClientRecorder.new(wrong.client)
	track(wrong.client, wrong.client.session.transport)
	wrong.client.join(host.address, "Asha", env.join_config(), identity)
	assert_true(await pump(func() -> bool: return wrong.recorder.has_outcome(), 3000))
	assert_eq(wrong.recorder.join_failures[0]["code"], ErrorCodes.APP_VERSION_MISMATCH)


# --- save and resume -------------------------------------------------------------

## A fresh host process loading a save. Returns the rig plus the restore result.
func resume_lobby(saved: Dictionary, as_player_id: String = "", app_version: String = APP, game_id: String = GAME) -> Array:
	var rig: LobbyHostRig = LobbyHostRig.new()
	rig.lobby = LobbyHost.new(env.make_transport(), app_version, game_id, "placeholder", 2, 4)
	rig.lobby.session.clock = clock.as_callable()
	rig.recorder = LobbyHostRecorder.new(rig.lobby)
	var restored: Dictionary = rig.lobby.restore(saved, as_player_id)
	if CoreResult.is_ok(restored):
		var info: Dictionary = rig.lobby.start(env.host_config())
		assert_true(CoreResult.is_ok(info), "resumed host failed to start: %s" % str(info))
		rig.address = str(info.get("address", ""))
	track(rig.lobby, rig.lobby.session.transport)
	return [rig, restored]


## Plays a 3-player game up to the point of saving; returns {snapshot, a, b} where a and
## b are the clients' identities before the "crash".
func play_and_save(game_state: Dictionary) -> Dictionary:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	var b: LobbyClientRig = await join_player(host, "Bo")
	await _start_game_with(host, [a, b])
	# through text, exactly as a save file would travel
	var text: String = SessionSnapshot.to_text(host.lobby.snapshot(game_state))
	var saved: Dictionary = SessionSnapshot.from_text(text)["snapshot"]
	var identities: Dictionary = {"a": a.client.identity(), "b": b.client.identity(), "host_id": host.lobby.local_player_id}
	host.lobby.session.transport.leave()  # the host app is gone
	await pump(func() -> bool: return a.recorder.left.size() >= 1 and b.recorder.left.size() >= 1)
	return {"snapshot": saved, "ids": identities}


func test_resume_as_same_host_players_rejoin_with_saved_identities() -> void:
	var played: Dictionary = await play_and_save({"turn": 3})
	var saved: Dictionary = played["snapshot"]
	var ids: Dictionary = played["ids"]

	var resumed: Array = resume_lobby(saved)
	var host: LobbyHostRig = resumed[0]
	assert_true(CoreResult.is_ok(resumed[1]))
	assert_eq(resumed[1]["game_state"], {"turn": 3}, "the game gets its own state back")
	assert_eq(host.state()["phase"], LobbyLogic.PHASE_IN_GAME)
	assert_eq(host.lobby.local_player_id, ids["host_id"])
	assert_eq(host.state()["slots"].size(), 3)
	assert_true(host.state()["slots"][0]["connected"])
	assert_false(host.state()["slots"][1]["connected"], "offline until they rejoin")
	assert_false(host.state()["slots"][2]["connected"])
	host.lobby.game_view_provider = func(player_id: String) -> Dictionary: return {"you": player_id, "turn": 3}

	var a2: LobbyClientRig = await join_player(host, "Asha", ids["a"])
	var b2: LobbyClientRig = await join_player(host, "Bo", ids["b"])
	assert_eq(a2.recorder.joined, [ids["a"]["player_id"]] as Array[String], "same player ids as before")
	assert_eq(b2.recorder.joined, [ids["b"]["player_id"]] as Array[String])
	assert_true(await converge(host, [a2, b2]))
	assert_true(host.state()["slots"][1]["connected"] and host.state()["slots"][2]["connected"])
	assert_ne(a2.client.identity()["rejoin_token"], ids["a"]["rejoin_token"], "token rotated on the first rejoin")
	assert_ne(b2.client.identity()["rejoin_token"], ids["b"]["rejoin_token"])
	assert_true(await pump(func() -> bool: return not a2.recorder.game_messages.is_empty()))
	assert_eq(a2.recorder.game_messages[0]["payload"]["view"], {"you": ids["a"]["player_id"], "turn": 3})


func test_resume_as_a_different_player_makes_them_host() -> void:
	var played: Dictionary = await play_and_save({"turn": 7})
	var saved: Dictionary = played["snapshot"]
	var ids: Dictionary = played["ids"]
	var new_host_id: String = ids["b"]["player_id"]

	var resumed: Array = resume_lobby(saved, new_host_id)
	var host: LobbyHostRig = resumed[0]
	assert_true(CoreResult.is_ok(resumed[1]))
	assert_eq(host.lobby.local_player_id, new_host_id)
	assert_eq(host.state()["host_player_id"], new_host_id)

	# The previous host comes back as an ordinary player, using the identity in the save.
	var old_host: LobbyClientRig = await join_player(host, "Hosty", SessionSnapshot.identity_of(saved, ids["host_id"]))
	assert_eq(old_host.recorder.joined, [ids["host_id"]] as Array[String])
	assert_true(await converge(host, [old_host]))
	assert_false(old_host.client.is_host())
	assert_eq(CoreResult.error_code(host.lobby.act({"type": "kick", "player_id": "nobody"})), ErrorCodes.UNKNOWN_PLAYER, "the new host has host powers")
	old_host.client.start_game()
	assert_true(await pump(func() -> bool: return not old_host.recorder.action_failures.is_empty()))
	assert_eq(old_host.recorder.action_failures[0]["code"], ErrorCodes.NOT_HOST, "and the old host no longer does")


func test_resumed_game_turns_away_strangers() -> void:
	var played: Dictionary = await play_and_save({})
	var host: LobbyHostRig = resume_lobby(played["snapshot"])[0]
	var stranger: LobbyClientRig = await join_player(host, "Newbie")
	assert_eq(stranger.recorder.join_failures[0]["code"], ErrorCodes.GAME_IN_PROGRESS)


func test_a_leaked_save_stops_working_once_the_real_player_is_back() -> void:
	var played: Dictionary = await play_and_save({})
	var saved: Dictionary = played["snapshot"]
	var host: LobbyHostRig = resume_lobby(saved)[0]
	var real: LobbyClientRig = await join_player(host, "Asha", played["ids"]["a"])
	assert_eq(real.recorder.joined.size(), 1)
	real.client.session.send(Envelope.make(Protocol.T_GAME_ACTION, {"action": "move"}))
	assert_true(await pump(func() -> bool: return not host.recorder.game_messages.is_empty()), "first message confirms the new token")
	real.client.session.transport.leave()
	await pump(func() -> bool: return not host.state()["slots"][1]["connected"])
	var thief: LobbyClientRig = await join_player(host, "Asha", played["ids"]["a"])
	assert_eq(thief.recorder.join_failures[0]["code"], ErrorCodes.BAD_TOKEN)


func test_a_save_for_another_game_or_app_version_is_refused() -> void:
	var played: Dictionary = await play_and_save({})
	var other_version: Array = resume_lobby(played["snapshot"], "", "2.0.0")
	assert_eq(CoreResult.error_code(other_version[1]), ErrorCodes.APP_VERSION_MISMATCH)
	var other_game: Array = resume_lobby(played["snapshot"], "", APP, "other_game")
	assert_eq(CoreResult.error_code(other_game[1]), ErrorCodes.WRONG_GAME)


func test_resume_refuses_a_player_who_left_or_does_not_exist() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	var b: LobbyClientRig = await join_player(host, "Bo")
	await _start_game_with(host, [a, b])
	a.client.leave()
	await pump(func() -> bool: return host.state()["slots"][1]["left"])
	var saved: Dictionary = host.lobby.snapshot({})
	assert_eq(CoreResult.error_code(resume_lobby(saved, a.client.player_id)[1]), ErrorCodes.PLAYER_LEFT)
	assert_eq(CoreResult.error_code(resume_lobby(saved, "p99")[1]), ErrorCodes.UNKNOWN_PLAYER)


func test_a_save_can_only_be_loaded_before_hosting_starts() -> void:
	var host: LobbyHostRig = start_lobby()
	var saved: Dictionary = host.lobby.snapshot({})
	assert_eq(CoreResult.error_code(host.lobby.restore(saved)), ErrorCodes.WRONG_PHASE)


func test_an_open_lobby_can_be_saved_and_resumed_too() -> void:
	var host: LobbyHostRig = start_lobby()
	var a: LobbyClientRig = await join_player(host, "Asha")
	a.client.set_ready(true)
	await converge(host, [a])
	var saved: Dictionary = SessionSnapshot.from_text(SessionSnapshot.to_text(host.lobby.snapshot({})))["snapshot"]
	var identity: Dictionary = a.client.identity()
	host.lobby.session.transport.leave()
	await pump(func() -> bool: return a.recorder.left.size() >= 1)

	var resumed: LobbyHostRig = resume_lobby(saved)[0]
	assert_eq(resumed.state()["phase"], LobbyLogic.PHASE_OPEN)
	assert_eq(CoreResult.error_code(resumed.lobby.act({"type": "start"})), ErrorCodes.NOT_ALL_READY, "Asha is still offline")
	var a2: LobbyClientRig = await join_player(resumed, "Asha", identity)
	assert_eq(a2.recorder.joined.size(), 1)
	assert_true(await converge(resumed, [a2]))
	assert_true(resumed.state()["slots"][1]["connected"])
	a2.client.set_ready(true)
	assert_true(await pump(func() -> bool: return LobbyLogic.ready_to_start(resumed.state())))
	assert_true(CoreResult.is_ok(resumed.lobby.act({"type": "start"})))
