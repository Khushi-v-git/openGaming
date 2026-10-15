class_name MainMenu
extends Control
## The home screen: a card per game built from the registry (Host game, Join game, Play on this
## computer), a top-level Join game, the hot-seat setup, and the glue from the lobby to a networked
## game. It knows no game by name: it reads manifests, asks the game's own settings scene for
## settings, and hands the game's UI scene a controller.
##
## Networked play: the lobby scene (core/lobby) does hosting, joining and readying up. When it says
## game_ready, this builds a GameHost (host) or GameClient (guest), a NetworkGameController, and the
## game's UI scene on top of the still-running lobby. When the game ends the lobby comes back.
## Command-line options (see LaunchOptions) can open the host or join lobby by themselves.

signal game_started(game_id: String)

const MAX_NAME_LENGTH: int = 20

var registry: GameRegistry
## Transport config for networked play. Empty = TransportFactory.network_config() when a lobby
## opens (tests put a loopback transport here).
var network_config: Dictionary = {}
## Parsed command-line options (see LaunchOptions). Tests set them and turn use_command_line off.
var launch_options: Dictionary = {}
var use_command_line: bool = true
var game_list: VBoxContainer
var join_button: Button
var setup_panel: Control
var error_label: Label

var _selected_id: String = ""
var _count_picker: OptionButton
var _name_fields: Array[LineEdit] = []
var _names_box: Container
var _settings_holder: Control
var _settings_node: Node
var _menu_root: Control
var _game_node: Control
var _title_label: Label

var _lobby: LobbyScene = null
var _net: Dictionary = {}  # the running networked game: {screen, controller}
var _game_host: GameHost = null  # one per hosted session, reused for every game in it
var _game_client: GameClient = null  # one per joined session
var _share_written: bool = false
var _auto_join_pending: bool = false


func _ready() -> void:
	theme = AppTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var launch_error: String = _read_launch_options()
	if registry == null:
		registry = GameRegistry.new()
		var loaded: Dictionary = registry.load_from()
		if not (loaded.get("errors", []) as Array).is_empty():
			push_error("Some games could not be loaded: %s" % str(loaded["errors"]))
	_build()
	show_game_list()
	if not launch_error.is_empty():
		_set_error(launch_error)
	elif not launch_options.is_empty():
		_apply_auto_launch()


func _process(_delta: float) -> void:
	if _lobby == null:
		return
	# --share_file: write the address once hosting is live
	if not _share_written and launch_options.has("share_file") and _lobby.shared_address != "":
		_share_written = true
		var file: FileAccess = FileAccess.open(str(launch_options["share_file"]), FileAccess.WRITE)
		if file != null:
			file.store_string(_lobby.shared_address)
			file.close()
	# --join_from_file: wait for the host to publish its code
	if _auto_join_pending and FileAccess.file_exists(str(launch_options.get("join_from_file", ""))):
		var code: String = FileAccess.get_file_as_string(str(launch_options["join_from_file"])).strip_edges()
		if not code.is_empty():
			_auto_join_pending = false
			_lobby.address_edit.text = code
			_lobby.join_session()
	# --auto_ready: a guest ticks "I'm ready" whenever the lobby asks for it
	if launch_options.get("auto_ready", false) and _lobby.lobby_client() != null and _lobby.lobby_view.visible and _lobby.ready_button.visible and not _lobby.ready_button.disabled and not _lobby.ready_button.button_pressed:
		_lobby.ready_button.button_pressed = true


func _build() -> void:
	var back: ColorRect = ColorRect.new()
	back.color = Tokens.PAPER_CREAM
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	add_child(LeafBorder.new())

	_menu_root = CenterContainer.new()
	_menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_menu_root)
	var panel: PaperCard = PaperCard.new()
	panel.back_color = Tokens.DEEP_TEAL
	panel.back_offset = Vector2(10, 12)
	panel.custom_minimum_size = Vector2(520, 0)
	_menu_root.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	panel.add_child(column)

	_title_label = Label.new()
	_title_label.text = "onlyGaming"
	_title_label.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_TITLE + 8)
	_title_label.add_theme_color_override("font_color", Tokens.INDIGO)
	column.add_child(_title_label)

	join_button = Button.new()
	join_button.name = "JoinButton"
	join_button.text = "Join game"
	join_button.pressed.connect(open_join_lobby)
	column.add_child(join_button)

	game_list = VBoxContainer.new()
	column.add_child(game_list)

	setup_panel = VBoxContainer.new()
	setup_panel.visible = false
	column.add_child(setup_panel)
	_build_setup(setup_panel as VBoxContainer)

	error_label = Label.new()
	error_label.add_theme_color_override("font_color", Tokens.TERRACOTTA)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.visible = false
	column.add_child(error_label)


