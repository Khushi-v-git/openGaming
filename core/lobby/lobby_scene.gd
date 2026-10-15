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
## The lobby phase became in_game, on the host (after Start) or on a guest (the host started).
## Exactly one of `host` / `client` is set. The owner builds the game on top of them.
signal game_ready(host: LobbyHost, client: LobbyClient)
## The session ended and the start view is showing again (code: LEFT, HOST_CLOSED, HOST_LOST, ...).
signal session_over(code: String, message: String)
## A valid player name was entered when hosting or joining (the app saves it).
signal name_chosen(player_name: String)
## The Back button on the start view was pressed.
signal back_requested()

var options: Dictionary = {}

# Widgets are public so tests can drive them like a user would.
var title_label: Label
var name_edit: LineEdit
var port_spin: SpinBox
var port_label: Label
var connection_panel: ConnectionPanel  # only when the transport config asks for it
var start_scroll: ScrollContainer  # the start view scrolls when a short window cannot show all of it
var address_edit: LineEdit
var host_button: Button
var join_button: Button
var rejoin_button: Button
var back_button: Button
var status_label: Label
var start_view: Control
var connecting_view: Control
var connecting_label: Label
var cancel_button: Button
var lobby_view: Control
var address_label: Label  # the full sentence (kept for tests and screen readers; the caption + field are what is drawn)
var address_caption: Label
var public_address_edit: LineEdit  # what the host shares; editable for a direct address
var copy_button: Button
var settings_box: VBoxContainer  # host only: the game's own house-rules panel
var settings_panel: Node
var house_rules_label: Label  # guests: the host's house rules, read-only
var players_box: VBoxContainer
var players_scroll: ScrollContainer  # the list scrolls when a big game does not fit the window
var claims_box: VBoxContainer  # host only: returning players waiting to be let in
var notice_label: Label  # "Waiting for X to come back."
var continue_button: Button  # host only, while paused: continue without waiting
var wait_button: Button  # host only, after continuing: wait for the absent player again
var ready_button: ReadyPill
var ready_caption: Label  # "Tap again if you need a moment", only while ready
var start_button: Button
var leave_button: Button
var lobby_status_label: Label
var panel: PanelContainer
var empty_seats_box: VBoxContainer  # dashed "Waiting for a player..." rows (not part of players_box)
var ready_card: Control  # the guest's big "I'm ready" row
var you_row: HBoxContainer  # guest: "You are playing as X"
var you_icon: TextureRect
var you_label: Label
var share_box: VBoxContainer  # host: what to share
var share_help_label: Label
var rules_card_node: PaperCard
var house_rules_box: VBoxContainer  # guest: the host's house rules as a list with leaf bullets
var bottom_caption: Label  # "Everyone must be ready" / "Waiting for the host to start..."

## The address or room code to share (host only), as reported by the transport.
var shared_address: String = ""
## What the transport calls what it shows the host to share ("address", "room code").
var share_label: String = "address"

var _host: LobbyHost = null
var _client: LobbyClient = null
var _address_editable: bool = false
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


## The host's lobby (null on a guest), for the game layer built on top.
func lobby_host() -> LobbyHost:
	return _host


## The guest's lobby client (null on the host).
func lobby_client() -> LobbyClient:
	return _client


## Shows the lobby again after a game ended in the same session (nobody reconnects).
func show_lobby_again() -> void:
	visible = true
	_show_lobby_view()


## Puts a message on the lobby (for the game layer, e.g. "the game could not start").
func show_status(text: String) -> void:
	_set_lobby_status(text)


func _process(_delta: float) -> void:
	status_label.visible = not status_label.text.is_empty()
	if _host != null:
		_host.poll()
	elif _client != null:
		_client.poll()


# --- building --------------------------------------------------------------------

