class_name PaperRow
extends HBoxContainer
## A row of a list drawn as a cream pill with a soft paper shadow, padded inside. It is a plain
## HBoxContainer to everything else: its children are exactly what the caller adds (no spacer
## nodes), the padding is applied after the container has sorted them.

const PAD: float = 10.0

var fill: Color = Tokens.PAPER_CREAM.lightened(0.3)
## The pill's height; the corners are as round as that allows.
var row_height: float = 56.0:
	set(value):
		row_height = value
		custom_minimum_size.y = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size.y = row_height
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(int(minf(size.y, row_height) / 2.0))
	box.shadow_color = Color(Tokens.INK, 0.22)
	box.shadow_size = 3
	box.shadow_offset = Vector2(1, 3)
	draw_style_box(box, Rect2(Vector2.ZERO, size))


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	var children: Array[Control] = []
	for child: Node in get_children():
		var control: Control = child as Control
		if control != null and control.visible and not control.top_level:
			children.append(control)
	if children.size() < 2:
		return
	# the first child stretches; everything after it moves left, so the strip has a right margin
	children[0].size.x = maxf(0.0, children[0].size.x - PAD)
	for i: int in range(1, children.size()):
		children[i].position.x -= PAD
	queue_redraw()
