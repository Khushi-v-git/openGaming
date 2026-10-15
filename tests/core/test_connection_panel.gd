extends NetTestCase
## The connection panel (relay address, "host with"), the relay probe behind its Test button, and
## the lobby start screen using them. Friends paste any relay's address into the box; nothing is
## edited in code.

const TEST_SETTINGS: String = "user://test_connection_settings.cfg"

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
	await get_tree().process_frame  # queued frees finish before the orphan check
	super.after_each()
	relay.stop()
	DirAccess.remove_absolute(TEST_SETTINGS)
	AppSettings.path = _saved_path


func _panel() -> ConnectionPanel:
	var panel: ConnectionPanel = ConnectionPanel.new()
	add_child_autofree(panel)
	return panel


func _until(condition: Callable, max_frames: int = 600) -> bool:
	for _i: int in max_frames:
		relay.poll()  # the scripted relay is a plain object: it only works when polled
		if condition.call():
			return true
		await get_tree().process_frame
	return false


# --- what people paste ------------------------------------------------------------------------------------

func test_whatever_a_friend_pastes_becomes_a_usable_relay_address() -> void:
	var cases: Dictionary = {
		"wss://relay.example.workers.dev": "wss://relay.example.workers.dev",
		"relay.example.workers.dev": "wss://relay.example.workers.dev",
		"  https://relay.example.workers.dev/health  ": "wss://relay.example.workers.dev",
		"http://relay.example.workers.dev/": "ws://relay.example.workers.dev",
		"WSS://Relay.Example.dev/host?x=1#y": "wss://Relay.Example.dev",
		"ws://127.0.0.1:8787": "ws://127.0.0.1:8787",
		"127.0.0.1:8787": "ws://127.0.0.1:8787",
		"localhost:8787": "ws://localhost:8787",
	}
	for typed: String in cases:
		assert_eq(AppSettings.normalize_relay_url(typed), cases[typed], typed)


func test_things_that_cannot_be_a_relay_address_are_refused() -> void:
	for typed: String in ["", "   ", "not a url", "relay", "ftp://x.example.com", ".example.com", "example.com.", ":8787", "https://", "two words.example.com"]:
		assert_eq(AppSettings.normalize_relay_url(typed), "", "'%s'" % typed)


# --- the panel ----------------------------------------------------------------------------------------------

func test_it_starts_from_the_saved_choices() -> void:
	AppSettings.set_relay_url("wss://mine.example.test")
	AppSettings.set_host_via("direct")
	var panel: ConnectionPanel = _panel()
	await get_tree().process_frame
	assert_eq(panel.url_edit.text, "wss://mine.example.test")
	assert_eq(panel.host_via(), "direct")
	assert_false(panel.uses_relay())


func test_it_defaults_to_the_relay_with_the_project_default_address() -> void:
	var panel: ConnectionPanel = _panel()
	await get_tree().process_frame
	assert_true(panel.uses_relay())
	assert_eq(panel.url_edit.text, str(ProjectSettings.get_setting(AppSettings.PROJECT_RELAY_URL, "")))


func test_typing_an_address_saves_it_cleaned_up_for_next_time() -> void:
	var panel: ConnectionPanel = _panel()
	await get_tree().process_frame
	panel.url_edit.text = "https://friends-relay.example.workers.dev/health"
	panel.url_edit.text_submitted.emit(panel.url_edit.text)
	assert_eq(panel.url_edit.text, "wss://friends-relay.example.workers.dev")
	assert_eq(AppSettings.relay_url(), "wss://friends-relay.example.workers.dev")
	var again: ConnectionPanel = _panel()
	await get_tree().process_frame
	assert_eq(again.url_edit.text, "wss://friends-relay.example.workers.dev", "remembered across runs")


