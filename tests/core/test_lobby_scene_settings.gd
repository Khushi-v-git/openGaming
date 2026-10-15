extends GutTest
## The lobby's house rules (the host's panel, the guests' summary) and the address the host shares.
## Two LobbyScenes in one process like two players, with a registry that knows Climb and Slither.

const TEST_SETTINGS: String = "user://test_lobby_settings.cfg"
const GAME: String = "climb_and_slither"

var hub: LoopbackHub
var registry: GameRegistry
var _saved_path: String
var relay: ScriptedRelay


func before_each() -> void:
	hub = LoopbackHub.new()
	MessageLog.enabled = false
	registry = GameRegistry.new()
	registry.load_from("res://games")
	_saved_path = AppSettings.path
	AppSettings.path = TEST_SETTINGS
	DirAccess.remove_absolute(TEST_SETTINGS)


func after_each() -> void:
	await get_tree().process_frame  # queued frees finish before the orphan check
	if relay != null:
		relay.stop()
		relay = null
	DirAccess.remove_absolute(TEST_SETTINGS)
	AppSettings.path = _saved_path


func _scene(player_name: String, transport: Dictionary, with_registry: bool = true) -> LobbyScene:
	var scene: LobbyScene = LobbyScene.new()
	var options: Dictionary = {
		"game_id": GAME, "game_title": "Climb", "app_version": "1.0.0",
		"transport": transport, "player_name": player_name,
	}
	if with_registry:
		options["game_registry"] = registry
	else:
		options.merge({"min_players": 2, "max_players": 3, "min_active_players": 1})
	scene.setup(options)
	add_child_autofree(scene)
	return scene


func _loopback() -> Dictionary:
	return {"transport": "loopback", "hub": hub}


func _until(condition: Callable, max_frames: int = 600) -> bool:
	for _i: int in max_frames:
		if relay != null:
			relay.poll()
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _host_live(scene: LobbyScene) -> void:
	scene.host_button.pressed.emit()
	assert_true(await _until(func() -> bool: return scene.lobby_view.visible and scene.shared_address != ""), "hosting never went live")


func _join(guest: LobbyScene, host: LobbyScene) -> void:
	guest.address_edit.text = host.shared_address
	guest.join_button.pressed.emit()
	assert_true(await _until(func() -> bool: return host.players_box.get_child_count() == 2 and guest.players_box.get_child_count() == 2))


func _checks(scene: LobbyScene) -> Array:
	return scene.settings_panel.get_children()


# --- house rules: the host's panel and the guests' summary ----------------------------------------------------

func test_the_host_gets_the_games_own_settings_panel_in_the_lobby() -> void:
	var host: LobbyScene = _scene("Hosty", _loopback())
	await _host_live(host)
	assert_not_null(host.settings_panel)
	assert_true(host.settings_panel is ClimbSettingsPanel)
	assert_true(host.settings_box.visible)
	assert_false(host.house_rules_box.visible, "hosts see the interactive panel, not the summary")


func test_the_settings_are_sent_once_hosting_is_live_so_guests_always_see_them() -> void:
	var host: LobbyScene = _scene("Hosty", _loopback())
	await _host_live(host)
	assert_eq(host.lobby_host().state["game_settings"], ClimbSettings.defaults())
	var guest: LobbyScene = _scene("Asha", _loopback())
	await _join(guest, host)
	assert_false(guest.settings_box.visible)
	assert_true(guest.house_rules_box.visible)
	assert_eq(guest.house_rules_box.get_child_count(), 1, "one line with a leaf bullet")
	assert_eq(guest.house_rules_label.text, "House rules: One die")


func test_a_change_in_the_hosts_panel_reaches_the_guests_summary() -> void:
	var host: LobbyScene = _scene("Hosty", _loopback())
	await _host_live(host)
	var guest: LobbyScene = _scene("Asha", _loopback())
	await _join(guest, host)
	(_checks(host)[2] as CheckButton).button_pressed = true  # Two dice
	(_checks(host)[1] as CheckButton).button_pressed = true  # Roll again after a 6
	assert_true(await _until(func() -> bool: return guest.house_rules_label.text == "House rules: Two dice, Roll again after a 6"))
	assert_eq(host.lobby_host().state["game_settings"]["dice_count"], 2)
	(_checks(host)[3] as CheckButton).button_pressed = true  # Need a 1 to start
	assert_true(await _until(func() -> bool: return guest.house_rules_label.text.ends_with("Need a 1 to start")))


func test_the_lobby_checks_house_rules_with_the_game_before_storing_them() -> void:
	var host: LobbyScene = _scene("Hosty", _loopback())
	await _host_live(host)
	var refused: Dictionary = host.lobby_host().act({"type": "set_game_settings", "settings": {"exact_finish": true, "dice_count": 2}})
	assert_eq(CoreResult.error_code(refused), ClimbErrors.INVALID_SETTINGS)
	assert_eq(host.lobby_host().state["game_settings"], ClimbSettings.defaults(), "nothing was stored")


