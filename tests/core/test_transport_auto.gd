extends NetTestCase
## The factory's "auto" transport (relay vs direct), what the join field accepts, and the app
## settings it reads. Sessions run over it end to end on a scripted relay and on localhost.

const TEST_SETTINGS: String = "user://test_settings.cfg"

var relay: ScriptedRelay
var _saved_path: String


func make_env() -> TransportEnv:
	return TransportEnv.new()


func before_each() -> void:
	super.before_each()
	relay = ScriptedRelay.new()
	relay.start()
	_pollers.append(relay)
	_saved_path = AppSettings.path
	AppSettings.path = TEST_SETTINGS
	DirAccess.remove_absolute(TEST_SETTINGS)


func after_each() -> void:
	super.after_each()
	relay.stop()
	DirAccess.remove_absolute(TEST_SETTINGS)
	AppSettings.path = _saved_path


# --- what the join field accepts -----------------------------------------------------------------------

func test_a_room_code_goes_to_the_relay_in_any_case() -> void:
	for typed: String in ["ABCDE2", "abcde2", " abc-de2 ", "K4M9XQ"]:
		var verdict: Dictionary = TransportFactory.classify_join_text(typed)
		assert_true(CoreResult.is_ok(verdict), typed)
		assert_eq(verdict["kind"], TransportFactory.KIND_RELAY, typed)
		assert_eq(verdict["address"], RelayTransport.normalize_code(typed), typed)


func test_anything_that_looks_like_an_address_goes_to_the_direct_transport_unchanged() -> void:
	for typed: String in ["192.168.1.20:24680", "192.168.1.20", "host.example.com", "mypc:24680", "ws://10.0.0.5:24680", "[::1]:24680", "playit.example.net:1234"]:
		var verdict: Dictionary = TransportFactory.classify_join_text(typed)
		assert_true(CoreResult.is_ok(verdict), typed)
		assert_eq(verdict["kind"], TransportFactory.KIND_DIRECT_WS, typed)
		assert_eq(verdict["address"], typed, typed)


func test_a_relay_prefix_forces_the_relay() -> void:
	var verdict: Dictionary = TransportFactory.classify_join_text("relay:abc-de2")
	assert_eq(verdict["kind"], TransportFactory.KIND_RELAY)
	assert_eq(verdict["address"], "ABCDE2")
	assert_false(CoreResult.is_ok(TransportFactory.classify_join_text("relay:nonsense")))


func test_a_bare_word_that_is_not_a_room_code_is_refused_not_guessed() -> void:
	for typed: String in ["", "laptop", "hostname", "ABCDE", "ABCDEFG", "ABCDE0", "with space word"]:
		var verdict: Dictionary = TransportFactory.classify_join_text(typed)
		assert_false(CoreResult.is_ok(verdict), "'%s'" % typed)
		assert_eq(CoreResult.error_code(verdict), AddressParser.BAD_ADDRESS)
		assert_string_contains(str(verdict["error"]["message"]), "room code")


# --- building transports -------------------------------------------------------------------------------------

func test_the_factory_builds_each_kind() -> void:
	assert_true(TransportFactory.create({"transport": "relay"}) is RelayTransport)
	assert_true(TransportFactory.create({"transport": "direct_ws"}) is DirectWsTransport)
	assert_true(TransportFactory.create({"transport": "auto"}) is Transport)
	assert_true(TransportFactory.create({}) is DirectWsTransport, "the old default is unchanged")


func test_network_config_reads_the_app_settings() -> void:
	AppSettings.set_relay_url("wss://relay.example.test")
	AppSettings.set_host_via("direct")
	var config: Dictionary = TransportFactory.network_config()
	assert_eq(config["transport"], "auto")
	assert_eq(config["relay_url"], "wss://relay.example.test")
	assert_eq(config["host_via"], "direct")
	assert_eq(config["port"], DirectWsTransport.DEFAULT_PORT)


# --- sessions over auto: relay ------------------------------------------------------------------------------------

func _auto_host(config: Dictionary) -> HostSession:
	var host: HostSession = HostSession.new(TransportFactory.create({"transport": "auto"}), APP, GAME)
	host.clock = clock.as_callable()
	track(host, host.transport)
	assert_true(CoreResult.is_ok(host.start(config)), str(config))
	return host


