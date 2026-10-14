extends GutTest
## Shared handshake/session tests. Not collected itself; each transport has a thin
## test_*.gd that extends this file and overrides make_env().

const APP: String = "1.0.0"
const GAME: String = "test_game"

var env: TransportEnv
var clock: FakeClock
var _pollers: Array = []
var _transports: Array[Transport] = []


func make_env() -> TransportEnv:
	return null


func before_each() -> void:
	env = make_env()
	clock = FakeClock.new()
	_pollers.clear()
	_transports.clear()
	MessageLog.enabled = false
	MessageLog.sink = Callable()


func after_each() -> void:
	for transport: Transport in _transports:
		transport.leave()
	_transports.clear()
	_pollers.clear()
	env.cleanup()
	MessageLog.enabled = OS.is_debug_build()
	MessageLog.sink = Callable()


# --- helpers ---------------------------------------------------------------------

func pump(condition: Callable, max_frames: int = NetWait.DEFAULT_MAX_FRAMES) -> bool:
	return await NetWait.until(self, _pollers, condition, max_frames)


func frames(count: int) -> void:
	await NetWait.frames(self, _pollers, count)


func start_host(options: Dictionary = {}) -> HostRig:
	var rig: HostRig = HostRig.new()
	rig.session = HostSession.new(env.make_transport(), APP, GAME, options)
	rig.session.clock = clock.as_callable()
	rig.recorder = HostRecorder.new(rig.session)
	var info: Dictionary = rig.session.start(env.host_config())
	assert_true(CoreResult.is_ok(info), "host start failed: %s" % str(info))
	rig.address = str(info.get("address", ""))
	_pollers.append(rig.session)
	_transports.append(rig.session.transport)
	return rig


func new_client(host: HostRig, player_name: String, app_version: String = APP, game_id: String = GAME, options: Dictionary = {}) -> ClientRig:
	var rig: ClientRig = ClientRig.new()
	rig.session = ClientSession.new(env.make_transport(), app_version, game_id, options)
	rig.session.clock = clock.as_callable()
	rig.recorder = ClientRecorder.new(rig.session)
	_pollers.append(rig.session)
	_transports.append(rig.session.transport)
	rig.session.join(host.address, player_name, env.join_config())
	return rig


## Joins a client and waits for its outcome (connected, rejected or failed).
func join_and_wait(host: HostRig, player_name: String, app_version: String = APP, game_id: String = GAME, options: Dictionary = {}) -> ClientRig:
	var rig: ClientRig = new_client(host, player_name, app_version, game_id, options)
	var ok: bool = await pump(func() -> bool: return rig.recorder.has_outcome(), 3000)
	assert_true(ok, "client got no outcome")
	return rig


## A bare transport that connects but speaks the protocol by hand.
func raw_connect(host: HostRig) -> TransportRig:
	var rig: TransportRig = TransportRig.new(env.make_transport())
	_pollers.append(rig.transport)
	_transports.append(rig.transport)
	rig.transport.join_session(host.address, env.join_config())
	var ok: bool = await pump(func() -> bool: return rig.recorder.join_ok_count > 0)
	assert_true(ok, "raw client failed to join transport")
	return rig


func raw_reject_code(raw: TransportRig) -> String:
	var rejects: Array[Dictionary] = raw.recorder.messages_of_type(Protocol.T_REJECT)
	if rejects.is_empty():
		return ""
	return str(rejects[0]["message"]["payload"]["code"])


func wait_for_raw_reject(raw: TransportRig) -> bool:
	return await pump(func() -> bool: return not raw.recorder.messages_of_type(Protocol.T_REJECT).is_empty())


# --- success path ----------------------------------------------------------------

func test_successful_handshake() -> void:
	var host: HostRig = start_host()
	var client: ClientRig = await join_and_wait(host, "Asha")
	assert_eq(client.recorder.connected.size(), 1)
	var welcome: Dictionary = client.recorder.connected[0]
	assert_eq(welcome["player_id"], "p1")
	assert_eq(str(welcome["rejoin_token"]).length(), 32)
	assert_eq(client.session.player_id, "p1")
	assert_eq(host.recorder.joined, ["p1"] as Array[String])
	assert_eq(host.session.registry.name_of("p1"), "Asha")
	assert_eq(host.session.registry.token_of("p1"), welcome["rejoin_token"])
	assert_true(client.session.is_active())