func _build_setup(box: VBoxContainer) -> void:
	var heading: Label = Label.new()
	heading.name = "Heading"
	heading.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_TITLE)
	box.add_child(heading)
	var count_row: HBoxContainer = HBoxContainer.new()
	var count_label: Label = Label.new()
	count_label.text = "Players"
	count_row.add_child(count_label)
	_count_picker = OptionButton.new()
	_count_picker.item_selected.connect(func(_i: int) -> void: _rebuild_names())
	count_row.add_child(_count_picker)
	box.add_child(count_row)
	_names_box = GridContainer.new()
	(_names_box as GridContainer).columns = 2
	box.add_child(_names_box)
	_settings_holder = VBoxContainer.new()
	box.add_child(_settings_holder)
	var buttons: HBoxContainer = HBoxContainer.new()
	var back_button: Button = Button.new()
	back_button.text = "Back"
	back_button.pressed.connect(show_game_list)
	buttons.add_child(back_button)
	var start_button: Button = Button.new()
	start_button.name = "StartButton"
	start_button.text = "Start game"
	start_button.theme_type_variation = "PrimaryButton"
	start_button.pressed.connect(start_hotseat)
	buttons.add_child(start_button)
	box.add_child(buttons)


## The playable games, one card each.
func show_game_list() -> void:
	_selected_id = ""
	setup_panel.visible = false
	game_list.visible = true
	join_button.visible = true
	_menu_root.visible = true
	_set_error("")
	for child: Node in game_list.get_children():
		game_list.remove_child(child)
		child.queue_free()
	for manifest: Dictionary in registry.playable():
		game_list.add_child(_game_card(manifest))


## One game: its name and description, and the three ways to play it.
func _game_card(manifest: Dictionary) -> Control:
	var card: VBoxContainer = VBoxContainer.new()
	card.set_meta("game_id", manifest["id"])
	var title: Label = Label.new()
	title.name = "Title"
	title.text = str(manifest["display_name"])
	title.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_TITLE)
	title.add_theme_color_override("font_color", Tokens.INDIGO)
	card.add_child(title)
	var description: Label = Label.new()
	description.name = "Description"
	description.text = str(manifest["description"])
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(description)
	var row: HBoxContainer = HBoxContainer.new()
	var host_button: Button = _pill("HostButton", "Host game", "PrimaryButton")
	host_button.pressed.connect(func() -> void: open_host_lobby(manifest["id"]))
	row.add_child(host_button)
	var join: Button = _pill("JoinGameButton", "Join game", "")
	join.pressed.connect(open_join_lobby)
	row.add_child(join)
	var hotseat: Button = _pill("HotseatButton", "Play on this computer", "CreamButton")
	hotseat.pressed.connect(func() -> void: choose_game(manifest["id"]))
	row.add_child(hotseat)
	card.add_child(row)
	return card


func _pill(button_name: String, text: String, variation: String) -> Button:
	var button: Button = Button.new()
	button.name = button_name
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not variation.is_empty():
		button.theme_type_variation = variation
	return button


# --- hot-seat ----------------------------------------------------------------------------------------

## Opens the "play on this computer" setup for a game.
func choose_game(game_id: String) -> void:
	if not registry.has_ui(game_id):
		return
	_selected_id = game_id
	var manifest: Dictionary = registry.get_manifest(game_id)
	game_list.visible = false
	join_button.visible = false
	setup_panel.visible = true
	_set_error("")
	(setup_panel.get_node("Heading") as Label).text = "%s: play on this computer" % manifest["display_name"]
	_count_picker.clear()
	for count: int in range(int(manifest["min_players"]), int(manifest["max_players"]) + 1):
		_count_picker.add_item(str(count), count)
	_count_picker.select(0)
	for child: Node in _settings_holder.get_children():
		_settings_holder.remove_child(child)
		child.queue_free()
	_settings_node = null
	var settings_scene: PackedScene = registry.load_settings_scene(game_id)
	if settings_scene != null:
		_settings_node = settings_scene.instantiate()
		_settings_holder.add_child(_settings_node)
	_rebuild_names()


func selected_game() -> String:
	return _selected_id


