extends GutTest
## The pause / host-decision overlay, driven by a scripted controller (no network): what it shows
## to the host and to a guest, and which controller calls its buttons make.


class FakeController:
	extends GameController
	var info: Dictionary = {"paused": false, "away": [], "can_continue": true, "is_host": true, "min_active": 2}
	var calls: Array = []
	var me: String = "p1"

	func presence() -> Dictionary:
		return info

	func local_player_id() -> String:
		return me

	func continue_without_waiting() -> Dictionary:
		calls.append(["continue"])
		return CoreResult.success()

	func wait_again() -> Dictionary:
		calls.append(["wait_again"])
		return CoreResult.success()

	func remove_player(player_id: String) -> Dictionary:
		calls.append(["remove", player_id])
		return CoreResult.success()

	func change(new_info: Dictionary) -> void:
		info = new_info
		presence_changed.emit(info)


func _away(ids: Array) -> Array:
	return ids.map(func(id: String) -> Dictionary: return {"player_id": id, "name": "Name " + id})


func _made(host: bool = true) -> Array:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child_autofree(viewport)
	var controller: FakeController = FakeController.new()
	controller.info["is_host"] = host
	var overlay: PresenceOverlay = PresenceOverlay.new()
	viewport.add_child(overlay)
	overlay.setup(controller)
	return [overlay, controller]


func _paused(away: Array = ["a"], extra: Dictionary = {}) -> Dictionary:
	var info: Dictionary = {"paused": true, "away": _away(away), "can_continue": true, "is_host": true, "min_active": 2}
	info.merge(extra, true)
	return info


# --- showing and hiding ---------------------------------------------------------------------------------

func test_nothing_shows_while_everyone_is_present() -> void:
	var made: Array = _made()
	var overlay: PresenceOverlay = made[0]
	assert_false(overlay.pause_layer.visible)
	assert_false(overlay.lost_layer.visible)
	assert_false(overlay.continued_panel.visible)
	assert_false(overlay.is_blocking())


func test_pausing_blocks_the_game_and_resuming_clears_it() -> void:
	var made: Array = _made()
	var overlay: PresenceOverlay = made[0]
	var controller: FakeController = made[1]
	controller.change(_paused())
	assert_true(overlay.pause_layer.visible)
	assert_true(overlay.is_blocking())
	controller.change({"paused": false, "away": [], "can_continue": true, "is_host": true, "min_active": 2})
	assert_false(overlay.pause_layer.visible)


# --- the host --------------------------------------------------------------------------------------------

func test_the_host_sees_who_is_away_and_the_three_decisions() -> void:
	var made: Array = _made(true)
	var overlay: PresenceOverlay = made[0]
	(made[1] as FakeController).change(_paused(["a", "b"]))
	assert_eq(overlay.pause_body.text, "Waiting for Name a and Name b to come back.")
	assert_true(overlay.keep_button.visible)
	assert_true(overlay.continue_button.visible)
	assert_false(overlay.continue_button.disabled)
	assert_false(overlay.continue_note.visible)
	assert_eq(overlay.remove_box.get_child_count(), 2)
	assert_eq((overlay.remove_box.get_child(0) as Button).text, "Remove Name a for good")


func test_keep_waiting_changes_nothing() -> void:
	var made: Array = _made(true)
	var overlay: PresenceOverlay = made[0]
	var kept: Array = [0]
	overlay.kept_waiting.connect(func() -> void: kept[0] += 1)
	(made[1] as FakeController).change(_paused())
	overlay.keep_button.pressed.emit()
	assert_eq(kept[0], 1)
	assert_true(overlay.pause_layer.visible)
	assert_eq((made[1] as FakeController).calls, [])


func test_continue_and_remove_call_the_controller() -> void:
	ConfirmDialog.auto_confirm = true  # the question has its own test below
	var made: Array = _made(true)
	var overlay: PresenceOverlay = made[0]
	var controller: FakeController = made[1]
	controller.change(_paused(["a", "b"]))
	overlay.continue_button.pressed.emit()
	(overlay.remove_box.get_child(1) as Button).pressed.emit()
	assert_eq(controller.calls, [["continue"], ["remove", "b"]])
	ConfirmDialog.auto_confirm = false


func test_continue_is_disabled_with_a_reason_when_too_few_would_remain() -> void:
	var made: Array = _made(true)
	var overlay: PresenceOverlay = made[0]
	(made[1] as FakeController).change(_paused(["a"], {"can_continue": false, "min_active": 3}))
	assert_true(overlay.continue_button.disabled)
	assert_true(overlay.continue_note.visible)
	assert_eq(overlay.continue_note.text, "The game needs at least 3 players.")