func _build_ui() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Tokens.PAPER_CREAM
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	add_child(LeafBorder.new())

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card: PaperCard = PaperCard.new()
	card.back_color = Tokens.DEEP_TEAL
	panel = card
	center.add_child(panel)
	var card_style: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
	card_style.content_margin_left = 34
	card_style.content_margin_right = 34
	card_style.content_margin_top = 22
	card_style.content_margin_bottom = 24
	card_style.set_corner_radius_all(32)
	card.corner_radius = 32
	card.back_offset = Vector2(10, 12)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	var title_row: HBoxContainer = HBoxContainer.new()
	root.add_child(title_row)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 44)
	title_label.add_theme_color_override("font_color", Tokens.INDIGO)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_label)

	start_view = _build_start_view()
	title_row.add_child(back_button)  # Back sits beside the title, so a scrolled start view never hides it
	start_scroll = ScrollContainer.new()
	start_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	start_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_scroll.add_child(start_view)
	start_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_view.minimum_size_changed.connect(_fit_start_view)  # the scroll follows what the screen needs
	root.add_child(start_scroll)
	connecting_view = _build_connecting_view()
	root.add_child(connecting_view)
	lobby_view = _build_lobby_view()
	root.add_child(lobby_view)


## The panel grows with the window (a little over a third of the width), but never
## wider than the window itself, so it fits from 1280x720 up to 1920x1080 and on resize.
func _update_layout() -> void:
	if panel == null:
		return
	# the card is about 73% of the window wide in the lobby (the design's 1400 of 1920), narrower on
	# the start screen and the waiting cards, and never wider than the window
	var share: float = 0.73
	var low: float = 700.0
	var high: float = 1400.0
	if start_view != null and start_view.visible:
		share = 0.52
		low = 520.0
		high = 1000.0
	elif connecting_view != null and connecting_view.visible:
		share = 0.36
		low = 460.0
		high = 700.0
	var wanted: float = clampf(size.x * share, low, high)
	panel.custom_minimum_size.x = minf(wanted, maxf(0.0, size.x - 2.0 * Tokens.SPACE_L))
	_fit_players_list()
	_fit_start_view()


## The start screen takes the room it needs, but never more than the window offers: beyond that it
## scrolls, so on a short window nothing is cut off at the top or the bottom of the card.
func _fit_start_view() -> void:
	if start_scroll == null or start_view == null:
		return
	var needed: float = start_view.get_combined_minimum_size().y
	var room: float = maxf(160.0, size.y - 190.0)  # the title, the card's padding and the leaf margin
	start_scroll.custom_minimum_size.y = minf(needed, room)


## The player list takes the room it needs, up to about 40% of the window height, and
## scrolls beyond that, so games with many players still fit from 1280x720 up.
func _fit_players_list() -> void:
	if players_scroll == null:
		return
	var needed: float = players_box.get_combined_minimum_size().y
	players_scroll.custom_minimum_size.y = minf(needed, maxf(120.0, size.y * 0.4))


func _build_start_view() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Your name"
	name_edit.max_length = Handshake.MAX_NAME_LENGTH
	name_edit.text = str(options.get("player_name", ""))
	PaperStyle.inset_field(name_edit)
	box.add_child(name_edit)

	if _transport_config.get("connection_ui", false):
		connection_panel = ConnectionPanel.new()
		connection_panel.initial_url = str(_transport_config.get("relay_url", ""))
		connection_panel.host_via_changed.connect(func(_via: String) -> void: _update_port_visibility())
		box.add_child(connection_panel)
	var host_row: HBoxContainer = HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 12)
	if _transport_config.has("port"):  # only transports that listen on a port show this
		port_label = _caption("Port")
		port_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		host_row.add_child(port_label)
		port_spin = SpinBox.new()
		port_spin.min_value = 1
		port_spin.max_value = 65535
		port_spin.value = int(_transport_config["port"])
		host_row.add_child(port_spin)
	host_button = Button.new()
	host_button.text = "Host"
	host_button.theme_type_variation = &"PrimaryButton"
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_button.pressed.connect(host_session)
	host_row.add_child(host_button)
	box.add_child(host_row)

	box.add_child(PaperStyle.dashed_rule())
	var join_title: Label = _label("Join a game")
	PaperStyle.title(join_title, 26)
	box.add_child(join_title)
	var join_row: HBoxContainer = HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 12)
	address_edit = LineEdit.new()
	address_edit.placeholder_text = "Address or room code from your host"
	address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PaperStyle.inset_field(address_edit)
	address_edit.text_changed.connect(func(_text: String) -> void: PaperStyle.mark_field_error(address_edit, false))
	join_row.add_child(address_edit)
	join_button = Button.new()
	join_button.text = "Join"
	join_button.custom_minimum_size.x = 110.0
	join_button.pressed.connect(join_session)
	join_row.add_child(join_button)
	box.add_child(join_row)

	_update_port_visibility()
	rejoin_button = Button.new()
	rejoin_button.text = "Rejoin the game you were in"
	rejoin_button.theme_type_variation = &"PrimaryButton"
	rejoin_button.pressed.connect(rejoin_session)
	box.add_child(rejoin_button)

	status_label = _label("")
	PaperStyle.error(status_label)
	box.add_child(status_label)
	back_button = Button.new()
	back_button.text = "Back"
	back_button.theme_type_variation = &"CreamButton"
	back_button.custom_minimum_size = Vector2(120.0, 44.0)
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_button.pressed.connect(func() -> void: back_requested.emit())
	return box


