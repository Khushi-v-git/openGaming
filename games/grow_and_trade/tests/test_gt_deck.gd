extends GutTest
## The fortune card deck: contents, seeded shuffle, draw order. Headless.

var config: Dictionary


func before_each() -> void:
	config = GtBank.load_config()["config"]


func test_the_unshuffled_deck_has_the_configured_mix() -> void:
	var deck: Array = GtDeck.build(config)
	assert_eq(deck.size(), 25)
	assert_eq(GtDeck.counts(deck), {"guard": 14, "two_paths": 2, "harvest": 2, "sweep": 2, "point": 5})
	assert_eq(deck.slice(0, 14), ["guard", "guard", "guard", "guard", "guard", "guard", "guard", "guard", "guard", "guard", "guard", "guard", "guard", "guard"], "file order, grouped by type")
	assert_eq(deck[24], "point")


func test_a_shuffle_keeps_the_same_cards() -> void:
	var deck: Array = GtDeck.new_deck(config, Prng.new(5))
	assert_eq(deck.size(), 25)
	assert_eq(GtDeck.counts(deck), GtDeck.counts(GtDeck.build(config)))


func test_the_same_seed_gives_the_same_deck_and_other_seeds_differ() -> void:
	var one: Array = GtDeck.new_deck(config, Prng.new(1234))
	var two: Array = GtDeck.new_deck(config, Prng.new(1234))
	assert_eq(one, two)
	var different: int = 0
	for seed_value: int in range(1, 21):
		if GtDeck.new_deck(config, Prng.new(seed_value)) != one:
			different += 1
	assert_gt(different, 18, "other seeds give other orders")


func test_the_shuffle_is_fisher_yates_over_range_int_from_the_top() -> void:
	# The documented draw order, replayed by hand with a second Prng of the same seed.
	var cards: Array = GtDeck.build(config)
	var mirror: Prng = Prng.new(99)
	var expected: Array = cards.duplicate()
	var i: int = expected.size() - 1
	while i >= 1:
		var j: int = mirror.range_int(0, i)
		var held: Variant = expected[i]
		expected[i] = expected[j]
		expected[j] = held
		i -= 1
	assert_eq(GtDeck.shuffle(cards, Prng.new(99)), expected)


func test_a_shuffle_of_n_cards_uses_exactly_n_minus_one_draws() -> void:
	var cards: Array = GtDeck.build(config)
	var used: Prng = Prng.new(31)
	GtDeck.shuffle(cards, used)
	var mirror: Prng = Prng.new(31)
	for i: int in range(cards.size() - 1, 0, -1):
		mirror.range_int(0, i)
	assert_eq(used.state_text(), mirror.state_text())
	var untouched: Prng = Prng.new(31)
	GtDeck.shuffle([], untouched)
	GtDeck.shuffle(["guard"], untouched)
	assert_eq(untouched.state_text(), Prng.new(31).state_text(), "0 or 1 cards use no randomness")


func test_shuffling_does_not_change_its_input() -> void:
	var cards: Array = GtDeck.build(config)
	var before: Array = cards.duplicate()
	GtDeck.shuffle(cards, Prng.new(8))
	assert_eq(cards, before)


func test_drawing_takes_the_top_card_without_touching_the_input() -> void:
	var deck: Array = ["point", "guard", "sweep"]
	var first: Dictionary = GtDeck.draw(deck)
	assert_true(CoreResult.is_ok(first))
	assert_eq(first["card"], "point")
	assert_eq(first["deck"], ["guard", "sweep"])
	assert_eq(deck, ["point", "guard", "sweep"])
	assert_eq(GtDeck.remaining(first["deck"]), 2)


func test_drawing_the_whole_deck_gives_every_card_once_then_refuses() -> void:
	var deck: Array = GtDeck.new_deck(config, Prng.new(2026))
	var drawn: Array = []
	while not deck.is_empty():
		var result: Dictionary = GtDeck.draw(deck)
		drawn.append(result["card"])
		deck = result["deck"]
	assert_eq(drawn.size(), 25)
	assert_eq(GtDeck.counts(drawn), GtDeck.counts(GtDeck.build(config)))
	assert_eq(CoreResult.error_code(GtDeck.draw(deck)), GtDeck.DECK_EMPTY)


func test_a_deck_survives_a_json_round_trip() -> void:
	var deck: Array = GtDeck.new_deck(config, Prng.new(3))
	var back: Variant = JSON.parse_string(JSON.stringify(deck))
	assert_eq(back, deck)
