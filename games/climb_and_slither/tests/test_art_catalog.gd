extends GutTest
## The anchor data must match the real art: a changed sprite breaks a test, not the screen.


func _catalog() -> Dictionary:
	var loaded: Dictionary = ClimbArt.load_catalog()
	assert_true(CoreResult.is_ok(loaded), str(loaded))
	return loaded["catalog"]


func test_the_catalog_loads() -> void:
	var catalog: Dictionary = _catalog()
	assert_eq(catalog["snakes"].size(), 5)
	assert_eq(catalog["ladder_sets"].size(), 2)
	assert_eq(catalog["snakes"][0]["name"], "snake-forest", "sorted by name")


func test_every_snake_sprite_exists_with_the_size_the_data_says() -> void:
	for art: Dictionary in _catalog()["snakes"]:
		var texture: Texture2D = load(art["path"])
		assert_not_null(texture, art["path"])
		assert_eq(Vector2(texture.get_size()), art["size"], "%s: size in anchors file matches the image" % art["name"])


func test_every_snake_anchor_is_inside_its_image_and_head_and_tail_are_apart() -> void:
	for art: Dictionary in _catalog()["snakes"]:
		var size: Vector2 = art["size"]
		for key: String in ["tail", "head"]:
			var point: Vector2 = art[key]
			assert_true(point.x >= 0.0 and point.y >= 0.0 and point.x <= size.x and point.y <= size.y, "%s %s" % [art["name"], key])
		assert_gt((art["head"] as Vector2).distance_to(art["tail"]), size.x * 0.5, "%s: the head is at the far end" % art["name"])
		assert_gt((art["head"] as Vector2).x, (art["tail"] as Vector2).x, "%s: heads are on the right" % art["name"])


func test_snake_anchors_match_the_svg_source() -> void:
	# The anchors were read from the SVG itself: the body path starts at the tail tip and the head
	# is the one big circle. Check against the source text so they cannot silently drift apart.
	var circle: RegEx = RegEx.new()
	circle.compile('<circle cx="([0-9.]+)" cy="([0-9.]+)" r="([0-9.]+)"')
	for art: Dictionary in _catalog()["snakes"]:
		var source: String = FileAccess.get_file_as_string(art["path"])
		var biggest: Vector3 = Vector3.ZERO
		for found: RegExMatch in circle.search_all(source):
			var radius: float = found.get_string(3).to_float()
			if radius > biggest.z:
				biggest = Vector3(found.get_string(1).to_float(), found.get_string(2).to_float(), radius)
		assert_eq(biggest.z, 47.0, "%s: the head circle is the biggest" % art["name"])
		assert_almost_eq((art["head"] as Vector2).x, biggest.x, 0.05, "%s head x" % art["name"])
		assert_almost_eq((art["head"] as Vector2).y, biggest.y, 0.05, "%s head y" % art["name"])
		assert_eq(art["tail"], Vector2(100, 220), "%s tail" % art["name"])


func test_the_ladder_pieces_exist_and_have_the_sizes_the_data_says() -> void:
	var catalog: Dictionary = _catalog()
	var ladder: Dictionary = catalog["ladder"]
	for set_entry: Dictionary in catalog["ladder_sets"]:
		for kind: String in ["top", "segment", "bottom"]:
			var texture: Texture2D = load(set_entry[kind])
			assert_not_null(texture, set_entry[kind])
			assert_eq(Vector2(texture.get_size()), ladder["%s_size" % kind], "%s %s size" % [set_entry["name"], kind])


func test_ladder_anchors_sit_on_the_rung_and_the_feet_in_the_svg_source() -> void:
	var catalog: Dictionary = _catalog()
	var ladder: Dictionary = catalog["ladder"]
	var rect: RegEx = RegEx.new()
	rect.compile('<rect x="([0-9.]+)" y="([0-9.]+)" width="([0-9.]+)" height="([0-9.]+)"')
	for set_entry: Dictionary in catalog["ladder_sets"]:
		# the top piece's rung: the widest rect (152 wide); its centre is the top anchor
		var top_source: String = FileAccess.get_file_as_string(set_entry["top"])
		var rung_centre: Vector2 = Vector2.ZERO
		for found: RegExMatch in rect.search_all(top_source):
			if found.get_string(3).to_float() > 100.0:
				rung_centre = Vector2(found.get_string(1).to_float() + found.get_string(3).to_float() / 2.0, found.get_string(2).to_float() + found.get_string(4).to_float() / 2.0)
				break
		assert_eq(rung_centre, ladder["top_anchor"], "%s: top anchor is the centre of the top rung" % set_entry["name"])
		# the bottom piece's feet: two pads 68 wide at y 98 to 120; the anchor is the middle of them
		var bottom_source: String = FileAccess.get_file_as_string(set_entry["bottom"])
		var pads: Array[Vector2] = []
		for found: RegExMatch in rect.search_all(bottom_source):
			if found.get_string(3).to_float() == 68.0:
				pads.append(Vector2(found.get_string(1).to_float() + 34.0, found.get_string(2).to_float() + found.get_string(4).to_float() / 2.0))
		assert_eq(pads.size(), 2, "%s: two foot pads" % set_entry["name"])
		assert_eq(Vector2((pads[0].x + pads[1].x) / 2.0, pads[0].y), ladder["foot_anchor"], "%s: foot anchor is between the pads" % set_entry["name"])


