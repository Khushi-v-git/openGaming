extends GutTest
## Grow & Trade board: geometry on the 30-hex island, data validation, and the seeded layout.


func _data() -> Dictionary:
	var file: FileAccess = FileAccess.open(GtBoard.DEFAULT_PATH, FileAccess.READ)
	var json: JSON = JSON.new()
	assert_eq(json.parse(file.get_as_text()), OK)
	return json.data


func _clean() -> Dictionary:
	var result: Dictionary = GtBoard.validate(_data())
	assert_true(CoreResult.is_ok(result), str(result))
	return result["board"]


func _board() -> GtBoard:
	return GtBoard.new(_clean())


func _error_of(data: Dictionary) -> String:
	return CoreResult.error_code(GtBoard.validate(data))


# --- the shipped board ---------------------------------------------------------------

func test_the_shipped_board_loads_and_is_valid() -> void:
	var result: Dictionary = GtBoard.load_file()
	assert_true(CoreResult.is_ok(result), str(result))
	assert_eq((result["board"]["hexes"] as Array).size(), 30)
	assert_eq((result["board"]["tokens"] as Array).size(), 28, "one token per non-desert hex")


func test_a_missing_or_broken_file_is_refused() -> void:
	assert_eq(CoreResult.error_code(GtBoard.load_file("res://games/grow_and_trade/data/nope.json")), GtBoard.INVALID_BOARD)
	assert_eq(CoreResult.error_code(GtBoard.load_file("res://project.godot")), GtBoard.INVALID_BOARD)


func test_validate_leaves_its_input_alone() -> void:
	var data: Dictionary = _data()
	var before: String = JSON.stringify(data)
	GtBoard.validate(data)
	assert_eq(JSON.stringify(data), before)


# --- geometry ------------------------------------------------------------------------

func test_the_large_board_has_the_expected_counts() -> void:
	var board: GtBoard = _board()
	assert_eq(board.hexes.size(), 30)
	assert_eq(board.corners().size(), 80)
	assert_eq(board.edges().size(), 109)
	assert_eq(board.coastal_edges().size(), 38)


func test_euler_holds_for_the_board() -> void:
	var board: GtBoard = _board()
	assert_eq(board.corners().size() - board.edges().size() + board.hexes.size(), 1, "V - E + F = 1 for a disc")


func test_every_hex_has_six_distinct_corners_and_edges() -> void:
	var board: GtBoard = _board()
	for hex: Vector2i in board.hexes:
		var corners: Array[String] = board.corners_of_hex(hex)
		var edges: Array[String] = board.edges_of_hex(hex)
		assert_eq(corners.size(), 6)
		assert_eq(edges.size(), 6)
		assert_eq(_unique(corners).size(), 6, "corners of %s" % str(hex))
		assert_eq(_unique(edges).size(), 6, "edges of %s" % str(hex))


func test_ids_are_the_same_whichever_hex_you_come_from() -> void:
	var board: GtBoard = _board()
	for corner: String in board.corners():
		for hex: Vector2i in board.hexes_of_corner(corner):
			assert_true(board.corners_of_hex(hex).has(corner), "%s from %s" % [corner, str(hex)])
	for edge: String in board.edges():
		for hex: Vector2i in board.hexes_of_edge(edge):
			assert_true(board.edges_of_hex(hex).has(edge))


func test_corners_touch_one_to_three_land_hexes() -> void:
	var board: GtBoard = _board()
	var total: int = 0
	for corner: String in board.corners():
		var count: int = board.hexes_of_corner(corner).size()
		assert_between(count, 1, 3)
		total += count
	assert_eq(total, 30 * 6, "each hex has six corners")


func test_edges_touch_one_or_two_land_hexes_and_have_two_corners() -> void:
	var board: GtBoard = _board()
	var corner_set: Dictionary = _unique(board.corners())
	for edge: String in board.edges():
		assert_between(board.hexes_of_edge(edge).size(), 1, 2)
		var ends: Array[String] = board.corners_of_edge(edge)
		assert_eq(ends.size(), 2)
		assert_ne(ends[0], ends[1])
		for end: String in ends:
			assert_true(corner_set.has(end), "%s is a board corner" % end)
			assert_true(board.edges_of_corner(end).has(edge), "corner %s lists edge %s" % [end, edge])