## The port only matters when hosting by direct address.
func _update_port_visibility() -> void:
	if port_spin == null:
		return
	var show_port: bool = connection_panel == null or not connection_panel.uses_relay()
	port_spin.visible = show_port
	port_label.visible = show_port


## "Starting your game...", "Connecting to ...", "Waiting for the host to let you back in...":
## bouncing dots, the message, and Cancel.
func _build_connecting_view() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	var loader: DotsLoader = DotsLoader.new()
	loader.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(loader)
	connecting_label = _label("Connecting...")
	PaperStyle.title(connecting_label, 30)
	connecting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	connecting_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(connecting_label)
	cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.theme_type_variation = &"CreamButton"
	cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel_button.custom_minimum_size.x = 200.0
	cancel_button.pressed.connect(cancel)
	box.add_child(cancel_button)
	return box


## The lobby: two columns. Left: the players (and, for a guest, the ready toggle). Right: what to
## share and the house rules. Bottom: Leave on the left, the start button or a waiting line on the right.
func _build_lobby_view() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	address_label = _label("")  # the full sentence; kept for tests and screen readers, not drawn
	address_label.visible = false
	box.add_child(address_label)

	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 36)
	box.add_child(columns)

	# --- left: players ---
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 55.0
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	left.add_child(_section_title("Players"))
	players_box = VBoxContainer.new()
	players_box.add_theme_constant_override("separation", 10)
	players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_scroll = ScrollContainer.new()
	players_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	players_scroll.add_child(players_box)
	left.add_child(players_scroll)
	empty_seats_box = VBoxContainer.new()
	empty_seats_box.add_theme_constant_override("separation", 10)
	left.add_child(empty_seats_box)
	claims_box = VBoxContainer.new()
	left.add_child(claims_box)
	ready_button = ReadyPill.new()
	ready_button.toggled.connect(func(pressed: bool) -> void: _act({"type": "set_ready", "ready": pressed}))
	var ready_box: VBoxContainer = VBoxContainer.new()
	ready_box.add_theme_constant_override("separation", 6)
	ready_box.add_child(ready_button)
	ready_caption = _label("Tap again if you need a moment")
	ready_caption.add_theme_font_size_override("font_size", 18)
	ready_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ready_caption.visible = false
	ready_box.add_child(ready_caption)
	ready_card = ready_box
	left.add_child(ready_box)

	# --- right: share + house rules ---
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 45.0
	right.add_theme_constant_override("separation", 12)
	columns.add_child(right)
	you_row = HBoxContainer.new()
	you_row.add_theme_constant_override("separation", 12)
	you_icon = TextureRect.new()
	you_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	you_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	you_icon.custom_minimum_size = Vector2(40.0, 40.0)
	you_row.add_child(you_icon)
	you_label = _label("")
	you_label.add_theme_font_size_override("font_size", 22)
	you_row.add_child(you_label)
	right.add_child(you_row)

	share_box = VBoxContainer.new()
	share_box.add_theme_constant_override("separation", 6)
	address_caption = _section_title("Share this address")
	share_box.add_child(address_caption)
	var address_row: HBoxContainer = HBoxContainer.new()
	address_row.add_theme_constant_override("separation", 10)
	public_address_edit = LineEdit.new()
	public_address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	public_address_edit.text_submitted.connect(func(_text: String) -> void: _save_public_address())
	public_address_edit.focus_exited.connect(_save_public_address)
	PaperStyle.inset_field(public_address_edit, 22)
	address_row.add_child(public_address_edit)
	copy_button = Button.new()
	copy_button.text = "Copy"
	copy_button.custom_minimum_size = Vector2(96.0, 44.0)
	copy_button.pressed.connect(func() -> void: DisplayServer.clipboard_set(public_address_edit.text))
	address_row.add_child(copy_button)
	share_box.add_child(address_row)
	share_help_label = _label("Friends type this code under Join game")
	share_help_label.add_theme_font_size_override("font_size", 16)
	share_box.add_child(share_help_label)
	right.add_child(share_box)

	var rules_card: PaperCard = PaperCard.new()
	rules_card.back_color = Tokens.SAFFRON
	rules_card.back_offset = Vector2(6, 8)
	rules_card.corner_radius = 22
	rules_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rules_style: StyleBoxFlat = rules_card.get_theme_stylebox("panel") as StyleBoxFlat
	rules_style.set_corner_radius_all(22)
	rules_style.content_margin_left = 20
	rules_style.content_margin_right = 20
	rules_style.content_margin_top = 12
	rules_style.content_margin_bottom = 12
	rules_card_node = rules_card
	var rules_box: VBoxContainer = VBoxContainer.new()
	rules_box.add_theme_constant_override("separation", 4)
	rules_card.add_child(rules_box)
	rules_box.add_child(_section_title("House rules"))
	settings_box = VBoxContainer.new()
	settings_box.add_theme_constant_override("separation", 0)
	settings_box.visible = false
	rules_box.add_child(settings_box)
	house_rules_label = _label("")  # "House rules: A, B": kept for tests and screen readers, not drawn
	house_rules_label.visible = false
	rules_box.add_child(house_rules_label)
	house_rules_box = VBoxContainer.new()
	house_rules_box.add_theme_constant_override("separation", 8)
	house_rules_box.visible = false
	rules_box.add_child(house_rules_box)
	right.add_child(rules_card)

	# --- notices and the bottom row ---
	notice_label = _label("")
	PaperStyle.notice(notice_label, Tokens.ROSE.lerp(Tokens.PAPER_CREAM, 0.75))
	box.add_child(notice_label)
	var decisions: HBoxContainer = HBoxContainer.new()
	decisions.add_theme_constant_override("separation", 12)
	continue_button = Button.new()
	continue_button.text = "Continue without waiting"
	continue_button.theme_type_variation = &"PrimaryButton"
	continue_button.pressed.connect(func() -> void: _act({"type": "set_paused", "paused": false}))
	decisions.add_child(continue_button)
	wait_button = Button.new()
	wait_button.text = "Wait for them"
	wait_button.theme_type_variation = &"CreamButton"
	wait_button.pressed.connect(func() -> void: _act({"type": "set_paused", "paused": true}))
	decisions.add_child(wait_button)
	box.add_child(decisions)

	lobby_status_label = _label("")
	lobby_status_label.visible = false  # only takes room while it has something to say
	PaperStyle.error(lobby_status_label)
	box.add_child(lobby_status_label)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	leave_button = Button.new()
	leave_button.text = "Leave"
	leave_button.theme_type_variation = &"CreamButton"
	leave_button.custom_minimum_size.x = 150.0
	leave_button.pressed.connect(ask_to_leave)
	actions.add_child(leave_button)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	bottom_caption = _label("")
	bottom_caption.add_theme_font_size_override("font_size", 20)
	actions.add_child(bottom_caption)
	start_button = Button.new()
	start_button.text = "Start game"
	start_button.theme_type_variation = &"PrimaryButton"
	PaperStyle.start_pill(start_button)
	start_button.pressed.connect(func() -> void: _act({"type": "start"}))
	actions.add_child(start_button)
	box.add_child(actions)
	return box