func test_the_ladder_pieces_stack_to_the_full_ladder_height() -> void:
	# top + five segments + bottom is exactly the full-height ladder sprite
	var ladder: Dictionary = _catalog()["ladder"]
	var total: float = (ladder["top_size"] as Vector2).y + 5.0 * (ladder["segment_size"] as Vector2).y + (ladder["bottom_size"] as Vector2).y
	assert_eq(total, float(load(ClimbArt.ASSET_DIR + "ladder.svg").get_height()))


func test_pawn_art_exists_for_every_player_colour() -> void:
	for color: String in ClimbAndSlitherRules.COLORS:
		assert_not_null(load(ClimbArt.pawn_path(color)), color)
	assert_not_null(load(ClimbArt.CROWN_PATH))


# --- the loader refuses damaged data ----------------------------------------------------------------------

const TMP: String = "user://test_art"


func after_each() -> void:
	for name: String in ["a.json"]:
		if FileAccess.file_exists("%s/%s" % [TMP, name]):
			DirAccess.remove_absolute("%s/%s" % [TMP, name])
	DirAccess.remove_absolute(TMP)


func _write(data: Variant) -> String:
	DirAccess.make_dir_recursive_absolute(TMP)
	var path: String = TMP + "/a.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(data if data is String else JSON.stringify(data))
	file.close()
	return path


func _good() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ClimbArt.ANCHORS_PATH))


func test_a_missing_or_broken_anchors_file_is_refused() -> void:
	assert_eq(CoreResult.error_code(ClimbArt.load_catalog(TMP + "/none.json")), ClimbArt.INVALID_ART)
	assert_eq(CoreResult.error_code(ClimbArt.load_catalog(_write("{ nope"))), ClimbArt.INVALID_ART)
	assert_eq(CoreResult.error_code(ClimbArt.load_catalog(_write("[1,2]"))), ClimbArt.INVALID_ART)


func test_an_anchor_outside_its_image_is_refused() -> void:
	var data: Dictionary = _good()
	data["snakes"]["snake-saffron"]["head"] = [5000, 10]
	var result: Dictionary = ClimbArt.load_catalog(_write(data))
	assert_eq(CoreResult.error_code(result), ClimbArt.INVALID_ART)
	assert_string_contains(str(result["error"]["message"]), "outside the image")


func test_a_sprite_that_does_not_exist_is_refused() -> void:
	var data: Dictionary = _good()
	data["snakes"]["snake-purple"] = data["snakes"]["snake-saffron"].duplicate()
	assert_eq(CoreResult.error_code(ClimbArt.load_catalog(_write(data))), ClimbArt.INVALID_ART)
	var sets: Dictionary = _good()
	sets["ladder_sets"]["orange"]["top"] = "ladder-missing"
	assert_eq(CoreResult.error_code(ClimbArt.load_catalog(_write(sets))), ClimbArt.INVALID_ART)


func test_missing_pieces_of_the_data_are_refused() -> void:
	for key: String in ["snakes", "ladder", "ladder_sets"]:
		var data: Dictionary = _good()
		data.erase(key)
		assert_eq(CoreResult.error_code(ClimbArt.load_catalog(_write(data))), ClimbArt.INVALID_ART, key)
	var no_body: Dictionary = _good()
	no_body["snakes"]["snake-saffron"].erase("body_width")
	assert_eq(CoreResult.error_code(ClimbArt.load_catalog(_write(no_body))), ClimbArt.INVALID_ART)
	var same_spot: Dictionary = _good()
	same_spot["snakes"]["snake-saffron"]["head"] = same_spot["snakes"]["snake-saffron"]["tail"]
	assert_eq(CoreResult.error_code(ClimbArt.load_catalog(_write(same_spot))), ClimbArt.INVALID_ART)
