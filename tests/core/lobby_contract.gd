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


func new_player(host: LobbyHostRig, player_name: String) -> LobbyClientRig:
	var rig: LobbyClientRig = LobbyClientRig.new()
	rig.client = LobbyClient.new(env.make_transport(), APP, GAME)
	rig.client.session.clock = clock.as_callable()
	rig.recorder = LobbyClientRecorder.new(rig.client)
	track(rig.client, rig.client.session.transport)
	rig.client.join(host.address, player_name, env.join_config())
	return rig


## Joins and waits until the client has an outcome and (if it joined) has seen a lobby state.
func join_player(host: LobbyHostRig, player_name: String) -> LobbyClientRig:
	var rig: LobbyClientRig = new_player(host, player_name)
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
