class_name PaperCard
extends PanelContainer
## A cream paper card with a coloured card peeking out behind it, offset to the bottom right
## (light from the top left), as in the design. Put content inside it like in any container.

## The colour of the card behind. Change it before the card is shown, or call queue_redraw on `back`.
@export var back_color: Color = Tokens.DEEP_TEAL
## How far the card behind peeks out, in pixels.
@export var back_offset: Vector2 = Vector2(8, 10)
@export var corner_radius: int = 28

var back: Control


func _init() -> void:
	var front: StyleBoxFlat = StyleBoxFlat.new()
	front.bg_color = Tokens.PAPER_CREAM
	front.set_corner_radius_all(corner_radius)
	front.shadow_color = Color(Tokens.INK, 0.25)
	front.shadow_size = 7
	front.shadow_offset = Vector2(3, 5)
	front.set_content_margin_all(Tokens.SPACE_M)
	add_theme_stylebox_override("panel", front)
	back = Control.new()
	back.show_behind_parent = true
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.draw.connect(_draw_back)
	add_child(back)


func _draw_back() -> void:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = back_color
	box.set_corner_radius_all(corner_radius)
	box.shadow_color = Color(Tokens.INK, 0.3)
	box.shadow_size = 4
	box.shadow_offset = Vector2(2, 3)
	# the container sizes `back` to the card's content area, so measure from the card itself
	back.draw_style_box(box, Rect2(back_offset - back.position, size))
