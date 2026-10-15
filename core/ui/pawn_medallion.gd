class_name PawnMedallion
extends Control
## The winner's badge on the game-over card: a big disc in the player's colour with a smaller
## darker disc on it and a paper crown on top (saffron, with a terracotta offset copy behind it).
## `color` is the player's colour; set it before showing the card.

var color: Color = Tokens.PLAYER_RED:
	set(value):
		color = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(170, 215)


func _draw() -> void:
	var centre: Vector2 = Vector2(size.x / 2.0, size.y - 88.0)
	draw_circle(centre + Vector2(3, 6), 82.0, Color(Tokens.INK, 0.3))
	draw_circle(centre, 82.0, color)
	draw_circle(centre + Vector2(1, 2), 46.0, Color(Tokens.INK, 0.28))
	draw_circle(centre, 46.0, color.darkened(0.08))
	# the crown sits on top of the disc, as in the design
	var width: float = 76.0
	var height: float = 56.0
	var origin: Vector2 = Vector2(centre.x - width / 2.0, centre.y - 82.0 - height + 22.0)
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(0, 1), Vector2(0, 0.2), Vector2(0.25, 0.55), Vector2(0.5, 0), Vector2(0.75, 0.55), Vector2(1, 0.2), Vector2(1, 1),
	])
	var crown: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		crown.append(origin + Vector2(point.x * width, point.y * height))
	var shadow: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in crown:
		shadow.append(point + Vector2(3, 4))
	draw_colored_polygon(shadow, Tokens.TERRACOTTA)
	draw_colored_polygon(crown, Tokens.SAFFRON)