## The player names as typed, one per seat.
func player_names() -> Array[String]:
	var result: Array[String] = []
	for field: LineEdit in _name_fields:
		result.append(field.text.strip_edges())
	return result


func set_player_count(count: int) -> void:
	for i: int in _count_picker.item_count:
		if _count_picker.get_item_id(i) == count:
			_count_picker.select(i)
	_rebuild_names()


func _rebuild_names() -> void:
	var previous: Array[String] = player_names()
	for child: Node in _names_box.get_children():
		_names_box.remove_child(child)
		child.queue_free()
	_name_fields.clear()
	var count: int = _count_picker.get_selected_id()
	for i: int in count:
		var field: LineEdit = LineEdit.new()
		field.max_length = MAX_NAME_LENGTH
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.placeholder_text = "Player %d" % (i + 1)
		field.text = previous[i] if i < previous.size() else "Player %d" % (i + 1)
		_names_box.add_child(field)
		_name_fields.append(field)


## Starts the chosen game with everyone at this computer. Shows a message and stays on the
## setup screen if the names or the settings are not acceptable.
func start_hotseat() -> void:
	if _selected_id == "":
		return
	var typed: Array[String] = player_names()
	var seen: Dictionary = {}
	for name: String in typed:
		if name.is_empty():
			_set_error("Every player needs a name.")
			return
		if seen.has(name.to_lower()):
			_set_error("Two players are called \"%s\". Names must be different." % name)
			return
		seen[name.to_lower()] = true
	var rules: GameRules = registry.create_rules(_selected_id) as GameRules
	if rules == null:
		_set_error("This game could not be started.")
		return
	var settings: Dictionary = {}
	if _settings_node != null and _settings_node.has_method("settings"):
		settings = _settings_node.call("settings")
	var ids: Array = []
	var players: Array = []
	for i: int in typed.size():
		ids.append("p%d" % (i + 1))
		players.append({"player_id": ids[i], "name": typed[i]})
	var controller: LocalGameController = LocalGameController.new(rules, ids, rules.default_setup(), settings, randi())
	var game: Control = registry.load_ui_scene(_selected_id).instantiate()
	add_child(game)
	game.setup(controller, players)
	var started: Dictionary = controller.start()
	if not CoreResult.is_ok(started):
		game.queue_free()
		_set_error(str(started["error"]["message"]))
		return
	_game_node = game
	_menu_root.visible = false
	game.leave_requested.connect(_on_leave_requested)
	game_started.emit(_selected_id)


func in_game() -> bool:
	return _game_node != null


func _on_leave_requested() -> void:
	if _game_node != null:
		remove_child(_game_node)
		_game_node.queue_free()
		_game_node = null
	_menu_root.visible = true
	show_game_list()


# --- networked play: the lobby ---------------------------------------------------------------------------

## Opens the lobby to host `game_id`.
func open_host_lobby(game_id: String) -> LobbyScene:
	if not registry.has_ui(game_id):
		return null
	return _open_lobby(game_id)


## Opens the lobby to join a game: whichever game the host runs.
func open_join_lobby() -> LobbyScene:
	return _open_lobby("")


func lobby() -> LobbyScene:
	return _lobby


## True while a networked game's screen is up.
func in_network_game() -> bool:
	return not _net.is_empty()


func network_screen() -> Control:
	return _net.get("screen", null)


func _open_lobby(game_id: String) -> LobbyScene:
	_dispose_lobby()
	var config: Dictionary = network_config.duplicate() if not network_config.is_empty() else TransportFactory.network_config()
	if launch_options.has("port"):
		config["port"] = int(launch_options["port"])
	var scene: LobbyScene = LobbyScene.new()
	scene.setup({
		"app_version": AppInfo.app_version(),
		"game_id": game_id,
		"game_registry": registry,
		"transport": config,
		"player_name": str(launch_options.get("name", AppSettings.player_name())),
	})
	scene.name_chosen.connect(func(player_name: String) -> void: AppSettings.set_player_name(player_name))
	scene.back_requested.connect(func() -> void: _go_home(""))
	scene.game_ready.connect(_on_game_ready)
	scene.session_over.connect(_on_session_over)
	_lobby = scene
	_share_written = false
	_menu_root.visible = false
	add_child(scene)
	return scene


## Frees the lobby (and the game objects that hang on it).
func _dispose_lobby() -> void:
	_teardown_game_screen()
	_game_host = null
	_game_client = null
	if _lobby != null:
		var old: LobbyScene = _lobby
		_lobby = null
		old.visible = false
		if old.get_parent() != null:
			old.get_parent().remove_child(old)
		old.queue_free()


