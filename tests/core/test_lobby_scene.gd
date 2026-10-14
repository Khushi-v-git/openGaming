extends GutTest
## Drives two LobbyScenes in one process like two players would (loopback transport).

var hub: LoopbackHub


func before_each() -> void:
	hub = LoopbackHub.new()
	MessageLog.enabled = false


func after_each() -> void:
	MessageLog.enabled = OS.is_debug_build()


func _make_scene(player_name: String, extra: Dictionary = {}) -> LobbyScene:
	var scene: LobbyScene = LobbyScene.new()
	var options: Dictionary = {
		"game_id": "test_game",
		"game_title": "Test Game",
		"app_version": "1.0.0",
		"min_players": 2,
		"max_players": 3,
		"min_active_players": 1,  # these tests are about the host's wait/continue choice, not the minimum
		"transport": {"transport": "loopback", "hub": hub},
		"player_name": player_name,
	}
	options.merge(extra, true)
	scene.setup(options)
	add_child_autofree(scene)
	return scene


func _until(condition: Callable, max_frames: int = 600) -> bool:
	for _i: int in max_frames:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


## Presses Host and waits until hosting is live (the address arrives asynchronously).
func _start_hosting(scene: LobbyScene) -> void:
	scene.host_button.pressed.emit()
	assert_true(await _until(func() -> bool: return scene.lobby_view.visible and scene.shared_address != ""), "hosting never went live")


func _host_and_guest() -> Array[LobbyScene]:
	var host: LobbyScene = _make_scene("Hosty")
	await _start_hosting(host)
	var guest: LobbyScene = _make_scene("Asha")
	guest.address_edit.text = host.shared_address
	guest.join_button.pressed.emit()
	await _until(func() -> bool: return host.players_box.get_child_count() == 2 and guest.players_box.get_child_count() == 2)
	return [host, guest]


func _row_text(scene: LobbyScene, index: int) -> String:
	var row: HBoxContainer = scene.players_box.get_child(index)
	return "%s | %s" % [(row.get_child(0) as Label).text, (row.get_child(1) as Label).text]


# --- start view ------------------------------------------------------------------

func test_starts_on_the_start_view() -> void:
	var scene: LobbyScene = _make_scene("")
	assert_true(scene.start_view.visible)
	assert_false(scene.lobby_view.visible)


func test_port_field_only_appears_for_port_based_transports() -> void:
	var loop: LobbyScene = _make_scene("")
	assert_null(loop.port_spin)
	var direct: LobbyScene = _make_scene("", {"transport": TransportFactory.default_config()})
	assert_not_null(direct.port_spin)
	assert_eq(int(direct.port_spin.value), DirectWsTransport.DEFAULT_PORT)


func test_hosting_needs_a_valid_name() -> void:
	var scene: LobbyScene = _make_scene("   ")
	scene.host_button.pressed.emit()
	assert_true(scene.start_view.visible)
	assert_ne(scene.status_label.text, "")


func test_joining_needs_an_address() -> void:
	var scene: LobbyScene = _make_scene("Asha")
	scene.join_button.pressed.emit()
	assert_true(scene.start_view.visible)
	assert_string_contains(scene.status_label.text, "address")


# --- hosting and joining ---------------------------------------------------------

func test_host_sees_lobby_with_shareable_address() -> void:
	var host: LobbyScene = _make_scene("Hosty")
	await _start_hosting(host)
	assert_true(host.lobby_view.visible)
	assert_false(host.start_view.visible)
	assert_ne(host.shared_address, "")
	assert_string_contains(host.address_label.text, host.shared_address)
	assert_true(host.start_button.visible)
	assert_false(host.ready_button.visible)
	assert_eq(host.players_box.get_child_count(), 1)
	assert_eq(_row_text(host, 0), "Hosty (host) (you) | Ready")


