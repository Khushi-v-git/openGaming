class_name PaperEmptySeat
extends Control
## An open seat in the lobby: a dashed pill with "Waiting for a player...". Purely decorative.

var seat_height: float = 56.0


func _init() -> void:
	custom_minimum_size.y = seat_height
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var radius: float = size.y / 2.0
	var color: Color = Color(Tokens.INK, 0.35)
	var points: PackedVector2Array = PackedVector2Array()
	# the outline of a pill, walked once, then drawn as short dashes
	var steps: int = 16
	for i: int in range(steps + 1):
		var angle: float = -PI / 2.0 + PI * float(i) / float(steps)
		points.append(Vector2(size.x - radius, radius) + Vector2(cos(angle), sin(angle)) * (radius - 2.0))
	for i: int in range(steps + 1):
		var angle: float = PI / 2.0 + PI * float(i) / float(steps)
		points.append(Vector2(radius, radius) + Vector2(cos(angle), sin(angle)) * (radius - 2.0))
	points.append(points[0])
	points = _subdivide(points, 6.0)  # the straight sides need points too, or they would be one long dash
	var drawing: bool = true
	var run: float = 0.0
	for i: int in range(points.size() - 1):
		var length: float = points[i].distance_to(points[i + 1])
		run += length
		if drawing:
			draw_line(points[i], points[i + 1], color, 2.0)
		if run > (9.0 if drawing else 6.0):
			drawing = not drawing
			run = 0.0
	var font: Font = get_theme_default_font()
	var text: String = "Waiting for a player..."
	var font_size: int = 19
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(maxf(radius, (size.x - width) / 2.0), size.y / 2.0 + font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(Tokens.INK, 0.55))


static func _subdivide(points: PackedVector2Array, step: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var pieces: int = maxi(1, int(ceil(a.distance_to(b) / step)))
		for k: int in pieces:
			out.append(a.lerp(b, float(k) / float(pieces)))
	out.append(points[points.size() - 1])
	return out