func _section_title(text: String) -> Label:
	var label: Label = _label(text)
	PaperStyle.title(label, 26)
	return label


## The raised pill behind a row of the lobby (a player, the ready toggle).
func _row_box() -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Tokens.PAPER_CREAM.lightened(0.3)
	box.set_corner_radius_all(28)
	box.shadow_color = Color(Tokens.INK, 0.22)
	box.shadow_size = 3
	box.shadow_offset = Vector2(1, 3)
	box.content_margin_left = 22
	box.content_margin_right = 14
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box


## The colour of the card peeking out behind the main card, and the card's width for this view.
func _look(back_color: Color) -> void:
	var card: PaperCard = panel as PaperCard
	if card != null:
		card.back_color = back_color
		card.back.queue_redraw()
	title_label.visible = not (connecting_view != null and connecting_view.visible)
	title_label.add_theme_font_size_override("font_size", 30 if (start_view != null and start_view.visible) else 44)
	_update_layout()


func _set_lobby_status(text: String) -> void:
	lobby_status_label.text = text
	lobby_status_label.visible = not text.is_empty()


func _label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	return label


func _caption(text: String) -> Label:
	var label: Label = _label(text)
	PaperStyle.caption(label)
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
	name_chosen.emit(cleaned["name"])
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
	name_chosen.emit(cleaned["name"])
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