func test_guest_joins_and_both_screens_list_both_players() -> void:
	var pair: Array[LobbyScene] = await _host_and_guest()
	var host: LobbyScene = pair[0]
	var guest: LobbyScene = pair[1]
	assert_eq(host.players_box.get_child_count(), 2)
	assert_eq(guest.players_box.get_child_count(), 2)
	assert_eq(_row_text(host, 1), "Asha | Not ready")
	assert_eq(_row_text(guest, 1), "Asha (you) | Not ready")
	assert_true(guest.ready_button.visible)
	assert_false(guest.start_button.visible)


func test_start_button_follows_readiness_and_starts_both_screens() -> void:
	var pair: Array[LobbyScene] = await _host_and_guest()
	var host: LobbyScene = pair[0]
	var guest: LobbyScene = pair[1]
	watch_signals(host)
	watch_signals(guest)
	assert_true(host.start_button.disabled, "not everyone is ready")
	guest.ready_button.button_pressed = true
	assert_true(await _until(func() -> bool: return not host.start_button.disabled))
	assert_eq(_row_text(host, 1), "Asha | Ready")
	host.start_button.pressed.emit()
	assert_true(await _until(func() -> bool: return get_signal_emit_count(guest, "game_started") == 1))
	assert_signal_emit_count(host, "game_started", 1)
	assert_true(guest.ready_button.disabled)


func test_ready_toggle_mirrors_the_host_after_leaving_and_joining_again() -> void:
	var pair: Array[LobbyScene] = await _host_and_guest()
	var host: LobbyScene = pair[0]
	var guest: LobbyScene = pair[1]
	guest.ready_button.button_pressed = true
	assert_true(await _until(func() -> bool: return _row_text(host, 1) == "Asha | Ready"))
	guest.leave_button.pressed.emit()
	assert_true(await _until(func() -> bool: return guest.start_view.visible))
	guest.address_edit.text = host.shared_address
	guest.join_button.pressed.emit()
	assert_true(await _until(func() -> bool: return guest.lobby_view.visible and guest.players_box.get_child_count() == 2))
	assert_eq(_row_text(guest, 1), "Asha (you) | Not ready")
	assert_false(guest.ready_button.button_pressed, "a fresh join starts not ready")


func test_unknown_address_returns_to_start_with_a_message() -> void:
	var guest: LobbyScene = _make_scene("Asha")
	guest.address_edit.text = "no-such-session"
	guest.join_button.pressed.emit()
	assert_true(await _until(func() -> bool: return guest.status_label.text.begins_with("Could not join")))
	assert_true(guest.start_view.visible)
	assert_false(guest.join_button.disabled, "can try again")


func test_full_room_message_is_shown_to_the_joiner() -> void:
	var host: LobbyScene = _make_scene("Hosty", {"max_players": 2})
	await _start_hosting(host)
	var first: LobbyScene = _make_scene("Asha")
	first.address_edit.text = host.shared_address
	first.join_button.pressed.emit()
	await _until(func() -> bool: return host.players_box.get_child_count() == 2)
	var late: LobbyScene = _make_scene("Late")
	late.address_edit.text = host.shared_address
	late.join_button.pressed.emit()
	assert_true(await _until(func() -> bool: return late.status_label.text.begins_with("Could not join")))
	assert_string_contains(late.status_label.text, "full")


func test_host_can_remove_a_player_with_the_remove_button() -> void:
	var pair: Array[LobbyScene] = await _host_and_guest()
	var host: LobbyScene = pair[0]
	var guest: LobbyScene = pair[1]
	var row: HBoxContainer = host.players_box.get_child(1)
	var remove: Button = row.get_child(2)
	assert_eq(remove.text, "Remove")
	remove.pressed.emit()
	assert_true(await _until(func() -> bool: return guest.start_view.visible))
	assert_string_contains(guest.status_label.text, "removed")
	assert_true(await _until(func() -> bool: return host.players_box.get_child_count() == 1))


