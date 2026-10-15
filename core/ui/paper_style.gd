class_name PaperStyle
extends RefCounted
## Small flat "paper" looks shared by the lobby and the connection panel: pills, titles, inset
## fields, segmented toggles and tinted notices. Flat colours, rounded corners, no gradients.


## A label drawn as a pill (a rounded chip): "Ready", "Not ready", ...
static func pill(label: Label, fill: Color, text: Color) -> void:
	label.add_theme_stylebox_override("normal", _box(fill, 22, 14, 4))
	label.add_theme_color_override("font_color", text)
	label.add_theme_font_size_override("font_size", 17)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER


## A small muted heading for a section.
static func caption(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Tokens.INDIGO)


## A big indigo heading (card titles, "Host a game").
static func title(label: Label, font_size: int = 34) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Tokens.INDIGO)


## A label on a tinted rounded box (notices, house rules).
static func notice(label: Label, fill: Color, text: Color = Tokens.INK) -> void:
	label.add_theme_stylebox_override("normal", _box(fill, 14, 12, 8))
	label.add_theme_color_override("font_color", text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Error and status text.
static func error(label: Label) -> void:
	label.add_theme_color_override("font_color", Tokens.TERRACOTTA)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## A slightly darker cream rounded box to group related controls.
static func group_box() -> StyleBoxFlat:
	return _box(Tokens.PAPER_CREAM.darkened(0.05), 18, 14, 10)


## A smaller pill button (for rows and secondary actions).
static func small_button(button: Button, variation: StringName = &"CreamButton") -> void:
	button.theme_type_variation = variation
	button.add_theme_font_size_override("font_size", 17)


## A text field that looks pressed into the paper (the design's inset fields): a darker cream
## well with a darker top and left edge, where the shadow falls.
static func inset_field(field: LineEdit, font_size: int = 20) -> void:
	var well: StyleBoxFlat = inset_box()
	for state: String in ["normal", "focus", "read_only"]:
		field.add_theme_stylebox_override(state, well)
	field.add_theme_font_size_override("font_size", font_size)
	field.custom_minimum_size.y = 40.0


## Marks a text field as having a problem (a rose edge all round) or clears the mark again.
static func mark_field_error(field: LineEdit, on: bool) -> void:
	if not on:
		inset_field(field, field.get_theme_font_size("font_size"))
		return
	var well: StyleBoxFlat = inset_box()
	well.set_border_width_all(3)
	well.border_color = Tokens.ROSE
	for state: String in ["normal", "focus", "read_only"]:
		field.add_theme_stylebox_override(state, well)


static func inset_box(radius: int = 18) -> StyleBoxFlat:
	var box: StyleBoxFlat = _box(Tokens.PAPER_CREAM.darkened(0.06), radius, 16, 8)
	box.border_width_top = 3
	box.border_width_left = 3
	box.border_color = Color(Tokens.INK, 0.2)
	return box


## The track of a segmented control (two or more pills side by side in an inset well).
static func segment_track() -> StyleBoxFlat:
	var box: StyleBoxFlat = inset_box(26)
	box.set_content_margin_all(4)
	return box


## One pill of a segmented control: selected = teal on cream text with a small drop shadow.
static func segment(button: Button, selected: bool) -> void:
	var box: StyleBoxFlat = _box(Tokens.DEEP_TEAL if selected else Color(0, 0, 0, 0), 22, 14, 6)
	if selected:
		box.shadow_color = Color(Tokens.INK, 0.3)
		box.shadow_size = 2
		box.shadow_offset = Vector2(1, 3)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		button.add_theme_stylebox_override(state, box)
	var text: Color = Tokens.PAPER_CREAM if selected else Tokens.INK
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		button.add_theme_color_override(color_name, text)
	button.add_theme_font_size_override("font_size", 18)


## A thin dashed rule between two sections.
static func dashed_rule(height: float = 10.0) -> Control:
	var rule: DashedRule = DashedRule.new()
	rule.custom_minimum_size.y = height
	return rule


static func _box(fill: Color, radius: int, margin_x: int, margin_y: int) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	return box


## A dashed line across the full width, in a soft indigo.
class DashedRule:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var y: float = size.y / 2.0
		var x: float = 0.0
		while x < size.x:
			draw_line(Vector2(x, y), Vector2(minf(x + 10.0, size.x), y), Color(Tokens.INDIGO, 0.35), 2.0)
			x += 16.0
