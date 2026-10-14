class_name AppTheme
extends RefCounted
## Builds the shared Theme from Tokens: flat cut-paper shapes, short soft shadow
## from the top-left light (so shadow falls bottom-right), no outlines or gradients.


static func build() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font_size = Tokens.FONT_SIZE

	theme.set_color("font_color", "Label", Tokens.INK)
	theme.set_font_size("font_size", "Label", Tokens.FONT_SIZE)

	var button_colors: Dictionary = {
		"normal": Tokens.DEEP_TEAL,
		"hover": Tokens.DEEP_TEAL.lightened(0.12),
		"pressed": Tokens.DEEP_TEAL.darkened(0.15),
		"disabled": Tokens.DEEP_TEAL.lerp(Tokens.PAPER_CREAM, 0.6),
	}
	for state: String in button_colors:
		theme.set_stylebox(state, "Button", _paper(button_colors[state], state != "pressed"))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		theme.set_color(color_name, "Button", Tokens.PAPER_CREAM)

	var field: StyleBoxFlat = _paper(Tokens.PAPER_CREAM.darkened(0.06), false)
	field.content_margin_left = Tokens.SPACE_M
	field.content_margin_right = Tokens.SPACE_M
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", field)
	theme.set_stylebox("read_only", "LineEdit", field)
	theme.set_color("font_color", "LineEdit", Tokens.INK)
	theme.set_color("font_placeholder_color", "LineEdit", Tokens.INK.lerp(Tokens.PAPER_CREAM, 0.5))

	var panel: StyleBoxFlat = _paper(Tokens.PAPER_CREAM, true)
	panel.content_margin_left = Tokens.SPACE_L
	panel.content_margin_right = Tokens.SPACE_L
	panel.content_margin_top = Tokens.SPACE_L
	panel.content_margin_bottom = Tokens.SPACE_L
	theme.set_stylebox("panel", "PanelContainer", panel)

	theme.set_color("font_color", "CheckButton", Tokens.INK)
	theme.set_color("font_hover_color", "CheckButton", Tokens.INK)
	theme.set_color("font_pressed_color", "CheckButton", Tokens.INK)
	theme.set_constant("separation", "VBoxContainer", Tokens.SPACE_M)
	theme.set_constant("separation", "HBoxContainer", Tokens.SPACE_S)
	return theme


static func _paper(color: Color, with_shadow: bool) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(Tokens.RADIUS)
	box.content_margin_left = Tokens.SPACE_M
	box.content_margin_right = Tokens.SPACE_M
	box.content_margin_top = Tokens.SPACE_S
	box.content_margin_bottom = Tokens.SPACE_S
	if with_shadow:
		box.shadow_color = Color(Tokens.INK, 0.22)
		box.shadow_size = 3
		box.shadow_offset = Vector2(2, 3)
	return box
