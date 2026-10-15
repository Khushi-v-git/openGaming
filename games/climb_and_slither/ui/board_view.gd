class_name ClimbBoardView
extends Control
## Draws a Climb and Slither board from board data: the squares, a Label with each square's
## number, ladders and snakes as separate sprites placed from their start and end squares, and the
## pawns. It shows what it is told and decides nothing (rule 12): pawn positions come from the
## game's view, the layout from ClimbBoardLayout, sprite placement from ClimbSpritePlacement.
##
## The board is the one place where sprites are positioned by maths instead of Control containers:
## it fills whatever rectangle its parent container gives it and lays itself out inside it.
##
## The frame, squares and start strip are drawn in code in the papercut style of the design: a
## layered teal and forest frame with leaves and dots, a recessed well, and tiles in a saffron,
## cream and terracotta cycle, each with a raised inner tile. Sprites that carry their own baked shadow get no extra shadow.

const MARGIN: float = 8.0
const FRAME_CELLS: float = 0.5  # width of the decorated frame round the squares, in cells
const STRIP_GAP_CELLS: float = 0.6  # room between the frame and the start strip
const PAWN_CELLS: float = 0.62  # pawn height in cells
const PAWN_TEXTURE_SIZE: float = 128.0
const PAWN_PIVOT: Vector2 = Vector2(64.0, 108.0)  # the middle of the pawn's base in its 128 px sprite
const GAP: float = 2.0  # paper gap between squares, in pixels

var board: Dictionary = {}
var layout: ClimbBoardLayout = null
var cell: float = 1.0
var origin: Vector2 = Vector2.ZERO  # top-left of the squares
var frame_rect: Rect2 = Rect2()  # the squares plus their decorated frame

## Built by _rebuild_art(); read by tests and by animations.
var snake_sprites: Array[Sprite2D] = []
var ladder_sprites: Array[Sprite2D] = []
var pawn_sprites: Dictionary = {}  # player_id -> Sprite2D
var number_labels: Array[Label] = []

var _catalog: Dictionary = {}
var _seat_order: Array[String] = []
var _colors: Dictionary = {}  # player_id -> colour name
var _positions: Dictionary = {}
var _label_layer: Control
var _ladder_layer: Node2D
var _snake_layer: Node2D
var _pawn_layer: Node2D
var _start_label: Label
var _crown: Texture2D
var _ready_built: bool = false
var _tween: Tween = null


func _init() -> void:
	clip_contents = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_ladder_layer = Node2D.new()
	add_child(_ladder_layer)
	_snake_layer = Node2D.new()
	add_child(_snake_layer)
	_label_layer = Control.new()  # numbers draw above the art so a snake never hides one
	_label_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label_layer)
	_pawn_layer = Node2D.new()
	add_child(_pawn_layer)
	_crown = load(ClimbArt.CROWN_PATH)
	var loaded: Dictionary = ClimbArt.load_catalog()
	assert(CoreResult.is_ok(loaded), "board art catalog: %s" % str(loaded))
	_catalog = loaded["catalog"]
	_ready_built = true
	resized.connect(relayout)
	if not board.is_empty():
		_build()


## Shows `new_board` with the given players ([{player_id, color}] in seat order) at `positions`.
func setup(new_board: Dictionary, players: Array, positions: Dictionary) -> void:
	board = new_board
	layout = ClimbBoardLayout.new(int(board["size"]), int(board["columns"]), STRIP_GAP_CELLS)
	_seat_order.clear()
	_colors.clear()
	for entry: Dictionary in players:
		_seat_order.append(entry["player_id"])
		_colors[entry["player_id"]] = entry["color"]
	_positions = positions.duplicate()
	if _ready_built:
		_build()


## Moves every pawn straight to where `positions` says (no animation).
func set_positions(positions: Dictionary) -> void:
	_positions = positions.duplicate()
	_place_pawns()


## The centre of a square, in this control's coordinates (square 0 is the start strip).
func square_center(square: int) -> Vector2:
	return layout.center(square, cell, origin)


