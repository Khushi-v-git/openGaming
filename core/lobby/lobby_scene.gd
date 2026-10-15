class_name LobbyScene
extends Control
## Minimal lobby screen: host or join, see players, ready up, start.
## It displays state and emits intents; every rule is decided by the host's
## LobbyHost (rules 1 and 12). It only knows the Transport interface: the concrete
## transport comes from TransportFactory according to options.transport.
##
## Three views: start (host / join / rejoin), connecting (with Cancel; also shown while
## a host session is being set up, which a relay may take a moment to do) and lobby.
##
## Usage: var scene := LobbyScene.new(); scene.setup({...}); add_child(scene)
## options:
##   app_version                 required
##   game_id                     the game to host (hosting only; joiners play the host's game)
##   min_players, max_players,
##   min_active_players          for hosting; default from the game's manifest if a registry is given
##   game_registry               optional GameRegistry: used for display names, player limits
##                               and to tell a joiner clearly when this app lacks the host's game
##   game_title                  optional title when there is no registry
##   join_game_id                optional: insist on this game when joining (normally unset)
##   transport                   config Dictionary, default TransportFactory.default_config()
##   player_name                 optional prefill
##   session_options             optional Dictionary passed to HostSession/ClientSession
##                               (timeouts, limits); tests use it to stretch timeouts

signal game_started(state: Dictionary)

var options: Dictionary = {}

# Widgets are public so tests can drive them like a user would.
var title_label: Label
var name_edit: LineEdit
var port_spin: SpinBox
var port_label: Label
var connection_panel: ConnectionPanel  # only when the transport config asks for it
var address_edit: LineEdit
var host_button: Button
var join_button: Button
var rejoin_button: Button
var status_label: Label
var start_view: Control
var connecting_view: Control
var connecting_label: Label
var cancel_button: Button
var lobby_view: Control
var address_label: Label
var copy_button: Button
var players_box: VBoxContainer
var players_scroll: ScrollContainer  # the list scrolls when a big game does not fit the window
var claims_box: VBoxContainer  # host only: returning players waiting to be let in
var notice_label: Label  # "Waiting for X to come back."
var continue_button: Button  # host only, while paused: continue without waiting
var wait_button: Button  # host only, after continuing: wait for the absent player again
var ready_button: CheckButton
var start_button: Button
var leave_button: Button
var lobby_status_label: Label
var panel: PanelContainer

## The address or room code to share (host only), as reported by the transport.
var shared_address: String = ""
## What the transport calls what it shows the host to share ("address", "room code").
var share_label: String = "address"

var _host: LobbyHost = null
var _client: LobbyClient = null
var _transport_config: Dictionary = {}
var _state: Dictionary = {}
var _joining_address: String = ""
var _joining_name: String = ""
## Set when the connection to a host dropped: {address, name, identity}. Enables Rejoin.
var _resume: Dictionary = {}


func setup(new_options: Dictionary) -> void:
	options = new_options
	_transport_config = options.get("transport", TransportFactory.default_config())


func _ready() -> void:
	theme = AppTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	resized.connect(_update_layout)
	_update_layout()
	_show_start_view("")


func _process(_delta: float) -> void:
	if _host != null:
		_host.poll()
	elif _client != null:
		_client.poll()


# --- building --------------------------------------------------------------------

func _build_ui() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Tokens.DEEP_TEAL
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = PanelContainer.new()
	center.add_child(panel)
	var root: VBoxContainer = VBoxContainer.new()
	panel.add_child(root)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_TITLE)
	root.add_child(title_label)

	start_view = _build_start_view()
	root.add_child(start_view)
	connecting_view = _build_connecting_view()
	root.add_child(connecting_view)
	lobby_view = _build_lobby_view()
	root.add_child(lobby_view)


## The panel grows with the window (a little over a third of the width), but never
## wider than the window itself, so it fits from 1280x720 up to 1920x1080 and on resize.
func _update_layout() -> void:
	if panel == null:
		return
	var wanted: float = clampf(size.x * 0.4, 520.0, 760.0)
	panel.custom_minimum_size.x = minf(wanted, maxf(0.0, size.x - 2.0 * Tokens.SPACE_L))
	_fit_players_list()


