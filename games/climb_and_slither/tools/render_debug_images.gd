extends SceneTree
## Developer tool, not part of the game: renders the classic board at two window sizes and one
## debug image per snake and ladder sprite with its anchors marked, so they can be checked by eye.
##
## Needs a real renderer (not --headless):
##   godot --rendering-driver opengl3 --resolution 1280x720 -s games/climb_and_slither/tools/render_debug_images.gd -- <out_dir>

const BOARD_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080)]
const MARK: Color = Color(1.0, 0.0, 0.8)
const PLAYERS: Array = [
	{"player_id": "p1", "color": "red"},
	{"player_id": "p2", "color": "blue"},
	{"player_id": "p3", "color": "green"},
	{"player_id": "p4", "color": "yellow"},
]

var _out: String = "."


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	await _run()
	quit()


func _run() -> void:
	var catalog: Dictionary = ClimbArt.load_catalog()["catalog"]
	var board: Dictionary = ClimbBoard.load_file()["board"]
	for art: Dictionary in catalog["snakes"]:
		await _snake_image(art)
	for set_entry: Dictionary in catalog["ladder_sets"]:
		await _ladder_image(catalog["ladder"], set_entry)
	for window: Vector2i in BOARD_SIZES:
		await _board_image(board, window)


func _snapshot(root: Node, size: Vector2i, file: String) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	viewport.add_child(root)
	await process_frame
	await process_frame
	await process_frame
	viewport.get_texture().get_image().save_png("%s/%s" % [_out, file])
	viewport.queue_free()


func _backdrop(size: Vector2) -> ColorRect:
	var back: ColorRect = ColorRect.new()
	back.color = Tokens.PAPER_CREAM
	back.size = size
	return back


func _marker(parent: Control, at: Vector2, label: String) -> void:
	var holder: Control = Control.new()
	parent.add_child(holder)
	holder.draw.connect(func() -> void:
		holder.draw_circle(at, 7.0, MARK)
		holder.draw_circle(at, 3.0, Color.WHITE)
		holder.draw_string(ThemeDB.fallback_font, at + Vector2(10, -8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, MARK))


func _snake_image(art: Dictionary) -> void:
	var size: Vector2 = art["size"]
	var root: Control = _backdrop(size + Vector2(40, 40))
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = load(art["path"])
	sprite.centered = false
	sprite.position = Vector2(20, 20)
	root.add_child(sprite)
	_marker(root, (art["tail"] as Vector2) + Vector2(20, 20), "tail")
	_marker(root, (art["head"] as Vector2) + Vector2(20, 20), "head")
	await _snapshot(root, Vector2i(root.size), "anchor-%s.png" % art["name"])


func _ladder_image(geometry: Dictionary, set_entry: Dictionary) -> void:
	# the three pieces as the board uses them, assembled at natural size: top, 3 segments, bottom
	var top_size: Vector2 = geometry["top_size"]
	var seg_size: Vector2 = geometry["segment_size"]
	var bottom_size: Vector2 = geometry["bottom_size"]
	var height: float = top_size.y + 3.0 * seg_size.y + bottom_size.y
	var root: Control = _backdrop(Vector2(top_size.x + 40.0, height + 40.0))
	var y: float = 20.0
	var kinds: Array = [["top", top_size]] + [["segment", seg_size], ["segment", seg_size], ["segment", seg_size]] + [["bottom", bottom_size]]
	var top_at: Vector2 = Vector2.ZERO
	var foot_at: Vector2 = Vector2.ZERO
	for piece: Array in kinds:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = load(set_entry[piece[0]])
		sprite.centered = false
		sprite.position = Vector2(20, y)
		root.add_child(sprite)
		if piece[0] == "top":
			top_at = Vector2(20, y) + (geometry["top_anchor"] as Vector2)
		if piece[0] == "bottom":
			foot_at = Vector2(20, y) + (geometry["foot_anchor"] as Vector2)
		y += (piece[1] as Vector2).y
	_marker(root, top_at, "top")
	_marker(root, foot_at, "foot")
	await _snapshot(root, Vector2i(root.size), "anchor-ladder-%s.png" % set_entry["name"])


func _board_image(board: Dictionary, window: Vector2i) -> void:
	var root: Control = _backdrop(Vector2(window))
	var view: ClimbBoardView = ClimbBoardView.new()
	view.size = Vector2(window)
	root.add_child(view)
	view.setup(board, PLAYERS, {"p1": 0, "p2": 14, "p3": 14, "p4": 87})
	await _snapshot(root, window, "board-%dx%d.png" % [window.x, window.y])
