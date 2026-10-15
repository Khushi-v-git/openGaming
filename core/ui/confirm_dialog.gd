class_name ConfirmDialog
extends Control
## The "are you sure?" card (design section 13): a dimmed screen, a cream paper card with a
## coloured card behind it, a round badge, a title, one line of text and pill buttons. The first
## button is the safe one: it has the keyboard focus when the card opens, and Escape chooses it.
## Enter chooses the focused button. The card frees itself after a choice.
##
##   ConfirmDialog.ask(self, ConfirmDialog.leave_lobby(), func(id: String) -> void: ...)
##
## config: {badge: "door" | "bang" | "pawn", back: Color, title, body, pawn_color: String,
##          stacked: bool, buttons: [{id, label, kind: "cream" | "teal" | "terracotta"}]}

signal chosen(button_id: String)

## Tests set this to answer every question with its last (destructive) button at once.
static var auto_confirm: bool = false

const CARD_WIDTH: float = 700.0
const CARD_WIDTH_STACKED: float = 640.0
const BADGE: float = 92.0
const PAWN_COLORS: Dictionary = {
	"red": Tokens.PLAYER_RED, "blue": Tokens.PLAYER_BLUE, "green": Tokens.PLAYER_GREEN, "yellow": Tokens.PLAYER_YELLOW,
}

var config: Dictionary = {}
var card: PaperCard
var title_label: Label
var body_label: Label
var badge: Control
var buttons: Array[Button] = []

var _done: bool = false


## Opens the question on `parent` (it covers everything under it). `on_choice` gets the button id.
## With auto_confirm the last button is chosen at once and nothing is shown.
static func ask(parent: Node, new_config: Dictionary, on_choice: Callable = Callable()) -> ConfirmDialog:
	var dialog: ConfirmDialog = ConfirmDialog.new()
	dialog.config = new_config
	if on_choice.is_valid():
		dialog.chosen.connect(on_choice)
	if auto_confirm:
		var list: Array = new_config["buttons"]
		dialog._done = true
		dialog.chosen.emit(str((list[list.size() - 1] as Dictionary)["id"]))
		dialog.free()
		return null
	parent.add_child(dialog)
	return dialog


# --- the questions the app asks ---------------------------------------------------------------------------------

static func leave_lobby() -> Dictionary:
	return {"badge": "door", "back": Tokens.SAFFRON, "title": "Leave this lobby?", "body": "You can join again with the room code.",
		"buttons": [_button("stay", "Stay", "cream"), _button("leave", "Leave", "terracotta")]}


static func close_room() -> Dictionary:
	return {"badge": "bang", "back": Tokens.ROSE, "title": "Close the room for everyone?", "body": "Everyone is sent back to the home screen.",
		"buttons": [_button("stay", "Keep hosting", "cream"), _button("close", "Close room", "terracotta")]}


static func leave_game() -> Dictionary:
	return {"badge": "door", "back": Tokens.SAFFRON, "title": "Leave this game?", "body": "Your seat is kept for a while, so you can rejoin.",
		"buttons": [_button("stay", "Stay", "cream"), _button("leave", "Leave game", "terracotta")]}


static func end_game_for_all() -> Dictionary:
	return {"badge": "bang", "back": Tokens.ROSE, "stacked": true, "title": "End the game for everyone?", "body": "Players will go back to the lobby.",
		"buttons": [_button("stay", "Keep playing", "cream"), _button("lobby", "Back to lobby", "teal"), _button("close", "Close room", "terracotta")]}


static func leave_hotseat() -> Dictionary:
	return {"badge": "door", "back": Tokens.SAFFRON, "title": "Leave this game?", "body": "Its progress will be lost.",
		"buttons": [_button("stay", "Stay", "cream"), _button("leave", "Leave", "terracotta")]}


static func remove_player(player_name: String, pawn_color: String) -> Dictionary:
	return {"badge": "pawn", "back": PAWN_COLORS.get(pawn_color, Tokens.DEEP_TEAL), "pawn_color": pawn_color,
		"title": "Remove %s for good?" % player_name, "body": "They can't come back to this game.",
		"buttons": [_button("stay", "Keep", "cream"), _button("remove", "Remove", "terracotta")]}


static func _button(id: String, label: String, kind: String) -> Dictionary:
	return {"id": id, "label": label, "kind": kind}


