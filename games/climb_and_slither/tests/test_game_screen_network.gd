extends NetTestCase
## The Climb and Slither game screen on a networked table: each player has their own screen on
## their own NetworkGameController. Checks who may roll, the pause and host-decision overlay, and
## going back to the lobby.

var rules: ClimbAndSlitherRules
var table: GameNetTable
var screens: Array[ClimbGameScreen] = []  # [host, guest1, guest2...]
var controllers: Array[NetworkGameController] = []
var ended: Array = []  # per screen: how many game_ended signals


func make_env() -> TransportEnv:
	return LoopbackEnv.new()


func before_each() -> void:
	super.before_each()
	rules = ClimbAndSlitherRules.new()
	screens.clear()
	controllers.clear()
	ended.clear()


func after_each() -> void:
	await get_tree().process_frame  # queued frees finish before the orphan check
	super.after_each()


func _screen_for(controller: NetworkGameController) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child_autofree(viewport)
	var screen: ClimbGameScreen = load("res://games/climb_and_slither/ui/climb_game_screen.tscn").instantiate()
	viewport.add_child(screen)
	screen.set_speed_by_label("Instant")
	var index: int = screens.size()
	ended.append(0)
	screen.game_ended.connect(func() -> void: ended[index] += 1)
	screens.append(screen)
	controllers.append(controller)


## A table with `guest_count` guests, a screen for each seat, and the game started.
func _seat(guest_count: int = 2, settings: Dictionary = {}) -> void:
	table = await GameNetTable.create(self, rules, ClimbRig.classic(), 21, guest_count, settings, "climb_and_slither", 2, 4, 2)
	_screen_for(NetworkGameController.for_host(table.host))
	for guest: GameNetTable.Guest in table.guests:
		_screen_for(NetworkGameController.for_client(guest.game, rules))
	await table.start_game()
	for i: int in screens.size():
		screens[i].setup(controllers[i], controllers[i].players())
	await get_tree().process_frame
	# the screens were set up after the start batch: show it
	for i: int in screens.size():
		var latest: Dictionary = controllers[i].latest_view()
		if not latest.is_empty():
			screens[i].timeline.push({"seq": 1, "reason": "start", "events": [], "view": latest})


func _until(condition: Callable, frames: int = 400) -> bool:
	return await table.until(condition, frames)


# --- who may roll ----------------------------------------------------------------------------------------------

func test_only_the_player_whose_turn_it_is_can_roll_and_the_others_are_told_who_is_rolling() -> void:
	await _seat(2)
	assert_false(screens[0].roll_button.disabled, "the host moves first")
	assert_eq(screens[0].roll_button.text, "Your turn: roll")
	for i: int in [1, 2]:
		assert_true(screens[i].roll_button.disabled)
		assert_eq(screens[i].roll_button.text, "Hosty is rolling...")


func test_a_roll_on_one_screen_moves_every_screen_and_passes_the_turn() -> void:
	await _seat(2)
	screens[0].roll_button.pressed.emit()
	assert_true(await _until(func() -> bool: return not screens[1].roll_button.disabled and screens[0].roll_button.disabled))
	assert_eq(screens[2].current_view()["rolls"], 1)
	assert_eq(screens[1].roll_button.text, "Your turn: roll")
	assert_eq(screens[1].current_view()["positions"], screens[0].current_view()["positions"])
	assert_eq(screens[1].current_view()["you"], table.guests[0].player_id())


# --- pause and the host's decision ----------------------------------------------------------------------------------

func test_when_someone_drops_everyone_sees_the_overlay_and_cannot_roll() -> void:
	await _seat(2)
	table.guests[1].lobby.session.transport.leave()
	assert_true(await _until(func() -> bool: return screens[0].presence_overlay.pause_layer.visible and screens[1].presence_overlay.pause_layer.visible))
	assert_true(screens[0].roll_button.disabled, "paused: even the player to move waits")
	assert_true(screens[0].presence_overlay.continue_button.visible, "the host gets the decisions")
	assert_false(screens[1].presence_overlay.continue_button.visible, "a guest only reads")
	assert_string_contains(screens[1].presence_overlay.pause_body.text, "The host is deciding")
	assert_string_contains(screens[0].presence_overlay.pause_body.text, "Guest2")


