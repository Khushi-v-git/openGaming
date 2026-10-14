class_name LobbyScene
extends Control
## Minimal lobby screen: host or join, see players, ready up, start.
## It displays state and emits intents; every rule is decided by the host's
## LobbyHost (rules 1 and 12). It only knows the Transport interface: the concrete
## transport comes from TransportFactory according to options.transport.
##
## Usage: var scene := LobbyScene.new(); scene.setup({...}); add_child(scene)
## options: game_id, game_title, app_version, min_players, max_players,
##          transport (config Dictionary, default TransportFactory.default_config()),
##          player_name (optional prefill)

signal game_started(state: Dictionary)
signal closed()  # the player left the lobby screen entirely (back to the menu)

var options: Dictionary = {}

# Widgets are public so tests can drive them like a user would.
var name_edit: LineEdit
var port_spin: SpinBox
var address_edit: LineEdit
var host_button: Button
var join_button: Button
var status_label: Label
var start_view: Control
var lobby_view: Control
var address_label: Label
var copy_button: Button
var players_box: VBoxContainer
var ready_button: CheckButton
var start_button: Button
var leave_button: Button
var lobby_status_label: Label

## The address or room code to share (host only), as reported by the transport.
var shared_address: String = ""

var _host: LobbyHost = null
var _client: LobbyClient = null
var _transport_config: Dictionary = {}
var _state: Dictionary = {}


func setup(new_options: Dictionary) -> void:
	options = new_options
	_transport_config = options.get("transport", TransportFactory.default_config())


func _ready() -> void:
	theme = AppTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
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
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var root: VBoxContainer = VBoxContainer.new()
	panel.add_child(root)

	var title: Label = Label.new()
	title.text = str(options.get("game_title", "Play with friends"))
	title.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_TITLE)
	root.add_child(title)

	start_view = _build_start_view()
	root.add_child(start_view)
	lobby_view = _build_lobby_view()
	root.add_child(lobby_view)


func _build_start_view() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Your name"
	name_edit.max_length = Handshake.MAX_NAME_LENGTH
	name_edit.text = str(options.get("player_name", ""))
	box.add_child(name_edit)

	box.add_child(_label("Host a game"))
	var host_row: HBoxContainer = HBoxContainer.new()
	if _transport_config.has("port"):  # only transports that listen on a port show this
		host_row.add_child(_label("Port"))
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
	address_edit.placeholder_text = "Address from your host"
	address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(address_edit)
	join_button = Button.new()
	join_button.text = "Join"
	join_button.pressed.connect(join_session)
	join_row.add_child(join_button)
	box.add_child(join_row)

	status_label = _label("")
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)
	return box


func _build_lobby_view() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	var address_row: HBoxContainer = HBoxContainer.new()
	address_label = _label("")
	address_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_row.add_child(address_label)
	copy_button = Button.new()
	copy_button.text = "Copy"
	copy_button.pressed.connect(func() -> void: DisplayServer.clipboard_set(shared_address))
	address_row.add_child(copy_button)
	box.add_child(address_row)

	players_box = VBoxContainer.new()
	box.add_child(players_box)

	ready_button = CheckButton.new()
	ready_button.text = "I'm ready"
	ready_button.toggled.connect(func(pressed: bool) -> void: _act({"type": "set_ready", "ready": pressed}))
	box.add_child(ready_button)

	start_button = Button.new()
	start_button.text = "Start game"
	start_button.pressed.connect(func() -> void: _act({"type": "start"}))
	box.add_child(start_button)

	lobby_status_label = _label("")
	lobby_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(lobby_status_label)

	leave_button = Button.new()
	leave_button.text = "Leave"
	leave_button.pressed.connect(leave)
	box.add_child(leave_button)
	return box


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
	var config: Dictionary = _transport_config.duplicate()
	if port_spin != null:
		config["port"] = int(port_spin.value)
	var transport: Transport = TransportFactory.create(config)
	_host = LobbyHost.new(transport, str(options["app_version"]), str(options["game_id"]), cleaned["name"], int(options["min_players"]), int(options["max_players"]))
	var info: Dictionary = _host.start(config)
	if not CoreResult.is_ok(info):
		status_label.text = "Could not host: %s" % str(info["error"]["message"])
		_host = null
		return
	_host.state_changed.connect(_on_state_changed)
	_host.game_started.connect(_on_game_started)
	_host.closed.connect(_on_host_closed)
	shared_address = str(info["address"])
	_state = _host.state
	_show_lobby_view()


