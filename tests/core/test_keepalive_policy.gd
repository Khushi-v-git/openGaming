extends NetTestCase
## Who sends application-level pings is decided by the transport's keepalive policy, and an
## explicit option still wins. Direct keeps today's numbers; a relay-style policy of zeros turns
## the session's pings and silence timeouts off.


## A loopback transport that declares it carries no app-level pings (as a relay does).
class QuietTransport extends LoopbackTransport:
	func keepalive_policy() -> Dictionary:
		return {"ping_interval_msec": 0, "ping_timeout_msec": 0, "host_silence_timeout_msec": 0}


class QuietEnv extends TransportEnv:
	var hub: LoopbackHub = LoopbackHub.new()

	func make_transport() -> Transport:
		return QuietTransport.new(hub)


var quiet: bool = false


func make_env() -> TransportEnv:
	return QuietEnv.new() if quiet else LoopbackEnv.new()


func _host(options: Dictionary = {}) -> HostSession:
	var session: HostSession = HostSession.new(env.make_transport(), APP, GAME, options)
	session.clock = clock.as_callable()
	assert_true(CoreResult.is_ok(session.start(env.host_config())))
	track(session, session.transport)
	return session


func _client(host: HostSession, options: Dictionary = {}) -> ClientSession:
	var session: ClientSession = ClientSession.new(env.make_transport(), APP, GAME, options)
	session.clock = clock.as_callable()
	track(session, session.transport)
	return session


## Waits for the host to be ready and returns the address to join. (Lambdas copy local variables,
## so the answer is collected in an Array.)
func _address(host: HostSession) -> String:
	var infos: Array = []
	host.hosting.connect(func(info: Dictionary) -> void: infos.append(info))
	await pump(func() -> bool: return not infos.is_empty())
	return str(infos[0]["address"])


# --- the policy numbers -------------------------------------------------------------------------------

func test_the_direct_and_loopback_transports_keep_todays_defaults() -> void:
	for transport: Transport in [DirectWsTransport.new(), LoopbackTransport.new(LoopbackHub.new()), FakeRelayTransport.new(FakeRelay.new())]:
		assert_eq(transport.keepalive_policy(), {"ping_interval_msec": 5000, "ping_timeout_msec": 15000, "host_silence_timeout_msec": 20000}, transport.get_script().resource_path)


# --- the default behaviour is unchanged -------------------------------------------------------------------

func test_with_default_options_the_host_pings_every_5_seconds_and_kicks_after_15_of_silence() -> void:
	var host: HostSession = _host()
	var left: Array = []
	host.player_disconnected.connect(func(id: String) -> void: left.append(id))
	var client: ClientSession = _client(host)
	var types: Array[String] = []
	client.transport.message_received.connect(func(_peer: int, message: Dictionary) -> void: types.append(str(message["type"])))
	var address: String = await _address(host)
	client.join(address, "Ghost")
	assert_true(await pump(func() -> bool: return client.is_active()))
	clock.now += 5000
	await frames(4)
	assert_true(types.has(Protocol.T_PING), "a ping went out after 5 s")
	assert_eq(left.size(), 0)
	_pollers.erase(client)  # the client app freezes: it stops answering
	clock.now += 16000
	assert_true(await pump(func() -> bool: return left.size() >= 1), "kicked after 15 s of silence")


# --- a transport that declares no pings -------------------------------------------------------------------

func test_a_transport_with_no_app_pings_gets_none_and_no_silence_kick() -> void:
	quiet = true
	env = make_env()
	var host: HostSession = _host()
	var left: Array = []
	host.player_disconnected.connect(func(id: String) -> void: left.append(id))
	var client: ClientSession = _client(host)
	var types: Array[String] = []
	client.transport.message_received.connect(func(_peer: int, message: Dictionary) -> void: types.append(str(message["type"])))
	var address: String = await _address(host)
	client.join(address, "Quiet")
	assert_true(await pump(func() -> bool: return client.is_active()))
	_pollers.erase(client)
	_pollers.append(client.transport)
	for _i: int in 20:
		clock.now += 60000  # twenty minutes of silence
		await frames(2)
	assert_false(types.has(Protocol.T_PING), "no application ping was ever sent")
	assert_eq(left.size(), 0, "silence alone does not kick when pings are off")
	quiet = false


func test_a_silent_host_is_not_declared_lost_when_the_transport_carries_no_pings() -> void:
	quiet = true
	env = make_env()
	var host: HostSession = _host()
	var client: ClientSession = _client(host)
	var lost: Array = []
	client.host_lost.connect(func(reason: String) -> void: lost.append(reason))
	var address: String = await _address(host)
	client.join(address, "Waiter")
	assert_true(await pump(func() -> bool: return client.is_active()))
	_pollers.erase(host)
	for _i: int in 10:
		clock.now += 60000
		await frames(2)
	assert_eq(lost.size(), 0, "liveness is the transport's job here")
	quiet = false


# --- options still win ----------------------------------------------------------------------------------------

func test_explicit_options_override_the_transport_policy() -> void:
	quiet = true
	env = make_env()
	var host: HostSession = _host({"ping_interval_msec": 1000, "ping_timeout_msec": 4000})
	var left: Array = []
	host.player_disconnected.connect(func(id: String) -> void: left.append(id))
	var client: ClientSession = _client(host, {"host_silence_timeout_msec": 4000})
	var address: String = await _address(host)
	client.join(address, "Explicit")
	assert_true(await pump(func() -> bool: return client.is_active()))
	_pollers.erase(client)
	assert_true(await pump(func() -> bool:
		clock.now += 500
		return left.size() >= 1))
	quiet = false