func test_hosting_and_joining_by_room_code_works_end_to_end_with_pings_off() -> void:
	var infos: Array = []
	var host: HostSession = _auto_host({"host_via": "relay", "relay_url": relay.url()})
	host.hosting.connect(func(info: Dictionary) -> void: infos.append(info))
	assert_true(await pump(func() -> bool: return not infos.is_empty()))
	assert_eq(infos[0]["kind"], "relay")
	assert_eq(infos[0]["share_label"], "room code")
	var client: ClientSession = ClientSession.new(TransportFactory.create({"transport": "auto"}), APP, GAME)
	client.clock = clock.as_callable()
	track(client, client.transport)
	client.join(str(infos[0]["address"]).to_lower(), "Asha", {"relay_url": relay.url()})
	assert_true(await pump(func() -> bool: return client.is_active()))
	assert_eq(host._ping_interval, 0, "no app pings through a relay")
	assert_eq(host._ping_timeout, 0)
	assert_eq(client._host_silence_timeout, 0)
	clock.now += 600000
	await frames(10)
	assert_true(client.is_active(), "ten minutes of silence do not drop anyone")
	assert_eq(host.connected_player_ids().size(), 1)


func test_hosting_by_relay_without_a_relay_url_fails_clearly() -> void:
	var host: HostSession = HostSession.new(TransportFactory.create({"transport": "auto"}), APP, GAME)
	track(host, host.transport)
	var result: Dictionary = host.start({"host_via": "relay"})
	assert_eq(CoreResult.error_code(result), "NO_RELAY")
	assert_false(host.transport.is_active())


# --- sessions over auto: direct (unchanged behaviour) ---------------------------------------------------------------

func test_direct_hosting_and_joining_by_address_keep_todays_ping_defaults() -> void:
	var infos: Array = []
	var host: HostSession = _auto_host({"host_via": "direct", "port": 0, "bind_address": "127.0.0.1"})
	host.hosting.connect(func(info: Dictionary) -> void: infos.append(info))
	assert_true(await pump(func() -> bool: return not infos.is_empty()))
	assert_eq(infos[0]["kind"], "direct_ws")
	assert_false(infos[0].has("share_label"), "a direct transport leaves the lobby's default word")
	var client: ClientSession = ClientSession.new(TransportFactory.create({"transport": "auto"}), APP, GAME)
	client.clock = clock.as_callable()
	track(client, client.transport)
	client.join("127.0.0.1:%d" % int(infos[0]["port"]), "Ben", {"join_timeout_msec": 3000})
	assert_true(await pump(func() -> bool: return client.is_active()))
	assert_eq(host._ping_interval, 5000)
	assert_eq(host._ping_timeout, 15000)
	assert_eq(client._host_silence_timeout, 20000)


func test_a_bad_join_text_fails_through_join_failed_not_a_crash() -> void:
	var client: ClientSession = ClientSession.new(TransportFactory.create({"transport": "auto"}), APP, GAME)
	var failures: Array = []
	client.connect_failed.connect(func(reason: String) -> void: failures.append(reason))
	track(client, client.transport)
	client.join("laptop", "Ben")
	assert_true(await pump(func() -> bool: return not failures.is_empty()))
	assert_string_contains(failures[0], "room code")


func test_leaving_lets_the_auto_transport_choose_again() -> void:
	var transport: Transport = TransportFactory.create({"transport": "auto"})
	track(transport, transport)
	assert_true(CoreResult.is_ok(transport.host_session({"host_via": "direct", "port": 0, "bind_address": "127.0.0.1"})))
	assert_true(transport.is_active())
	transport.leave()
	assert_false(transport.is_active())
	assert_true(CoreResult.is_ok(transport.host_session({"host_via": "relay", "relay_url": relay.url()})))


# --- app settings --------------------------------------------------------------------------------------------------

func test_settings_round_trip_and_default_sensibly() -> void:
	assert_eq(AppSettings.get_value("x", "y", "fallback"), "fallback")
	assert_true(AppSettings.set_value("x", "y", 42))
	assert_eq(AppSettings.get_value("x", "y"), 42)
	AppSettings.clear_value("x", "y")
	assert_eq(AppSettings.get_value("x", "y", "gone"), "gone")
	assert_eq(AppSettings.host_via(), "relay")
	AppSettings.set_host_via("direct")
	assert_eq(AppSettings.host_via(), "direct")
	AppSettings.set_value("network", "host_via", "garbage")
	assert_eq(AppSettings.host_via(), "relay", "an unreadable value falls back to the default")


func test_the_players_relay_url_beats_the_project_default() -> void:
	var project_default: String = str(ProjectSettings.get_setting(AppSettings.PROJECT_RELAY_URL, ""))
	assert_eq(AppSettings.relay_url(), project_default)
	AppSettings.set_relay_url("  wss://mine.example.test/  ")
	assert_eq(AppSettings.relay_url(), "wss://mine.example.test/")
	AppSettings.set_relay_url("")
	assert_eq(AppSettings.relay_url(), project_default, "blank means use the default again")


func test_the_project_has_exactly_one_relay_url_setting() -> void:
	assert_true(ProjectSettings.has_setting(AppSettings.PROJECT_RELAY_URL))