## Where a pawn rests right now (the point its base touches), in this control's coordinates.
func pawn_rest_position(player_id: String) -> Vector2:
	return layout.pawn_positions(_positions, _seat_order, cell, origin)[player_id]


## The square a player's pawn is on right now (0 = the start strip).
func square_of(player_id: String) -> int:
	return int(_positions.get(player_id, 0))


func pawn_node(player_id: String) -> Sprite2D:
	return pawn_sprites.get(player_id, null)


## Re-runs the layout for the current size. Called when the control is resized.
func relayout() -> void:
	if layout == null or not _ready_built:
		return
	var fitted: Dictionary = layout.fit(size, MARGIN, FRAME_CELLS)
	cell = fitted["cell"]
	origin = fitted["origin"]
	frame_rect = fitted["frame_rect"]
	_place_labels()
	_rebuild_art()
	_place_pawns()
	queue_redraw()


func _build() -> void:
	for label: Label in number_labels:
		label.queue_free()
	number_labels.clear()
	for square: int in range(1, layout.size + 1):
		var label: Label = Label.new()
		label.text = str(square)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_color", Color(Tokens.INK, 0.85))
		label.add_theme_color_override("font_outline_color", Color(Tokens.PAPER_CREAM, 0.9))
		label.add_theme_constant_override("outline_size", 4)
		_label_layer.add_child(label)
		number_labels.append(label)
	if _start_label == null:
		_start_label = Label.new()
		_start_label.text = "Start"
		_start_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_start_label.add_theme_color_override("font_color", Color(Tokens.INK, 0.7))
		_label_layer.add_child(_start_label)
	for sprite: Variant in pawn_sprites.values():
		(sprite as Node).queue_free()
	pawn_sprites.clear()
	for player_id: String in _seat_order:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = load(ClimbArt.pawn_path(_colors[player_id]))
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_pawn_layer.add_child(sprite)
		pawn_sprites[player_id] = sprite
	relayout()


func _place_labels() -> void:
	var font_size: int = maxi(10, roundi(cell * 0.24))
	for i: int in number_labels.size():
		var label: Label = number_labels[i]
		var at: Vector2i = layout.cell_of(i + 1)
		label.position = origin + Vector2(float(at.x), float(at.y)) * cell + Vector2(0.11, 0.07) * cell
		label.size = Vector2(cell * 0.8, cell * 0.4)
		label.add_theme_font_size_override("font_size", font_size)
	_start_label.position = Vector2(origin.x + 4.3 * cell, origin.y + (float(layout.rows) + layout.strip_gap + 0.3) * cell)
	_start_label.size = Vector2(cell * 2.0, cell * 0.5)
	_start_label.add_theme_font_size_override("font_size", maxi(10, roundi(cell * 0.26)))


## Ladders and snakes are rebuilt from the board data whenever the layout changes. Which sprite a
## snake gets depends only on the board (never on the window), so every player sees the same art.
func _rebuild_art() -> void:
	for sprite: Sprite2D in ladder_sprites:
		sprite.free()
	for sprite: Sprite2D in snake_sprites:
		sprite.free()
	ladder_sprites.clear()
	snake_sprites.clear()

	var sets: Array = _catalog["ladder_sets"]
	for i: int in (board["ladders"] as Array).size():
		var ladder: Dictionary = board["ladders"][i]
		var set_entry: Dictionary = sets[i % sets.size()]
		var foot: Vector2 = square_center(int(ladder["from"]))
		var top: Vector2 = square_center(int(ladder["to"]))
		for piece: Dictionary in ClimbSpritePlacement.ladder_pieces(_catalog["ladder"], top, foot, cell):
			var sprite: Sprite2D = _sprite(set_entry[piece["kind"]], piece["transform"])
			sprite.set_meta("ladder", {"from": ladder["from"], "to": ladder["to"], "kind": piece["kind"]})
			_ladder_layer.add_child(sprite)
			ladder_sprites.append(sprite)

	var lengths: Array = []
	for snake: Dictionary in board["snakes"]:
		lengths.append(square_center(int(snake["from"])).distance_to(square_center(int(snake["to"]))) / cell)
	var chosen: Array[int] = ClimbSpritePlacement.choose_snake_arts(lengths, _catalog["snakes"])
	for i: int in (board["snakes"] as Array).size():
		var snake: Dictionary = board["snakes"][i]
		var art: Dictionary = _catalog["snakes"][chosen[i]]
		var placed: Dictionary = ClimbSpritePlacement.snake_transform(art, square_center(int(snake["from"])), square_center(int(snake["to"])), cell)
		var sprite: Sprite2D = _sprite(art["path"], placed["transform"])
		sprite.set_meta("snake", {"from": snake["from"], "to": snake["to"], "art": art["name"]})
		_snake_layer.add_child(sprite)
		snake_sprites.append(sprite)


