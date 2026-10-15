extends GutTest
## The leaf border is deterministic, scales with the rectangle, stays at the edges and only does
## its work when the size changes.


func _border(width: int, height: int) -> LeafBorder:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(width, height)
	add_child_autofree(viewport)
	var border: LeafBorder = LeafBorder.new()
	viewport.add_child(border)
	await get_tree().process_frame
	return border


func _signature(border: LeafBorder) -> Array:
	return border.leaves.map(func(l: Dictionary) -> Array: return [snappedf(l["centre"].x, 0.01), snappedf(l["centre"].y, 0.01), l["c1"], l["c2"]])


func test_it_makes_leaves_all_round_the_edges() -> void:
	var border: LeafBorder = await _border(1920, 1080)
	assert_gt(border.leaves.size(), 40)
	var top: int = 0
	var bottom: int = 0
	var left: int = 0
	var right: int = 0
	for leaf: Dictionary in border.leaves:
		var c: Vector2 = leaf["centre"]
		top += 1 if c.y < 80.0 else 0
		bottom += 1 if c.y > 1000.0 else 0
		left += 1 if c.x < 80.0 else 0
		right += 1 if c.x > 1840.0 else 0
	for side: int in [top, bottom, left, right]:
		assert_gt(side, 5)


func test_the_same_size_always_gives_the_same_border() -> void:
	var a: LeafBorder = await _border(1280, 720)
	var b: LeafBorder = await _border(1280, 720)
	assert_eq(_signature(a), _signature(b))
	assert_ne(_signature(a), _signature(await _border(1920, 1080)))


func test_it_scales_with_the_short_side() -> void:
	var small: LeafBorder = await _border(1280, 720)
	var large: LeafBorder = await _border(1920, 1080)
	var small_leaf: float = small.leaves[0]["radius"]
	var large_leaf: float = large.leaves[0]["radius"]
	assert_almost_eq(small_leaf / large_leaf, 720.0 / 1080.0, 0.0001, "the first leaf is the same leaf, drawn smaller")
	assert_almost_eq(LeafBorder.scale_for(Vector2(1920, 1080)), 1.0, 0.0001)
	assert_almost_eq(LeafBorder.scale_for(Vector2(1280, 720)), 720.0 / 1080.0, 0.0001)


func test_leaves_stay_near_the_edges_and_inside_a_sensible_margin() -> void:
	for window: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(900, 900)]:
		var border: LeafBorder = await _border(window.x, window.y)
		var s: float = LeafBorder.scale_for(Vector2(window))
		for leaf: Dictionary in border.leaves:
			for point: Vector2 in (leaf["outer"] as PackedVector2Array):
				assert_gt(point.x, -110.0 * s, "%s: not far off the left" % str(window))
				assert_lt(point.x, float(window.x) + 110.0 * s)
				assert_gt(point.y, -110.0 * s)
				assert_lt(point.y, float(window.y) + 110.0 * s)
			var c: Vector2 = leaf["centre"]
			var to_edge: float = minf(minf(c.x, float(window.x) - c.x), minf(c.y, float(window.y) - c.y))
			assert_lt(to_edge, 80.0 * s, "%s: a leaf is within about 80 px (at 1080p) of an edge" % str(window))


func test_a_leaf_is_a_closed_shape_with_two_arcs() -> void:
	var points: PackedVector2Array = LeafBorder.leaf_points(100.0, 50.0)
	assert_gt(points.size(), 12)
	assert_eq(points[0], Vector2(0.0, 50.0), "starts at the bottom-left tip")
	var tip: Vector2 = points[LeafBorder.ARC_POINTS]
	assert_almost_eq(tip.x, 100.0, 0.001, "the top-right tip")
	assert_almost_eq(tip.y, 0.0, 0.001)
	for p: Vector2 in points:
		assert_between(p.x, -0.001, 100.001)
		assert_between(p.y, -0.001, 50.001)
	assert_true(Geometry2D.triangulate_polygon(points).size() > 0, "the polygon can be filled")


func test_every_leaf_has_its_two_colours_from_the_design_palette() -> void:
	var border: LeafBorder = await _border(1920, 1080)
	var allowed: Array[Color] = []
	for pair: Array in LeafBorder.PAIRS:
		allowed.append(Color(pair[0]))
		allowed.append(Color(pair[1]))
	for leaf: Dictionary in border.leaves:
		assert_true(allowed.has(leaf["c1"]) and allowed.has(leaf["c2"]))
		assert_ne(leaf["c1"], leaf["c2"])


func test_it_only_lays_out_when_the_size_changes() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child_autofree(viewport)
	var border: LeafBorder = LeafBorder.new()
	viewport.add_child(border)
	await get_tree().process_frame
	var count: int = border.layout_count
	assert_gte(count, 1)
	for _i: int in 30:
		await get_tree().process_frame
	assert_eq(border.layout_count, count, "idle frames do no layout work")
	viewport.size = Vector2i(1920, 1080)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(border.layout_count, count)
	var after: int = border.layout_count
	border.size = border.size  # the same size again
	assert_eq(border.layout_count, after)


func test_it_never_catches_the_mouse() -> void:
	var border: LeafBorder = LeafBorder.new()
	assert_eq(border.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	border.free()