## The player list takes the room it needs, up to about 40% of the window height, and
## scrolls beyond that, so games with many players still fit from 1280x720 up.
func _fit_players_list() -> void:
	if players_scroll == null:
		return
	var needed: float = players_box.get_combined_minimum_size().y
	players_scroll.custom_minimum_size.y = minf(needed, maxf(120.0, size.y * 0.4))


func _build_start_view() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Your name"
	name_edit.max_length = Handshake.MAX_NAME_LENGTH
	name_edit.text = str(options.get("player_name", ""))
	box.add_child(name_edit)

	box.add_child(_label("Host a game"))
	if _transport_config.get("connection_ui", false):
		connection_panel = ConnectionPanel.new()
		connection_panel.initial_url = str(_transport_config.get("relay_url", ""))
		connection_panel.host_via_changed.connect(func(_via: String) -> void: _update_port_visibility())
		box.add_child(connection_panel)
	var host_row: HBoxContainer = HBoxContainer.new()
	if _transport_config.has("port"):  # only transports that listen on a port show this
		port_label = _label("Port")
		host_row.add_child(port_label)
		port_spin = SpinBox.new()
		port_spin.min_value = 1
		port_spin.max_value = 65535
		port_spin.value = int(_transport_config["port"])
		host_row.add_child(port_spin)
	host_button = Button.new()
	host_button.text = "Host"
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_button.pressed.connect(host_session)
	host_row.add_child(host_button)
	box.add_child(host_row)

	box.add_child(_label("Join a game"))
	var join_row: HBoxContainer = HBoxContainer.new()
	address_edit = LineEdit.new()
	address_edit.placeholder_text = "Address or room code from your host"
	address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(address_edit)
	join_button = Button.new()
	join_button.text = "Join"
	join_button.pressed.connect(join_session)
	join_row.add_child(join_button)
	box.add_child(join_row)

	_update_port_visibility()
	rejoin_button = Button.new()
	rejoin_button.text = "Rejoin the game you were in"
	rejoin_button.pressed.connect(rejoin_session)
	box.add_child(rejoin_button)

	status_label = _label("")
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)
	return box


## The port only matters when hosting by direct address.
func _update_port_visibility() -> void:
	if port_spin == null:
		return
	var show_port: bool = connection_panel == null or not connection_panel.uses_relay()
	port_spin.visible = show_port
	port_label.visible = show_port


func _build_connecting_view() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	connecting_label = _label("Connecting...")
	connecting_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(connecting_label)
	cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(cancel)
	box.add_child(cancel_button)
	return box


func _build_lobby_view() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	var address_row: HBoxContainer = HBoxContainer.new()
	address_label = _label("")
	address_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	address_row.add_child(address_label)
	copy_button = Button.new()
	copy_button.text = "Copy"
	copy_button.pressed.connect(func() -> void: DisplayServer.clipboard_set(shared_address))
	address_row.add_child(copy_button)
	box.add_child(address_row)

	players_box = VBoxContainer.new()
	players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_scroll = ScrollContainer.new()
	players_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	players_scroll.add_child(players_box)
	box.add_child(players_scroll)

	claims_box = VBoxContainer.new()
	box.add_child(claims_box)

	notice_label = _label("")
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(notice_label)
	continue_button = Button.new()
	continue_button.text = "Continue without waiting"
	continue_button.pressed.connect(func() -> void: _act({"type": "set_paused", "paused": false}))
	box.add_child(continue_button)
	wait_button = Button.new()
	wait_button.text = "Wait for them"
	wait_button.pressed.connect(func() -> void: _act({"type": "set_paused", "paused": true}))
	box.add_child(wait_button)

	ready_button = CheckButton.new()
	ready_button.text = "I'm ready"
	ready_button.toggled.connect(func(pressed: bool) -> void: _act({"type": "set_ready", "ready": pressed}))
	box.add_child(ready_button)

	start_button = Button.new()
	start_button.text = "Start game"
	start_button.pressed.connect(func() -> void: _act({"type": "start"}))
	box.add_child(start_button)

	lobby_status_label = _label("")
	lobby_status_label.visible = false  # only takes room while it has something to say
	lobby_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(lobby_status_label)

	leave_button = Button.new()
	leave_button.text = "Leave"
	leave_button.pressed.connect(leave)
	box.add_child(leave_button)
	return box