# --- building --------------------------------------------------------------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = AppTheme.build()  # looks the same over any screen, themed or not
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(Tokens.INK, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	card = PaperCard.new()
	card.corner_radius = 36
	card.back_offset = Vector2(10, 12)
	card.back_color = config.get("back", Tokens.SAFFRON)
	var front: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	front.set_corner_radius_all(36)
	front.set_content_margin_all(36)
	card.add_theme_stylebox_override("panel", front)
	center.add_child(card)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	card.add_child(column)

	badge = Badge.new(str(config.get("badge", "door")), config.get("back", Tokens.SAFFRON), str(config.get("pawn_color", "")))
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(badge)

	title_label = Label.new()
	title_label.text = str(config.get("title", ""))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	PaperStyle.title(title_label, 36)
	column.add_child(title_label)

	body_label = Label.new()
	body_label.text = str(config.get("body", ""))
	body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size", 22)
	column.add_child(body_label)

	var spacer: Control = Control.new()
	spacer.custom_minimum_size.y = 6.0
	column.add_child(spacer)

	var stacked: bool = bool(config.get("stacked", false))
	var row: BoxContainer = VBoxContainer.new() if stacked else HBoxContainer.new()
	row.add_theme_constant_override("separation", 14 if stacked else 20)
	column.add_child(row)
	for entry: Dictionary in config["buttons"]:
		row.add_child(_make_button(entry))

	resized.connect(_fit)
	_fit()
	if not buttons.is_empty():
		buttons[0].grab_focus.call_deferred()
	var parent_control: Control = get_parent() as Control
	if parent_control != null:
		parent_control.visibility_changed.connect(_parent_visibility_changed)


## Narrower on a small window; the design's 700 px (640 stacked) otherwise.
func _fit() -> void:
	if card == null:
		return
	var wanted: float = CARD_WIDTH_STACKED if bool(config.get("stacked", false)) else CARD_WIDTH
	card.custom_minimum_size.x = minf(wanted, maxf(280.0, size.x - 64.0))
	var narrow: bool = size.x < 700.0
	for button: Button in buttons:
		button.add_theme_font_size_override("font_size", 20 if narrow else 26)
	var front: StyleBoxFlat = card.get_theme_stylebox("panel") as StyleBoxFlat
	if front != null:
		front.set_content_margin_all(20 if narrow else 36)


func _make_button(entry: Dictionary) -> Button:
	var button: Button = Button.new()
	button.text = str(entry["label"])
	match str(entry.get("kind", "cream")):
		"cream":
			button.theme_type_variation = &"CreamButton"
		"terracotta":
			button.theme_type_variation = &"PrimaryButton"
	button.custom_minimum_size = Vector2(0.0, 64.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 26)
	button.add_theme_stylebox_override("focus", _ring())
	var id: String = str(entry["id"])
	button.pressed.connect(func() -> void: _choose(id))
	buttons.append(button)
	return button


## The keyboard focus mark: a saffron ring 4 px outside the button.
func _ring() -> StyleBoxFlat:
	var ring: StyleBoxFlat = StyleBoxFlat.new()
	ring.draw_center = false
	ring.set_border_width_all(4)
	ring.border_color = Tokens.SAFFRON
	ring.set_corner_radius_all(40)
	ring.set_expand_margin_all(4.0)
	return ring


func _choose(id: String) -> void:
	if _done:
		return
	_done = true
	chosen.emit(id)
	queue_free()


## Escape = the first (safe) button; Enter = the focused button.
func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or buttons.is_empty() or _done:
		return
	if key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		buttons[0].pressed.emit()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		get_viewport().set_input_as_handled()
		var focused: Control = get_viewport().gui_get_focus_owner()
		var target: Button = focused as Button if focused != null and buttons.has(focused) else buttons[0]
		target.pressed.emit()


## The question belongs to the screen it was asked on: if that screen hides, so does the question.
func _parent_visibility_changed() -> void:
	var parent_control: Control = get_parent() as Control
	if parent_control != null and not parent_control.visible and not _done:
		_done = true
		queue_free()


## The round badge: a coloured disc with a small drawn picture (a door with an arrow, a "!", or the
## player's pawn), lifted off the card by a soft shadow.
class Badge:
	extends Control

	var kind: String
	var fill: Color
	var pawn: Texture2D = null

	func _init(new_kind: String, new_fill: Color, pawn_color: String) -> void:
		kind = new_kind
		fill = new_fill if new_kind != "pawn" else Tokens.PAPER_CREAM.darkened(0.1)
		custom_minimum_size = Vector2(ConfirmDialog.BADGE, ConfirmDialog.BADGE)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if new_kind == "pawn":
			pawn = load("res://core/assets/pawn-%s.svg" % (pawn_color if ConfirmDialog.PAWN_COLORS.has(pawn_color) else "red"))

	func _draw() -> void:
		var middle: Vector2 = Vector2(ConfirmDialog.BADGE, ConfirmDialog.BADGE) / 2.0
		var radius: float = ConfirmDialog.BADGE / 2.0 - 4.0
		draw_circle(middle + Vector2(2.0, 4.0), radius, Color(Tokens.INK, 0.28))
		draw_circle(middle, radius, fill)
		match kind:
			"door":
				_draw_door(middle)
			"bang":
				_draw_bang(middle)
			"pawn":
				if pawn != null:
					var edge: float = ConfirmDialog.BADGE * 0.72
					draw_texture_rect(pawn, Rect2(middle - Vector2(edge, edge) / 2.0, Vector2(edge, edge)), false)

	## A door (cream slab, ink handle) with an arrow leaving through it.
	func _draw_door(middle: Vector2) -> void:
		var door: Rect2 = Rect2(middle + Vector2(-22.0, -24.0), Vector2(24.0, 48.0))
		draw_rect(door, Tokens.PAPER_CREAM)
		draw_circle(door.position + Vector2(18.0, 24.0), 2.5, Tokens.INK)
		var arrow: PackedVector2Array = PackedVector2Array([
			middle + Vector2(2.0, -6.0), middle + Vector2(14.0, -6.0), middle + Vector2(14.0, -14.0),
			middle + Vector2(28.0, 0.0), middle + Vector2(14.0, 14.0), middle + Vector2(14.0, 6.0), middle + Vector2(2.0, 6.0),
		])
		draw_colored_polygon(arrow, Tokens.INDIGO)

	## A cream exclamation mark.
	func _draw_bang(middle: Vector2) -> void:
		draw_rect(Rect2(middle + Vector2(-5.0, -26.0), Vector2(10.0, 30.0)), Tokens.PAPER_CREAM)
		draw_circle(middle + Vector2(0.0, -26.0), 5.0, Tokens.PAPER_CREAM)
		draw_circle(middle + Vector2(0.0, 4.0), 5.0, Tokens.PAPER_CREAM)
		draw_circle(middle + Vector2(0.0, 19.0), 6.0, Tokens.PAPER_CREAM)