func _sprite(path: String, placement: Transform2D) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = load(path)
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.transform = placement
	return sprite


## Carries out one pawn step of a ClimbAnimationPlan ("hop", "slide", "shake" or "win"; the
## other ops are the screen's business and finish at once). `done` is called when it ends.
## `speed` is a multiplier; 0 means instant. Only one animation runs at a time.
func animate(step: Dictionary, speed: float, done: Callable) -> void:
	cancel_animation()
	var op: String = str(step.get("op", ""))
	var player_id: String = str(step.get("player_id", ""))
	var sprite: Sprite2D = pawn_sprites.get(player_id, null)
	if sprite == null or not ["hop", "slide", "shake", "win"].has(op):
		done.call()
		return
	if op == "hop" or op == "slide":
		_positions[player_id] = int(step["to"])
	var rest: Vector2 = _rest_sprite_position(player_id)
	var seconds: float = 0.0 if speed <= 0.0 else float(step["duration"]) / speed
	_snap_others(player_id)
	if seconds <= 0.0 or not is_inside_tree():
		sprite.position = rest
		done.call()
		return
	var tween: Tween = create_tween()
	_tween = tween
	match op:
		"hop":
			var lift: float = cell * 0.22
			var mid: Vector2 = (sprite.position + rest) / 2.0 + Vector2(0.0, -lift)
			tween.tween_property(sprite, "position", mid, seconds / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tween.tween_property(sprite, "position", rest, seconds / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		"slide":
			tween.tween_property(sprite, "position", rest, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		"shake":
			var amount: float = cell * 0.12
			for offset: float in [-amount, amount, -amount * 0.6, amount * 0.6, 0.0]:
				tween.tween_property(sprite, "position", rest + Vector2(offset, 0.0), seconds / 5.0)
		"win":
			var scale_up: Vector2 = sprite.scale * 1.35
			var base_scale: Vector2 = sprite.scale
			tween.tween_property(sprite, "scale", scale_up, seconds / 2.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(sprite, "scale", base_scale, seconds / 2.0)
	tween.finished.connect(func() -> void:
		if _tween == tween:
			_tween = null
			_place_pawns()
			done.call())


## Stops a running animation and puts every pawn on its resting spot.
func cancel_animation() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_place_pawns()


func is_animating() -> bool:
	return _tween != null


func _rest_sprite_position(player_id: String) -> Vector2:
	var pawn_scale: float = PAWN_CELLS * cell / PAWN_TEXTURE_SIZE
	return pawn_rest_position(player_id) - PAWN_PIVOT * pawn_scale


## Pawns that are not the one moving jump to their resting spots (they may share a square now).
func _snap_others(moving: String) -> void:
	for player_id: String in pawn_sprites:
		if player_id != moving:
			(pawn_sprites[player_id] as Sprite2D).position = _rest_sprite_position(player_id)


func _place_pawns() -> void:
	if layout == null or pawn_sprites.is_empty():
		return
	var spots: Dictionary = layout.pawn_positions(_positions, _seat_order, cell, origin)
	var pawn_scale: float = PAWN_CELLS * cell / PAWN_TEXTURE_SIZE
	for player_id: String in pawn_sprites:
		var sprite: Sprite2D = pawn_sprites[player_id]
		sprite.scale = Vector2(pawn_scale, pawn_scale)
		sprite.position = (spots[player_id] as Vector2) - PAWN_PIVOT * pawn_scale


# --- drawing: the papercut board, in code ---------------------------------------------------------------

const TILE_COLOURS: Array = [Tokens.SAFFRON, Tokens.PAPER_CREAM, Tokens.TERRACOTTA]
## Colour pairs [outer, inner] for the frame's leaves and dots, from the design.
const LEAF_PAIRS: Array = [
	[Tokens.FOREST_GREEN, Tokens.SAFFRON], [Tokens.SAFFRON, Tokens.TERRACOTTA],
	[Tokens.FOREST_GREEN, Tokens.ROSE], [Tokens.PAPER_CREAM, Tokens.FOREST_GREEN],
]
const DOT_PAIRS: Array = [
	[Tokens.PAPER_CREAM, Tokens.SAFFRON], [Tokens.SAFFRON, Tokens.TERRACOTTA], [Tokens.ROSE, Tokens.PAPER_CREAM],
]
const SHADOW_INK: Color = Color(0.1686, 0.1647, 0.2)


func _draw() -> void:
	if layout == null:
		return
	_draw_frame()
	_draw_well_and_tiles()
	_draw_start_strip()


## A rounded paper piece with a soft shadow falling to the bottom right (light from the top left).
func _paper(rect: Rect2, colour: Color, radius: float, shadow: float = 0.3, depth: float = 3.0) -> void:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(maxi(1, roundi(radius)))
	box.shadow_color = Color(SHADOW_INK, shadow)
	box.shadow_size = maxi(1, roundi(depth))
	box.shadow_offset = Vector2(depth * 0.6, depth * 0.8)
	draw_style_box(box, rect)


func _draw_frame() -> void:
	var band: float = cell * FRAME_CELLS
	_paper(frame_rect, Tokens.DEEP_TEAL, cell * 0.34, 0.32, maxf(3.0, cell * 0.1))
	_paper(frame_rect.grow(-band * 0.125), Tokens.FOREST_GREEN, cell * 0.28, 0.3, maxf(2.0, cell * 0.04))
	_paper(frame_rect.grow(-band * 0.2), Tokens.DEEP_TEAL, cell * 0.22, 0.28, maxf(2.0, cell * 0.04))
	# leaves and dots along the middle of the band, one per square, alternating
	var mid: float = band * 0.5
	var left: float = frame_rect.position.x + mid
	var right: float = frame_rect.end.x - mid
	var top: float = frame_rect.position.y + mid
	var bottom: float = frame_rect.end.y - mid
	for k: int in layout.columns:
		var x: float = origin.x + (float(k) + 0.5) * cell
		_decor(Vector2(x, top), k, 0.0)
		_decor(Vector2(x, bottom), k + 1, 180.0)
	for k: int in layout.rows:
		var y: float = origin.y + (float(k) + 0.5) * cell
		_decor(Vector2(left, y), k + 2, 90.0)
		_decor(Vector2(right, y), k, 270.0)
	for corner: int in 4:
		var at: Vector2 = Vector2(left if corner % 2 == 0 else right, top if corner < 2 else bottom)
		_leaf(at, cell * 0.36, [45.0, 135.0, 315.0, 225.0][corner], LEAF_PAIRS[corner % 4])


func _decor(at: Vector2, k: int, base_degrees: float) -> void:
	if k % 2 == 0:
		var tilt: float = -22.0 if (k / 2) % 2 == 0 else 22.0
		_leaf(at, cell * 0.27, base_degrees + tilt, LEAF_PAIRS[k % 4])
	else:
		var pair: Array = DOT_PAIRS[k % 3]
		var radius: float = cell * 0.06
		draw_circle(at + Vector2(1.5, 2.0), radius, Color(SHADOW_INK, 0.3))
		draw_circle(at, radius, pair[0])
		draw_circle(at, radius * 0.5, pair[1])


func _leaf(centre: Vector2, width: float, degrees: float, pair: Array) -> void:
	var shapes: Array = LeafBorder.leaf_shapes(centre, width, degrees)
	var offset: Vector2 = Vector2(width * 0.03, width * 0.04) + Vector2(1.0, 1.0)
	draw_colored_polygon(_moved(shapes[0], offset), Color(SHADOW_INK, 0.32))
	draw_colored_polygon(shapes[0], pair[0])
	draw_colored_polygon(_moved(shapes[1], offset * 0.5), Color(SHADOW_INK, 0.25))
	draw_colored_polygon(shapes[1], pair[1])


static func _moved(points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out: PackedVector2Array = points.duplicate()
	for i: int in out.size():
		out[i] += by
	return out


func _draw_well_and_tiles() -> void:
	var board_rect: Rect2 = Rect2(origin, Vector2(float(layout.columns), float(layout.rows)) * cell)
	var well: Rect2 = board_rect.grow(cell * 0.06)
	var edge: float = maxf(2.0, cell * 0.06)
	draw_style_box(_flat(Tokens.FOREST_GREEN, cell * 0.14), well)
	# the well is sunk into the frame: a darker lip along its top and left
	draw_rect(Rect2(well.position + Vector2(cell * 0.1, 0.0), Vector2(well.size.x - cell * 0.2, edge)), Color(SHADOW_INK, 0.42))
	draw_rect(Rect2(well.position + Vector2(0.0, cell * 0.1), Vector2(edge, well.size.y - cell * 0.2)), Color(SHADOW_INK, 0.42))
	var gap: float = maxf(1.0, cell * 0.0625)
	for square: int in range(1, layout.size + 1):
		var at: Vector2i = layout.cell_of(square)
		var tile: Rect2 = Rect2(origin + Vector2(float(at.x), float(at.y)) * cell, Vector2(cell, cell)).grow(-gap * 0.5)
		var colour: Color = _tile_colour(square, at)
		_paper(tile, colour, cell * 0.0625, 0.35, maxf(2.0, cell * 0.035))
		_paper(tile.grow(-cell * 0.0875), colour, cell * 0.05, 0.3, maxf(1.5, cell * 0.025))
	# finish: the crown on the last square
	var last: Vector2i = layout.cell_of(layout.size)
	var crown_size: float = cell * 0.5
	var crown_at: Vector2 = origin + (Vector2(float(last.x), float(last.y)) + Vector2(0.5, 0.58)) * cell - Vector2(crown_size, crown_size) / 2.0
	draw_texture_rect(_crown, Rect2(crown_at, Vector2(crown_size, crown_size)), false)


func _draw_start_strip() -> void:
	var strip: Rect2 = Rect2(
		Vector2(frame_rect.position.x, origin.y + (float(layout.rows) + layout.strip_gap) * cell),
		Vector2(frame_rect.size.x, cell)).grow(-2.0)
	_paper(strip, Tokens.SAFFRON.lerp(Tokens.PAPER_CREAM, 0.55), cell * 0.3, 0.3, maxf(2.0, cell * 0.06))


func _flat(colour: Color, radius: float) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(maxi(1, roundi(radius)))
	return box


## Tiles cycle saffron, cream, terracotta along the diagonals; square 1 is teal paper (where
## everyone starts) so the way in is easy to see.
func _tile_colour(square: int, at: Vector2i) -> Color:
	if square == 1:
		return Tokens.DEEP_TEAL.lerp(Tokens.PAPER_CREAM, 0.55)
	if square == layout.size:
		return Tokens.FOREST_GREEN.lerp(Tokens.PAPER_CREAM, 0.7)  # pale paper so the crown shows
	return TILE_COLOURS[(at.x + at.y) % 3]