func test_name_is_trimmed() -> void:
	var host: HostRig = start_host()
	await join_and_wait(host, "  Asha  ")
	assert_eq(host.session.registry.name_of("p1"), "Asha")


func test_each_player_gets_unique_id_and_token() -> void:
	var host: HostRig = start_host()
	var a: ClientRig = await join_and_wait(host, "A")
	var b: ClientRig = await join_and_wait(host, "B")
	assert_ne(a.session.player_id, b.session.player_id)
	assert_ne(a.session.rejoin_token, b.session.rejoin_token)


func test_welcome_extra_is_included() -> void:
	var host: HostRig = start_host()
	host.session.welcome_extra = func(player_id: String) -> Dictionary: return {"hello_to": player_id}
	var client: ClientRig = await join_and_wait(host, "A")
	assert_eq(client.recorder.connected[0]["hello_to"], "p1")


# --- version / game mismatches ----------------------------------------------------

func test_protocol_mismatch_is_rejected_with_clear_code() -> void:
	var host: HostRig = start_host()
	var raw: TransportRig = await raw_connect(host)
	var hello: Dictionary = Handshake.hello(APP, GAME, "Zed")
	hello["protocol_version"] = 999
	raw.transport.send(Transport.HOST_PEER_ID, hello)
	assert_true(await wait_for_raw_reject(raw))
	assert_eq(raw_reject_code(raw), ErrorCodes.PROTOCOL_MISMATCH)
	assert_string_contains(str(raw.recorder.messages_of_type(Protocol.T_REJECT)[0]["message"]["payload"]["message"]), "999")
	assert_eq(host.recorder.joined.size(), 0)


func test_app_version_mismatch_is_rejected() -> void:
	var host: HostRig = start_host()
	var client: ClientRig = await join_and_wait(host, "Zed", "2.0.0")
	assert_eq(client.recorder.rejected.size(), 1)
	assert_eq(client.recorder.rejected[0]["code"], ErrorCodes.APP_VERSION_MISMATCH)
	assert_string_contains(client.recorder.rejected[0]["message"], "1.0.0")
	assert_eq(client.recorder.connected.size(), 0)
	assert_eq(host.recorder.joined.size(), 0)


func test_wrong_game_is_rejected() -> void:
	var host: HostRig = start_host()
	var client: ClientRig = await join_and_wait(host, "Zed", APP, "other_game")
	assert_eq(client.recorder.rejected[0]["code"], ErrorCodes.WRONG_GAME)
	assert_string_contains(client.recorder.rejected[0]["message"], GAME)
	assert_eq(host.recorder.joined.size(), 0)


func test_protocol_is_checked_before_game_and_version() -> void:
	var host: HostRig = start_host()
	var raw: TransportRig = await raw_connect(host)
	var hello: Dictionary = Handshake.hello("9.9.9", "other_game", "Zed")
	hello["protocol_version"] = 2
	raw.transport.send(Transport.HOST_PEER_ID, hello)
	assert_true(await wait_for_raw_reject(raw))
	assert_eq(raw_reject_code(raw), ErrorCodes.PROTOCOL_MISMATCH)


func test_invalid_names_are_rejected() -> void:
	var host: HostRig = start_host()
	for bad: String in ["", "   ", "x".repeat(Handshake.MAX_NAME_LENGTH + 1), "bad\nname"]:
		var client: ClientRig = await join_and_wait(host, bad)
		assert_eq(client.recorder.rejected.size(), 1, "name '%s'" % bad.c_escape())
		assert_eq(client.recorder.rejected[0]["code"], ErrorCodes.NAME_INVALID)


func test_malformed_hello_is_rejected() -> void:
	var host: HostRig = start_host()
	var raw: TransportRig = await raw_connect(host)
	raw.transport.send(Transport.HOST_PEER_ID, Envelope.make(Protocol.T_HELLO, {"player_name": "x"}))
	assert_true(await wait_for_raw_reject(raw))
	assert_eq(raw_reject_code(raw), ErrorCodes.MALFORMED)