func test_guest_leave_returns_to_start_and_host_updates() -> void:
	var pair: Array[LobbyScene] = await _host_and_guest()
	var host: LobbyScene = pair[0]
	var guest: LobbyScene = pair[1]
	guest.leave_button.pressed.emit()
	assert_true(await _until(func() -> bool: return guest.start_view.visible))
	assert_eq(guest.status_label.text, "", "leaving on purpose is not an error")
	assert_true(await _until(func() -> bool: return host.players_box.get_child_count() == 1))


func test_host_leaving_ends_the_session_for_guests() -> void:
	var pair: Array[LobbyScene] = await _host_and_guest()
	var host: LobbyScene = pair[0]
	var guest: LobbyScene = pair[1]
	host.leave_button.pressed.emit()
	assert_true(await _until(func() -> bool: return host.start_view.visible and guest.start_view.visible))
	assert_string_contains(guest.status_label.text, "Left the session")


func test_rejoin_button_brings_a_dropped_guest_back_as_the_same_player() -> void:
	var pair: Array[LobbyScene] = await _host_and_guest()
	var host: LobbyScene = pair[0]
	var guest: LobbyScene = pair[1]
	assert_false(guest.rejoin_button.visible)
	var guest_id: String = guest._client.player_id
	# The guest's connection drops (the host is fine): the host cuts the line.
	var peer_id: int = host._host.session.registry.peer_of(guest_id)
	host._host.session.transport.disconnect_peer(peer_id)
	assert_true(await _until(func() -> bool: return guest.start_view.visible))
	assert_true(guest.rejoin_button.visible, "offered because the connection was lost")
	assert_string_contains(guest.status_label.text, "Left the session")
	guest.rejoin_button.pressed.emit()
	assert_true(await _until(func() -> bool: return guest.lobby_view.visible and guest.players_box.get_child_count() == 2))
	assert_eq(guest._client.player_id, guest_id, "same player")
	assert_false(guest.rejoin_button.visible)
	assert_eq(host.players_box.get_child_count(), 2)


func test_rejoin_button_is_hidden_after_being_removed_by_the_host() -> void:
	var pair: Array[LobbyScene] = await _host_and_guest()
	var host: LobbyScene = pair[0]
	var guest: LobbyScene = pair[1]
	(host.players_box.get_child(1).get_child(2) as Button).pressed.emit()
	assert_true(await _until(func() -> bool: return guest.start_view.visible))
	assert_false(guest.rejoin_button.visible)


# --- connecting state and Cancel --------------------------------------------------

## Relay delays are counted in frames but handshake timeouts run on the real clock, so
## stretch the timeouts: a slow or loaded machine must not turn a delay into a timeout.
const PATIENT: Dictionary = {"handshake_timeout_msec": 600000, "host_silence_timeout_msec": 600000, "ping_timeout_msec": 600000}


func _relay_scene(relay: FakeRelay, player_name: String, extra: Dictionary = {}) -> LobbyScene:
	var options: Dictionary = {"transport": {"transport": "fake_relay", "relay": relay}, "session_options": PATIENT}
	options.merge(extra, true)
	return _make_scene(player_name, options)


func test_joining_shows_connecting_with_cancel_until_the_host_answers() -> void:
	var relay: FakeRelay = FakeRelay.new()
	var host: LobbyScene = _relay_scene(relay, "Hosty")
	await _start_hosting(host)
	relay.delay_polls = 40  # a slow network
	var guest: LobbyScene = _relay_scene(relay, "Asha")
	guest.address_edit.text = host.shared_address
	guest.join_button.pressed.emit()
	assert_true(guest.connecting_view.visible)
	assert_false(guest.start_view.visible)
	assert_false(guest.lobby_view.visible)
	assert_string_contains(guest.connecting_label.text, host.shared_address)
	assert_true(guest.cancel_button.visible)
	await get_tree().process_frame
	assert_true(guest.connecting_view.visible, "still connecting")
	assert_true(await _until(func() -> bool: return guest.lobby_view.visible, 2000))
	assert_false(guest.connecting_view.visible)


