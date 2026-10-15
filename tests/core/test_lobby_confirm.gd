extends GutTest
## Leaving the lobby, closing the room and removing a player each ask first; Stay does nothing.
## Also: the ready pill and the Start pill in the lobby, and the chips' dots.

var hub: LoopbackHub


func before_each() -> void:
	hub = LoopbackHub.new()
	MessageLog.enabled = false
	ConfirmDialog.auto_confirm = false


func after_each() -> void:
	await get_tree().process_frame
	MessageLog.enabled = OS.is_debug_build()
	ConfirmDialog.auto_confirm = false


func _make_scene(player_name: String) -> LobbyScene:
	var scene: LobbyScene = LobbyScene.new()
	scene.setup({
		"game_id": "test_game", "game_title": "Test Game", "app_version": "1.0.0",
		"min_players": 2, "max_players": 3, "min_active_players": 1,
		"transport": {"transport": "loopback", "hub": hub}, "player_name": player_name,
	})
	add_child_autofree(scene)
	return scene


func _until(condition: Callable, max_frames: int = 600) -> bool:
	for _i: int in max_frames:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _pair() -> Array[LobbyScene]:
	var host: LobbyScene = _make_scene("Hosty")
	host.host_button.pressed.emit()
	await _until(func() -> bool: return host.lobby_view.visible and host.shared_address != "")
	var guest: LobbyScene = _make_scene("Asha")
	guest.address_edit.text = host.shared_address
	guest.join_button.pressed.emit()
	await _until(func() -> bool: return host.players_box.get_child_count() == 2 and guest.players_box.get_child_count() == 2)
	return [host, guest]


func _dialog_of(scene: Node) -> ConfirmDialog:
	for child: Node in scene.get_children():
		if child is ConfirmDialog and not child.is_queued_for_deletion():
			return child
	return null


# --- leaving -------------------------------------------------------------------------------------------

func test_a_guest_pressing_leave_is_asked_and_stay_changes_nothing() -> void:
	var pair: Array[LobbyScene] = await _pair()
	var guest: LobbyScene = pair[1]
	guest.leave_button.pressed.emit()
	var dialog: ConfirmDialog = _dialog_of(guest)
	assert_not_null(dialog)
	assert_eq(dialog.title_label.text, "Leave this lobby?")
	dialog.buttons[0].pressed.emit()
	await get_tree().process_frame
	assert_true(guest.lobby_view.visible, "still in the lobby")
	assert_eq(pair[0].players_box.get_child_count(), 2)


func test_a_guest_confirming_leave_goes_back_to_the_start_screen() -> void:
	var pair: Array[LobbyScene] = await _pair()
	var guest: LobbyScene = pair[1]
	guest.leave_button.pressed.emit()
	_dialog_of(guest).buttons[1].pressed.emit()
	assert_true(await _until(func() -> bool: return guest.start_view.visible))
	assert_true(await _until(func() -> bool: return pair[0].players_box.get_child_count() == 1))


func test_the_host_is_asked_whether_to_close_the_room_for_everyone() -> void:
	var pair: Array[LobbyScene] = await _pair()
	var host: LobbyScene = pair[0]
	host.leave_button.pressed.emit()
	var dialog: ConfirmDialog = _dialog_of(host)
	assert_eq(dialog.title_label.text, "Close the room for everyone?")
	dialog.buttons[0].pressed.emit()  # Keep hosting
	await get_tree().process_frame
	assert_true(host.lobby_view.visible)
	assert_true(pair[1].lobby_view.visible)
	host.leave_button.pressed.emit()
	_dialog_of(host).buttons[1].pressed.emit()  # Close room
	assert_true(await _until(func() -> bool: return host.start_view.visible and pair[1].start_view.visible))


func test_cancelling_while_connecting_is_not_asked() -> void:
	var host: LobbyScene = _make_scene("Hosty")
	host.host_button.pressed.emit()
	host.cancel_button.pressed.emit()
	assert_null(_dialog_of(host))


func test_leave_without_a_session_asks_nothing() -> void:
	var scene: LobbyScene = _make_scene("Nobody")
	scene.ask_to_leave()
	assert_null(_dialog_of(scene))


# --- removing ------------------------------------------------------------------------------------------

func test_removing_a_player_asks_with_their_name_and_keep_changes_nothing() -> void:
	var pair: Array[LobbyScene] = await _pair()
	var host: LobbyScene = pair[0]
	var remove: Button = (host.players_box.get_child(1) as HBoxContainer).get_child(2)
	remove.pressed.emit()
	var dialog: ConfirmDialog = _dialog_of(host)
	assert_eq(dialog.title_label.text, "Remove Asha for good?")
	assert_eq(dialog.config["pawn_color"], "blue", "the second seat is blue")
	dialog.buttons[0].pressed.emit()
	await get_tree().process_frame
	assert_eq(host.players_box.get_child_count(), 2)
	assert_true(pair[1].lobby_view.visible)


func test_confirming_the_removal_removes_the_player() -> void:
	var pair: Array[LobbyScene] = await _pair()
	var host: LobbyScene = pair[0]
	((host.players_box.get_child(1) as HBoxContainer).get_child(2) as Button).pressed.emit()
	_dialog_of(host).buttons[1].pressed.emit()
	assert_true(await _until(func() -> bool: return pair[1].start_view.visible))
	assert_true(await _until(func() -> bool: return host.players_box.get_child_count() == 1))


# --- the ready pill and the start pill in the lobby ---------------------------------------------------------

func test_the_guests_ready_control_is_the_pill_with_its_caption_only_while_ready() -> void:
	var pair: Array[LobbyScene] = await _pair()
	var guest: LobbyScene = pair[1]
	assert_true(guest.ready_button is ReadyPill)
	assert_false(guest.ready_caption.visible)
	guest.ready_button.button_pressed = true
	assert_true(await _until(func() -> bool: return guest.ready_caption.visible))
	assert_eq(guest.ready_caption.text, "Tap again if you need a moment")
	assert_eq(guest.ready_button.text, "Ready!")
	guest.ready_button.button_pressed = false
	assert_true(await _until(func() -> bool: return not guest.ready_caption.visible))


func test_the_host_never_sees_the_ready_pill_and_start_is_a_wide_pill() -> void:
	var pair: Array[LobbyScene] = await _pair()
	var host: LobbyScene = pair[0]
	assert_false(host.ready_card.visible)
	assert_gte(host.start_button.custom_minimum_size.x, 240.0)
	assert_gte(host.start_button.custom_minimum_size.y, 60.0)
	assert_true(host.start_button.disabled, "the guest is not ready yet")
	assert_true(host.bottom_caption.visible)
	assert_eq(host.bottom_caption.text, "Everyone must be ready")


func test_the_chips_carry_a_dot_and_a_check_only_when_ready() -> void:
	var pair: Array[LobbyScene] = await _pair()
	var host: LobbyScene = pair[0]
	pair[1].ready_button.button_pressed = true
	assert_true(await _until(func() -> bool: return not host.start_button.disabled))
	for index: int in 2:
		var chip: Label = (host.players_box.get_child(index) as HBoxContainer).get_child(1)
		assert_eq(chip.text, "Ready")
		var dot: ChipDot = chip.get_child(0)
		assert_true(dot.ready_mark)
		assert_lte(chip.custom_minimum_size.y, 52.0)
