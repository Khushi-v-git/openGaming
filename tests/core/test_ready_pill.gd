extends GutTest
## The ready pill: an ordinary toggle button that wears the design's states.

var viewport: SubViewport


func before_each() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child_autofree(viewport)


func after_each() -> void:
	await get_tree().process_frame


func _pill(width: float = 560.0) -> ReadyPill:
	var pill: ReadyPill = ReadyPill.new()
	pill.custom_minimum_size.x = width
	viewport.add_child(pill)
	await get_tree().process_frame
	await get_tree().process_frame
	return pill


func _fill(pill: ReadyPill) -> Color:
	return (pill.get_theme_stylebox("normal") as StyleBoxFlat).bg_color


func test_it_is_a_toggle_button_that_behaves_like_a_check_button_did() -> void:
	var pill: ReadyPill = await _pill()
	assert_true(pill is Button)
	assert_true(pill.toggle_mode)
	var toggles: Array = []
	pill.toggled.connect(func(on: bool) -> void: toggles.append(on))
	pill.button_pressed = true
	assert_eq(toggles, [true])
	pill.set_pressed_no_signal(false)
	assert_eq(toggles, [true], "set_pressed_no_signal stays silent")
	assert_false(pill.button_pressed)
	pill.pressed.emit()
	assert_eq(toggles.size(), 1, "pressed alone does not toggle: the click does")


func test_not_ready_is_a_cream_pill_with_im_ready() -> void:
	var pill: ReadyPill = await _pill()
	assert_eq(pill.text, "I'm ready")
	assert_eq(_fill(pill), Tokens.PAPER_CREAM)
	assert_eq(pill.get_theme_color("font_color"), Tokens.INDIGO)
	assert_false(pill.is_ready_look())


func test_ready_is_forest_green_with_ready_and_a_cream_text() -> void:
	var pill: ReadyPill = await _pill()
	pill.button_pressed = true
	await get_tree().process_frame
	assert_eq(pill.text, "Ready!")
	assert_eq(_fill(pill), Tokens.FOREST_GREEN)
	assert_eq(pill.get_theme_color("font_color"), Tokens.PAPER_CREAM)
	assert_true(pill.is_ready_look())
	pill.button_pressed = false
	await get_tree().process_frame
	assert_eq(pill.text, "I'm ready")
	assert_eq(_fill(pill), Tokens.PAPER_CREAM)


func test_disabled_is_flat_and_grey_whatever_it_was() -> void:
	var pill: ReadyPill = await _pill()
	pill.disabled = true
	await get_tree().process_frame
	assert_eq(_fill(pill), ReadyPill.DISABLED_FILL)
	assert_eq(pill.get_theme_color("font_disabled_color"), ReadyPill.DISABLED_TEXT)
	assert_eq((pill.get_theme_stylebox("disabled") as StyleBoxFlat).shadow_offset.y, 3.0, "a flat 3px shadow")
	pill.button_pressed = true  # the host kept it ready when the game started
	await get_tree().process_frame
	assert_eq(_fill(pill), ReadyPill.DISABLED_FILL)
	assert_eq(pill.text, "I'm ready")
	assert_false(pill.is_ready_look(), "a disabled pill never looks ready")


func test_hover_lifts_and_pressing_sinks_with_a_flatter_shadow() -> void:
	var pill: ReadyPill = await _pill()
	var shadow: Callable = func() -> float: return (pill.get_theme_stylebox("normal") as StyleBoxFlat).shadow_offset.y
	assert_eq(shadow.call(), 6.0)
	pill.mouse_entered.emit()
	await get_tree().process_frame
	assert_eq(shadow.call(), 8.0, "hover: a longer hard shadow")
	pill.button_down.emit()
	await get_tree().process_frame
	assert_eq(shadow.call(), 2.0, "pressed: the shadow flattens")
	assert_gt((pill.get_theme_stylebox("normal") as StyleBoxFlat).content_margin_top, 8.0, "and the text sinks")
	pill.button_up.emit()
	pill.mouse_exited.emit()
	await get_tree().process_frame
	assert_eq(shadow.call(), 6.0)


func test_it_fits_a_compact_card_and_keeps_its_height() -> void:
	var pill: ReadyPill = await _pill(0.0)
	assert_gte(pill.size.y, 80.0)
	assert_lte(pill.size.y, 100.0)
	var wide: ReadyPill = await _pill(560.0)
	assert_gte(wide.size.x, 560.0)


func test_the_dot_and_starburst_are_drawn_by_a_child_that_ignores_the_mouse() -> void:
	var pill: ReadyPill = await _pill()
	var decor: Control = null
	for child: Node in pill.get_children():
		if child is Control:
			decor = child
	assert_not_null(decor)
	assert_eq(decor.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_not_null(pill._starburst)


func test_the_chip_dot_is_empty_until_ready_and_has_the_designs_check() -> void:
	var empty: ChipDot = ChipDot.new(false)
	var done: ChipDot = ChipDot.new(true)
	assert_false(empty.ready_mark)
	assert_true(done.ready_mark)
	assert_eq(ChipDot.CHECK.size(), 6)
	assert_eq(empty.size, Vector2(30.0, 30.0))
	empty.free()
	done.free()