func test_cancel_while_connecting_returns_to_start_and_nobody_sees_a_ghost() -> void:
	var relay: FakeRelay = FakeRelay.new()
	var host: LobbyScene = _relay_scene(relay, "Hosty")
	await _start_hosting(host)
	relay.delay_polls = 40
	var guest: LobbyScene = _relay_scene(relay, "Asha")
	guest.address_edit.text = host.shared_address
	guest.join_button.pressed.emit()
	await get_tree().process_frame
	guest.cancel_button.pressed.emit()
	assert_true(guest.start_view.visible)
	assert_false(guest.connecting_view.visible)
	assert_eq(guest.status_label.text, "", "cancelling is not an error")
	assert_false(guest.join_button.disabled)
	relay.delay_polls = 0
	for _i: int in 90:
		await get_tree().process_frame
	assert_eq(host.players_box.get_child_count(), 1, "the host never saw the cancelled joiner stay")
	assert_true(guest.start_view.visible, "a late reply does not drag the guest back in")


func test_joining_can_be_tried_again_after_cancelling() -> void:
	var relay: FakeRelay = FakeRelay.new()
	var host: LobbyScene = _relay_scene(relay, "Hosty")
	await _start_hosting(host)
	var guest: LobbyScene = _relay_scene(relay, "Asha")
	guest.address_edit.text = host.shared_address
	guest.join_button.pressed.emit()
	guest.cancel_button.pressed.emit()
	guest.join_button.pressed.emit()
	assert_true(await _until(func() -> bool: return guest.lobby_view.visible and host.players_box.get_child_count() == 2))


func test_hosting_shows_starting_with_cancel_while_the_relay_answers() -> void:
	var relay: FakeRelay = FakeRelay.new()
	relay.delay_polls = 40
	var host: LobbyScene = _relay_scene(relay, "Hosty")
	host.host_button.pressed.emit()
	assert_true(host.connecting_view.visible)
	assert_string_contains(host.connecting_label.text, "Starting")
	await get_tree().process_frame
	assert_true(host.connecting_view.visible, "relay has not answered yet")
	assert_true(await _until(func() -> bool: return host.lobby_view.visible, 2000))
	assert_ne(host.shared_address, "")


func test_cancel_while_starting_to_host_frees_everything() -> void:
	var relay: FakeRelay = FakeRelay.new()
	relay.delay_polls = 40
	var host: LobbyScene = _relay_scene(relay, "Hosty")
	host.host_button.pressed.emit()
	await get_tree().process_frame
	host.cancel_button.pressed.emit()
	assert_true(host.start_view.visible)
	assert_eq(relay.get_room_codes().size(), 0, "the room was given back")
	assert_false(host.host_button.disabled)
	for _i: int in 90:
		await get_tree().process_frame
	assert_true(host.start_view.visible, "a late registration does not bring the lobby back")


func test_a_host_that_cannot_start_returns_to_start_with_a_message() -> void:
	var relay: FakeRelay = FakeRelay.new()
	var first: LobbyScene = _relay_scene(relay, "Hosty", {"transport": {"transport": "fake_relay", "relay": relay, "room_code": "TAKEN"}})
	await _start_hosting(first)
	var second: LobbyScene = _relay_scene(relay, "Other", {"transport": {"transport": "fake_relay", "relay": relay, "room_code": "TAKEN"}})
	second.host_button.pressed.emit()
	assert_true(await _until(func() -> bool: return second.start_view.visible and second.status_label.text.begins_with("Could not host")))
	assert_string_contains(second.status_label.text, "taken")
	assert_false(second.host_button.disabled)


