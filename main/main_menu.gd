class_name MainMenu
extends Control
## The home screen: a list of games built from the registry, and a hot-seat setup screen
## ("Play on this computer"). It knows no game by name: it reads manifests, asks the game's own
## settings scene for settings, and hands the game's UI scene a controller.
##
## Hosting and joining over the network come later; this is the one-window path.

signal game_started(game_id: String)

const MAX_NAME_LENGTH: int = 20

var registry: GameRegistry
var game_list: VBoxContainer
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


func _ready() -> void:
	theme = AppTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if registry == null:
		registry = GameRegistry.new()
		var loaded: Dictionary = registry.load_from()
		if not (loaded.get("errors", []) as Array).is_empty():
			push_error("Some games could not be loaded: %s" % str(loaded["errors"]))
	_build()
	show_game_list()


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


## The playable games, one button each.
func show_game_list() -> void:
	_selected_id = ""
	setup_panel.visible = false
	game_list.visible = true
	_set_error("")
	for child: Node in game_list.get_children():
		game_list.remove_child(child)
		child.queue_free()
	for manifest: Dictionary in registry.playable():
		var button: Button = Button.new()
		button.text = "%s\n%s" % [manifest["display_name"], manifest["description"]]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 72)
		button.set_meta("game_id", manifest["id"])
		button.pressed.connect(func() -> void: choose_game(manifest["id"]))
		game_list.add_child(button)


## Opens the "play on this computer" setup for a game.
func choose_game(game_id: String) -> void:
	if not registry.has_ui(game_id):
		return
	_selected_id = game_id
	var manifest: Dictionary = registry.get_manifest(game_id)
	game_list.visible = false
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


func _set_error(text: String) -> void:
	error_label.text = text
	error_label.visible = text != ""
