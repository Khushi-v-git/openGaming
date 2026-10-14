extends GutTest
## Golden values come from an independent Python implementation of the same algorithm
## (xoshiro128** + murmur3 finalizer seeding). If any of these fail, rolls would differ
## between Godot versions or platforms and old saves/replays would stop reproducing.


func _take_u32(prng: Prng, count: int) -> Array[int]:
	var out: Array[int] = []
	for _i: int in count:
		out.append(prng.next_u32())
	return out


func _take_dice(prng: Prng, count: int) -> Array[int]:
	var out: Array[int] = []
	for _i: int in count:
		out.append(prng.range_int(1, 6))
	return out


# --- the algorithm itself ----------------------------------------------------------

func test_matches_the_published_xoshiro128_starstar_test_vector() -> void:
	assert_eq(_take_u32(Prng.from_words(1, 2, 3, 4), 6), [11520, 0, 5927040, 70819200, 2031721883, 1637235492] as Array[int])


# --- golden sequences (permanent) -------------------------------------------------------

func test_golden_seed_words() -> void:
	assert_eq(Prng.new(0).state_text(), "2462723854,775240163,144147271,3676528445")
	assert_eq(Prng.new(1).state_text(), "920564995,670327936,3245310522,2066905361")
	assert_eq(Prng.new(42).state_text(), "3856264912,2282290856,1178297421,860757876")
	assert_eq(Prng.new(123456789).state_text(), "3077212414,2740949102,3166753250,1383559095")
	assert_eq(Prng.new(-1).state_text(), "996586154,3599120240,3802144797,1036557639")


func test_golden_raw_outputs() -> void:
	assert_eq(_take_u32(Prng.new(0), 5), [2912319371, 824669019, 419659425, 2333838462, 1530979625] as Array[int])
	assert_eq(_take_u32(Prng.new(1), 5), [4208280443, 400278216, 3530528252, 1385312840, 2189596575] as Array[int])
	assert_eq(_take_u32(Prng.new(42), 5), [3395405556, 456567893, 3744787970, 768791073, 2764790857] as Array[int])


func test_golden_dice_sequences() -> void:
	assert_eq(_take_dice(Prng.new(0), 16), [6, 4, 4, 1, 6, 2, 6, 3, 3, 1, 2, 6, 4, 1, 4, 6] as Array[int])
	assert_eq(_take_dice(Prng.new(1), 16), [6, 1, 3, 3, 4, 2, 6, 5, 6, 4, 2, 6, 6, 5, 5, 4] as Array[int])
	assert_eq(_take_dice(Prng.new(42), 16), [1, 6, 3, 4, 2, 3, 2, 2, 1, 1, 1, 4, 3, 5, 6, 6] as Array[int])
	assert_eq(_take_dice(Prng.new(123456789), 16), [1, 1, 2, 6, 2, 3, 4, 2, 5, 2, 1, 5, 2, 4, 2, 4] as Array[int])
	assert_eq(_take_dice(Prng.new(-1), 16), [5, 3, 3, 3, 5, 4, 1, 3, 1, 6, 2, 4, 5, 2, 1, 1] as Array[int])


func test_golden_state_after_drawing() -> void:
	var prng: Prng = Prng.new(42)
	_take_dice(prng, 16)
	assert_eq(prng.state_text(), "2433310238,633234897,3678824000,878824747")


func test_golden_other_ranges() -> void:
	var zero_to_nine: Prng = Prng.new(2024)
	var got: Array[int] = []
	for _i: int in 12:
		got.append(zero_to_nine.range_int(0, 9))
	assert_eq(got, [1, 6, 5, 8, 1, 6, 8, 8, 0, 8, 8, 4] as Array[int])
	var signed: Prng = Prng.new(7)
	var got_signed: Array[int] = []
	for _i: int in 8:
		got_signed.append(signed.range_int(-5, 5))
	assert_eq(got_signed, [4, 1, 1, -4, -2, -5, -4, -1] as Array[int])