func test_a_host_that_fails_to_listen_says_so() -> void:
	var taken: DirectWsTransport = DirectWsTransport.new()
	assert_true(CoreResult.is_ok(taken.host_session({"port": 0, "bind_address": "127.0.0.1"})))
	var config: Dictionary = {"transport": "direct_ws", "port": taken.listening_port(), "bind_address": "127.0.0.1"}
	var scene: LobbyScene = _make_scene("Hosty", {"transport": config})
	scene.host_button.pressed.emit()
	assert_true(scene.start_view.visible)
	assert_string_contains(scene.status_label.text, "Could not host")
	taken.leave()


# --- games the app does not have --------------------------------------------------

func _registry() -> GameRegistry:
	var registry: GameRegistry = GameRegistry.new()
	registry.load_from("res://tests/fixtures/games")
	return registry


func test_joiner_whose_app_lacks_the_hosts_game_sees_a_clear_error() -> void:
	var host: LobbyScene = _make_scene("Hosty", {"game_id": "some_game_only_the_host_has"})
	await _start_hosting(host)
	var guest: LobbyScene = _make_scene("Asha", {"game_registry": _registry()})
	guest.address_edit.text = host.shared_address
	guest.join_button.pressed.emit()
	assert_true(await _until(func() -> bool: return guest.start_view.visible and guest.status_label.text != ""))
	assert_string_contains(guest.status_label.text, "some_game_only_the_host_has")
	assert_string_contains(guest.status_label.text, "does not have")
	assert_true(await _until(func() -> bool: return host.players_box.get_child_count() == 1), "the host is not left with a ghost")


func test_joiner_whose_app_has_the_game_joins_and_sees_its_name() -> void:
	var registry: GameRegistry = _registry()
	var host: LobbyScene = _make_scene("Hosty", {"game_id": "alpha", "game_registry": registry})
	await _start_hosting(host)
	assert_eq(host.title_label.text, "Zebra Race")
	var guest: LobbyScene = _make_scene("Asha", {"game_registry": registry})
	guest.address_edit.text = host.shared_address
	guest.join_button.pressed.emit()
	assert_true(await _until(func() -> bool: return guest.lobby_view.visible and guest.players_box.get_child_count() == 2))
	assert_eq(guest.title_label.text, "Zebra Race", "the joiner never chose a game; it follows the host")


func test_player_limits_come_from_the_manifest_when_a_registry_is_given() -> void:
	var registry: GameRegistry = _registry()
	var host: LobbyScene = _make_scene("Hosty", {"game_id": "beta", "game_registry": registry, "min_players": 3, "max_players": 4})
	await _start_hosting(host)
	assert_eq(host._host.state["min_players"], 1)
	assert_eq(host._host.state["max_players"], 2)


# --- layout -----------------------------------------------------------------------

func _in_viewport(size: Vector2i, player_name: String = "Hosty") -> Array:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	viewport.disable_3d = true
	add_child_autofree(viewport)
	var scene: LobbyScene = LobbyScene.new()
	scene.setup({
		"game_id": "test_game", "game_title": "Test Game", "app_version": "1.0.0",
		"min_players": 2, "max_players": 4,
		"transport": {"transport": "loopback", "hub": hub}, "player_name": player_name,
	})
	viewport.add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	return [viewport, scene]


func _assert_fits(viewport: SubViewport, scene: LobbyScene, label: String) -> void:
	var window: Rect2 = Rect2(Vector2.ZERO, Vector2(viewport.size))
	var rect: Rect2 = scene.panel.get_global_rect()
	assert_true(window.encloses(rect), "%s: panel %s must fit inside %s" % [label, str(rect), str(window)])
	assert_gte(rect.position.x, 8.0, "%s: left margin" % label)
	assert_gte(rect.position.y, 8.0, "%s: top margin" % label)
	var centered_x: float = absf((rect.position.x + rect.size.x * 0.5) - window.size.x * 0.5)
	var centered_y: float = absf((rect.position.y + rect.size.y * 0.5) - window.size.y * 0.5)
	assert_lt(centered_x, 2.0, "%s: horizontally centered" % label)
	assert_lt(centered_y, 2.0, "%s: vertically centered" % label)
	assert_eq(scene.size, Vector2(viewport.size), "%s: scene fills the window" % label)


