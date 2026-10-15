extends NetTestCase
## RelayTransport against a scripted relay that speaks the real wire format on localhost: the
## protocol behaviour, error mapping, reconnect and the keepalive, without Node or wrangler.
## (The shared transport, session and lobby contract suites run on the real relay separately.)

var relay: ScriptedRelay
var rig_host: Dictionary  # {transport, rec}


func make_env() -> TransportEnv:
	return TransportEnv.new()


func before_each() -> void:
	super.before_each()
	relay = ScriptedRelay.new()
	relay.start()
	_pollers.append(relay)


func after_each() -> void:
	super.after_each()
	relay.stop()


func _config(extra: Dictionary = {}) -> Dictionary:
	var config: Dictionary = {"relay_url": relay.url(), "join_timeout_msec": 2500}
	config.merge(extra, true)
	return config


class Rig extends RefCounted:
	var transport: RelayTransport
	var rec: TransportRecorder
	var links: Array[String] = []


func _rig(fake_clock: bool = false) -> Rig:
	var rig: Rig = Rig.new()
	rig.transport = RelayTransport.new()
	if fake_clock:
		rig.transport.clock = clock.as_callable()
	rig.rec = TransportRecorder.new(rig.transport)
	rig.transport.link_state_changed.connect(func(state: String) -> void: rig.links.append(state))
	track(rig.transport, rig.transport)
	return rig


func _host(extra: Dictionary = {}, fake_clock: bool = false) -> Rig:
	var rig: Rig = _rig(fake_clock)
	assert_true(CoreResult.is_ok(rig.transport.host_session(_config(extra))))
	assert_true(await pump(func() -> bool: return not rig.rec.ready.is_empty() or not rig.rec.host_failures.is_empty()))
	return rig


func _join(code: String = ScriptedRelay.CODE, extra: Dictionary = {}, fake_clock: bool = false) -> Rig:
	var rig: Rig = _rig(fake_clock)
	rig.transport.join_session(code, _config(extra))
	assert_true(await pump(func() -> bool: return rig.rec.join_ok_count > 0 or not rig.rec.join_failures.is_empty()))
	return rig


func _msg(text: String) -> Dictionary:
	return Envelope.make("game_action", {"text": text})


# --- hosting ---------------------------------------------------------------------------------------------

func test_hosting_reports_the_room_code_and_what_to_call_it() -> void:
	var host: Rig = await _host()
	assert_eq(host.rec.ready.size(), 1)
	var info: Dictionary = host.rec.ready[0]
	assert_eq(info["address"], ScriptedRelay.CODE)
	assert_eq(info["kind"], "relay")
	assert_eq(info["share_label"], "room code")
	assert_eq(relay.paths, ["/host"])
	assert_eq(host.transport.room_code(), ScriptedRelay.CODE)


func test_hosting_needs_a_relay_url_and_refuses_a_nonsense_one() -> void:
	var t: RelayTransport = RelayTransport.new()
	assert_eq(CoreResult.error_code(t.host_session({})), "NO_RELAY")
	assert_eq(CoreResult.error_code(t.host_session({"relay_url": "https://example.com"})), "BAD_RELAY_URL")
	assert_false(t.is_active())


func test_a_relay_that_refuses_hosting_gives_host_failed_with_a_readable_reason() -> void:
	relay.refuse_hosting_with = "RELAY_BUSY"
	var host: Rig = await _host()
	assert_eq(host.rec.ready.size(), 0)
	assert_eq(host.rec.host_failures.size(), 1)
	assert_string_contains(host.rec.host_failures[0], "busy")
	assert_eq(host.transport.last_error_code, "RELAY_BUSY")
	assert_false(host.transport.is_active())


func test_a_relay_that_cannot_be_reached_is_reported_as_busy() -> void:
	var rig: Rig = _rig()
	relay.stop()
	assert_true(CoreResult.is_ok(rig.transport.host_session(_config({"join_timeout_msec": 600}))))
	assert_true(await pump(func() -> bool: return not rig.rec.host_failures.is_empty(), 900))
	assert_string_contains(rig.rec.host_failures[0], "relay")