## The Leave button: asks first (design section 13). A guest only leaves; the host closes the
## room for everyone.
func ask_to_leave() -> void:
	if _host == null and _client == null:
		return
	var question: Dictionary = ConfirmDialog.close_room() if _host != null else ConfirmDialog.leave_lobby()
	ConfirmDialog.ask(self, question, func(id: String) -> void:
		if id == "leave" or id == "close":
			leave())


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
	PaperStyle.mark_field_error(address_edit, false)
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
	_address_editable = bool(info.get("public_address_editable", false))
	_use_game_settings_check()
	_state = _host.state
	_show_lobby_view()
	_push_settings()  # guests must always see the house rules, even if the host never touches them


func _on_host_failed(reason: String) -> void:
	_drop_host()
	_show_start_view("Could not host: %s" % reason)


func _on_state_changed(state: Dictionary) -> void:
	_state = state
	_render()


func _on_game_started(state: Dictionary) -> void:
	_set_lobby_status("Game starting...")
	game_started.emit(state)
	game_ready.emit(_host, _client)


func _on_joined() -> void:
	_resume = {}
	rejoin_button.visible = false
	_show_lobby_view()


func _on_join_failed(code: String, message: String, _host_info: Dictionary) -> void:
	if code != ErrorCodes.CONNECT_FAILED:
		_resume = {}  # the host answered and said no; retrying with the same identity won't help
	_forget_client()
	_show_start_view("Could not join: %s" % message)
	PaperStyle.mark_field_error(address_edit, true)


func _on_left(code: String, message: String) -> void:
	_resume = {}
	if code == ErrorCodes.HOST_LOST and _client != null:
		_resume = {"address": _joining_address, "name": _joining_name, "identity": _client.identity()}
	_forget_client()
	var shown: String = "" if code == ErrorCodes.LEFT else "Left the session: %s" % message
	_show_start_view(shown)
	session_over.emit(code, shown)


func _on_host_closed() -> void:
	_host = null
	_show_start_view("")
	session_over.emit("HOST_CLOSED", "")


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
	start_scroll.visible = true
	back_button.visible = true
	connecting_view.visible = false
	lobby_view.visible = false
	rejoin_button.visible = not _resume.is_empty()
	status_label.text = message
	_look(Tokens.ROSE if not message.is_empty() else Tokens.DEEP_TEAL)
	_update_title()
	_update_layout()
	if not message.is_empty():
		_show_the_bottom.call_deferred()  # a message sits at the bottom: make sure it is in view


func _show_the_bottom() -> void:
	if is_inside_tree() and not get_tree().process_frame.is_connected(_scroll_to_status):
		# next frame, once the new text has changed the size (a signal connection ends with the node)
		get_tree().process_frame.connect(_scroll_to_status, CONNECT_ONE_SHOT)


func _scroll_to_status() -> void:
	if start_scroll != null and start_scroll.is_visible_in_tree():
		start_scroll.ensure_control_visible(status_label)


func _show_connecting(message: String) -> void:
	start_view.visible = false
	start_scroll.visible = false
	back_button.visible = false
	connecting_view.visible = true
	lobby_view.visible = false
	connecting_label.text = message
	_look(Tokens.INDIGO if message.begins_with("Waiting") else Tokens.SAFFRON)