func _set_lobby_status(text: String) -> void:
	lobby_status_label.text = text
	lobby_status_label.visible = not text.is_empty()


func _label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	return label


# --- user intents ----------------------------------------------------------------

func host_session() -> void:
	var cleaned: Dictionary = Handshake.clean_name(name_edit.text)
	if not CoreResult.is_ok(cleaned):
		status_label.text = str(cleaned["error"]["message"])
		return
	var game_id: String = str(options.get("game_id", ""))
	if game_id.is_empty():
		status_label.text = "No game selected to host."
		return
	var limits: Dictionary = _player_limits(game_id)
	var config: Dictionary = _transport_config.duplicate()
	if port_spin != null:
		config["port"] = int(port_spin.value)
	if connection_panel != null and not connection_panel.apply_to(config):
		status_label.text = connection_panel.result_label.text
		return
	_host = LobbyHost.new(TransportFactory.create(config), str(options["app_version"]), game_id, cleaned["name"], limits["min"], limits["max"], options.get("session_options", {}), limits["min_active"])
	_host.hosting.connect(_on_hosting)
	_host.host_failed.connect(_on_host_failed)
	_host.state_changed.connect(_on_state_changed)
	_host.game_started.connect(_on_game_started)
	_host.closed.connect(_on_host_closed)
	_host.rejoin_requested.connect(func(_player_id: String, _player_name: String) -> void: _render())
	_host.rejoin_request_cancelled.connect(func(_player_id: String) -> void: _render())
	var started: Dictionary = _host.start(config)
	if not CoreResult.is_ok(started):
		var message: String = str(started["error"]["message"])
		_drop_host()
		_show_start_view("Could not host: %s" % message)
		return
	_show_connecting("Starting your game...")


func join_session() -> void:
	var cleaned: Dictionary = Handshake.clean_name(name_edit.text)
	if not CoreResult.is_ok(cleaned):
		status_label.text = str(cleaned["error"]["message"])
		return
	if address_edit.text.strip_edges().is_empty():
		status_label.text = "Paste the address or room code your host gave you."
		return
	_resume = {}
	_begin_join(address_edit.text, cleaned["name"], {})


## Comes back to a game after the connection dropped, using the identity the host gave us.
func rejoin_session() -> void:
	if _resume.is_empty():
		return
	var resume: Dictionary = _resume
	_begin_join(resume["address"], resume["name"], resume["identity"])


## Stops connecting or starting, and returns to the start screen.
func cancel() -> void:
	if _host != null:
		_host.close_now()  # hosting is not live yet, nobody is in it; _on_host_closed returns us
	elif _client != null:
		_client.leave_now()  # _on_left returns us to the start view


func leave() -> void:
	if _host != null:
		_set_lobby_status("Closing...")
		_host.close()  # _on_host_closed returns us to the start view
	elif _client != null:
		_set_lobby_status("Leaving...")
		_client.leave()  # _on_left returns us to the start view


func _begin_join(address: String, player_name: String, identity: Dictionary) -> void:
	var config: Dictionary = _transport_config.duplicate()
	if connection_panel != null:
		connection_panel.apply_for_joining(config)
	_client = LobbyClient.new(TransportFactory.create(config), str(options["app_version"]), str(options.get("join_game_id", "")), options.get("session_options", {}))
	var registry: GameRegistry = options.get("game_registry", null)
	if registry != null:
		_client.game_validator = registry.validator()
	_client.waiting.connect(func(message: String) -> void: connecting_label.text = message)
	_client.joined.connect(func(_player_id: String) -> void: _on_joined())
	_client.join_failed.connect(_on_join_failed)
	_client.state_changed.connect(_on_state_changed)
	_client.action_failed.connect(func(_code: String, message: String, _action: String) -> void: _set_lobby_status(message))
	_client.game_started.connect(_on_game_started)
	_client.left.connect(_on_left)
	_joining_address = address
	_joining_name = player_name
	_show_connecting("Connecting to %s..." % address.strip_edges())
	_client.join(address, player_name, config, identity)


