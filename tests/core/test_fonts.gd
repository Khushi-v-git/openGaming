extends GutTest
## The shared font covers Latin, and Devanagari names fall back to Baloo 2.


func test_the_theme_uses_fredoka_with_baloo_as_fallback() -> void:
	var theme: Theme = AppTheme.build()
	assert_not_null(theme.default_font)
	var variation: FontVariation = theme.default_font
	assert_eq((variation.base_font as FontFile).resource_path, AppTheme.FONT_PATH)
	assert_eq((variation.fallbacks[0] as FontFile).resource_path, AppTheme.FALLBACK_FONT_PATH)


func test_latin_is_in_fredoka_and_devanagari_is_not() -> void:
	var fredoka: FontFile = load(AppTheme.FONT_PATH)
	assert_true(fredoka.has_char("A".unicode_at(0)))
	assert_true(fredoka.has_char("é".unicode_at(0)))
	assert_false(fredoka.has_char("न".unicode_at(0)), "Fredoka has no Devanagari")


func test_a_hindi_name_is_drawable_through_the_fallback() -> void:
	var baloo: FontFile = load(AppTheme.FALLBACK_FONT_PATH)
	for letter: String in "नमस्ते":
		assert_true(baloo.has_char(letter.unicode_at(0)), "Baloo 2 has %s" % letter)
	var width: float = AppTheme.build_font().get_string_size("नमस्ते", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	assert_gt(width, 20.0)


func test_font_licences_ship_next_to_the_fonts() -> void:
	for name: String in ["OFL-fredoka.txt", "OFL-baloo2.txt"]:
		var text: String = FileAccess.get_file_as_string("res://core/assets/fonts/" + name)
		assert_string_contains(text, "SIL OPEN FONT LICENSE Version 1.1")