func _show_lobby_view() -> void:
	start_view.visible = false
	start_scroll.visible = false
	back_button.visible = false
	connecting_view.visible = false
	lobby_view.visible = true
	_look(Tokens.ROSE)
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
	var open: bool = _state["phase"] == LobbyLogic.PHASE_OPEN
	address_caption.text = "Share this %s" % share_label
	share_box.visible = is_host
	address_caption.visible = is_host
	copy_button.visible = is_host
	public_address_edit.visible = is_host
	var shown: String = _shown_address()
	address_label.text = "Share this %s: %s" % [share_label, shown]
	if not public_address_edit.has_focus():
		public_address_edit.text = shown
	public_address_edit.editable = _address_editable
	_style_share_field()
	share_help_label.visible = is_host and share_label == "room code"
	_render_settings(is_host)
	ready_button.visible = not is_host
	ready_card.visible = not is_host
	start_button.visible = is_host and open
	start_button.disabled = not LobbyLogic.ready_to_start(_state)
	for child: Node in players_box.get_children():
		players_box.remove_child(child)
		child.queue_free()
	var seat: int = 0
	var my_seat: int = -1
	var my_name: String = ""
	for slot: Dictionary in _state["slots"]:
		players_box.add_child(_player_row(slot, my_id, is_host, seat))
		if slot["player_id"] == my_id:
			ready_button.set_pressed_no_signal(bool(slot["ready"]))  # the toggle mirrors the host's state
			my_seat = seat
			my_name = str(slot["name"])
		seat += 1
	_render_empty_seats(open)
	_render_you(is_host, my_seat, my_name)
	_render_claims(is_host)
	_render_pause(is_host)
	_fit_players_list()
	var started: bool = not open
	ready_button.disabled = started
	if started:
		start_button.disabled = true
	ready_caption.visible = not is_host and open and ready_button.button_pressed
	_render_bottom_caption(is_host, open)
	_update_title()


## One dashed "Waiting for a player..." row per free seat (never part of players_box).
func _render_empty_seats(open: bool) -> void:
	for child: Node in empty_seats_box.get_children():
		empty_seats_box.remove_child(child)
		child.queue_free()
	if not open:
		return
	var free: int = int(_state["max_players"]) - (_state["slots"] as Array).size()
	for _i: int in mini(free, 2):  # one or two hints are enough; a big table need not show them all
		var seat: PaperEmptySeat = PaperEmptySeat.new()
		seat.seat_height = _row_height()
		seat.custom_minimum_size.y = _row_height()
		empty_seats_box.add_child(seat)


## Guests: "You are playing as <name>" with their pawn.
func _render_you(is_host: bool, my_seat: int, my_name: String) -> void:
	you_row.visible = not is_host and my_seat >= 0
	if not you_row.visible:
		return
	you_label.text = "You are playing as %s" % my_name
	var colors: Array = options.get("seat_colors", _PAWN_COLORS)
	you_icon.visible = my_seat < colors.size()
	if you_icon.visible:
		you_icon.texture = load("res://core/assets/pawn-%s.svg" % str(colors[my_seat]))


func _render_bottom_caption(is_host: bool, open: bool) -> void:
	if is_host:
		bottom_caption.visible = open and not LobbyLogic.ready_to_start(_state)
		bottom_caption.text = "Everyone must be ready"
	else:
		bottom_caption.visible = open
		bottom_caption.text = "Waiting for the host to start..."


## A relay room code is shown big and spaced out and cannot be edited; a direct address is a
## normal field.
func _style_share_field() -> void:
	var big: bool = not _address_editable and _shown_address().length() <= 8  # a room code, not a long address
	if big:
		var spaced: FontVariation = FontVariation.new()
		spaced.base_font = AppTheme.build_font()
		spaced.spacing_glyph = 9
		public_address_edit.add_theme_font_override("font", spaced)
		public_address_edit.add_theme_font_size_override("font_size", 40)
		public_address_edit.add_theme_color_override("font_color", Tokens.DEEP_TEAL)
		public_address_edit.add_theme_color_override("font_uneditable_color", Tokens.DEEP_TEAL)
		public_address_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		public_address_edit.custom_minimum_size.y = 64.0
	else:
		public_address_edit.remove_theme_font_override("font")
		public_address_edit.add_theme_font_size_override("font_size", 22)
		public_address_edit.remove_theme_color_override("font_color")
		public_address_edit.add_theme_color_override("font_uneditable_color", Tokens.INK)  # readable when not editable
		public_address_edit.alignment = HORIZONTAL_ALIGNMENT_LEFT
		public_address_edit.custom_minimum_size.y = 48.0


## Rows get taller with the window: 56 px at 720p up to 80 px at 1080p.
func _row_height() -> float:
	return clampf(size.y / 13.5, 52.0, 80.0)