# --- joining ---------------------------------------------------------------------------------------------------

func test_joining_succeeds_and_the_host_sees_a_numbered_peer() -> void:
	var host: Rig = await _host()
	var guest: Rig = await _join()
	assert_eq(guest.rec.join_ok_count, 1)
	assert_true(await pump(func() -> bool: return host.rec.connected.size() == 1))
	assert_eq(host.rec.connected, [2])
	assert_eq(guest.transport.get_peer_ids(), [Transport.HOST_PEER_ID])
	assert_eq(relay.paths, ["/host", "/join/" + ScriptedRelay.CODE])


func test_the_code_is_accepted_as_typed() -> void:
	var host: Rig = await _host()
	var guest: Rig = await _join(" abc-de2 ")
	assert_eq(guest.rec.join_ok_count, 1, "lower case, spaces and a hyphen are fine")
	assert_eq(relay.paths.back(), "/join/ABCDE2")


func test_something_that_is_not_a_room_code_fails_before_touching_the_network() -> void:
	var guest: Rig = await _join("not-a-code!")
	assert_eq(guest.rec.join_failures.size(), 1)
	assert_string_contains(guest.rec.join_failures[0], "room code")
	assert_eq(relay.paths.size(), 0)


func test_every_relay_error_has_its_own_readable_join_failure() -> void:
	for code: String in ["ROOM_NOT_FOUND", "ROOM_FULL", "HOST_AWAY", "RATE_LIMITED", "RELAY_BUSY"]:
		relay.refuse_joins_with = code
		var guest: Rig = await _join()
		assert_eq(guest.rec.join_failures.size(), 1, code)
		assert_eq(guest.rec.join_failures[0], RelayTransport.REASONS[code], code)
		assert_eq(guest.transport.last_error_code, code)
		assert_false(guest.transport.is_active(), code)


func test_an_unknown_room_is_room_not_found() -> void:
	await _host()
	var guest: Rig = await _join("ZZZZZ9")
	assert_eq(guest.rec.join_failures[0], RelayTransport.REASONS["ROOM_NOT_FOUND"])


func test_an_unexpected_close_or_an_unknown_error_while_joining_is_reported_as_the_relay_being_busy() -> void:
	relay.refuse_joins_with = "SOMETHING_NEW"
	var odd: Rig = await _join()
	assert_eq(odd.rec.join_failures, [RelayTransport.REASONS["RELAY_BUSY"]])
	assert_eq(odd.transport.last_error_code, "RELAY_BUSY")
	relay.refuse_silently = true
	relay.refuse_joins_with = "ROOM_FULL"
	var silent: Rig = await _join()
	assert_eq(silent.rec.join_failures, [RelayTransport.REASONS["RELAY_BUSY"]])
	assert_eq(silent.transport.last_error_code, "RELAY_BUSY")


# --- messages --------------------------------------------------------------------------------------------------

func test_messages_go_both_ways_untouched_and_in_order() -> void:
	var host: Rig = await _host()
	var guest: Rig = await _join()
	await pump(func() -> bool: return host.rec.connected.size() == 1)
	for i: int in 20:
		guest.transport.send(Transport.HOST_PEER_ID, _msg("up %d" % i))
		host.transport.send(2, _msg("down %d" % i))
	assert_true(await pump(func() -> bool: return host.rec.messages.size() == 20 and guest.rec.messages.size() == 20))
	for i: int in 20:
		assert_eq(host.rec.messages[i]["peer_id"], 2)
		assert_eq(host.rec.messages[i]["message"]["payload"]["text"], "up %d" % i)
		assert_eq(guest.rec.messages[i]["peer_id"], Transport.HOST_PEER_ID)
		assert_eq(guest.rec.messages[i]["message"]["payload"]["text"], "down %d" % i)


func test_sending_to_an_unknown_peer_is_dropped_silently() -> void:
	var host: Rig = await _host()
	host.transport.send(7, _msg("nobody"))
	await frames(5)
	assert_eq(relay.count_frames("host", "S"), 0)


