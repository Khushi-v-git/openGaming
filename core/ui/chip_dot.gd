class_name ChipDot
extends Control
## The round dot at the left of a status chip (design section 14): a cream dot with a green check
## when the player is ready, an empty pale dot when not. Put it inside the chip's label.

const DIAMETER: float = 30.0
## The design's check mark, in 0..1 coordinates of the dot.
const CHECK: Array = [Vector2(0.22, 0.52), Vector2(0.32, 0.42), Vector2(0.44, 0.58), Vector2(0.70, 0.28), Vector2(0.80, 0.38), Vector2(0.44, 0.78)]

var ready_mark: bool = false:
	set(value):
		ready_mark = value
		queue_redraw()


func _init(is_ready: bool = false) -> void:
	ready_mark = is_ready
	custom_minimum_size = Vector2(DIAMETER, DIAMETER)
	size = Vector2(DIAMETER, DIAMETER)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var middle: Vector2 = Vector2(DIAMETER, DIAMETER) / 2.0
	if not ready_mark:
		draw_circle(middle, DIAMETER / 2.0, Color("#E4DCC6"))
		return
	draw_circle(middle, DIAMETER / 2.0, Tokens.PAPER_CREAM)
	var check: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in CHECK:
		check.append(point * DIAMETER)
	draw_colored_polygon(check, Tokens.FOREST_GREEN)
