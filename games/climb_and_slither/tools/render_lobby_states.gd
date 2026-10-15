extends SceneTree
## Developer tool, not part of the game: saves screenshots of every lobby state (start screen with a
## long relay address and a test result, the "Starting your game..." card, host and guest lobbies,
## the pause notice, a rejoin request and the waiting card, join errors, a closed session) in ONE
## process. Each lobby lives in its own off-screen viewport the size of the window. Needs a real
## renderer (not --headless); exits non-zero if a step did not happen:
##   godot --rendering-driver opengl3 --resolution 1280x720 -s games/climb_and_slither/tools/render_lobby_states.gd -- <out_dir>

const GAME: String = "climb_and_slither"
const LONG_ADDRESS: String = "wss://onlygaming-relay-with-a-very-long-name.some-subdomain.workers.dev"

var _out: String = "."
var _failed: bool = false
var _hub: LoopbackHub = LoopbackHub.new()
var _registry: GameRegistry = GameRegistry.new()
var _holders: Array[SubViewport] = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	AppSettings.path = "user://render_lobby_states_settings.cfg"
	DirAccess.remove_absolute(AppSettings.path)
	await _run()
	DirAccess.remove_absolute(AppSettings.path)
	quit(1 if _failed else 0)


func _frames(count: int = 4) -> void:
	for _i: int in count:
		await process_frame


func _until(condition: Callable, what: String, max_frames: int = 600) -> bool:
	for _i: int in max_frames:
		if condition.call():
			return true
		await process_frame
	push_error("never happened: %s" % what)
	_failed = true
	return false


func _tag() -> String:
	return "%dx%d" % [get_root().size.x, get_root().size.y]


func _config(connection_ui: bool = true) -> Dictionary:
	return {"transport": "loopback", "hub": _hub, "connection_ui": connection_ui, "port": 24680}


func _scene(player_name: String, config: Dictionary = {}, max_players: int = 4, game_id: String = GAME) -> LobbyScene:
	var holder: SubViewport = SubViewport.new()
	holder.size = get_root().size
	holder.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(holder)
	_holders.append(holder)
	var scene: LobbyScene = LobbyScene.new()
	scene.setup({
		"app_version": "1.0.0", "game_id": game_id, "game_registry": _registry,
		"min_players": 2, "max_players": max_players, "min_active_players": 2,
		"transport": config if not config.is_empty() else _config(), "player_name": player_name,
	})
	holder.add_child(scene)
	return scene


func _shot(scene: Node, name: String) -> void:
	await _frames(5)
	var holder: SubViewport = scene.get_parent() as SubViewport
	holder.get_texture().get_image().save_png("%s/%s-%s.png" % [_out, name, _tag()])


func _host_up(player_name: String, max_players: int = 4) -> LobbyScene:
	var host: LobbyScene = _scene(player_name, {}, max_players)
	await _frames()
	host.name_edit.text = player_name
	host.host_session()
	await _until(func() -> bool: return host.shared_address != "", "hosting went live")
	return host


func _join(player_name: String, address: String, max_players: int = 4) -> LobbyScene:
	var guest: LobbyScene = _scene(player_name, {}, max_players, "")
	await _frames()
	guest.name_edit.text = player_name
	guest.address_edit.text = address
	guest.join_session()
	return guest


