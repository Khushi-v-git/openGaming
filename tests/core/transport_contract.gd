extends GutTest
## Shared Transport contract tests. Not collected itself (no test_ prefix); each
## transport has a thin test_*.gd that extends this file and overrides make_env().

var env: TransportEnv
var _rigs: Array[TransportRig] = []


func make_env() -> TransportEnv:
	return null


func before_each() -> void:
	env = make_env()
	_rigs.clear()


func after_each() -> void:
	for rig: TransportRig in _rigs:
		rig.transport.leave()
	_rigs.clear()
	env.cleanup()


# --- helpers ---------------------------------------------------------------------

func _transports() -> Array:
	var out: Array = []
	for rig: TransportRig in _rigs:
		out.append(rig.transport)
	return out


func pump(condition: Callable, max_frames: int = NetWait.DEFAULT_MAX_FRAMES) -> bool:
	return await NetWait.until(self, _transports(), condition, max_frames)


func start_host() -> TransportRig:
	var rig: TransportRig = TransportRig.new(env.make_transport())
	_rigs.append(rig)
	var info: Dictionary = rig.transport.host_session(env.host_config())
	assert_true(CoreResult.is_ok(info), "host_session failed: %s" % str(info))
	rig.address = str(info.get("address", ""))
	return rig


## Joins a new client and waits until both ends see the connection.
func join_client(host: TransportRig) -> TransportRig:
	var expected: int = host.recorder.connected.size() + 1
	var rig: TransportRig = TransportRig.new(env.make_transport())
	_rigs.append(rig)
	rig.transport.join_session(host.address, env.join_config())
	var ok: bool = await pump(func() -> bool: return rig.recorder.join_ok_count > 0 and host.recorder.connected.size() >= expected)
	assert_true(ok, "client failed to join: %s" % str(rig.recorder.join_failures))
	return rig


# --- tests -----------------------------------------------------------------------

func test_host_session_returns_address_and_kind() -> void:
	var host: TransportRig = start_host()
	assert_ne(host.address, "")
	assert_true(host.transport.is_active())


func test_join_connects_both_ends() -> void:
	var host: TransportRig = start_host()
	var client: TransportRig = await join_client(host)
	assert_eq(client.recorder.join_ok_count, 1)
	assert_eq(host.recorder.connected.size(), 1)
	var peer_id: int = host.recorder.connected[0]
	assert_gt(peer_id, 0)
	assert_ne(peer_id, Transport.HOST_PEER_ID)
	assert_eq(host.transport.get_peer_ids(), [peer_id] as Array[int])
	assert_eq(client.transport.get_peer_ids(), [Transport.HOST_PEER_ID] as Array[int])


func test_join_to_unknown_address_fails() -> void:
	var rig: TransportRig = TransportRig.new(env.make_transport())
	_rigs.append(rig)
	var bad: String = "127.0.0.1:1" if env.host_config().has("port") else "nowhere-xyz"
	rig.transport.join_session(bad, env.join_config())
	var ok: bool = await pump(func() -> bool: return not rig.recorder.join_failures.is_empty(), 3000)
	assert_true(ok, "expected join_failed")
	assert_eq(rig.recorder.join_ok_count, 0)


func test_client_to_host_message() -> void:
	var host: TransportRig = start_host()
	var client: TransportRig = await join_client(host)
	client.transport.send(Transport.HOST_PEER_ID, Envelope.make("t", {"n": 5, "s": "hi"}))
	var ok: bool = await pump(func() -> bool: return host.recorder.messages.size() >= 1)
	assert_true(ok)
	var got: Dictionary = host.recorder.messages[0]
	assert_eq(got["peer_id"], host.recorder.connected[0])
	assert_eq(got["message"], Envelope.make("t", {"n": 5, "s": "hi"}))
	assert_eq(typeof(got["message"]["payload"]["n"]), TYPE_INT)


func test_host_to_client_message_comes_from_host_peer_id() -> void:
	var host: TransportRig = start_host()
	var client: TransportRig = await join_client(host)
	host.transport.send(host.recorder.connected[0], Envelope.make("t", {"x": 1}))
	var ok: bool = await pump(func() -> bool: return client.recorder.messages.size() >= 1)
	assert_true(ok)
	assert_eq(client.recorder.messages[0]["peer_id"], Transport.HOST_PEER_ID)


func test_broadcast_reaches_every_client() -> void:
	var host: TransportRig = start_host()
	var clients: Array[TransportRig] = []
	for _i: int in 3:
		clients.append(await join_client(host))
	host.transport.broadcast(Envelope.make("b", {"v": 1}))
	var ok: bool = await pump(func() -> bool:
		for c: TransportRig in clients:
			if c.recorder.messages.is_empty():
				return false
		return true)
	assert_true(ok)