func test_corners_have_two_or_three_edges_and_matching_neighbours() -> void:
	var board: GtBoard = _board()
	var twos: int = 0
	var threes: int = 0
	for corner: String in board.corners():
		var edges: Array[String] = board.edges_of_corner(corner)
		assert_between(edges.size(), 2, 3)
		var near: Array[String] = board.adjacent_corners(corner)
		assert_eq(near.size(), edges.size())
		assert_false(near.has(corner))
		for other: String in near:
			assert_true(board.adjacent_corners(other).has(corner), "adjacency is symmetric")
		if edges.size() == 2:
			twos += 1
		else:
			threes += 1
	assert_eq(twos + threes, 80)
	assert_eq(twos * 2 + threes * 3, 109 * 2, "every edge has two ends")
	assert_eq(twos, 22, "rim corners that touch a single land hex")
	assert_eq(threes, 58)


func test_coastal_edges_have_exactly_one_land_hex_and_form_a_ring() -> void:
	var board: GtBoard = _board()
	var coast: Array[String] = board.coastal_edges()
	var counts: Dictionary = {}
	for edge: String in coast:
		assert_eq(board.hexes_of_edge(edge).size(), 1)
		for corner: String in board.corners_of_edge(edge):
			counts[corner] = int(counts.get(corner, 0)) + 1
	for corner: String in counts:
		assert_eq(counts[corner], 2, "each rim corner joins exactly two coastal edges")
	assert_eq(counts.size(), 38)


func test_a_village_blocks_its_neighbours_corners() -> void:
	var board: GtBoard = _board()
	var centre: String = board.corners_of_hex(Vector2i(0, 0))[0]
	assert_eq(board.adjacent_corners(centre).size(), 3, "an inland corner has three one-edge neighbours")
	for other: String in board.adjacent_corners(centre):
		assert_false(board.adjacent_corners(centre).has(centre))
		assert_true(board.corners().has(other))


func test_ids_have_a_stable_readable_form() -> void:
	assert_eq(GtBoard.edge_id(Vector2i(0, 0), 0), "0,0|1,0")
	assert_eq(GtBoard.edge_id(Vector2i(1, 0), 3), "0,0|1,0", "the same edge from the other hex")
	assert_eq(GtBoard.corner_id(Vector2i(0, 0), 0), "1,-1|0,0|1,0")
	assert_eq(GtBoard.parse_id("1,-1|0,0|1,0"), [Vector2i(1, -1), Vector2i(0, 0), Vector2i(1, 0)])


func test_land_neighbours_stay_on_the_board() -> void:
	var board: GtBoard = _board()
	assert_eq(board.land_neighbors(Vector2i(-1, 0)).size(), 6, "an inland hex")
	assert_true(board.land_neighbors(Vector2i(0, -3)).size() < 6, "a rim hex")
	assert_true(board.has_hex(Vector2i(0, 0)))
	assert_false(board.has_hex(Vector2i(9, 9)))


# --- validation failures -------------------------------------------------------------

func test_a_non_text_name_is_refused() -> void:
	var data: Dictionary = _data()
	data["name"] = 5
	assert_eq(_error_of(data), GtBoard.INVALID_BOARD)


func test_bad_hex_lists_are_refused() -> void:
	for bad: Variant in [null, "x", [], [[0, 0]], [[0, 0, 0]]]:
		var data: Dictionary = _data()
		data["hexes"] = bad
		assert_eq(_error_of(data), GtBoard.INVALID_BOARD, str(bad))
	var data2: Dictionary = _data()
	data2["hexes"][3] = "a"
	assert_eq(_error_of(data2), GtBoard.INVALID_BOARD)
	var data3: Dictionary = _data()
	data3["hexes"][3] = [0.5, 1]
	assert_eq(_error_of(data3), GtBoard.INVALID_BOARD)


func test_a_duplicate_hex_is_refused() -> void:
	var data: Dictionary = _data()
	data["hexes"][5] = data["hexes"][4]
	assert_eq(_error_of(data), GtBoard.INVALID_BOARD)


func test_a_disconnected_island_is_refused() -> void:
	var data: Dictionary = _data()
	data["hexes"][29] = [10, 10]
	var result: Dictionary = GtBoard.validate(data)
	assert_eq(CoreResult.error_code(result), GtBoard.INVALID_BOARD)
	assert_string_contains(result["error"]["message"], "connected")


func test_tile_counts_must_match_the_hex_count() -> void:
	var data: Dictionary = _data()
	data["tiles"]["timber"] = 7
	assert_eq(_error_of(data), GtBoard.INVALID_BOARD)