func join_session() -> void:
	var cleaned: Dictionary = Handshake.clean_name(name_edit.text)
	if not CoreResult.is_ok(cleaned):
		status_label.text = str(cleaned["error"]["message"])
		return
	if address_edit.text.strip_edges().is_empty():
		status_label.text = "Paste the address your host gave you."
		return
	var config: Dictionary = _transport_config.duplicate()
	_client = LobbyClient.new(TransportFactory.create(config), str(options["app_version"]), str(options["game_id"]))
	_client.joined.connect(func(_player_id: String) -> void: _show_lobby_view())
	_client.join_failed.connect(_on_join_failed)
	_client.state_changed.connect(_on_state_changed)
	_client.action_failed.connect(func(_code: String, message: String, _action: String) -> void: lobby_status_label.text = message)
	_client.game_started.connect(_on_game_started)
	_client.left.connect(_on_left)
	join_button.disabled = true
	host_button.disabled = true
	status_label.text = "Connecting..."
	_client.join(address_edit.text, cleaned["name"], config)


func leave() -> void:
	if _host != null:
		lobby_status_label.text = "Closing..."
		_host.close()  # _on_host_closed returns us to the start view
	elif _client != null:
		_client.leave()
		_forget_client()
		_show_start_view("")


func _act(action: Dictionary) -> void:
	if _host != null:
		var result: Dictionary = _host.act(action)
		lobby_status_label.text = "" if CoreResult.is_ok(result) else str(result["error"]["message"])
	elif _client != null:
		_client.act(action)


# --- reacting to the session -----------------------------------------------------

func _on_state_changed(state: Dictionary) -> void:
	_state = state
	_render()


func _on_game_started(state: Dictionary) -> void:
	lobby_status_label.text = "Game starting..."
	game_started.emit(state)


func _on_join_failed(_code: String, message: String) -> void:
	_forget_client()
	_show_start_view("Could not join: %s" % message)


func _on_left(_code: String, message: String) -> void:
	_forget_client()
	_show_start_view("Left the session: %s" % message)


func _on_host_closed() -> void:
	_host = null
	_show_start_view("")


func _forget_client() -> void:
	_client = null
	_state = {}


func _show_start_view(message: String) -> void:
	start_view.visible = true
	lobby_view.visible = false
	join_button.disabled = false
	host_button.disabled = false
	status_label.text = message


func _show_lobby_view() -> void:
	start_view.visible = false
	lobby_view.visible = true
	lobby_status_label.text = ""
	if _client != null:
		_state = _client.state
	_render()


## Draws `_state`. Nothing here decides anything; buttons just reflect what is allowed.
func _render() -> void:
	if not lobby_view.visible or _state.is_empty():
		return
	var is_host: bool = _host != null
	var my_id: String = _host.local_player_id if is_host else (_client.player_id if _client != null else "")
	address_label.visible = is_host
	copy_button.visible = is_host
	address_label.text = "Share this address: %s" % shared_address
	ready_button.visible = not is_host
	start_button.visible = is_host
	start_button.disabled = not LobbyLogic.ready_to_start(_state)
	for child: Node in players_box.get_children():
		players_box.remove_child(child)
		child.queue_free()
	for slot: Dictionary in _state["slots"]:
		players_box.add_child(_player_row(slot, my_id, is_host))
	var started: bool = _state["phase"] == LobbyLogic.PHASE_IN_GAME
	ready_button.disabled = started
	if started:
		start_button.disabled = true


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
	if is_host and not is_host_slot and not slot["left"] and _state["phase"] == LobbyLogic.PHASE_OPEN:
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