func test_continuing_unpauses_and_gives_the_roll_back_to_whose_turn_it_is() -> void:
	await _seat(2)
	table.guests[1].lobby.session.transport.leave()
	await _until(func() -> bool: return screens[0].presence_overlay.pause_layer.visible)
	screens[0].presence_overlay.continue_button.pressed.emit()
	assert_true(await _until(func() -> bool: return not screens[0].presence_overlay.pause_layer.visible and not screens[1].presence_overlay.pause_layer.visible))
	assert_false(screens[0].roll_button.disabled, "it is the host's turn and play goes on")
	assert_true(screens[1].roll_button.disabled, "not guest 1's turn yet")
	assert_true(screens[0].presence_overlay.continued_panel.visible, "the host can still choose to wait again")
	screens[0].presence_overlay.wait_again_button.pressed.emit()
	assert_true(await _until(func() -> bool: return screens[0].presence_overlay.pause_layer.visible))
	assert_true(screens[0].roll_button.disabled)


func test_the_overlay_goes_when_the_player_comes_back() -> void:
	await _seat(2)
	var identity: Dictionary = table.guests[1].lobby.identity()
	table.guests[1].lobby.session.transport.leave()
	await _until(func() -> bool: return screens[0].presence_overlay.pause_layer.visible)
	await table.add_guest("Guest2", identity)
	assert_true(await _until(func() -> bool: return not screens[0].presence_overlay.pause_layer.visible and not screens[1].presence_overlay.pause_layer.visible))
	assert_false(screens[0].roll_button.disabled)


func test_the_host_can_remove_the_absent_player_from_the_overlay() -> void:
	await _seat(3)
	table.guests[2].lobby.session.transport.leave()
	await _until(func() -> bool: return screens[0].presence_overlay.pause_layer.visible)
	var remove: Button = screens[0].presence_overlay.remove_box.get_child(0)
	assert_eq(remove.text, "Remove Guest3 for good")
	remove.pressed.emit()
	assert_true(await _until(func() -> bool: return not screens[0].presence_overlay.pause_layer.visible))
	assert_false(screens[0].roll_button.disabled)


# --- the end of the game ---------------------------------------------------------------------------------------------

func _finish_everywhere(winner_index: int) -> void:
	var view: Dictionary = screens[0].current_view().duplicate(true)
	view["phase"] = "finished"
	view["winner"] = view["players"][winner_index]["player_id"]
	view["positions"][view["winner"]] = 100
	for i: int in screens.size():
		var copy: Dictionary = view.duplicate(true)
		copy["you"] = controllers[i].local_player_id()
		screens[i].timeline.push({"seq": 900, "reason": "resync", "events": [], "view": copy})


func test_at_game_over_the_host_chooses_play_again_or_the_lobby_and_guests_wait() -> void:
	await _seat(2)
	_finish_everywhere(1)
	for screen: ClimbGameScreen in screens:
		assert_true(screen.overlay.visible)
		assert_string_contains(screen.overlay_title.text, "Guest1")
	assert_true(screens[0].rematch_button.visible)
	assert_true(screens[0].lobby_button.visible)
	assert_false(screens[0].overlay_wait_label.visible)
	assert_false(screens[0].overlay_menu_button.visible, "no hot-seat menu button on a network game")
	for i: int in [1, 2]:
		assert_false(screens[i].rematch_button.visible)
		assert_false(screens[i].lobby_button.visible)
		assert_true(screens[i].overlay_wait_label.visible)
		assert_eq(screens[i].overlay_wait_label.text, "Waiting for the host...")


func test_play_again_from_the_host_screen_restarts_everyones_game() -> void:
	await _seat(2)
	_finish_everywhere(0)
	screens[0].rematch_button.pressed.emit()
	assert_true(await _until(func() -> bool: return not screens[1].overlay.visible and not screens[2].overlay.visible and not screens[0].overlay.visible))
	for screen: ClimbGameScreen in screens:
		assert_eq(screen.current_view()["rolls"], 0)
		assert_false(rules.is_finished(screen.current_view()))


func test_back_to_lobby_from_the_host_screen_makes_every_screen_say_the_game_ended() -> void:
	await _seat(2)
	_finish_everywhere(0)
	screens[0].lobby_button.pressed.emit()
	assert_true(await _until(func() -> bool: return ended[0] == 1 and ended[1] == 1 and ended[2] == 1))
	assert_eq(table.lobby.state["phase"], LobbyLogic.PHASE_OPEN)


func test_a_guest_who_loses_the_session_gets_the_disconnected_card_and_a_way_out() -> void:
	await _seat(2)
	var left: Array = [0]
	screens[1].leave_requested.connect(func() -> void: left[0] += 1)
	table.lobby.close()
	assert_true(await _until(func() -> bool: return screens[1].presence_overlay.lost_layer.visible))
	screens[1].presence_overlay.lost_button.pressed.emit()
	assert_eq(left[0], 1)
