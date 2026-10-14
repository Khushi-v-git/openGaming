extends "res://tests/core/transport_contract.gd"


func make_env() -> TransportEnv:
	return DirectWsEnv.new()


func test_address_is_host_and_port() -> void:
	var host: TransportRig = start_host()
	var parsed: Dictionary = AddressParser.parse(host.address, 1)
	assert_true(CoreResult.is_ok(parsed))
	assert_eq(parsed["host"], "127.0.0.1")
	assert_gt(parsed["port"], 0)
	assert_eq((host.transport as DirectWsTransport).listening_port(), parsed["port"])


func test_port_in_use_reports_listen_failed() -> void:
	var host: TransportRig = start_host()
	var port: int = (host.transport as DirectWsTransport).listening_port()
	var other: DirectWsTransport = DirectWsTransport.new()
	var result: Dictionary = other.host_session({"port": port, "bind_address": "127.0.0.1"})
	assert_eq(CoreResult.error_code(result), "LISTEN_FAILED")


func test_bad_address_fails_to_join() -> void:
	var rig: TransportRig = TransportRig.new(env.make_transport())
	_rigs.append(rig)
	rig.transport.join_session("not a valid address", {})
	var ok: bool = await pump(func() -> bool: return rig.recorder.join_failures.size() == 1)
	assert_true(ok)


func test_malformed_message_drops_the_peer() -> void:
	var host: TransportRig = start_host()
	var raw: WebSocketPeer = WebSocketPeer.new()
	assert_eq(raw.connect_to_url("ws://%s" % host.address), OK)
	var ok: bool = await pump(func() -> bool:
		raw.poll()
		return raw.get_ready_state() == WebSocketPeer.STATE_OPEN and host.recorder.connected.size() == 1)
	assert_true(ok)
	raw.send_text("this is not json")
	ok = await pump(func() -> bool:
		raw.poll()
		return host.recorder.disconnected.size() == 1)
	assert_true(ok, "host should drop a peer that sends garbage")
	assert_eq(host.recorder.messages.size(), 0)


func test_binary_message_drops_the_peer() -> void:
	var host: TransportRig = start_host()
	var raw: WebSocketPeer = WebSocketPeer.new()
	raw.connect_to_url("ws://%s" % host.address)
	var ok: bool = await pump(func() -> bool:
		raw.poll()
		return raw.get_ready_state() == WebSocketPeer.STATE_OPEN and host.recorder.connected.size() == 1)
	assert_true(ok)
	raw.send(PackedByteArray([1, 2, 3]))
	ok = await pump(func() -> bool:
		raw.poll()
		return host.recorder.disconnected.size() == 1)
	assert_true(ok)


func test_max_pending_limits_upgrade_connections() -> void:
	var host_transport: DirectWsTransport = DirectWsTransport.new()
	var info: Dictionary = host_transport.host_session({"port": 0, "bind_address": "127.0.0.1", "max_pending": 2, "max_connections": 3})
	assert_true(CoreResult.is_ok(info))
	var rig: TransportRig = TransportRig.new(host_transport)
	_rigs.append(rig)
	# Open raw TCP sockets that never finish the WebSocket upgrade.
	var raw: Array[StreamPeerTCP] = []
	for _i: int in 6:
		var tcp: StreamPeerTCP = StreamPeerTCP.new()
		tcp.connect_to_host("127.0.0.1", info["port"])
		raw.append(tcp)
	await NetWait.frames(self, _transports(), 30)
	for tcp: StreamPeerTCP in raw:
		tcp.poll()
		if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			tcp.get_partial_data(1)  # a read is what reveals a server-side close
			tcp.poll()
	var still_open: int = 0
	for tcp: StreamPeerTCP in raw:
		if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			still_open += 1
	assert_lte(still_open, 2, "at most max_pending half-open connections are kept")
	for tcp: StreamPeerTCP in raw:
		tcp.disconnect_from_host()