## What the host shares: the address the transport reports, or the one the host typed instead
## (only for transports that allow it, i.e. a direct address).
func _shown_address() -> String:
	var typed: String = AppSettings.public_address()
	return typed if _address_editable and not typed.is_empty() else shared_address


func _save_public_address() -> void:
	if not _address_editable or _host == null:
		return
	var typed: String = public_address_edit.text.strip_edges()
	AppSettings.set_public_address("" if typed == shared_address else typed)
	_render()


## The host's house-rules panel (the game's own settings scene), or the guests' read-only summary.
func _render_settings(is_host: bool) -> void:
	settings_box.visible = false
	house_rules_label.visible = false  # the plain sentence is kept for tests; the list below is what is drawn
	house_rules_box.visible = false
	var registry: GameRegistry = options.get("game_registry", null)
	var game_id: String = str(options.get("game_id", ""))
	if game_id.is_empty():
		game_id = str(_state.get("game_id", ""))  # a guest learns the game from the host
	if registry == null or game_id.is_empty() or not registry.has(game_id):
		return
	if is_host and _state["phase"] == LobbyLogic.PHASE_OPEN:
		if settings_panel == null:
			_build_settings_panel(registry, game_id)
		settings_box.visible = settings_panel != null
		return
	var rules: GameRules = registry.create_rules(game_id) as GameRules
	if rules == null:
		return
	var lines: Array = rules.describe_settings(_state.get("game_settings", {}))
	house_rules_label.text = "House rules: %s" % ", ".join(lines)
	house_rules_box.visible = not lines.is_empty()
	for child: Node in house_rules_box.get_children():
		house_rules_box.remove_child(child)
		child.queue_free()
	for line: Variant in lines:
		var item: HBoxContainer = HBoxContainer.new()
		item.add_theme_constant_override("separation", 12)
		item.add_child(LeafBullet.new())
		var text: Label = _label(str(line))
		text.add_theme_font_size_override("font_size", 22)
		item.add_child(text)
		house_rules_box.add_child(item)


func _build_settings_panel(registry: GameRegistry, game_id: String) -> void:
	var scene: PackedScene = registry.load_settings_scene(game_id)
	if scene == null:
		return
	settings_panel = scene.instantiate()
	if settings_panel is Control:
		(settings_panel as Control).add_theme_constant_override("separation", 0)  # compact rows
	settings_box.add_child(settings_panel)
	if settings_panel.has_signal("changed"):
		settings_panel.connect("changed", func(_settings: Dictionary) -> void: _push_settings())


## Lets the lobby ask the game whether house rules are acceptable before it stores them (a game
## host built later replaces this with its own, which asks the same rules).
func _use_game_settings_check() -> void:
	var registry: GameRegistry = options.get("game_registry", null)
	var game_id: String = str(options.get("game_id", ""))
	if registry == null or game_id.is_empty() or not registry.has(game_id) or _host == null:
		return
	var rules: GameRules = registry.create_rules(game_id) as GameRules
	if rules != null:
		_host.settings_validator = func(settings: Dictionary) -> Dictionary: return rules.validate_settings(settings)


## Sends the panel's current settings to the lobby (the game checks them first; a refusal shows).
func _push_settings() -> void:
	if _host == null or settings_panel == null or not settings_panel.has_method("settings"):
		return
	var result: Dictionary = _host.act({"type": "set_game_settings", "settings": settings_panel.call("settings")})
	_set_lobby_status("" if CoreResult.is_ok(result) else str(result["error"]["message"]))


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
		PaperStyle.small_button(allow, &"PrimaryButton")
		allow.text = "Let in"
		allow.pressed.connect(func() -> void: _host.answer_rejoin(player_id, true))
		row.add_child(allow)
		var decline: Button = Button.new()
		PaperStyle.small_button(decline)
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


const _PAWN_COLORS: Array = ["red", "blue", "green", "yellow"]


