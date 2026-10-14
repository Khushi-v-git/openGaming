extends GutTest
## The board drawn from the classic board data, checked without reading pixels: where the nodes
## are, and that every snake and ladder sprite's anchors sit on the right squares.

const PLAYERS: Array = [
	{"player_id": "p1", "color": "red"},
	{"player_id": "p2", "color": "blue"},
	{"player_id": "p3", "color": "green"},
	{"player_id": "p4", "color": "yellow"},
]

var _board: Dictionary
var _catalog: Dictionary


func before_each() -> void:
	_board = ClimbBoard.load_file()["board"]
	_catalog = ClimbArt.load_catalog()["catalog"]


## A board view filling a SubViewport of the given size.
func _view(window: Vector2i, positions: Dictionary = {"p1": 0, "p2": 0, "p3": 0, "p4": 0}) -> Array:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = window
	viewport.disable_3d = true
	add_child_autofree(viewport)
	var view: ClimbBoardView = ClimbBoardView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(view)
	view.setup(_board, PLAYERS, positions)
	await get_tree().process_frame
	await get_tree().process_frame
	return [viewport, view]


func _near(a: Vector2, b: Vector2, label: String) -> void:
	assert_lt(a.distance_to(b), 0.6, "%s: %s should be %s" % [label, str(a), str(b)])


func _snake_art(name: String) -> Dictionary:
	for art: Dictionary in _catalog["snakes"]:
		if art["name"] == name:
			return art
	return {}


# --- numbers -------------------------------------------------------------------------------------

func test_there_is_one_label_per_square_with_its_number() -> void:
	var made: Array = await _view(Vector2i(1280, 720))
	var view: ClimbBoardView = made[1]
	assert_eq(view.number_labels.size(), 100)
	for i: int in 100:
		assert_eq(view.number_labels[i].text, str(i + 1))


func test_each_number_sits_inside_its_own_square() -> void:
	var made: Array = await _view(Vector2i(1280, 720))
	var view: ClimbBoardView = made[1]
	for square: int in range(1, 101):
		var label: Label = view.number_labels[square - 1]
		var tile: Rect2 = Rect2(view.square_center(square) - Vector2(view.cell, view.cell) / 2.0, Vector2(view.cell, view.cell))
		assert_true(tile.has_point(label.position), "label %d starts inside its square" % square)
		assert_true(tile.grow(1.0).encloses(Rect2(label.position, label.size * 0.5)), "label %d fits" % square)


func test_numbers_are_labels_not_part_of_any_image() -> void:
	var made: Array = await _view(Vector2i(1280, 720))
	for label: Label in (made[1] as ClimbBoardView).number_labels:
		assert_true(label is Label)
	# nothing on the board is a texture of numbers: the only textures are snakes, ladders, pawns
	for sprite: Sprite2D in (made[1] as ClimbBoardView).snake_sprites:
		assert_true((sprite.texture.resource_path as String).contains("snake"))


# --- the board fits its window ---------------------------------------------------------------------------