func _fill_lobby(scene: LobbyScene) -> void:
	scene.host_button.pressed.emit()
	await _until(func() -> bool: return scene.lobby_view.visible)


func test_layout_fits_at_1280x720_and_1920x1080() -> void:
	for dims: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var made: Array = await _in_viewport(dims)
		var viewport: SubViewport = made[0]
		var scene: LobbyScene = made[1]
		_assert_fits(viewport, scene, "start view %s" % str(dims))
		await _fill_lobby(scene)
		await get_tree().process_frame
		_assert_fits(viewport, scene, "lobby view %s" % str(dims))


func test_full_lobby_with_long_names_still_fits_at_1280x720() -> void:
	var made: Array = await _in_viewport(Vector2i(1280, 720), "H".repeat(Handshake.MAX_NAME_LENGTH))
	var viewport: SubViewport = made[0]
	var host: LobbyScene = made[1]
	await _fill_lobby(host)
	for i: int in 3:
		var guest: LobbyScene = _make_scene("G".repeat(Handshake.MAX_NAME_LENGTH - 1) + str(i))
		guest.address_edit.text = host.shared_address
		guest.join_button.pressed.emit()
	assert_true(await _until(func() -> bool: return host.players_box.get_child_count() == 4))
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_fits(viewport, host, "full lobby")


func test_panel_grows_with_the_window_but_stays_within_bounds() -> void:
	var small: Array = await _in_viewport(Vector2i(1280, 720))
	var large: Array = await _in_viewport(Vector2i(1920, 1080))
	var small_w: float = (small[1] as LobbyScene).panel.size.x
	var large_w: float = (large[1] as LobbyScene).panel.size.x
	assert_gt(large_w, small_w)
	assert_lte(large_w, 760.0 + 2.0 * Tokens.SPACE_L + 1.0)


func test_layout_follows_a_window_resize_in_both_directions() -> void:
	var made: Array = await _in_viewport(Vector2i(1920, 1080))
	var viewport: SubViewport = made[0]
	var scene: LobbyScene = made[1]
	await _fill_lobby(scene)
	var widths: Array[float] = []
	for dims: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1000, 600), Vector2i(1920, 1080), Vector2i(1280, 720)]:
		viewport.size = dims
		await get_tree().process_frame
		await get_tree().process_frame
		_assert_fits(viewport, scene, "after resizing to %s" % str(dims))
		widths.append(scene.panel.size.x)
	assert_gt(widths[0], 0.0)
	assert_eq(widths[0], widths[4], "returning to the same size gives the same layout")
	assert_gt(widths[3], widths[0])


func test_connecting_view_also_fits() -> void:
	var made: Array = await _in_viewport(Vector2i(1280, 720))
	var viewport: SubViewport = made[0]
	var scene: LobbyScene = made[1]
	scene.address_edit.text = "no-such-session"
	scene.join_button.pressed.emit()
	assert_true(scene.connecting_view.visible)
	await get_tree().process_frame
	_assert_fits(viewport, scene, "connecting view")


# --- a guest comes back and the host decides ---------------------------------------

## A started game with a host and one guest ("Asha"); then Asha's connection dies.
func _started_game_with_asha_dropped() -> Array[LobbyScene]:
	var pair: Array[LobbyScene] = await _host_and_guest()
	var host: LobbyScene = pair[0]
	var guest: LobbyScene = pair[1]
	guest.ready_button.button_pressed = true
	await _until(func() -> bool: return not host.start_button.disabled)
	host.start_button.pressed.emit()
	await _until(func() -> bool: return guest.ready_button.disabled)
	guest._client.session.transport.leave()  # the app closed
	assert_true(await _until(func() -> bool: return _row_text(host, 1).ends_with("Disconnected")))
	return pair