func test_first_message_must_be_hello() -> void:
	var host: HostRig = start_host()
	var raw: TransportRig = await raw_connect(host)
	raw.transport.send(Transport.HOST_PEER_ID, Envelope.make(Protocol.T_GAME_ACTION, {"action": "roll"}))
	assert_true(await wait_for_raw_reject(raw))
	assert_eq(raw_reject_code(raw), ErrorCodes.UNEXPECTED_MESSAGE)
	assert_eq(host.recorder.messages.size(), 0)


func test_rejected_peer_is_disconnected() -> void:
	var host: HostRig = start_host()
	var client: ClientRig = await join_and_wait(host, "Zed", "2.0.0")
	assert_false(client.session.is_active())
	assert_false(client.session.transport.is_active())
	var ok: bool = await pump(func() -> bool: return host.session.transport.get_peer_ids().is_empty())
	assert_true(ok, "host should drop the rejected peer")


func test_unknown_rejoin_identity_is_rejected() -> void:
	var host: HostRig = start_host()
	var client: ClientRig = ClientRig.new()
	client.session = ClientSession.new(env.make_transport(), APP, GAME)
	client.recorder = ClientRecorder.new(client.session)
	_pollers.append(client.session)
	_transports.append(client.session.transport)
	client.session.join(host.address, "Zed", env.join_config(), {"player_id": "p99", "rejoin_token": "nope"})
	var ok: bool = await pump(func() -> bool: return client.recorder.has_outcome(), 3000)
	assert_true(ok)
	assert_eq(client.recorder.rejected[0]["code"], ErrorCodes.BAD_TOKEN)


# --- admission hook ---------------------------------------------------------------

func test_admission_policy_can_refuse() -> void:
	var host: HostRig = start_host()
	host.session.admission_policy = func(_name: String) -> Dictionary: return CoreResult.failure(ErrorCodes.ROOM_FULL, "Room is full.")
	var client: ClientRig = await join_and_wait(host, "Late")
	assert_eq(client.recorder.rejected[0]["code"], ErrorCodes.ROOM_FULL)
	assert_eq(host.session.registry.count(), 0)


# --- connection failures ----------------------------------------------------------

func test_connect_to_nothing_reports_connect_failed() -> void:
	var host: HostRig = start_host()
	host.address = "127.0.0.1:1" if env.host_config().has("port") else "no-such-room"
	var client: ClientRig = await join_and_wait(host, "Zed")
	assert_eq(client.recorder.connect_failed.size(), 1)


# --- limits and liveness ----------------------------------------------------------

func test_handshake_timeout() -> void:
	var host: HostRig = start_host()
	var raw: TransportRig = await raw_connect(host)
	await frames(3)
	clock.now += 6000
	assert_true(await wait_for_raw_reject(raw))
	assert_eq(raw_reject_code(raw), ErrorCodes.HANDSHAKE_TIMEOUT)


func test_pending_handshake_limit() -> void:
	var host: HostRig = start_host({"max_pending_handshakes": 2})
	var first: TransportRig = await raw_connect(host)
	var second: TransportRig = await raw_connect(host)
	var third: TransportRig = await raw_connect(host)
	assert_true(await wait_for_raw_reject(third))
	assert_eq(raw_reject_code(third), ErrorCodes.TOO_MANY_PENDING)
	assert_eq(first.recorder.messages_of_type(Protocol.T_REJECT).size(), 0)
	assert_eq(second.recorder.messages_of_type(Protocol.T_REJECT).size(), 0)


func test_pending_slot_is_freed_after_handshake() -> void:
	var host: HostRig = start_host({"max_pending_handshakes": 1})
	var client: ClientRig = await join_and_wait(host, "A")
	assert_eq(client.recorder.connected.size(), 1)
	var second: ClientRig = await join_and_wait(host, "B")
	assert_eq(second.recorder.connected.size(), 1, "limit applies only to peers still in the handshake")


func test_flooding_player_is_kicked_with_rate_limited() -> void:
	var host: HostRig = start_host({"rate_burst": 5, "rate_per_sec": 1, "max_rate_violations": 3})
	var client: ClientRig = await join_and_wait(host, "Flood")
	for i: int in 30:
		client.session.send(Envelope.make(Protocol.T_GAME_ACTION, {"i": i}))
	var ok: bool = await pump(func() -> bool: return client.recorder.ended.size() >= 1 and host.recorder.left.size() >= 1)
	assert_true(ok)
	assert_eq(client.recorder.ended[0]["code"], ErrorCodes.RATE_LIMITED)
	assert_lte(host.recorder.messages.size(), 5, "only the burst allowance gets through")
	assert_eq(host.recorder.left, ["p1"] as Array[String])