func test_an_address_that_is_nonsense_is_not_saved_and_says_so() -> void:
	AppSettings.set_relay_url("wss://good.example.test")
	var panel: ConnectionPanel = _panel()
	await get_tree().process_frame
	panel.url_edit.text = "not a url"
	panel.save()
	assert_string_contains(panel.result_label.text, "does not look like")
	assert_eq(AppSettings.relay_url(), "wss://good.example.test", "the old good address is kept")


func test_clearing_the_box_goes_back_to_the_project_default() -> void:
	AppSettings.set_relay_url("wss://mine.example.test")
	var panel: ConnectionPanel = _panel()
	await get_tree().process_frame
	panel.url_edit.text = ""
	panel.save()
	assert_eq(AppSettings.relay_url(), str(ProjectSettings.get_setting(AppSettings.PROJECT_RELAY_URL, "")))


func test_apply_to_fills_the_transport_config() -> void:
	var panel: ConnectionPanel = _panel()
	await get_tree().process_frame
	panel.url_edit.text = "relay.example.workers.dev"
	var config: Dictionary = {"transport": "auto"}
	assert_true(panel.apply_to(config))
	assert_eq(config["relay_url"], "wss://relay.example.workers.dev")
	assert_eq(config["host_via"], "relay")


func test_hosting_by_relay_without_an_address_is_stopped_with_a_message() -> void:
	var panel: ConnectionPanel = _panel()
	await get_tree().process_frame
	panel.url_edit.text = ""
	if AppSettings.relay_url().is_empty():
		var config: Dictionary = {}
		assert_false(panel.apply_to(config))
		assert_string_contains(panel.result_label.text, "relay address")


func test_hosting_directly_does_not_need_a_relay_address() -> void:
	AppSettings.set_host_via("direct")
	var panel: ConnectionPanel = _panel()
	await get_tree().process_frame
	panel.url_edit.text = ""
	var config: Dictionary = {}
	assert_true(panel.apply_to(config))
	assert_eq(config["host_via"], "direct")


func test_choosing_direct_is_saved_and_announced() -> void:
	var panel: ConnectionPanel = _panel()
	await get_tree().process_frame
	var seen: Array = []
	panel.host_via_changed.connect(func(via: String) -> void: seen.append(via))
	panel.via_picker.select(1)
	panel.via_picker.item_selected.emit(1)
	assert_eq(seen, ["direct"])
	assert_eq(AppSettings.host_via(), "direct")


# --- the Test button -------------------------------------------------------------------------------------------

func test_the_test_button_reports_a_working_relay_and_closes_its_test_room() -> void:
	var panel: ConnectionPanel = _panel()
	await get_tree().process_frame
	panel.url_edit.text = relay.url()
	panel.test_button.pressed.emit()
	assert_true(panel.test_button.disabled, "one test at a time")
	assert_true(await _until(func() -> bool: return not panel.test_button.disabled))
	assert_string_contains(panel.result_label.text, "The relay works")
	assert_eq(relay.paths, ["/host"])


func test_the_test_button_reports_what_a_refusing_relay_said() -> void:
	relay.refuse_hosting_with = "RELAY_BUSY"
	var panel: ConnectionPanel = _panel()
	await get_tree().process_frame
	panel.url_edit.text = relay.url()
	panel.test_button.pressed.emit()
	assert_true(await _until(func() -> bool: return not panel.test_button.disabled))
	assert_eq(panel.result_label.text, RelayTransport.REASONS["RELAY_BUSY"])


func test_the_test_button_without_an_address_says_what_to_do() -> void:
	var panel: ConnectionPanel = _panel()
	await get_tree().process_frame
	panel.url_edit.text = ""
	panel.test_button.pressed.emit()
	assert_string_contains(panel.result_label.text, "relay address")
	assert_false(panel.test_button.disabled)