func test_tile_types_must_all_be_present_and_known() -> void:
	var missing: Dictionary = _data()
	missing["tiles"].erase("stone")
	assert_eq(_error_of(missing), GtBoard.INVALID_BOARD)
	var extra: Dictionary = _data()
	extra["tiles"]["lava"] = 1
	assert_eq(_error_of(extra), GtBoard.INVALID_BOARD)
	var no_desert: Dictionary = _data()
	no_desert["tiles"]["desert"] = 0
	no_desert["tiles"]["timber"] = 8
	assert_eq(_error_of(no_desert), GtBoard.INVALID_BOARD, "the blocker needs a desert to start on")
	var text: Dictionary = _data()
	text["tiles"] = "many"
	assert_eq(_error_of(text), GtBoard.INVALID_BOARD)


func test_bad_tokens_are_refused() -> void:
	for bad_value: Variant in [7, 1, 13, 0, "6", 6.5]:
		var data: Dictionary = _data()
		data["tokens"][0] = bad_value
		assert_eq(_error_of(data), GtBoard.INVALID_BOARD, "token %s" % str(bad_value))
	var short: Dictionary = _data()
	short["tokens"].pop_back()
	assert_eq(_error_of(short), GtBoard.INVALID_BOARD, "one token short")
	var long: Dictionary = _data()
	long["tokens"].append(5)
	assert_eq(_error_of(long), GtBoard.INVALID_BOARD, "one token too many")
	var not_list: Dictionary = _data()
	not_list["tokens"] = 28
	assert_eq(_error_of(not_list), GtBoard.INVALID_BOARD)


func test_a_harbor_slot_off_the_island_or_inland_is_refused() -> void:
	var off: Dictionary = _data()
	off["harbor_slots"][0] = {"hex": [20, 20], "side": 0}
	assert_eq(_error_of(off), GtBoard.INVALID_BOARD)
	var inland: Dictionary = _data()
	inland["harbor_slots"][0] = {"hex": [-1, 0], "side": 0}
	var result: Dictionary = GtBoard.validate(inland)
	assert_eq(CoreResult.error_code(result), GtBoard.INVALID_BOARD)
	assert_string_contains(result["error"]["message"], "coast")


func test_malformed_harbor_slots_are_refused() -> void:
	for bad: Variant in [5, {"hex": [0, -3]}, {"hex": [0, -3], "side": 6}, {"hex": [0, -3], "side": -1},
			{"hex": [0], "side": 1}, {"hex": "x", "side": 1}]:
		var data: Dictionary = _data()
		data["harbor_slots"][0] = bad
		assert_eq(_error_of(data), GtBoard.INVALID_BOARD, str(bad))


func test_harbor_slots_may_not_repeat_an_edge_or_share_a_corner() -> void:
	var same_edge: Dictionary = _data()
	same_edge["harbor_slots"][1] = same_edge["harbor_slots"][0].duplicate()
	assert_eq(_error_of(same_edge), GtBoard.INVALID_BOARD)
	var touching: Dictionary = _data()
	# Hex [0,-3] sides 1 and 2 are neighbouring coastal edges: they meet at a corner.
	touching["harbor_slots"][1] = {"hex": [0, -3], "side": 2}
	touching["harbor_slots"][2] = {"hex": [0, -3], "side": 1}
	var result: Dictionary = GtBoard.validate(touching)
	assert_eq(CoreResult.error_code(result), GtBoard.INVALID_BOARD)
	assert_string_contains(result["error"]["message"], "corner")


func test_the_harbor_pool_must_fit_the_slots_and_use_known_kinds() -> void:
	var short: Dictionary = _data()
	short["harbor_pool"].pop_back()
	assert_eq(_error_of(short), GtBoard.INVALID_BOARD)
	var unknown: Dictionary = _data()
	unknown["harbor_pool"][0] = "gold"
	assert_eq(_error_of(unknown), GtBoard.INVALID_BOARD)
	var wrong_type: Dictionary = _data()
	wrong_type["harbor_pool"] = "generic"
	assert_eq(_error_of(wrong_type), GtBoard.INVALID_BOARD)


func test_a_board_where_no_layout_can_separate_hot_tokens_is_refused() -> void:
	# Seven hexes in a flower, six tokens that are all 6s and 8s: some pair always touches.
	var data: Dictionary = {
		"name": "Hot",
		"hexes": [[0, 0], [1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]],
		"tiles": {"timber": 2, "clay": 1, "fleece": 1, "wheat": 1, "stone": 1, "desert": 1},
		"tokens": [6, 6, 6, 8, 8, 8],
		"harbor_slots": [],
		"harbor_pool": [],
	}
	var result: Dictionary = GtBoard.validate(data)
	assert_eq(CoreResult.error_code(result), GtBoard.INVALID_BOARD)
	assert_string_contains(result["error"]["message"], "6 and 8")
	data["tokens"] = [2, 3, 4, 5, 6, 8]
	assert_true(CoreResult.is_ok(GtBoard.validate(data)), "with a mix it is fine")


