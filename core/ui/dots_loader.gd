class_name DotsLoader
extends Control
## Five coloured paper dots that bounce in turn: "something is happening". It only animates while
## it is visible on screen, so a hidden loader costs nothing.

const COLORS: Array[Color] = [Tokens.TERRACOTTA, Tokens.SAFFRON, Tokens.FOREST_GREEN, Tokens.ROSE, Tokens.INDIGO]

var _time: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(150.0, 64.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(_update_processing)
	set_process(false)


func _enter_tree() -> void:
	_update_processing()


func _update_processing() -> void:
	set_process(is_visible_in_tree())


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var radius: float = 11.0
	var gap: float = (size.x - 2.0 * radius) / float(COLORS.size() - 1)
	for i: int in COLORS.size():
		var wave: float = maxf(0.0, sin(_time * 5.0 - float(i) * 0.7))
		var center: Vector2 = Vector2(radius + gap * float(i), size.y - radius - 6.0 - wave * (size.y - 2.0 * radius - 12.0))
		draw_circle(center + Vector2(2.0, 3.0), radius, Color(Tokens.INK, 0.25))
		draw_circle(center, radius, COLORS[i])