func test_peer_ids_are_unique() -> void:
	var host: TransportRig = start_host()
	for _i: int in 3:
		await join_client(host)
	var seen: Dictionary = {}
	for peer_id: int in host.recorder.connected:
		assert_false(seen.has(peer_id), "duplicate peer_id %d" % peer_id)
		seen[peer_id] = true
	assert_eq(seen.size(), 3)


func test_messages_keep_send_order() -> void:
	var host: TransportRig = start_host()
	var client: TransportRig = await join_client(host)
	for i: int in 20:
		client.transport.send(Transport.HOST_PEER_ID, Envelope.make("seq", {"i": i}))
	var ok: bool = await pump(func() -> bool: return host.recorder.messages.size() >= 20)
	assert_true(ok)
	for i: int in 20:
		assert_eq(host.recorder.messages[i]["message"]["payload"]["i"], i)


func test_receiver_gets_independent_copy() -> void:
	var host: TransportRig = start_host()
	var client: TransportRig = await join_client(host)
	var msg: Dictionary = Envelope.make("t", {"list": [1, 2]})
	client.transport.send(Transport.HOST_PEER_ID, msg)
	msg["payload"]["list"].append(3)
	var ok: bool = await pump(func() -> bool: return host.recorder.messages.size() >= 1)
	assert_true(ok)
	assert_eq(host.recorder.messages[0]["message"]["payload"]["list"], [1, 2])


func test_events_only_come_from_poll() -> void:
	var host: TransportRig = start_host()
	var client: TransportRig = await join_client(host)
	client.transport.send(Transport.HOST_PEER_ID, Envelope.make("t"))
	assert_eq(host.recorder.messages.size(), 0, "no delivery before poll")


func test_client_leave_notifies_host() -> void:
	var host: TransportRig = start_host()
	var client: TransportRig = await join_client(host)
	var peer_id: int = host.recorder.connected[0]
	client.transport.leave()
	var ok: bool = await pump(func() -> bool: return host.recorder.disconnected.size() >= 1)
	assert_true(ok)
	assert_eq(host.recorder.disconnected[0], peer_id)
	assert_eq(host.transport.get_peer_ids().size(), 0)


func test_host_disconnect_peer_kicks_client() -> void:
	var host: TransportRig = start_host()
	var client: TransportRig = await join_client(host)
	var peer_id: int = host.recorder.connected[0]
	host.transport.disconnect_peer(peer_id)
	var ok: bool = await pump(func() -> bool: return host.recorder.disconnected.size() >= 1 and client.recorder.disconnected.size() >= 1)
	assert_true(ok)
	assert_eq(host.recorder.disconnected[0], peer_id)
	assert_eq(client.recorder.disconnected[0], Transport.HOST_PEER_ID)


func test_host_leave_notifies_all_clients() -> void:
	var host: TransportRig = start_host()
	var c1: TransportRig = await join_client(host)
	var c2: TransportRig = await join_client(host)
	host.transport.leave()
	var ok: bool = await pump(func() -> bool: return c1.recorder.disconnected.size() >= 1 and c2.recorder.disconnected.size() >= 1)
	assert_true(ok)
	assert_eq(c1.recorder.disconnected[0], Transport.HOST_PEER_ID)
	assert_false(host.transport.is_active())


func test_rejoin_gets_new_peer_id() -> void:
	var host: TransportRig = start_host()
	var first: TransportRig = await join_client(host)
	first.transport.leave()
	await pump(func() -> bool: return host.recorder.disconnected.size() >= 1)
	await join_client(host)
	assert_eq(host.recorder.connected.size(), 2)
	assert_ne(host.recorder.connected[0], host.recorder.connected[1], "peer_id must not be reused")


func test_send_to_unknown_peer_is_ignored() -> void:
	var host: TransportRig = start_host()
	var client: TransportRig = await join_client(host)
	host.transport.send(9999, Envelope.make("t"))
	client.transport.send(9999, Envelope.make("t"))
	await NetWait.frames(self, _transports(), 5)
	assert_eq(client.recorder.messages.size(), 0)
	assert_eq(host.recorder.messages.size(), 0)


func test_leave_is_idempotent() -> void:
	var host: TransportRig = start_host()
	host.transport.leave()
	host.transport.leave()
	assert_false(host.transport.is_active())


func test_oversized_message_is_not_delivered() -> void:
	var host: TransportRig = start_host()
	var client: TransportRig = await join_client(host)
	client.transport.send(Transport.HOST_PEER_ID, Envelope.make("big", {"s": "x".repeat(Protocol.MAX_MESSAGE_BYTES + 10)}))
	await NetWait.frames(self, _transports(), 20)
	assert_eq(host.recorder.messages_of_type("big").size(), 0)