func _act(action: Dictionary) -> void:
	if _host != null:
		var result: Dictionary = _host.act(action)
		_set_lobby_status("" if CoreResult.is_ok(result) else str(result["error"]["message"]))
	elif _client != null:
		_client.act(action)


# --- reacting to the session -----------------------------------------------------

func _on_hosting(info: Dictionary) -> void:
	shared_address = str(info["address"])
	share_label = str(info.get("share_label", "address"))
	_state = _host.state
	_show_lobby_view()


func _on_host_failed(reason: String) -> void:
	_drop_host()
	_show_start_view("Could not host: %s" % reason)


func _on_state_changed(state: Dictionary) -> void:
	_state = state
	_render()


func _on_game_started(state: Dictionary) -> void:
	_set_lobby_status("Game starting...")
	game_started.emit(state)


func _on_joined() -> void:
	_resume = {}
	rejoin_button.visible = false
	_show_lobby_view()


func _on_join_failed(code: String, message: String, _host_info: Dictionary) -> void:
	if code != ErrorCodes.CONNECT_FAILED:
		_resume = {}  # the host answered and said no; retrying with the same identity won't help
	_forget_client()
	_show_start_view("Could not join: %s" % message)


func _on_left(code: String, message: String) -> void:
	_resume = {}
	if code == ErrorCodes.HOST_LOST and _client != null:
		_resume = {"address": _joining_address, "name": _joining_name, "identity": _client.identity()}
	_forget_client()
	_show_start_view("" if code == ErrorCodes.LEFT else "Left the session: %s" % message)


func _on_host_closed() -> void:
	_host = null
	_show_start_view("")


## Releases a host that never went live (or failed) without waiting for a goodbye.
func _drop_host() -> void:
	if _host != null:
		var host: LobbyHost = _host
		_host = null
		host.close_now()


func _forget_client() -> void:
	_client = null
	_state = {}


func _show_start_view(message: String) -> void:
	start_view.visible = true
	connecting_view.visible = false
	lobby_view.visible = false
	rejoin_button.visible = not _resume.is_empty()
	status_label.text = message
	_update_title()


func _show_connecting(message: String) -> void:
	start_view.visible = false
	connecting_view.visible = true
	lobby_view.visible = false
	connecting_label.text = message


func _show_lobby_view() -> void:
	start_view.visible = false
	connecting_view.visible = false
	lobby_view.visible = true
	_set_lobby_status("")
	if _client != null:
		_state = _client.state
	_update_title()
	_render()


## Draws `_state`. Nothing here decides anything; buttons just reflect what is allowed.
func _render() -> void:
	if not lobby_view.visible or _state.is_empty():
		return
	var is_host: bool = _host != null
	var my_id: String = _host.local_player_id if is_host else (_client.player_id if _client != null else "")
	address_label.visible = is_host
	copy_button.visible = is_host
	address_label.text = "Share this %s: %s" % [share_label, shared_address]
	ready_button.visible = not is_host
	start_button.visible = is_host and _state["phase"] == LobbyLogic.PHASE_OPEN
	start_button.disabled = not LobbyLogic.ready_to_start(_state)
	for child: Node in players_box.get_children():
		players_box.remove_child(child)
		child.queue_free()
	for slot: Dictionary in _state["slots"]:
		players_box.add_child(_player_row(slot, my_id, is_host))
		if slot["player_id"] == my_id:
			ready_button.set_pressed_no_signal(bool(slot["ready"]))  # the toggle mirrors the host's state
	_render_claims(is_host)
	_render_pause(is_host)
	_fit_players_list()
	var started: bool = _state["phase"] == LobbyLogic.PHASE_IN_GAME
	ready_button.disabled = started
	if started:
		start_button.disabled = true
	_update_title()