func test_the_host_sees_a_pause_notice_and_can_continue_or_wait_again() -> void:
	var pair: Array[LobbyScene] = await _started_game_with_asha_dropped()
	var host: LobbyScene = pair[0]
	assert_true(host.notice_label.visible)
	assert_string_contains(host.notice_label.text, "paused")
	assert_string_contains(host.notice_label.text, "Asha")
	assert_true(host.continue_button.visible)
	assert_false(host.wait_button.visible)
	host.continue_button.pressed.emit()
	assert_true(await _until(func() -> bool: return host.wait_button.visible))
	assert_false(host.continue_button.visible)
	assert_string_contains(host.notice_label.text, "continuing without")
	host.wait_button.pressed.emit()
	assert_true(await _until(func() -> bool: return host.continue_button.visible))


func test_an_absent_player_can_be_removed_by_the_host_in_a_started_game() -> void:
	var pair: Array[LobbyScene] = await _started_game_with_asha_dropped()
	var host: LobbyScene = pair[0]
	var row: HBoxContainer = host.players_box.get_child(1)
	assert_eq((row.get_child(2) as Button).text, "Remove")
	(row.get_child(2) as Button).pressed.emit()
	assert_true(await _until(func() -> bool: return not host.notice_label.visible), "nobody left to wait for")
	assert_eq(host.players_box.get_child(1).get_child_count(), 2, "no Remove button for a player who is already gone")


func test_a_guest_whose_app_restarted_asks_and_the_host_lets_them_in() -> void:
	var pair: Array[LobbyScene] = await _started_game_with_asha_dropped()
	var host: LobbyScene = pair[0]
	var back: LobbyScene = _make_scene("Asha")  # a fresh app: same name, no saved identity
	back.address_edit.text = host.shared_address
	back.join_button.pressed.emit()
	assert_true(await _until(func() -> bool: return host.claims_box.get_child_count() == 1))
	var row: HBoxContainer = host.claims_box.get_child(0)
	assert_eq((row.get_child(0) as Label).text, "Asha wants to rejoin")
	assert_eq((row.get_child(1) as Button).text, "Let in")
	assert_eq((row.get_child(2) as Button).text, "Decline")
	assert_true(await _until(func() -> bool: return back.connecting_label.text.contains("host to let you back in")))
	assert_true(back.connecting_view.visible)
	assert_true(back.cancel_button.visible)
	(row.get_child(1) as Button).pressed.emit()
	assert_true(await _until(func() -> bool: return back.lobby_view.visible and host.claims_box.get_child_count() == 0))
	assert_eq(_row_text(host, 1), "Asha | Ready", "the seat kept its state")
	assert_false(host.notice_label.visible, "everyone is back")
	assert_eq(host.players_box.get_child_count(), 2, "same seat, no duplicate")


func test_the_host_can_decline_and_the_guest_is_told() -> void:
	var pair: Array[LobbyScene] = await _started_game_with_asha_dropped()
	var host: LobbyScene = pair[0]
	var back: LobbyScene = _make_scene("Asha")
	back.address_edit.text = host.shared_address
	back.join_button.pressed.emit()
	await _until(func() -> bool: return host.claims_box.get_child_count() == 1)
	((host.claims_box.get_child(0) as HBoxContainer).get_child(2) as Button).pressed.emit()
	assert_true(await _until(func() -> bool: return back.start_view.visible and back.status_label.text != ""))
	assert_string_contains(back.status_label.text, "did not let you back in")
	assert_eq(host.claims_box.get_child_count(), 0)
	assert_true(host.notice_label.visible, "the seat is still waiting")


func test_a_waiting_guest_can_cancel_and_the_request_disappears() -> void:
	var pair: Array[LobbyScene] = await _started_game_with_asha_dropped()
	var host: LobbyScene = pair[0]
	var back: LobbyScene = _make_scene("Asha")
	back.address_edit.text = host.shared_address
	back.join_button.pressed.emit()
	await _until(func() -> bool: return host.claims_box.get_child_count() == 1)
	back.cancel_button.pressed.emit()
	assert_true(back.start_view.visible)
	assert_true(await _until(func() -> bool: return host.claims_box.get_child_count() == 0))