func test_a_probe_gives_up_on_a_relay_that_never_answers() -> void:
	var probe: RelayProbe = RelayProbe.new()
	probe.clock = clock.as_callable()
	var results: Array = []
	probe.finished.connect(func(ok: bool, message: String) -> void: results.append([ok, message]))
	relay.stop()
	probe.start("ws://127.0.0.1:%d" % relay.port)
	assert_true(probe.is_running())
	clock.now += RelayProbe.TIMEOUT_MSEC + 1
	probe.poll()
	assert_eq(results.size(), 1)
	assert_false(results[0][0])
	assert_string_contains(results[0][1], "did not answer")
	assert_false(probe.is_running())


func test_a_probe_with_a_bad_address_fails_at_once_and_a_stopped_probe_is_silent() -> void:
	var probe: RelayProbe = RelayProbe.new()
	var results: Array = []
	probe.finished.connect(func(ok: bool, message: String) -> void: results.append([ok, message]))
	probe.start("https://nope.example.com")
	assert_eq(results.size(), 1)
	assert_false(results[0][0])
	probe.start(relay.url())
	probe.stop()
	assert_false(probe.is_running())
	assert_eq(results.size(), 1, "stopping reports nothing")


# --- the lobby start screen -----------------------------------------------------------------------------------------

func _scene(player_name: String) -> LobbyScene:
	var scene: LobbyScene = LobbyScene.new()
	scene.setup({
		"game_id": "test_game", "game_title": "Test Game", "app_version": "1.0.0",
		"min_players": 2, "max_players": 3, "min_active_players": 1,
		"transport": TransportFactory.network_config(), "player_name": player_name,
	})
	add_child_autofree(scene)
	return scene


func test_the_lobby_shows_the_panel_only_for_the_app_config() -> void:
	var plain: LobbyScene = LobbyScene.new()
	plain.setup({"game_id": "test_game", "game_title": "T", "app_version": "1.0.0", "transport": TransportFactory.default_config()})
	add_child_autofree(plain)
	await get_tree().process_frame
	assert_null(plain.connection_panel, "tests and direct-only setups are unchanged")
	var app: LobbyScene = _scene("Asha")
	await get_tree().process_frame
	assert_not_null(app.connection_panel)


func test_the_port_is_only_shown_when_hosting_by_direct_address() -> void:
	var scene: LobbyScene = _scene("Asha")
	await get_tree().process_frame
	assert_false(scene.port_spin.visible, "room codes need no port")
	scene.connection_panel.via_picker.select(1)
	scene.connection_panel.via_picker.item_selected.emit(1)
	assert_true(scene.port_spin.visible)
	assert_true(scene.port_label.visible)


func test_hosting_and_joining_through_the_boxes_by_room_code() -> void:
	var host: LobbyScene = _scene("Hosty")
	await get_tree().process_frame
	host.connection_panel.url_edit.text = relay.url()
	host.host_button.pressed.emit()
	assert_true(await _until(func() -> bool: return host.lobby_view.visible and host.shared_address != ""), "hosting never went live")
	assert_eq(host.shared_address, ScriptedRelay.CODE)
	assert_eq(host.address_label.text, "Share this room code: %s" % ScriptedRelay.CODE)

	var guest: LobbyScene = _scene("Asha")
	await get_tree().process_frame
	guest.connection_panel.url_edit.text = relay.url()
	guest.address_edit.text = host.shared_address.to_lower()
	guest.join_button.pressed.emit()
	assert_true(await _until(func() -> bool: return host.players_box.get_child_count() == 2 and guest.players_box.get_child_count() == 2))
	assert_eq(AppSettings.relay_url(), relay.url(), "the address was remembered for next time")


func test_the_lobby_will_not_host_by_relay_without_an_address() -> void:
	if not AppSettings.relay_url().is_empty():
		return  # a project default exists; this test is about having none
	var scene: LobbyScene = _scene("Hosty")
	await get_tree().process_frame
	scene.connection_panel.url_edit.text = ""
	scene.host_button.pressed.emit()
	assert_string_contains(scene.status_label.text, "relay address")
	assert_false(scene.lobby_view.visible)
	assert_false(scene.connecting_view.visible)