func test_normal_traffic_is_not_rate_limited() -> void:
	var host: HostRig = start_host()
	var client: ClientRig = await join_and_wait(host, "Calm")
	for i: int in 10:
		client.session.send(Envelope.make(Protocol.T_GAME_ACTION, {"i": i}))
		clock.now += 200
	var ok: bool = await pump(func() -> bool: return host.recorder.messages.size() >= 10)
	assert_true(ok)
	assert_eq(host.recorder.left.size(), 0)


func test_silent_client_is_dropped_after_ping_timeout() -> void:
	var host: HostRig = start_host({"ping_interval_msec": 1000, "ping_timeout_msec": 4000})
	var client: ClientRig = await join_and_wait(host, "Ghost")
	_pollers.erase(client.session)  # the client app froze: it never answers pings
	var ok: bool = await pump(func() -> bool:
		clock.now += 500
		return host.recorder.left.size() >= 1)
	assert_true(ok)
	assert_eq(host.recorder.left, ["p1"] as Array[String])


func test_ping_pong_keeps_a_healthy_connection_alive() -> void:
	var host: HostRig = start_host({"ping_interval_msec": 1000, "ping_timeout_msec": 4000})
	var client: ClientRig = await join_and_wait(host, "Alive", APP, GAME, {"host_silence_timeout_msec": 4000})
	for _i: int in 60:
		clock.now += 500
		await frames(3)
	assert_eq(host.recorder.left.size(), 0)
	assert_eq(client.recorder.host_lost.size(), 0)
	assert_true(client.session.is_active())


func test_client_detects_a_silent_host() -> void:
	var host: HostRig = start_host()
	var client: ClientRig = await join_and_wait(host, "Watcher", APP, GAME, {"host_silence_timeout_msec": 3000})
	_pollers.erase(host.session)  # host app froze
	var ok: bool = await pump(func() -> bool:
		clock.now += 500
		return client.recorder.host_lost.size() >= 1)
	assert_true(ok)


# --- routing ---------------------------------------------------------------------

func test_messages_reach_host_tagged_with_player_id() -> void:
	var host: HostRig = start_host()
	var a: ClientRig = await join_and_wait(host, "A")
	var b: ClientRig = await join_and_wait(host, "B")
	b.session.send(Envelope.make(Protocol.T_GAME_ACTION, {"action": "roll"}))
	var ok: bool = await pump(func() -> bool: return host.recorder.messages.size() >= 1)
	assert_true(ok)
	assert_eq(host.recorder.messages[0]["player_id"], b.session.player_id)
	assert_eq(host.recorder.messages[0]["message"]["payload"], {"action": "roll"})
	assert_eq(a.recorder.messages.size(), 0)


func test_host_can_send_to_one_player_or_broadcast() -> void:
	var host: HostRig = start_host()
	var a: ClientRig = await join_and_wait(host, "A")
	var b: ClientRig = await join_and_wait(host, "B")
	host.session.send_to_player(a.session.player_id, Envelope.make(Protocol.T_GAME_STATE, {"for": "a"}))
	host.session.broadcast(Envelope.make(Protocol.T_GAME_STATE, {"for": "all"}))
	var ok: bool = await pump(func() -> bool: return a.recorder.messages.size() >= 2 and b.recorder.messages.size() >= 1)
	assert_true(ok)
	assert_eq(a.recorder.messages[0]["payload"], {"for": "a"})
	assert_eq(b.recorder.messages.size(), 1)
	assert_eq(b.recorder.messages[0]["payload"], {"for": "all"})


func test_liveness_messages_are_not_forwarded_to_game_code() -> void:
	var host: HostRig = start_host({"ping_interval_msec": 500})
	var client: ClientRig = await join_and_wait(host, "A")
	for _i: int in 10:
		clock.now += 600
		await frames(3)
	assert_eq(host.recorder.messages.size(), 0)
	assert_eq(client.recorder.messages.size(), 0)