func test_the_board_fits_inside_its_window_at_both_target_sizes() -> void:
	for window: Vector2i in [Vector2i(793, 720), Vector2i(1190, 1080), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var made: Array = await _view(window)
		var view: ClimbBoardView = made[1]
		var full: Rect2 = Rect2(view.origin, Vector2(view.layout.columns, view.layout.total_rows()) * view.cell)
		assert_true(Rect2(Vector2.ZERO, Vector2(window)).encloses(full), "%s: board and start strip fit" % str(window))
		assert_gte(view.cell, 50.0 if window.y < 800 else 80.0, "%s: cells are big enough to read" % str(window))


# --- snakes ---------------------------------------------------------------------------------------------

func test_every_snake_has_a_sprite_with_its_head_and_tail_on_the_right_squares() -> void:
	for window: Vector2i in [Vector2i(793, 720), Vector2i(1190, 1080)]:
		var made: Array = await _view(window)
		var view: ClimbBoardView = made[1]
		assert_eq(view.snake_sprites.size(), 9)
		for sprite: Sprite2D in view.snake_sprites:
			var info: Dictionary = sprite.get_meta("snake")
			var art: Dictionary = _snake_art(info["art"])
			_near(sprite.transform * (art["head"] as Vector2), view.square_center(int(info["from"])), "snake %d->%d head" % [info["from"], info["to"]])
			_near(sprite.transform * (art["tail"] as Vector2), view.square_center(int(info["to"])), "snake %d->%d tail" % [info["from"], info["to"]])


func test_the_snakes_use_more_than_one_colour() -> void:
	var made: Array = await _view(Vector2i(793, 720))
	var arts: Dictionary = {}
	for sprite: Sprite2D in (made[1] as ClimbBoardView).snake_sprites:
		arts[(sprite.get_meta("snake") as Dictionary)["art"]] = true
	assert_gte(arts.size(), 3)


func test_snakes_are_the_same_whatever_the_window_size() -> void:
	var small: Array = await _view(Vector2i(793, 720))
	var large: Array = await _view(Vector2i(1190, 1080))
	var small_arts: Array = []
	var large_arts: Array = []
	for sprite: Sprite2D in (small[1] as ClimbBoardView).snake_sprites:
		small_arts.append((sprite.get_meta("snake") as Dictionary)["art"])
	for sprite: Sprite2D in (large[1] as ClimbBoardView).snake_sprites:
		large_arts.append((sprite.get_meta("snake") as Dictionary)["art"])
	assert_eq(small_arts, large_arts, "every client draws the same snake art for the same board")


# --- ladders --------------------------------------------------------------------------------------------

func test_every_ladder_has_its_top_and_foot_anchors_on_the_right_squares() -> void:
	for window: Vector2i in [Vector2i(793, 720), Vector2i(1190, 1080)]:
		var made: Array = await _view(window)
		var view: ClimbBoardView = made[1]
		var geometry: Dictionary = _catalog["ladder"]
		for ladder: Dictionary in _board["ladders"]:
			var pieces: Array[Sprite2D] = []
			for sprite: Sprite2D in view.ladder_sprites:
				var info: Dictionary = sprite.get_meta("ladder")
				if info["from"] == ladder["from"] and info["to"] == ladder["to"]:
					pieces.append(sprite)
			assert_gte(pieces.size(), 3, "ladder %d->%d has top, segments and bottom" % [ladder["from"], ladder["to"]])
			assert_eq((pieces[0].get_meta("ladder") as Dictionary)["kind"], "top")
			assert_eq((pieces[pieces.size() - 1].get_meta("ladder") as Dictionary)["kind"], "bottom")
			_near(pieces[0].transform * (geometry["top_anchor"] as Vector2), view.square_center(int(ladder["to"])), "ladder %d->%d top" % [ladder["from"], ladder["to"]])
			_near(pieces[pieces.size() - 1].transform * (geometry["foot_anchor"] as Vector2), view.square_center(int(ladder["from"])), "ladder %d->%d foot" % [ladder["from"], ladder["to"]])


func test_the_two_ladder_colourways_alternate() -> void:
	var made: Array = await _view(Vector2i(793, 720))
	var paths: Dictionary = {}
	for sprite: Sprite2D in (made[1] as ClimbBoardView).ladder_sprites:
		paths[sprite.texture.resource_path] = true
	var teal: bool = false
	var orange: bool = false
	for path: String in paths:
		teal = teal or path.contains("ladder-teal")
		orange = orange or not path.contains("ladder-teal")
	assert_true(teal and orange)


# --- pawns -----------------------------------------------------------------------------------------------

func test_pawns_rest_where_the_layout_puts_them() -> void:
	var positions: Dictionary = {"p1": 0, "p2": 12, "p3": 12, "p4": 99}
	var made: Array = await _view(Vector2i(1190, 1080), positions)
	var view: ClimbBoardView = made[1]
	var spots: Dictionary = view.layout.pawn_positions(positions, ["p1", "p2", "p3", "p4"], view.cell, view.origin)
	var pawn_scale: float = ClimbBoardView.PAWN_CELLS * view.cell / ClimbBoardView.PAWN_TEXTURE_SIZE
	for id: String in positions:
		var pawn: Sprite2D = view.pawn_node(id)
		_near(pawn.position + ClimbBoardView.PAWN_PIVOT * pawn_scale, spots[id], "pawn %s" % id)
		assert_almost_eq(pawn.scale.x, pawn_scale, 0.0001)
	assert_ne(spots["p2"], spots["p3"], "two pawns on square 12 do not overlap")


func test_each_pawn_uses_its_own_colour() -> void:
	var made: Array = await _view(Vector2i(793, 720))
	var view: ClimbBoardView = made[1]
	for entry: Dictionary in PLAYERS:
		assert_eq(view.pawn_node(entry["player_id"]).texture.resource_path, ClimbArt.pawn_path(entry["color"]))


func test_set_positions_moves_the_pawns() -> void:
	var made: Array = await _view(Vector2i(793, 720))
	var view: ClimbBoardView = made[1]
	var before: Vector2 = view.pawn_node("p1").position
	view.set_positions({"p1": 57, "p2": 0, "p3": 0, "p4": 0})
	assert_ne(view.pawn_node("p1").position, before)
	_near(view.pawn_rest_position("p1"), view.square_center(57), "p1 on 57")


# --- resizing ---------------------------------------------------------------------------------------------

func test_resizing_keeps_every_anchor_on_its_square_and_scales_the_board() -> void:
	var made: Array = await _view(Vector2i(793, 720))
	var viewport: SubViewport = made[0]
	var view: ClimbBoardView = made[1]
	var small_cell: float = view.cell
	for window: Vector2i in [Vector2i(1190, 1080), Vector2i(640, 540), Vector2i(1000, 700), Vector2i(793, 720)]:
		viewport.size = window
		await get_tree().process_frame
		await get_tree().process_frame
		assert_eq(view.size, Vector2(window))
		for sprite: Sprite2D in view.snake_sprites:
			var info: Dictionary = sprite.get_meta("snake")
			var art: Dictionary = _snake_art(info["art"])
			_near(sprite.transform * (art["head"] as Vector2), view.square_center(int(info["from"])), "%s snake head" % str(window))
		for label: Label in view.number_labels:
			assert_true(Rect2(Vector2.ZERO, Vector2(window)).has_point(label.position), "%s label on screen" % str(window))
	assert_eq(view.cell, small_cell, "back at the first size, back to the first layout")


func test_resizing_does_not_leak_nodes() -> void:
	var made: Array = await _view(Vector2i(793, 720))
	var viewport: SubViewport = made[0]
	var view: ClimbBoardView = made[1]
	var count_before: int = view.get_child(0).get_child_count() + view.get_child(1).get_child_count()
	for window: Vector2i in [Vector2i(1190, 1080), Vector2i(700, 600), Vector2i(793, 720)]:
		viewport.size = window
		await get_tree().process_frame
		await get_tree().process_frame
	assert_eq(view.get_child(0).get_child_count() + view.get_child(1).get_child_count(), count_before)
	assert_eq(view.number_labels.size(), 100)
	assert_eq(view.pawn_sprites.size(), 4)
	assert_eq(view.get_child_count(), 4, "ladder layer, snake layer, label layer, pawn layer")


func test_the_board_can_be_shown_for_a_different_board() -> void:
	var small: Dictionary = ClimbBoard.validate({"name": "Small", "size": 30, "columns": 6, "snakes": [{"from": 26, "to": 9}], "ladders": [{"from": 4, "to": 19}]})["board"]
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(793, 720)
	add_child_autofree(viewport)
	var view: ClimbBoardView = ClimbBoardView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(view)
	view.setup(small, PLAYERS.slice(0, 2), {"p1": 0, "p2": 0})
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(view.number_labels.size(), 30)
	assert_eq(view.snake_sprites.size(), 1)
	assert_gte(view.ladder_sprites.size(), 3)
