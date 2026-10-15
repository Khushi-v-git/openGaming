class_name ReadyPill
extends Button
## The guest's "I'm ready" control (design section 14): a big paper pill that toggles. It is an
## ordinary toggle Button (button_pressed, pressed, toggled work as with any check button).
##
##   not ready  cream pill, indigo "I'm ready", an empty terracotta-edged dot
##   ready      forest-green pill, cream "Ready!", a cream dot with a check on a saffron starburst
##   disabled   flat pale pill and grey text (the game has started)
## Hovering lifts the pill (a longer hard shadow); pressing it sinks it 4 px.

const STARBURST: String = "res://core/assets/starburst-saffron.svg"
const DISABLED_FILL: Color = Color("#E4DCC6")
const DISABLED_TEXT: Color = Color("#8A8576")
const DISABLED_EDGE: Color = Color("#B5AE9B")

var _hover: bool = false
var _down: bool = false
var _look_key: String = ""
var _decor: Decor
var _starburst: Texture2D


func _init() -> void:
	toggle_mode = true
	text = "I'm ready"
	custom_minimum_size = Vector2(0.0, 84.0)
	focus_mode = Control.FOCUS_ALL
	add_theme_font_size_override("font_size", 32)
	_starburst = load(STARBURST)
	_decor = Decor.new(self)
	add_child(_decor)
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))
	button_down.connect(_set_down.bind(true))
	button_up.connect(_set_down.bind(false))
	_apply_look()


func _ready() -> void:
	set_process(true)  # toggling, hovering, pressing, enabling: dressed at once, never from inside a draw
	_apply_look()


func _process(_delta: float) -> void:
	_apply_look()


## Re-dress the pill when its state changed (called from the decor's draw, which runs whenever
## the button redraws: toggling, hovering, pressing, enabling).
func refresh() -> void:
	_apply_look()


func _set_hover(on: bool) -> void:
	_hover = on
	queue_redraw()


func _set_down(on: bool) -> void:
	_down = on
	queue_redraw()


func is_ready_look() -> bool:
	return button_pressed and not disabled


func _apply_look() -> void:
	var key: String = "%s|%s|%s|%s" % [disabled, button_pressed, _hover, _down]
	if key == _look_key:
		return
	_look_key = key
	var fill: Color = Tokens.PAPER_CREAM
	var ink: Color = Tokens.INDIGO
	var shadow_y: int = 6
	if disabled:
		fill = DISABLED_FILL
		ink = DISABLED_TEXT
		shadow_y = 3
	elif button_pressed:
		fill = Tokens.FOREST_GREEN
		ink = Tokens.PAPER_CREAM
	if not disabled:
		if _down:
			shadow_y = 2
		elif _hover:
			shadow_y = 8
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(48)
	box.content_margin_left = 84.0
	box.content_margin_right = 24.0
	var sink: int = 4 if (_down and not disabled) else 0
	box.content_margin_top = 8 + sink
	box.content_margin_bottom = 8 - sink
	box.shadow_color = Color(Tokens.INK, 0.15 if disabled else 0.32)
	box.shadow_size = 1
	box.shadow_offset = Vector2(0, shadow_y)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, box)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(color_name, ink)
	text = "Ready!" if is_ready_look() else "I'm ready"
	if _decor != null:
		_decor.queue_redraw()


## The dot (and the starburst behind it), drawn over the pill, ignoring the mouse.
class Decor:
	extends Control

	var pill: ReadyPill

	func _init(owner_pill: ReadyPill) -> void:
		pill = owner_pill
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var scale_by: float = clampf(size.y / 96.0, 0.6, 1.2)
		var diameter: float = 54.0 * scale_by
		var sink: float = 4.0 if pill._down and not pill.disabled else 0.0
		var middle: Vector2 = Vector2(21.0 * scale_by + diameter / 2.0, size.y / 2.0 + sink)
		if pill.is_ready_look():
			var burst: float = 112.0 * scale_by
			draw_texture_rect(pill._starburst, Rect2(middle - Vector2(burst, burst) / 2.0, Vector2(burst, burst)), false)
			draw_circle(middle + Vector2(1.0, 2.0), diameter / 2.0, Color(Tokens.INK, 0.35))
			draw_circle(middle, diameter / 2.0, Tokens.PAPER_CREAM)
			var check: PackedVector2Array = PackedVector2Array()
			for point: Vector2 in ChipDot.CHECK:
				check.append(middle - Vector2(diameter, diameter) / 2.0 + point * diameter)
			draw_colored_polygon(check, Tokens.FOREST_GREEN)
			return
		var edge: Color = ReadyPill.DISABLED_EDGE if pill.disabled else Tokens.TERRACOTTA
		draw_circle(middle, diameter / 2.0, Tokens.PAPER_CREAM)
		if not pill.disabled:  # the inset shadow falls from the top left
			draw_arc(middle + Vector2(1.5, 2.0), diameter / 2.0 - 5.0, PI * 0.9, PI * 1.6, 24, Color(Tokens.INK, 0.25), 3.0)
		draw_arc(middle, diameter / 2.0 - 2.0, 0.0, TAU, 48, edge, 4.0, true)