func test_second_hello_after_welcome_is_refused() -> void:
	var host: HostRig = start_host()
	var client: ClientRig = await join_and_wait(host, "A")
	client.session.send(Handshake.hello(APP, GAME, "A"))
	var ok: bool = await pump(func() -> bool: return client.recorder.ended.size() >= 1)
	assert_true(ok)
	assert_eq(client.recorder.ended[0]["code"], ErrorCodes.UNEXPECTED_MESSAGE)


func test_kick_player_tells_them_why() -> void:
	var host: HostRig = start_host()
	var client: ClientRig = await join_and_wait(host, "A")
	host.session.kick_player("p1", ErrorCodes.KICKED, "Removed by host")
	var ok: bool = await pump(func() -> bool: return client.recorder.ended.size() >= 1 and host.recorder.left.size() >= 1)
	assert_true(ok)
	assert_eq(client.recorder.ended[0]["code"], ErrorCodes.KICKED)
	assert_eq(client.recorder.ended[0]["message"], "Removed by host")


# --- ending ----------------------------------------------------------------------

func test_host_close_tells_clients_the_session_ended() -> void:
	var host: HostRig = start_host()
	var client: ClientRig = await join_and_wait(host, "A")
	host.session.close("Game over, thanks")
	var ok: bool = await pump(func() -> bool: return host.session.is_closed())
	assert_true(ok, "host finishes closing once the client has left")
	assert_eq(client.recorder.ended.size(), 1, "clean close is reported as session_ended")
	assert_eq(client.recorder.host_lost.size(), 0)
	assert_eq(client.recorder.ended[0]["code"], "HOST_CLOSED")
	assert_eq(client.recorder.ended[0]["message"], "Game over, thanks")
	assert_false(host.session.transport.is_active())


func test_close_gives_up_waiting_after_grace_period() -> void:
	var host: HostRig = start_host({"close_grace_msec": 2000})
	var client: ClientRig = await join_and_wait(host, "Stuck")
	_pollers.erase(client.session)  # never reads the goodbye, never leaves
	host.session.close()
	await frames(5)
	assert_false(host.session.is_closed())
	clock.now += 2500
	var ok: bool = await pump(func() -> bool: return host.session.is_closed())
	assert_true(ok)


func test_close_now_is_immediate() -> void:
	var host: HostRig = start_host()
	await join_and_wait(host, "A")
	host.session.close_now()
	assert_true(host.session.is_closed())
	assert_false(host.session.transport.is_active())


func test_joins_during_shutdown_are_refused() -> void:
	var host: HostRig = start_host()
	var first: ClientRig = await join_and_wait(host, "A")
	_pollers.erase(first.session)  # keeps the host from finishing right away
	host.session.close()
	var late: ClientRig = await join_and_wait(host, "Late")
	assert_eq(late.recorder.connected.size(), 0)


func test_host_vanishing_is_reported_as_host_lost() -> void:
	var host: HostRig = start_host()
	var client: ClientRig = await join_and_wait(host, "A")
	host.session.transport.leave()
	var ok: bool = await pump(func() -> bool: return client.recorder.host_lost.size() >= 1)
	assert_true(ok)
	assert_false(client.session.is_active())


func test_client_leaving_is_reported_to_host() -> void:
	var host: HostRig = start_host()
	var client: ClientRig = await join_and_wait(host, "A")
	client.session.leave()
	var ok: bool = await pump(func() -> bool: return host.recorder.left.size() >= 1)
	assert_true(ok)
	assert_eq(host.recorder.left, ["p1"] as Array[String])


# --- logging ---------------------------------------------------------------------

func test_every_message_is_logged_with_type_and_player() -> void:
	var lines: Array[String] = []
	MessageLog.sink = func(line: String) -> void: lines.append(line)
	MessageLog.enabled = true
	var host: HostRig = start_host()
	var client: ClientRig = await join_and_wait(host, "A")
	client.session.send(Envelope.make(Protocol.T_GAME_ACTION, {"action": "roll"}))
	await pump(func() -> bool: return host.recorder.messages.size() >= 1)
	var joined: String = "\n".join(lines)
	assert_string_contains(joined, "<- player=- peer=")
	assert_string_contains(joined, "type=hello")
	assert_string_contains(joined, "-> player=p1")
	assert_string_contains(joined, "type=welcome")
	assert_string_contains(joined, "<- player=p1")
	assert_string_contains(joined, "type=game_action")
	assert_false(joined.contains(client.session.rejoin_token), "tokens must never be logged")