func _go_home(message: String) -> void:
	_dispose_lobby()
	_auto_join_pending = false
	show_game_list()
	if not message.is_empty():
		_set_error(message)


## The lobby says the game starts: build the game on top of it.
func _on_game_ready(host: LobbyHost, client: LobbyClient) -> void:
	if _lobby == null or not _net.is_empty():
		return
	var state: Dictionary = host.state if host != null else client.state
	var game_id: String = str(state.get("game_id", ""))
	var rules: GameRules = registry.create_rules(game_id) as GameRules
	var scene: PackedScene = registry.load_ui_scene(game_id)
	if rules == null or scene == null:
		_lobby.show_status("This app cannot play \"%s\"." % game_id)
		if host != null:
			host.act({"type": "end_game"})
		return
	var controller: NetworkGameController
	if host != null:
		if _game_host == null or _game_host.lobby != host:
			_game_host = GameHost.new(host, rules, rules.default_setup(), randi())
		controller = NetworkGameController.for_host(_game_host)
	else:
		if _game_client == null or _game_client.lobby != client:
			_game_client = GameClient.new(client)
		controller = NetworkGameController.for_client(_game_client, rules)
	var screen: Control = scene.instantiate()
	add_child(screen)
	screen.setup(controller, controller.players())
	_net = {"screen": screen, "controller": controller}
	_lobby.visible = false
	screen.leave_requested.connect(_on_network_leave)
	controller.ended.connect(_on_network_game_ended)
	if screen.has_signal("game_ended"):
		screen.connect("game_ended", _on_network_game_ended)
	if host != null:
		var started: Dictionary = _game_host.start()
		if not CoreResult.is_ok(started):
			_teardown_game_screen()
			_lobby.visible = true
			_lobby.show_status(str(started["error"]["message"]))
			host.act({"type": "end_game"})
			return
	game_started.emit(game_id)


## The host sent everyone back to the lobby.
func _on_network_game_ended() -> void:
	if _net.is_empty():
		return
	_teardown_game_screen()
	if _lobby != null:
		_lobby.show_lobby_again()


func _on_network_leave() -> void:
	_teardown_game_screen()
	if _lobby == null:
		_go_home("")
		return
	_lobby.visible = false
	_lobby.leave()  # the lobby tells us (session_over) when the goodbye is done


## The lobby session ended (we left, the host closed, we were removed, or the link was lost).
func _on_session_over(code: String, message: String) -> void:
	_teardown_game_screen()
	if code == ErrorCodes.HOST_LOST and _lobby != null:
		_lobby.visible = true  # its start view offers Rejoin
		return
	_go_home(message)


func _teardown_game_screen() -> void:
	if _net.is_empty():
		return
	var screen: Control = _net["screen"]
	_net = {}
	if screen != null and is_instance_valid(screen):
		if screen.get_parent() != null:
			screen.get_parent().remove_child(screen)
		screen.queue_free()


# --- command line ----------------------------------------------------------------------------------------------

## Reads the options (from the process unless a test set them); "" or an error message.
func _read_launch_options() -> String:
	if use_command_line and launch_options.is_empty():
		var parsed: Dictionary = LaunchOptions.parse(OS.get_cmdline_user_args())
		if not CoreResult.is_ok(parsed):
			return str(parsed["error"]["message"])
		launch_options = parsed["options"]
	if not launch_options.is_empty():
		LaunchOptions.isolate_settings(launch_options)
		LaunchOptions.apply_to_settings(launch_options)
	return ""


## --auto=host / --auto=join open the right lobby and start it. The host still presses Start.
func _apply_auto_launch() -> void:
	var mode: String = str(launch_options.get("auto", ""))
	if mode == "host":
		var game_id: String = str(launch_options.get("game", ""))
		if game_id.is_empty():
			var playable: Array[Dictionary] = registry.playable()
			game_id = str(playable[0]["id"]) if not playable.is_empty() else ""
		var scene: LobbyScene = open_host_lobby(game_id)
		if scene == null:
			_set_error("Cannot host \"%s\"." % game_id)
			return
		scene.host_session()
	elif mode == "join":
		var scene: LobbyScene = open_join_lobby()
		if launch_options.has("join"):
			scene.address_edit.text = str(launch_options["join"])
			scene.join_session()
		else:
			_auto_join_pending = true


func _set_error(text: String) -> void:
	error_label.text = text
	error_label.visible = text != ""