func test_the_panel_disappears_once_the_game_has_started() -> void:
	var host: LobbyScene = _scene("Hosty", _loopback())
	await _host_live(host)
	var guest: LobbyScene = _scene("Asha", _loopback())
	await _join(guest, host)
	guest.ready_button.button_pressed = true
	await _until(func() -> bool: return host.start_button.visible and not host.start_button.disabled)
	host.start_button.pressed.emit()
	assert_true(await _until(func() -> bool: return not host.settings_box.visible))


func test_without_a_registry_there_is_no_panel_and_no_summary() -> void:
	var host: LobbyScene = _scene("Hosty", _loopback(), false)
	await _host_live(host)
	assert_null(host.settings_panel)
	assert_false(host.settings_box.visible)
	var guest: LobbyScene = _scene("Asha", _loopback(), false)
	await _join(guest, host)
	assert_false(guest.house_rules_box.visible)


func test_describe_settings_words_the_climb_rules() -> void:
	var rules: ClimbAndSlitherRules = ClimbAndSlitherRules.new()
	assert_eq(rules.describe_settings({}), ["One die"])
	assert_eq(rules.describe_settings({"dice_count": 2, "extra_turn_on_six": true}), ["Two dice", "Roll again after a 6"])
	assert_eq(rules.describe_settings({"exact_finish": true, "need_one_to_start": true}), ["One die", "Exact finish", "Need a 1 to start"])
	assert_eq(rules.describe_settings({"nonsense": 1}), ["One die"], "unusable settings fall back to the defaults")
	assert_eq(CountGameRules.new().describe_settings({"b": 2, "a": 1}), ["a: 1", "b: 2"], "the default is key: value")


# --- the address the host shares ---------------------------------------------------------------------------------

func test_the_shared_address_sits_in_an_editable_looking_field_with_copy() -> void:
	var host: LobbyScene = _scene("Hosty", _loopback())
	await _host_live(host)
	assert_true(host.public_address_edit.visible)
	assert_true(host.copy_button.visible)
	assert_eq(host.public_address_edit.text, host.shared_address)
	assert_string_contains(host.address_label.text, host.shared_address)
	assert_false(host.public_address_edit.editable, "only a direct address can be replaced")
	var guest: LobbyScene = _scene("Asha", _loopback())
	await _join(guest, host)
	assert_false(guest.public_address_edit.visible, "guests never see it")


func test_a_direct_address_can_be_replaced_by_a_public_one_and_it_is_remembered() -> void:
	var port: int = 24700 + randi() % 800
	var direct: Dictionary = {"transport": "direct_ws", "port": port, "bind_address": "127.0.0.1"}
	var host: LobbyScene = _scene("Hosty", direct)
	host.port_spin.value = port
	await _host_live(host)
	var real: String = host.shared_address
	assert_true(host.public_address_edit.editable)
	assert_eq(host.public_address_edit.text, real)
	host.public_address_edit.text = "play.example.org:24680"
	host.public_address_edit.text_submitted.emit(host.public_address_edit.text)
	assert_eq(AppSettings.public_address(), "play.example.org:24680")
	assert_eq(host.address_label.text, "Share this address: play.example.org:24680")
	assert_eq(host.shared_address, real, "the real listen address is untouched")
	host.lobby_host().close_now()
	await _until(func() -> bool: return host.start_view.visible)
	# next time it is still the thing to share
	var again: LobbyScene = _scene("Hosty", direct)
	again.port_spin.value = port + 1
	await _host_live(again)
	assert_eq(again.public_address_edit.text, "play.example.org:24680")
	# typing the real address back clears the override
	again.public_address_edit.text = again.shared_address
	again.public_address_edit.text_submitted.emit(again.public_address_edit.text)
	assert_eq(AppSettings.public_address(), "")
	again.lobby_host().close_now()


func test_a_room_code_is_shown_read_only_and_never_overridden() -> void:
	relay = ScriptedRelay.new()
	relay.start()
	AppSettings.set_public_address("should.not.apply:1")
	var config: Dictionary = {"transport": "relay", "relay_url": relay.url()}
	var host: LobbyScene = _scene("Hosty", config)
	await _host_live(host)
	assert_eq(host.shared_address, ScriptedRelay.CODE)
	assert_false(host.public_address_edit.editable)
	assert_eq(host.public_address_edit.text, ScriptedRelay.CODE)
	assert_eq(host.address_label.text, "Share this room code: %s" % ScriptedRelay.CODE)
	host.lobby_host().close_now()


func test_public_address_setting_round_trips() -> void:
	assert_eq(AppSettings.public_address(), "")
	assert_true(AppSettings.set_public_address("  me.example.net:1  "))
	assert_eq(AppSettings.public_address(), "me.example.net:1")
	AppSettings.set_public_address("")
	assert_eq(AppSettings.public_address(), "")
