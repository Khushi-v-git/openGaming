extends "res://tests/core/transport_contract.gd"


func make_env() -> TransportEnv:
	return FakeRelayEnv.new()


func _relay() -> FakeRelay:
	return (env as FakeRelayEnv).relay


func test_address_is_a_room_code_not_a_network_address() -> void:
	var host: TransportRig = await start_host()
	assert_true(host.address.begins_with("ROOM-"))
	assert_false(host.address.contains(":"))
	assert_eq(_relay().get_room_codes(), [host.address] as Array[String])


func test_requested_room_code_is_used() -> void:
	var rig: TransportRig = TransportRig.new(env.make_transport())
	_rigs.append(rig)
	assert_true(CoreResult.is_ok(rig.transport.host_session({"room_code": "MYROOM"})))
	assert_true(await pump(func() -> bool: return rig.recorder.ready.size() == 1))
	assert_eq(rig.recorder.ready[0]["address"], "MYROOM")
	assert_eq(rig.recorder.ready[0]["kind"], "fake_relay")


func test_taken_room_code_fails_through_host_failed_not_the_return_value() -> void:
	var first: TransportRig = TransportRig.new(env.make_transport())
	var second: TransportRig = TransportRig.new(env.make_transport())
	_rigs.append(first)
	_rigs.append(second)
	first.transport.host_session({"room_code": "MYROOM"})
	await pump(func() -> bool: return first.recorder.ready.size() == 1)
	assert_true(CoreResult.is_ok(second.transport.host_session({"room_code": "MYROOM"})), "a relay only finds out later")
	assert_true(await pump(func() -> bool: return second.recorder.host_failures.size() == 1))
	assert_eq(second.recorder.ready.size(), 0)
	assert_false(second.transport.is_active(), "failed hosting leaves the transport inactive")
	assert_eq(first.recorder.host_failures.size(), 0)


func test_session_ready_waits_for_the_relay() -> void:
	_relay().delay_polls = 6
	var rig: TransportRig = TransportRig.new(env.make_transport())
	_rigs.append(rig)
	rig.transport.host_session({})
	assert_true(rig.transport.is_active())
	await NetWait.frames(self, _transports(), 4)
	assert_eq(rig.recorder.ready.size(), 0, "relay has not answered yet")
	assert_true(await pump(func() -> bool: return rig.recorder.ready.size() == 1))


func test_leave_while_registering_cancels_quietly_and_frees_the_room() -> void:
	_relay().delay_polls = 6
	var rig: TransportRig = TransportRig.new(env.make_transport())
	_rigs.append(rig)
	rig.transport.host_session({"room_code": "SLOW"})
	rig.transport.leave()
	await NetWait.frames(self, _transports(), 10)
	assert_eq(rig.recorder.ready.size(), 0)
	assert_eq(_relay().get_room_codes().size(), 0)


func test_closing_host_removes_room() -> void:
	var host: TransportRig = await start_host()
	host.transport.leave()
	assert_eq(_relay().get_room_codes().size(), 0)


func test_delay_postpones_delivery() -> void:
	var host: TransportRig = await start_host()
	var client: TransportRig = await join_client(host)
	_relay().delay_polls = 5
	client.transport.send(Transport.HOST_PEER_ID, Envelope.make("slow"))
	await NetWait.frames(self, _transports(), 3)
	assert_eq(host.recorder.messages.size(), 0, "still in flight")
	var ok: bool = await pump(func() -> bool: return host.recorder.messages.size() >= 1)
	assert_true(ok, "arrives eventually")


func test_delay_preserves_order() -> void:
	var host: TransportRig = await start_host()
	var client: TransportRig = await join_client(host)
	_relay().delay_polls = 3
	for i: int in 5:
		client.transport.send(Transport.HOST_PEER_ID, Envelope.make("seq", {"i": i}))
	_relay().delay_polls = 0
	var ok: bool = await pump(func() -> bool: return host.recorder.messages.size() >= 5)
	assert_true(ok)
	for i: int in 5:
		assert_eq(host.recorder.messages[i]["message"]["payload"]["i"], i)


func test_delay_applies_to_join() -> void:
	_relay().delay_polls = 4
	var host: TransportRig = await start_host()
	var client: TransportRig = TransportRig.new(env.make_transport())
	_rigs.append(client)
	client.transport.join_session(host.address, {})
	await NetWait.frames(self, _transports(), 2)
	assert_eq(client.recorder.join_ok_count, 0)
	var ok: bool = await pump(func() -> bool: return client.recorder.join_ok_count == 1)
	assert_true(ok)


func test_dropped_client_connection_is_seen_by_both_sides() -> void:
	var host: TransportRig = await start_host()
	var client: TransportRig = await join_client(host)
	var peer_id: int = host.recorder.connected[0]
	_relay().drop_connection((client.transport as FakeRelayTransport).connection_id())
	var ok: bool = await pump(func() -> bool: return host.recorder.disconnected.size() >= 1 and client.recorder.disconnected.size() >= 1)
	assert_true(ok)
	assert_eq(host.recorder.disconnected[0], peer_id)
	assert_eq(client.recorder.disconnected[0], Transport.HOST_PEER_ID)
	assert_false(client.transport.is_active())


func test_dropped_client_can_join_again() -> void:
	var host: TransportRig = await start_host()
	var client: TransportRig = await join_client(host)
	_relay().drop_connection((client.transport as FakeRelayTransport).connection_id())
	await pump(func() -> bool: return client.recorder.disconnected.size() >= 1)
	client.transport.join_session(host.address, {})
	var ok: bool = await pump(func() -> bool: return client.recorder.join_ok_count == 2 and host.recorder.connected.size() == 2)
	assert_true(ok)
	assert_ne(host.recorder.connected[0], host.recorder.connected[1])


func test_dropped_host_connection_ends_room_for_clients() -> void:
	var host: TransportRig = await start_host()
	var client: TransportRig = await join_client(host)
	_relay().drop_connection((host.transport as FakeRelayTransport).connection_id())
	var ok: bool = await pump(func() -> bool: return client.recorder.disconnected.size() >= 1 and host.recorder.disconnected.size() >= 1)
	assert_true(ok)
	assert_eq(client.recorder.disconnected[0], Transport.HOST_PEER_ID)
	assert_false(host.transport.is_active())
	assert_eq(_relay().get_room_codes().size(), 0)