func test_after_continuing_a_slim_banner_offers_to_wait_again() -> void:
	var made: Array = _made(true)
	var overlay: PresenceOverlay = made[0]
	var controller: FakeController = made[1]
	controller.change(_paused())
	controller.change({"paused": false, "away": _away(["a"]), "can_continue": true, "is_host": true, "min_active": 2})
	assert_false(overlay.pause_layer.visible, "play goes on")
	assert_false(overlay.is_blocking())
	assert_true(overlay.continued_panel.visible)
	assert_eq(overlay.continued_label.text, "Waiting for Name a is off: play continues.")
	overlay.wait_again_button.pressed.emit()
	assert_eq(controller.calls, [["wait_again"]])
	controller.change({"paused": false, "away": [], "can_continue": true, "is_host": true, "min_active": 2})
	assert_false(overlay.continued_panel.visible, "everyone is back")


# --- a guest ----------------------------------------------------------------------------------------------------

func test_a_guest_only_reads_that_the_host_is_deciding() -> void:
	var made: Array = _made(false)
	var overlay: PresenceOverlay = made[0]
	(made[1] as FakeController).change(_paused(["a"], {"is_host": false}))
	assert_true(overlay.pause_layer.visible)
	assert_eq(overlay.pause_body.text, "The host is deciding what to do about Name a.")
	assert_false(overlay.keep_button.visible)
	assert_false(overlay.continue_button.visible)
	assert_false(overlay.remove_box.visible)


func test_a_guest_gets_no_wait_again_banner() -> void:
	var made: Array = _made(false)
	var overlay: PresenceOverlay = made[0]
	(made[1] as FakeController).change({"paused": false, "away": _away(["a"]), "can_continue": true, "is_host": false, "min_active": 2})
	assert_false(overlay.continued_panel.visible)


# --- the link and losing the session ----------------------------------------------------------------------------------

func test_link_banners_come_and_go_with_the_link_state() -> void:
	var made: Array = _made(false)
	var overlay: PresenceOverlay = made[0]
	var controller: FakeController = made[1]
	var panel: Control = overlay.link_panel
	assert_false(panel.visible)
	controller.link_changed.emit(Transport.LINK_HOST_AWAY)
	assert_true(panel.visible)
	assert_eq(overlay.link_label.text, "Waiting for the host's connection...")
	controller.link_changed.emit(Transport.LINK_RECONNECTING)
	assert_eq(overlay.link_label.text, "Reconnecting...")
	controller.link_changed.emit(Transport.LINK_OK)
	assert_false(panel.visible)
	assert_false(overlay.is_blocking(), "a degraded link never blocks the game")


func test_losing_the_session_shows_a_card_with_the_reason_and_a_way_out() -> void:
	var made: Array = _made(false)
	var overlay: PresenceOverlay = made[0]
	var controller: FakeController = made[1]
	var left: Array = [0]
	overlay.leave_requested.connect(func() -> void: left[0] += 1)
	controller.lost.emit({"code": "HOST_CLOSED", "message": "The host closed the session."})
	assert_true(overlay.lost_layer.visible)
	assert_eq(overlay.lost_title.text, "Disconnected")
	assert_eq(overlay.lost_body.text, "The host closed the session.")
	overlay.lost_button.pressed.emit()
	assert_eq(left[0], 1)


func test_a_lost_session_wins_over_a_pause() -> void:
	var made: Array = _made(false)
	var overlay: PresenceOverlay = made[0]
	var controller: FakeController = made[1]
	controller.change(_paused(["a"], {"is_host": false}))
	controller.lost.emit({"code": "HOST_LOST", "message": "Lost connection to the host."})
	assert_true(overlay.lost_layer.visible)
	assert_false(overlay.pause_layer.visible)


func test_removing_a_player_asks_first_and_keep_does_nothing() -> void:
	ConfirmDialog.auto_confirm = false
	var made: Array = _made(true)
	var overlay: PresenceOverlay = made[0]
	var controller: FakeController = made[1]
	controller.change(_paused(["a", "b"]))
	(overlay.remove_box.get_child(1) as Button).pressed.emit()
	var dialog: ConfirmDialog = null
	for child: Node in overlay.get_children():
		if child is ConfirmDialog:
			dialog = child
	assert_not_null(dialog, "a question appears")
	assert_string_contains(dialog.title_label.text, "Remove")
	dialog.buttons[0].pressed.emit()  # Keep
	assert_eq(controller.calls, [])
	(overlay.remove_box.get_child(1) as Button).pressed.emit()
	for child: Node in overlay.get_children():
		if child is ConfirmDialog and not child.is_queued_for_deletion():
			(child as ConfirmDialog).buttons[1].pressed.emit()  # Remove
	assert_eq(controller.calls, [["remove", "b"]])
