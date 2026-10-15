class_name GameBadge
extends Control
## A small geometric badge for a game card: a coloured disc, a turned rounded square on it and a
## small round dot, all cut-paper style with a soft shadow to the bottom right (as in the design's
## home screen). Pure drawing, no textures. `palette` picks the three colours; `seed_value` makes
## the badge of one game always the same.

const PALETTES: Array = [
	[Tokens.SAFFRON, Tokens.DEEP_TEAL, Tokens.TERRACOTTA],
	[Tokens.ROSE, Tokens.INDIGO, Tokens.PAPER_CREAM],
	[Tokens.FOREST_GREEN, Tokens.SAFFRON, Tokens.ROSE],
	[Tokens.INDIGO, Tokens.TERRACOTTA, Tokens.SAFFRON],
]

@export var badge_size: float = 110.0

var disc: Color = Tokens.SAFFRON
var square: Color = Tokens.DEEP_TEAL
var dot: Color = Tokens.TERRACOTTA


## The colours for the game at `index` in the list (they cycle).
static func colors_for(index: int) -> Array:
	return PALETTES[posmod(index, PALETTES.size())]


func use_palette(index: int) -> void:
	var colors: Array = colors_for(index)
	disc = colors[0]
	square = colors[1]
	dot = colors[2]
	queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(badge_size + 10.0, badge_size + 12.0)


func _draw() -> void:
	var centre: Vector2 = Vector2(size.x / 2.0, (size.y - 6.0) / 2.0)
	var radius: float = badge_size / 2.0
	var shade: Color = Color(Tokens.INK, 0.28)
	draw_circle(centre + Vector2(3, 5), radius, shade)
	draw_circle(centre, radius, disc)
	var half: float = radius * 0.5
	var turned: Transform2D = Transform2D(deg_to_rad(45.0), centre)
	draw_set_transform_matrix(turned)
	var rounded: StyleBoxFlat = StyleBoxFlat.new()
	rounded.set_corner_radius_all(int(radius * 0.18))
	rounded.shadow_color = Color(Tokens.INK, 0.3)
	rounded.shadow_size = 3
	rounded.shadow_offset = Vector2(2, 3)
	rounded.bg_color = square
	draw_style_box(rounded, Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0)))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_circle(centre + Vector2(1, 2), radius * 0.22, shade)
	draw_circle(centre, radius * 0.22, dot)
