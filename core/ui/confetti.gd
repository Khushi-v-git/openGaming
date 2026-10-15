class_name Confetti
extends Control
## A scatter of small cut-paper squares in the palette colours, each turned and with a soft
## shadow, for celebrations (the game-over card). Deterministic: the same `seed_value` and size
## always give the same picture, and it is drawn once per resize, never per frame.

const COLORS: Array = [
	Tokens.SAFFRON, Tokens.TERRACOTTA, Tokens.ROSE, Tokens.DEEP_TEAL, Tokens.INDIGO, Tokens.FOREST_GREEN,
]

@export var seed_value: int = 11
@export var count: int = 30

var pieces: Array[Dictionary] = []  # {x, y, size, angle, color}: x and y are fractions of the size


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scatter()
	resized.connect(queue_redraw)


## Lays the pieces out again (after changing seed_value or count).
func _scatter() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	pieces.clear()
	for i: int in count:
		pieces.append({
			"x": rng.randf(),
			"y": rng.randf(),
			"size": rng.randf_range(10.0, 22.0),
			"angle": rng.randf_range(0.0, TAU),
			"color": COLORS[rng.randi_range(0, COLORS.size() - 1)],
		})


func reseed(new_seed: int) -> void:
	seed_value = new_seed
	_scatter()
	queue_redraw()


func _draw() -> void:
	for piece: Dictionary in pieces:
		var centre: Vector2 = Vector2(float(piece["x"]) * size.x, float(piece["y"]) * size.y)
		var half: float = float(piece["size"]) / 2.0
		draw_set_transform(centre, float(piece["angle"]))
		draw_rect(Rect2(Vector2(-half, -half) + Vector2(2, 3), Vector2(half * 2.0, half * 2.0)), Color(Tokens.INK, 0.25))
		draw_rect(Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0)), piece["color"])
	draw_set_transform(Vector2.ZERO, 0.0)
