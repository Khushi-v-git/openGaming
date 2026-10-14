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


func _host_and_guest() -> Array[LobbyScene]:
	var host: LobbyScene = _make_scene("Hosty")
	host.host_button.pressed.emit()
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
	host.host_button.pressed.emit()
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


func test_unknown_address_returns_to_start_with_a_message() -> void:
	var guest: LobbyScene = _make_scene("Asha")
	guest.address_edit.text = "no-such-session"
	guest.join_button.pressed.emit()
	assert_true(await _until(func() -> bool: return guest.status_label.text.begins_with("Could not join")))
	assert_true(guest.start_view.visible)
	assert_false(guest.join_button.disabled, "can try again")


func test_full_room_message_is_shown_to_the_joiner() -> void:
	var host: LobbyScene = _make_scene("Hosty", {"max_players": 2})
	host.host_button.pressed.emit()
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