func test_the_busiest_host_screen_still_fits_at_1280x720() -> void:
	# started game, four players with long names, one away, a rejoin request waiting,
	# the pause notice and its button: the tallest the lobby screen gets
	var made: Array = await _in_viewport(Vector2i(1280, 720), "H".repeat(Handshake.MAX_NAME_LENGTH))
	var viewport: SubViewport = made[0]
	var host: LobbyScene = made[1]
	await _fill_lobby(host)
	var guests: Array[LobbyScene] = []
	for i: int in 3:
		var guest: LobbyScene = _make_scene("G".repeat(Handshake.MAX_NAME_LENGTH - 1) + str(i))
		guest.address_edit.text = host.shared_address
		guest.join_button.pressed.emit()
		guests.append(guest)
	assert_true(await _until(func() -> bool: return host.players_box.get_child_count() == 4))
	for guest: LobbyScene in guests:
		guest.ready_button.button_pressed = true
	assert_true(await _until(func() -> bool: return not host.start_button.disabled))
	host.start_button.pressed.emit()
	assert_true(await _until(func() -> bool: return guests[0].ready_button.disabled))
	var away_name: String = "G".repeat(Handshake.MAX_NAME_LENGTH - 1) + "0"
	guests[0]._client.session.transport.leave()
	assert_true(await _until(func() -> bool: return host.notice_label.visible))
	var back: LobbyScene = _make_scene(away_name)
	back.address_edit.text = host.shared_address
	back.join_button.pressed.emit()
	assert_true(await _until(func() -> bool: return host.claims_box.get_child_count() == 1))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(host.continue_button.visible)
	_assert_fits(viewport, host, "busiest host screen")


# --- bigger games (5+ players) ----------------------------------------------------

func _lobby_of(count: int, size: Vector2i) -> Array:
	var made: Array = await _in_viewport(size, "Hosty")
	var host: LobbyScene = made[1]
	host.options["max_players"] = 8
	await _fill_lobby(host)
	for i: int in count - 1:
		var guest: LobbyScene = _make_scene("Guest%d" % i, {"max_players": 8})
		guest.address_edit.text = host.shared_address
		guest.join_button.pressed.emit()
	assert_true(await _until(func() -> bool: return host.players_box.get_child_count() == count))
	await get_tree().process_frame
	await get_tree().process_frame
	return made


func test_five_and_eight_player_lobbies_fit_at_1280x720() -> void:
	for count: int in [5, 6, 8]:
		var made: Array = await _lobby_of(count, Vector2i(1280, 720))
		_assert_fits(made[0], made[1], "%d players" % count)
		for child: Node in (made[0] as SubViewport).get_children():
			child.queue_free()
		await get_tree().process_frame


func test_continue_is_not_offered_when_too_few_players_would_remain() -> void:
	var host: LobbyScene = _make_scene("Hosty", {"min_active_players": 2})
	await _start_hosting(host)
	var guest: LobbyScene = _make_scene("Asha")
	guest.address_edit.text = host.shared_address
	guest.join_button.pressed.emit()
	await _until(func() -> bool: return host.players_box.get_child_count() == 2)
	guest.ready_button.button_pressed = true
	await _until(func() -> bool: return not host.start_button.disabled)
	host.start_button.pressed.emit()
	await _until(func() -> bool: return guest.ready_button.disabled)
	guest._client.session.transport.leave()
	assert_true(await _until(func() -> bool: return host.notice_label.visible))
	assert_string_contains(host.notice_label.text, "Not enough players")
	assert_string_contains(host.notice_label.text, "needs 2")
	assert_false(host.continue_button.visible, "the host cannot choose to go on with one player")