func _run() -> void:
	await _frames()
	_registry.load_from()
	AppSettings.set_host_via("direct")

	# 1. the start screen: a long relay address must stay inside the card; a good and a bad test result
	var start: LobbyScene = _scene("Asha")
	await _frames()
	start.connection_panel.url_edit.text = LONG_ADDRESS
	start.connection_panel._say("The relay works. A test room (K4M9XQ) was opened and closed.", ConnectionPanel.ResultIcon.OK)
	await _shot(start, "state-01-start-long-address-ok")
	start.connection_panel._say("The relay is busy or cannot be reached right now. Try again later, or use a direct address.", ConnectionPanel.ResultIcon.ERROR)
	await _shot(start, "state-02-start-long-address-error")

	# 2. "Starting your game..." while a relay is slow (nothing listens on that port)
	var slow: LobbyScene = _scene("Asha", {"transport": "relay", "relay_url": "ws://127.0.0.1:1", "connection_ui": false})
	await _frames()
	slow.host_session()
	await _until(func() -> bool: return slow.connecting_view.visible, "the connecting card showed")
	await _shot(slow, "state-03-starting-your-game")
	slow.cancel()

	# 3. host and guest lobbies with one guest
	var host: LobbyScene = await _host_up("Asha")
	var guest: LobbyScene = await _join("Ben", host.shared_address)
	await _until(func() -> bool: return guest.lobby_view.visible and host.players_box.get_child_count() == 2, "the guest joined")
	await _shot(host, "state-04-host-lobby")
	await _shot(guest, "state-05-guest-lobby")
	guest.ready_button.button_pressed = true
	await _until(func() -> bool: return not host.start_button.disabled, "the host could start")

	# 4. the game starts; a guest drops: the host's lobby shows the pause notice
	host.start_button.pressed.emit()
	await _until(func() -> bool: return host.lobby_host().state["phase"] == LobbyLogic.PHASE_IN_GAME, "the lobby game started")
	guest.lobby_client().session.transport.leave()
	await _until(func() -> bool: return host.lobby_host().is_game_paused(), "the host noticed the drop")
	await _shot(host, "state-06-host-lobby-paused")

	# 5. the same player comes back by name without a saved identity: the host is asked, the guest waits
	var returning: LobbyScene = await _join("Ben", host.shared_address)
	await _until(func() -> bool: return not host.lobby_host().pending_rejoins().is_empty(), "the rejoin request arrived")
	await _shot(host, "state-07-host-rejoin-request")
	await _shot(returning, "state-08-guest-waiting-to-be-let-in")

	# 6. join errors on a fresh table: unknown address, a full room, a protocol mismatch
	var lost: LobbyScene = await _join("Cleo", "no-such-host:1")
	await _until(func() -> bool: return lost.start_view.visible and not lost.status_label.text.is_empty(), "the unknown-address error")
	await _shot(lost, "state-09-join-error-unknown")
	var small: LobbyScene = await _host_up("Dev")
	for seated: String in ["Eli", "Fay", "Gus"]:  # the game seats four: host and three guests fill it
		var other: LobbyScene = await _join(seated, small.shared_address)
		await _until(func() -> bool: return other.lobby_view.visible, "%s joined" % seated)
	var full: LobbyScene = await _join("Hal", small.shared_address)
	await _until(func() -> bool: return full.start_view.visible and not full.status_label.text.is_empty(), "the room-full error")
	await _shot(full, "state-10-join-error-room-full")
	full._on_join_failed(ErrorCodes.PROTOCOL_MISMATCH, "This host uses protocol 3 but you use protocol 2. Update the game so everyone has the same version.", {"game_id": GAME, "app_version": "1.0.0"})
	await _shot(full, "state-11-join-error-protocol")

	# 7. the host closes the session politely (guest lands on the start screen), and a lost connection
	var closer: LobbyScene = await _host_up("Gus")
	var watcher: LobbyScene = await _join("Hal", closer.shared_address)
	await _until(func() -> bool: return watcher.lobby_view.visible, "the watcher joined")
	closer.leave()
	await _until(func() -> bool: return watcher.start_view.visible, "the guest saw the session close")
	await _shot(watcher, "state-12-guest-host-closed")
	var dropper: LobbyScene = await _host_up("Ida")
	var victim: LobbyScene = await _join("Jon", dropper.shared_address)
	await _until(func() -> bool: return victim.lobby_view.visible, "the victim joined")
	dropper.lobby_host().close_now()
	await _until(func() -> bool: return victim.start_view.visible, "the guest saw the connection drop")
	await _shot(victim, "state-13-guest-host-lost-with-rejoin")