func test_large_seeds_keep_all_their_bits() -> void:
	# 2^53 + 1 is where floats start losing integers; the seed must still be distinct
	assert_eq(Prng.new(9007199254740993).state_text(), "920564995,3777983421,2726127530,471924250")
	assert_ne(Prng.new(9007199254740993).state_text(), Prng.new(9007199254740992).state_text())
	assert_eq(Prng.new(9007199254740993).seed_text(), "9007199254740993")
	assert_eq(_take_dice(Prng.new(4611686018427387904), 16), [1, 4, 1, 1, 5, 3, 2, 4, 6, 5, 1, 1, 1, 4, 2, 6] as Array[int])


# --- behaviour ------------------------------------------------------------------------

func test_same_seed_same_sequence_different_seed_different_sequence() -> void:
	assert_eq(_take_u32(Prng.new(5), 20), _take_u32(Prng.new(5), 20))
	assert_ne(_take_u32(Prng.new(5), 20), _take_u32(Prng.new(6), 20))


func test_a_span_of_one_consumes_no_randomness() -> void:
	var prng: Prng = Prng.new(99)
	var before: String = prng.state_text()
	assert_eq(prng.range_int(1, 1), 1)
	assert_eq(prng.state_text(), before)


func test_ranges_stay_inside_their_bounds() -> void:
	var prng: Prng = Prng.new(3)
	for _i: int in 5000:
		var v: int = prng.range_int(-3, 4)
		assert_between(v, -3, 4)
	for _i: int in 5000:
		assert_between(prng.range_int(1, 6), 1, 6)


func test_dice_are_close_to_uniform() -> void:
	var prng: Prng = Prng.new(20240601)
	var counts: Array[int] = [0, 0, 0, 0, 0, 0, 0]
	var rolls: int = 60000
	for _i: int in rolls:
		counts[prng.range_int(1, 6)] += 1
	for face: int in range(1, 7):
		assert_between(counts[face], 9400, 10600, "face %d came up %d times in %d rolls" % [face, counts[face], rolls])


func test_no_modulo_bias_for_a_span_that_does_not_divide_2_to_the_32() -> void:
	# span 3 * 2^30 leaves a large rejected tail: a biased "% span" would favour low values
	var prng: Prng = Prng.new(8)
	var span: int = 3 * 1073741824
	var low_third: int = 0
	var samples: int = 30000
	for _i: int in samples:
		if prng.range_int(0, span - 1) < span / 3:
			low_third += 1
	assert_between(low_third, 9400, 10600)


func test_state_round_trips_through_strings_and_continues_identically() -> void:
	var original: Prng = Prng.new(77)
	_take_u32(original, 13)
	var copy: Prng = Prng.restore(original.seed_text(), original.state_text())
	assert_not_null(copy)
	assert_eq(_take_u32(copy, 30), _take_u32(original, 30))


func test_state_strings_survive_json() -> void:
	var original: Prng = Prng.new(9007199254740993)
	_take_u32(original, 7)
	var text: String = JSON.stringify({"seed": original.seed_text(), "state": original.state_text()})
	var parsed: Dictionary = JSON.parse_string(text)
	var copy: Prng = Prng.restore(parsed["seed"], parsed["state"])
	assert_eq(_take_u32(copy, 10), _take_u32(original, 10))


func test_restore_rejects_bad_strings() -> void:
	assert_null(Prng.restore("abc", "1,2,3,4"))
	assert_null(Prng.restore("1", ""))
	assert_null(Prng.restore("1", "1,2,3"))
	assert_null(Prng.restore("1", "1,2,3,4,5"))
	assert_null(Prng.restore("1", "1,2,x,4"))
	assert_null(Prng.restore("1", "0,0,0,0"))
	assert_null(Prng.restore("1", "1,2,3,4294967296"))
	assert_null(Prng.restore("1", "-1,2,3,4"))
	assert_not_null(Prng.restore("1", "0,0,0,1"))