## One row: [name (with the seat's pawn and, for the host, a crown)] [status pill] [Remove].
## Pawn colours follow seat order; set options["seat_colors"] = [] for a game that has none.
func _player_row(slot: Dictionary, my_id: String, is_host: bool, seat: int = 0) -> Control:
	var row: PaperRow = PaperRow.new()
	var height: float = _row_height()
	row.row_height = height
	var label: Label = _label(_slot_text(slot, my_id))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size.x = 80.0
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Tokens.INDIGO)
	var indent: StyleBoxEmpty = StyleBoxEmpty.new()
	indent.content_margin_left = height * 0.95
	label.add_theme_stylebox_override("normal", indent)
	var colors: Array = options.get("seat_colors", _PAWN_COLORS)
	if seat < colors.size():
		label.add_child(_icon("res://core/assets/pawn-%s.svg" % str(colors[seat]), 12.0, height * 0.75))
	var is_host_slot: bool = slot["player_id"] == _state["host_player_id"]
	if is_host_slot:
		# the crown sits on the pawn's head
		label.add_child(_icon("res://core/assets/icon-crown.svg", 12.0 + (height * 0.75 - 24.0) / 2.0, 24.0, -height * 0.36))
	row.add_child(label)
	row.add_child(_status_chip(slot, height))
	var removable: bool = _state["phase"] == LobbyLogic.PHASE_OPEN or not slot["connected"]
	if is_host and not is_host_slot and not slot["left"] and removable:
		var kick: Button = Button.new()
		PaperStyle.small_button(kick)
		kick.text = "Remove"
		kick.custom_minimum_size.y = 38.0
		var target: String = slot["player_id"]
		var shown_name: String = str(slot["name"])
		var pawn_color: String = str(colors[seat]) if seat < colors.size() else ""
		kick.pressed.connect(func() -> void:
			ConfirmDialog.ask(self, ConfirmDialog.remove_player(shown_name, pawn_color), func(id: String) -> void:
				if id == "remove":
					_act({"type": "kick", "player_id": target})))
		row.add_child(kick)
	return row


## The chip at the right of a row (design section 14): a green "Ready" with a check dot, a grey
## "Not ready" with an empty dot, or a rose "Disconnected".
func _status_chip(slot: Dictionary, row_height: float) -> Label:
	var connected: bool = slot["connected"]
	var is_ready: bool = slot["ready"] and connected
	var chip: Label = _label("Ready" if is_ready else ("Not ready" if connected else "Disconnected"))
	var fill: Color = Tokens.FOREST_GREEN if is_ready else (Color("#CFC7B2") if connected else Tokens.ROSE)
	var text: Color = Tokens.PAPER_CREAM if (is_ready or not connected) else Color("#4F4B42")
	PaperStyle.pill(chip, fill, text)
	chip.add_theme_font_size_override("font_size", 22)
	chip.custom_minimum_size.y = minf(52.0, row_height - 14.0)
	if connected:
		var padded: StyleBoxFlat = chip.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		padded.content_margin_left = 50
		padded.content_margin_right = 20
		chip.add_theme_stylebox_override("normal", padded)
		chip.custom_minimum_size.x = 176.0  # room for the dot and the longer "Not ready"
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var dot: ChipDot = ChipDot.new(is_ready)
		dot.position = Vector2(14.0, (chip.custom_minimum_size.y - ChipDot.DIAMETER) / 2.0)
		chip.add_child(dot)
	return chip


## A small picture pinned to the left of its parent label, vertically centred (plus `lift`).
func _icon(path: String, left: float, edge: float, lift: float = 0.0) -> TextureRect:
	var icon: TextureRect = TextureRect.new()
	icon.texture = load(path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	icon.offset_left = left
	icon.offset_right = left + edge
	icon.offset_top = -edge / 2.0 + lift
	icon.offset_bottom = edge / 2.0 + lift
	return icon


func _slot_text(slot: Dictionary, my_id: String) -> String:
	var text: String = slot["name"]
	if slot["player_id"] == _state["host_player_id"]:
		text += " (host)"
	if slot["player_id"] == my_id:
		text += " (you)"
	return text


## A small green paper leaf: the bullet in front of a house rule.
class LeafBullet:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(24.0, 24.0)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var leaf: PackedVector2Array = PackedVector2Array()
		for i: int in range(11):
			var t: float = float(i) / 10.0
			leaf.append(Vector2(2.0 + t * 20.0, 12.0 - sin(t * PI) * 8.0))
		for i: int in range(11):
			var t: float = float(i) / 10.0
			leaf.append(Vector2(22.0 - t * 20.0, 12.0 + sin(t * PI) * 8.0))
		var shadow: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in leaf:
			shadow.append(point + Vector2(1.5, 2.0))
		draw_colored_polygon(shadow, Color(Tokens.INK, 0.25))
		draw_colored_polygon(leaf, Tokens.FOREST_GREEN)
