class_name AppTheme
extends RefCounted
## Builds the shared Theme from Tokens: flat cut-paper shapes, short soft shadow
## from the top-left light (so shadow falls bottom-right), no outlines or gradients.


const FONT_PATH: String = "res://core/assets/fonts/Fredoka.ttf"
const FALLBACK_FONT_PATH: String = "res://core/assets/fonts/Baloo2.ttf"  # Devanagari (and Vietnamese) names


## Fredoka for text; Baloo 2 fills in the scripts Fredoka does not have (both OFL 1.1).
static func build_font() -> Font:
	var font: FontFile = load(FONT_PATH)
	var fallback: FontFile = load(FALLBACK_FONT_PATH)
	var combined: FontVariation = FontVariation.new()
	combined.base_font = font
	combined.fallbacks = [fallback]
	return combined


static func build() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font = build_font()
	theme.default_font_size = Tokens.FONT_SIZE

	theme.set_color("font_color", "Label", Tokens.INK)
	theme.set_font_size("font_size", "Label", Tokens.FONT_SIZE)

	# Buttons are pills with a hard shadow underneath that flattens when pressed (like the design).
	# Variations: "PrimaryButton" (terracotta, the one main action) and "CreamButton" (quiet).
	_pill_button(theme, "Button", Tokens.DEEP_TEAL, Tokens.PAPER_CREAM)
	theme.set_type_variation("PrimaryButton", "Button")
	_pill_button(theme, "PrimaryButton", Tokens.TERRACOTTA, Tokens.PAPER_CREAM)
	theme.set_type_variation("CreamButton", "Button")
	_pill_button(theme, "CreamButton", Tokens.PAPER_CREAM.darkened(0.07), Tokens.INK)

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

	# check buttons are plain rows of text with a switch, not teal buttons
	for state: String in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
		var flat: StyleBoxEmpty = StyleBoxEmpty.new()
		flat.content_margin_top = Tokens.SPACE_S / 2.0
		flat.content_margin_bottom = Tokens.SPACE_S / 2.0
		theme.set_stylebox(state, "CheckButton", flat)
	theme.set_color("font_disabled_color", "CheckButton", Tokens.INK.lerp(Tokens.PAPER_CREAM, 0.55))
	theme.set_color("font_color", "CheckButton", Tokens.INK)
	theme.set_color("font_hover_color", "CheckButton", Tokens.INK)
	theme.set_color("font_pressed_color", "CheckButton", Tokens.INK)
	theme.set_constant("separation", "VBoxContainer", Tokens.SPACE_M)
	theme.set_constant("separation", "HBoxContainer", Tokens.SPACE_S)
	return theme


static func _pill_button(theme: Theme, type_name: String, color: Color, text: Color) -> void:
	var colors: Dictionary = {
		"normal": color,
		"hover": color.lightened(0.1),
		"pressed": color.darkened(0.12),
		"disabled": color.lerp(Tokens.PAPER_CREAM, 0.6) if color != Tokens.PAPER_CREAM else Tokens.PAPER_CREAM.darkened(0.08),
	}
	for state: String in colors:
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = colors[state]
		box.set_corner_radius_all(40)
		box.content_margin_left = Tokens.SPACE_L
		box.content_margin_right = Tokens.SPACE_L
		var pressed: bool = state == "pressed"
		box.content_margin_top = Tokens.SPACE_S + (3 if pressed else 0)
		box.content_margin_bottom = Tokens.SPACE_S - (3 if pressed else 0)
		if state != "disabled":
			box.shadow_color = Color(Tokens.INK, 0.32)
			box.shadow_size = 1
			box.shadow_offset = Vector2(0, 2 if pressed else 5)
		theme.set_stylebox(state, type_name, box)
	theme.set_stylebox("focus", type_name, StyleBoxEmpty.new())
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(color_name, type_name, text)
	theme.set_color("font_disabled_color", type_name, text.lerp(Tokens.PAPER_CREAM, 0.45) if text != Tokens.INK else Tokens.INK.lerp(Tokens.PAPER_CREAM, 0.5))


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
