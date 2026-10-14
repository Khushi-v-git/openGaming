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
## The squares, frame and start strip are code-drawn placeholders in flat palette colours (no
## board art exists yet). Sprites that carry their own baked shadow get no extra shadow.

const MARGIN: float = 16.0
const PAWN_CELLS: float = 0.62  # pawn height in cells
const PAWN_TEXTURE_SIZE: float = 128.0
const PAWN_PIVOT: Vector2 = Vector2(64.0, 108.0)  # the middle of the pawn's base in its 128 px sprite
const GAP: float = 2.0  # paper gap between squares, in pixels

var board: Dictionary = {}
var layout: ClimbBoardLayout = null
var cell: float = 1.0
var origin: Vector2 = Vector2.ZERO

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
	layout = ClimbBoardLayout.new(int(board["size"]), int(board["columns"]))
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


func pawn_node(player_id: String) -> Sprite2D:
	return pawn_sprites.get(player_id, null)


## Re-runs the layout for the current size. Called when the control is resized.
func relayout() -> void:
	if layout == null or not _ready_built:
		return
	var fitted: Dictionary = layout.fit(size, MARGIN)
	cell = fitted["cell"]
	origin = fitted["origin"]
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
	var font_size: int = maxi(9, roundi(cell * 0.2))
	for i: int in number_labels.size():
		var label: Label = number_labels[i]
		var at: Vector2i = layout.cell_of(i + 1)
		label.position = origin + Vector2(float(at.x), float(at.y)) * cell + Vector2(0.07, 0.03) * cell
		label.size = Vector2(cell * 0.9, cell * 0.4)
		label.add_theme_font_size_override("font_size", font_size)
	_start_label.position = Vector2(origin.x + 4.3 * cell, origin.y + (float(layout.rows) + 0.3) * cell)
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


# --- drawing: code-drawn placeholder board ---------------------------------------------------------

func _draw() -> void:
	if layout == null:
		return
	var fitted: Dictionary = layout.fit(size, MARGIN)
	var board_rect: Rect2 = fitted["board_rect"]
	var full_rect: Rect2 = fitted["full_rect"]

	# soft paper shadow falls to the bottom right (light from the top left)
	var frame: StyleBoxFlat = StyleBoxFlat.new()
	frame.bg_color = Tokens.PAPER_CREAM.darkened(0.12)
	frame.set_corner_radius_all(Tokens.RADIUS)
	frame.shadow_color = Color(Tokens.INK, 0.25)
	frame.shadow_size = 5
	frame.shadow_offset = Vector2(3, 4)
	draw_style_box(frame, board_rect.grow(cell * 0.12))

	for square: int in range(1, layout.size + 1):
		var at: Vector2i = layout.cell_of(square)
		var tile: Rect2 = Rect2(origin + Vector2(float(at.x), float(at.y)) * cell, Vector2(cell, cell)).grow(-GAP)
		draw_rect(tile, _tile_colour(square, at))

	# finish: the crown on the last square
	var last: Vector2i = layout.cell_of(layout.size)
	var crown_size: float = cell * 0.5
	var crown_at: Vector2 = origin + (Vector2(float(last.x), float(last.y)) + Vector2(0.5, 0.58)) * cell - Vector2(crown_size, crown_size) / 2.0
	draw_texture_rect(_crown, Rect2(crown_at, Vector2(crown_size, crown_size)), false)

	# the start strip under the board
	var strip: StyleBoxFlat = StyleBoxFlat.new()
	strip.bg_color = Tokens.SAFFRON.lerp(Tokens.PAPER_CREAM, 0.55)
	strip.set_corner_radius_all(int(cell * 0.25))
	var strip_rect: Rect2 = Rect2(full_rect.position + Vector2(0.0, float(layout.rows) * cell), Vector2(full_rect.size.x, cell)).grow(-GAP * 2.0)
	draw_style_box(strip, strip_rect)


func _tile_colour(square: int, at: Vector2i) -> Color:
	if square == 1:
		return Tokens.DEEP_TEAL.lerp(Tokens.PAPER_CREAM, 0.65)
	if square == layout.size:
		return Tokens.SAFFRON.lerp(Tokens.PAPER_CREAM, 0.5)
	return Tokens.PAPER_CREAM if (at.x + at.y) % 2 == 0 else Tokens.PAPER_CREAM.darkened(0.06)
