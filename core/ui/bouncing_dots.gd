class_name BouncingDots
extends Control
## A row of calm bouncing paper dots ("waiting..."), as in the design's Reconnecting card. It only
## animates while it is visible on screen, so a hidden card costs nothing.

const COLORS: Array = [Tokens.SAFFRON, Tokens.TERRACOTTA, Tokens.ROSE, Tokens.DEEP_TEAL, Tokens.INDIGO]

@export var dot_count: int = 5
@export var dot_radius: float = 7.0
@export var spacing: float = 12.0

var _time: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(dot_count * (dot_radius * 2.0 + spacing) - spacing + 6.0, dot_radius * 2.0 + 22.0)
	set_process(false)
	visibility_changed.connect(_on_visibility_changed)


## The vertical offset of dot `index` at time `t` (negative = up). Public so it can be tested.
static func bounce(index: int, t: float) -> float:
	return -9.0 * maxf(0.0, sin(t * 4.0 - float(index) * 0.7))


func is_animating() -> bool:
	return is_processing()


func _on_visibility_changed() -> void:
	set_process(is_visible_in_tree())


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var baseline: float = size.y - dot_radius - 4.0
	for i: int in dot_count:
		var x: float = 3.0 + dot_radius + float(i) * (dot_radius * 2.0 + spacing)
		var centre: Vector2 = Vector2(x, baseline + bounce(i, _time))
		draw_circle(centre + Vector2(1, 2), dot_radius, Color(Tokens.INK, 0.28))
		draw_circle(centre, dot_radius, COLORS[i % COLORS.size()])