func test_a_malformed_message_from_the_relay_is_ignored() -> void:
	var host: Rig = await _host()
	var guest: Rig = await _join()
	await pump(func() -> bool: return host.rec.connected.size() == 1)
	relay.send_to_host("M2:{not json")
	relay.send_to_host("M2:" + JSON.stringify(_msg("fine")))
	relay.send_to_host("Mxyz")
	assert_true(await pump(func() -> bool: return host.rec.messages.size() == 1))
	assert_eq(host.rec.messages[0]["message"]["payload"]["text"], "fine")
	assert_eq(guest.rec.messages.size(), 0)


# --- leaving, kicking, closing -------------------------------------------------------------------------------

func test_a_joiner_leaving_is_reported_to_the_host() -> void:
	var host: Rig = await _host()
	var guest: Rig = await _join()
	await pump(func() -> bool: return host.rec.connected.size() == 1)
	guest.transport.leave()
	assert_true(await pump(func() -> bool: return host.rec.disconnected == [2]))
	assert_false(guest.transport.is_active())


func test_a_kick_delivers_what_came_before_it_then_disconnects_the_joiner() -> void:
	var host: Rig = await _host()
	var guest: Rig = await _join()
	await pump(func() -> bool: return host.rec.connected.size() == 1)
	host.transport.send(2, _msg("reason"))
	host.transport.disconnect_peer(2)
	assert_true(await pump(func() -> bool: return guest.rec.disconnected == [Transport.HOST_PEER_ID]))
	assert_eq(guest.rec.messages.size(), 1, "the message sent just before the kick arrived")
	assert_eq(guest.rec.messages[0]["message"]["payload"]["text"], "reason")
	assert_true(await pump(func() -> bool: return host.rec.disconnected == [2]), "the host hears the peer is gone")
	assert_eq(relay.frames_of("host").filter(func(f: String) -> bool: return f.begins_with("K")), ["K2:KICKED"])


func test_after_a_kick_nothing_more_from_that_peer_reaches_the_host() -> void:
	var host: Rig = await _host()
	var guest: Rig = await _join()
	await pump(func() -> bool: return host.rec.connected.size() == 1)
	host.transport.disconnect_peer(2)
	relay.send_to_host("M2:" + JSON.stringify(_msg("late")))
	await frames(10)
	assert_eq(host.rec.messages.size(), 0)


func test_a_host_that_leaves_closes_its_socket_and_the_relay_decides_what_joiners_see() -> void:
	# (The Q frame that ends the room at once is covered on the real relay: a Godot-based test
	# server drops a frame that arrives together with a close frame, which Cloudflare does not.)
	var host: Rig = await _host()
	var guest: Rig = await _join()
	await pump(func() -> bool: return host.rec.connected.size() == 1)
	host.transport.leave()
	assert_false(host.transport.is_active())
	assert_true(await pump(func() -> bool: return guest.links == [Transport.LINK_HOST_AWAY]))


func test_leave_is_idempotent_and_the_transport_can_be_reused() -> void:
	var host: Rig = await _host()
	host.transport.leave()
	host.transport.leave()
	assert_false(host.transport.is_active())
	assert_true(CoreResult.is_ok(host.transport.host_session(_config())))
	assert_true(await pump(func() -> bool: return host.rec.ready.size() == 2))


# --- link state: the relay holds the room while the host is away -----------------------------------------------

func test_joiners_are_told_when_the_host_is_away_and_when_it_is_back() -> void:
	var host: Rig = await _host({"reconnect_backoff_msec": [50]})
	var guest: Rig = await _join()
	await pump(func() -> bool: return host.rec.connected.size() == 1)
	relay.drop_host()
	assert_true(await pump(func() -> bool: return guest.links == [Transport.LINK_HOST_AWAY]))
	assert_eq(guest.rec.disconnected.size(), 0, "the joiner is not disconnected while the room is held")
	assert_true(await pump(func() -> bool: return guest.links.size() == 2))
	assert_eq(guest.links, [Transport.LINK_HOST_AWAY, Transport.LINK_OK])


