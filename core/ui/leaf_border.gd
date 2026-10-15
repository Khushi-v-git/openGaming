class_name LeafBorder
extends Control
## A border of paper-cut leaves round the edges of its own rectangle (the look of the design's
## "Leaves" component). Deterministic: the same size always gives the same leaves, so every screen
## and every player sees the same border. Everything is polygons from _draw (no textures), laid
## out once per size change and redrawn only when asked to, never per frame.
##
## Leaves scale with min(width, height) / 1080 and are spaced in proportion, so the border looks
## the same at 1280x720 and 1920x1080.

const SEED: int = 7
const REFERENCE: float = 1080.0
const SPACING: float = 118.0
const ARC_POINTS: int = 9
const SHADOW: Color = Color(0.1686, 0.1647, 0.2, 0.28)  # ink at 28%
## Colour pairs [outer leaf, inner leaf] from the design.
const PAIRS: Array = [
	["#1F6F6B", "#2F6B4F"], ["#2F6B4F", "#1F6F6B"], ["#1F6F6B", "#F0A93B"],
	["#2F6B4F", "#D2603E"], ["#2E3A6B", "#1F6F6B"], ["#2F6B4F", "#C94F6D"],
]

## Built by _layout(): [{shadow, outer, inner_shadow, inner, c1, c2, offset}] (read by tests).
var leaves: Array[Dictionary] = []
## How many times the leaves were laid out (tests check it only changes on a size change).
var layout_count: int = 0

var _laid_out_for: Vector2 = Vector2.ZERO
var _state: int = SEED


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	resized.connect(_layout)
	_layout()


## The scale factor for a rectangle: 1 at 1080 px on the short side.
static func scale_for(rect_size: Vector2) -> float:
	return maxf(0.2, minf(rect_size.x, rect_size.y) / REFERENCE)


## The corners of one leaf, a box of w x h whose top-left is at the origin: two quarter-ellipse arcs
## meeting at the top-right and bottom-left corners (CSS border-radius: 100% 0 100% 0).
static func leaf_points(w: float, h: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in ARC_POINTS + 1:  # from the bottom-left corner up and over to the top-right
		var a: float = PI + (PI / 2.0) * float(i) / float(ARC_POINTS)
		points.append(Vector2(w + w * cos(a), h + h * sin(a)))
	for i: int in range(1, ARC_POINTS):  # and back along the lower arc
		var a: float = (PI / 2.0) * float(i) / float(ARC_POINTS)
		points.append(Vector2(w * cos(a), h * sin(a)))
	return points


func _layout() -> void:
	if size.x < 8.0 or size.y < 8.0 or size == _laid_out_for:
		return
	_laid_out_for = size
	layout_count += 1
	leaves.clear()
	_state = SEED
	var s: float = scale_for(size)
	var step: float = SPACING * s
	var x: float = -20.0 * s
	while x < size.x + 20.0 * s:
		_add(x + _rnd() * 30.0 * s, -22.0 * s + _rnd() * 26.0 * s, 20.0 + _rnd() * 50.0, s)
		_add(x + _rnd() * 30.0 * s, size.y - 18.0 * s - _rnd() * 26.0 * s, 200.0 + _rnd() * 50.0, s)
		x += step
	var y: float = 90.0 * s
	while y < size.y - 60.0 * s:
		_add(-24.0 * s + _rnd() * 26.0 * s, y + _rnd() * 30.0 * s, 80.0 + _rnd() * 40.0, s)
		_add(size.x - 48.0 * s - _rnd() * 26.0 * s, y + _rnd() * 30.0 * s, 260.0 + _rnd() * 40.0, s)
		y += step
	queue_redraw()


## The two polygons (outer leaf, smaller inner leaf) of a leaf `width` wide whose box is centred on
## `centre` and rotated by `degrees` about it. The box is width x width/2, as in the design.
static func leaf_shapes(centre: Vector2, width: float, degrees: float) -> Array:
	var h: float = width * 0.5
	var turn: Transform2D = Transform2D(deg_to_rad(degrees), centre) * Transform2D(0.0, Vector2(-width / 2.0, -h / 2.0))
	var inner_box: Rect2 = Rect2(width * 0.12, h * 0.18, width * 0.70, h * 0.64)
	var inner_shape: PackedVector2Array = leaf_points(inner_box.size.x, inner_box.size.y)
	for i: int in inner_shape.size():
		inner_shape[i] += inner_box.position
	return [turn * leaf_points(width, h), turn * inner_shape]


## Adds one leaf with its top-left at (x, y), rotated by `degrees` about its centre.
func _add(x: float, y: float, degrees: float, s: float) -> void:
	var pair: Array = PAIRS[int(_rnd() * PAIRS.size())]
	var w: float = (70.0 + _rnd() * 50.0) * s
	var centre: Vector2 = Vector2(x + w / 2.0, y + w / 4.0)
	var shapes: Array = leaf_shapes(centre, w, degrees)
	leaves.append({
		"outer": shapes[0],
		"inner": shapes[1],
		"c1": Color(pair[0]),
		"c2": Color(pair[1]),
		"offset": Vector2(3.0, 4.0) * s,
		"centre": centre,
		"radius": w,
	})


func _rnd() -> float:
	_state = (_state * 16807) % 2147483647
	return float(_state) / 2147483647.0


func _draw() -> void:
	for leaf: Dictionary in leaves:
		var offset: Vector2 = leaf["offset"]
		var outer: PackedVector2Array = leaf["outer"]
		var inner: PackedVector2Array = leaf["inner"]
		draw_colored_polygon(_shifted(outer, offset), SHADOW)
		draw_colored_polygon(_shifted(outer, offset * 0.5), Color(SHADOW, 0.14))
		draw_colored_polygon(outer, leaf["c1"])
		draw_colored_polygon(_shifted(inner, offset * 0.6), Color(SHADOW, 0.25))
		draw_colored_polygon(inner, leaf["c2"])


static func _shifted(points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out: PackedVector2Array = points.duplicate()
	for i: int in out.size():
		out[i] += by
	return out