## Returning players asking the host to let them back in.
func _render_claims(is_host: bool) -> void:
	for child: Node in claims_box.get_children():
		claims_box.remove_child(child)
		child.queue_free()
	claims_box.visible = is_host
	if not is_host:
		return
	for request: Dictionary in _host.pending_rejoins():
		var row: HBoxContainer = HBoxContainer.new()
		var label: Label = _label("%s wants to rejoin" % request["name"])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var player_id: String = request["player_id"]
		var allow: Button = Button.new()
		allow.text = "Let in"
		allow.pressed.connect(func() -> void: _host.answer_rejoin(player_id, true))
		row.add_child(allow)
		var decline: Button = Button.new()
		decline.text = "Decline"
		decline.pressed.connect(func() -> void: _host.answer_rejoin(player_id, false))
		row.add_child(decline)
		claims_box.add_child(row)


## The game waits for absent players until the host says otherwise.
func _render_pause(is_host: bool) -> void:
	var away: Array[Dictionary] = LobbyLogic.away_players(_state)
	var names: PackedStringArray = PackedStringArray()
	for slot: Dictionary in away:
		names.append(slot["name"])
	var paused: bool = LobbyLogic.is_paused(_state)
	notice_label.visible = not away.is_empty()
	if paused:
		notice_label.text = "Game paused: waiting for %s to come back." % ", ".join(names)
	else:
		notice_label.text = "%s is away; the game is continuing without them." % ", ".join(names)
	var can_go_on: bool = LobbyLogic.can_continue(_state)
	if paused and not can_go_on:
		notice_label.visible = true
		notice_label.text = "Not enough players to go on: the game needs %d present. Waiting for %s." % [LobbyLogic.min_active(_state), ", ".join(names) if not names.is_empty() else "more players"]
	continue_button.visible = is_host and paused and can_go_on
	wait_button.visible = is_host and not paused and not away.is_empty()


func _update_title() -> void:
	var game_id: String = str(_state.get("game_id", options.get("game_id", "")))
	var registry: GameRegistry = options.get("game_registry", null)
	if registry != null and registry.has(game_id):
		title_label.text = registry.display_name(game_id)
	else:
		title_label.text = str(options.get("game_title", "Play with friends"))


func _player_limits(game_id: String) -> Dictionary:
	var registry: GameRegistry = options.get("game_registry", null)
	if registry != null and registry.has(game_id):
		var manifest: Dictionary = registry.get_manifest(game_id)
		return {"min": int(manifest["min_players"]), "max": int(manifest["max_players"]), "min_active": int(manifest["min_active_players"])}
	return {"min": int(options.get("min_players", 2)), "max": int(options.get("max_players", 4)), "min_active": int(options.get("min_active_players", 0))}


func _player_row(slot: Dictionary, my_id: String, is_host: bool) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = _label(_slot_text(slot, my_id))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var is_host_slot: bool = slot["player_id"] == _state["host_player_id"]
	var status: String = "Ready" if slot["ready"] else "Not ready"
	if not slot["connected"]:
		status = "Disconnected"
	row.add_child(_label(status))
	var removable: bool = _state["phase"] == LobbyLogic.PHASE_OPEN or not slot["connected"]
	if is_host and not is_host_slot and not slot["left"] and removable:
		var kick: Button = Button.new()
		kick.text = "Remove"
		var target: String = slot["player_id"]
		kick.pressed.connect(func() -> void: _act({"type": "kick", "player_id": target}))
		row.add_child(kick)
	return row


func _slot_text(slot: Dictionary, my_id: String) -> String:
	var text: String = slot["name"]
	if slot["player_id"] == _state["host_player_id"]:
		text += " (host)"
	if slot["player_id"] == my_id:
		text += " (you)"
	return text