func test_the_host_reconnects_with_its_token_and_keeps_its_peers() -> void:
	var host: Rig = await _host({"reconnect_backoff_msec": [50]})
	var guest: Rig = await _join()
	await pump(func() -> bool: return host.rec.connected.size() == 1)
	relay.drop_host()
	assert_true(await pump(func() -> bool: return host.links.has(Transport.LINK_RECONNECTING)))
	assert_true(await pump(func() -> bool: return host.links.has(Transport.LINK_OK)))
	assert_eq(relay.resumes, 1)
	assert_eq(relay.paths.back(), "/resume/" + ScriptedRelay.CODE)
	assert_eq(relay.frames_of("resume")[0], "R" + ScriptedRelay.TOKEN)
	assert_eq(host.rec.disconnected.size(), 0, "peers are untouched by a reconnect")
	assert_eq(host.rec.ready.size(), 1, "session_ready is not emitted again")
	host.transport.send(2, _msg("after"))
	guest.transport.send(Transport.HOST_PEER_ID, _msg("back"))
	assert_true(await pump(func() -> bool: return host.rec.messages.size() == 1 and guest.rec.messages.size() == 1))


func test_messages_sent_while_reconnecting_are_delivered_in_order_afterwards() -> void:
	var host: Rig = await _host({"reconnect_backoff_msec": [200]})
	var guest: Rig = await _join()
	await pump(func() -> bool: return host.rec.connected.size() == 1)
	relay.drop_host()
	await pump(func() -> bool: return host.links.has(Transport.LINK_RECONNECTING))
	for i: int in 5:
		host.transport.send(2, _msg("queued %d" % i))
	assert_true(await pump(func() -> bool: return guest.rec.messages.size() == 5))
	for i: int in 5:
		assert_eq(guest.rec.messages[i]["message"]["payload"]["text"], "queued %d" % i)


func test_the_host_gives_up_when_the_relay_refuses_its_key() -> void:
	var host: Rig = await _host({"reconnect_backoff_msec": [50]})
	relay.refuse_resume_with = "BAD_TOKEN"
	relay.drop_host()
	assert_true(await pump(func() -> bool: return not host.rec.host_failures.is_empty()))
	assert_eq(host.transport.last_error_code, "BAD_TOKEN")
	assert_false(host.transport.is_active())


func test_a_queue_that_would_overflow_fails_the_host_instead_of_losing_messages() -> void:
	var host: Rig = await _host({"reconnect_backoff_msec": [60000]})
	var guest: Rig = await _join()
	await pump(func() -> bool: return host.rec.connected.size() == 1)
	relay.drop_host()
	await pump(func() -> bool: return host.links.has(Transport.LINK_RECONNECTING))
	for i: int in RelayTransport.MAX_QUEUED_MESSAGES + 5:
		host.transport.send(2, _msg("x"))
	assert_eq(host.rec.host_failures.size(), 1)
	assert_false(host.transport.is_active())


func test_a_relay_that_closes_the_room_ends_the_hosts_session() -> void:
	var host: Rig = await _host()
	relay.send_to_host("XROOM_CLOSED")
	assert_true(await pump(func() -> bool: return not host.rec.host_failures.is_empty()))
	assert_eq(host.transport.last_error_code, "ROOM_CLOSED")


func test_a_joiner_told_the_room_is_closed_is_disconnected_after_its_messages() -> void:
	var host: Rig = await _host()
	var guest: Rig = await _join()
	await pump(func() -> bool: return host.rec.connected.size() == 1)
	relay.send_to_peer(2, "M" + JSON.stringify(_msg("last words")))
	relay.send_to_peer(2, "XROOM_CLOSED")
	assert_true(await pump(func() -> bool: return guest.rec.disconnected.size() == 1))
	assert_eq(guest.rec.messages.size(), 1)