# --- layout --------------------------------------------------------------------------

func _layout(seed_value: int) -> Dictionary:
	var result: Dictionary = GtBoard.layout(_clean(), Prng.new(seed_value))
	assert_true(CoreResult.is_ok(result), str(result))
	return result["layout"]


func test_a_layout_has_the_right_pieces() -> void:
	var clean: Dictionary = _clean()
	var layout: Dictionary = _layout(1)
	var types: Dictionary = {}
	var tokens: Array = []
	for tile: Dictionary in layout["tiles"]:
		types[tile["type"]] = int(types.get(tile["type"], 0)) + 1
		if tile["type"] == GtBoard.DESERT:
			assert_eq(tile["token"], 0)
		else:
			tokens.append(tile["token"])
	assert_eq(types, clean["tiles"])
	tokens.sort()
	assert_eq(tokens, clean["tokens"])
	var kinds: Array = []
	for harbor: Dictionary in layout["harbors"]:
		kinds.append(harbor["kind"])
	kinds.sort()
	assert_eq(kinds, clean["harbor_pool"])


func test_tiles_come_in_board_hex_order() -> void:
	var board: GtBoard = _board()
	var layout: Dictionary = _layout(2)
	for i: int in board.hexes.size():
		assert_eq(Vector2i(layout["tiles"][i]["q"], layout["tiles"][i]["r"]), board.hexes[i])


func test_the_blocker_starts_on_a_desert() -> void:
	for seed_value: int in 40:
		var layout: Dictionary = _layout(seed_value)
		var found: bool = false
		for tile: Dictionary in layout["tiles"]:
			if tile["q"] == layout["blocker"]["q"] and tile["r"] == layout["blocker"]["r"]:
				assert_eq(tile["type"], GtBoard.DESERT)
				found = true
		assert_true(found)


func test_harbors_sit_on_coastal_edges_with_the_right_rates() -> void:
	var board: GtBoard = _board()
	var coast: Dictionary = _unique(board.coastal_edges())
	for harbor: Dictionary in _layout(3)["harbors"]:
		assert_true(coast.has(harbor["edge"]))
		assert_eq(harbor["corners"], board.corners_of_edge(harbor["edge"]))
		assert_eq(harbor["ratio"], 3 if harbor["kind"] == GtBoard.GENERIC else 2)


func test_the_same_seed_gives_the_same_layout() -> void:
	assert_eq(_layout(77), _layout(77))
	assert_eq(_layout(0), _layout(0))


func test_different_seeds_give_different_layouts() -> void:
	var seen: Dictionary = {}
	for seed_value: int in 30:
		seen[JSON.stringify(_layout(seed_value))] = true
	assert_gt(seen.size(), 25, "layouts are shuffled, not fixed")


func test_a_layout_is_json_safe_and_survives_a_round_trip() -> void:
	var layout: Dictionary = _layout(5)
	var back: Dictionary = Envelope.normalize(JSON.parse_string(JSON.stringify(layout)))
	assert_eq(back, layout)


func test_hot_tokens_never_touch_over_many_seeds() -> void:
	var board: GtBoard = _board()
	for seed_value: int in 300:
		var token_at: Dictionary = {}
		for tile: Dictionary in _layout(seed_value)["tiles"]:
			token_at[Vector2i(tile["q"], tile["r"])] = tile["token"]
		for hex: Vector2i in token_at:
			if token_at[hex] != 6 and token_at[hex] != 8:
				continue
			for other: Vector2i in board.land_neighbors(hex):
				assert_false(token_at[other] == 6 or token_at[other] == 8, "seed %d: %s touches %s" % [seed_value, str(hex), str(other)])


func test_layout_does_not_change_its_input() -> void:
	var clean: Dictionary = _clean()
	var before: String = JSON.stringify(clean)
	GtBoard.layout(clean, Prng.new(9))
	assert_eq(JSON.stringify(clean), before)


func test_layout_advances_the_prng_it_is_given() -> void:
	var prng: Prng = Prng.new(4)
	var before: String = prng.state_text()
	GtBoard.layout(_clean(), prng)
	assert_ne(prng.state_text(), before, "the draws come from the shared generator")


# --- helpers -------------------------------------------------------------------------

func _unique(items: Array) -> Dictionary:
	var out: Dictionary = {}
	for item: Variant in items:
		out[item] = true
	return out