func test_a_dropped_joiner_socket_is_a_lost_host_so_the_session_can_offer_a_rejoin() -> void:
	var host: Rig = await _host()
	var guest: Rig = await _join()
	await pump(func() -> bool: return host.rec.connected.size() == 1)
	relay.drop_peer(2)
	assert_true(await pump(func() -> bool: return guest.rec.disconnected == [Transport.HOST_PEER_ID]))
	assert_true(await pump(func() -> bool: return host.rec.disconnected == [2]))


# --- keepalive ---------------------------------------------------------------------------------------------------

func test_it_pings_on_its_own_schedule_and_the_relay_answers() -> void:
	var host: Rig = await _host({"ping_msec": 15000, "watchdog_msec": 45000}, true)
	await frames(3)
	assert_eq(relay.count_frames("host", "ping"), 0, "the relay answers pings itself, so they are never counted as frames")
	clock.now += 16000
	await frames(5)
	# pings are consumed by the scripted relay like the real runtime does; check the answer arrived
	assert_true(host.transport._last_heard >= 0)
	assert_eq(host.rec.host_failures.size(), 0)


func test_the_relays_own_advice_sets_the_ping_and_watchdog_intervals() -> void:
	relay.advice = {"ping_sec": 7, "watchdog_sec": 21, "grace_sec": 33}
	var host: Rig = await _host()
	assert_eq(host.transport._ping_msec, 7000)
	assert_eq(host.transport._watchdog_msec, 21000)
	assert_eq(host.transport._grace_msec, 33000)
	var overridden: Rig = await _join(ScriptedRelay.CODE, {"ping_msec": 1000, "watchdog_msec": 3000})
	assert_eq(overridden.transport._ping_msec, 1000, "an explicit config value wins over the relay's advice")
	assert_eq(overridden.transport._watchdog_msec, 3000)


func test_a_joiner_that_hears_nothing_for_the_watchdog_time_loses_the_host() -> void:
	await _host()
	var guest: Rig = await _join(ScriptedRelay.CODE, {"ping_msec": 1000000, "watchdog_msec": 45000}, true)
	_pollers.erase(relay)  # the relay stops answering altogether
	clock.now += 46000
	assert_true(await pump(func() -> bool: return guest.rec.disconnected == [Transport.HOST_PEER_ID], 200))
	assert_eq(guest.transport.last_error_code, "TIMEOUT")


func test_a_host_that_hears_nothing_for_the_watchdog_time_starts_reconnecting() -> void:
	var host: Rig = await _host({"watchdog_msec": 45000, "ping_msec": 1000000, "reconnect_backoff_msec": [60000]}, true)
	_pollers.erase(relay)
	clock.now += 46000
	assert_true(await pump(func() -> bool: return host.links.has(Transport.LINK_RECONNECTING), 200))


# --- the transport contract it must honour --------------------------------------------------------------------------

func test_it_never_names_its_keepalive_as_app_pings() -> void:
	assert_eq(RelayTransport.new().keepalive_policy(), {"ping_interval_msec": 0, "ping_timeout_msec": 0, "host_silence_timeout_msec": 0})


func test_events_come_only_from_poll() -> void:
	var rig: Rig = _rig()
	assert_true(CoreResult.is_ok(rig.transport.host_session(_config())))
	await get_tree().create_timer(0.2).timeout
	assert_eq(rig.rec.ready.size(), 0, "nothing is emitted until poll() runs")
	assert_true(await pump(func() -> bool: return rig.rec.ready.size() == 1))


func test_the_room_code_helpers() -> void:
	assert_eq(RelayTransport.normalize_code("abc-d23"), "ABCD23", "a hyphen is allowed for readability")
	assert_eq(RelayTransport.normalize_code("abcd23"), "ABCD23")
	assert_eq(RelayTransport.normalize_code(" A B C D 2 3 "), "ABCD23")
	for bad: String in ["ABCDE0", "ABCDEO", "ABCDE1", "ABCDEI", "ABCDEL", "ABCDE", "ABCDEFG", ""]:
		assert_eq(RelayTransport.normalize_code(bad), "", bad)
	assert_true(RelayTransport.looks_like_code("k4m9xq"))
