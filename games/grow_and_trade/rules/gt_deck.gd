class_name GtDeck
extends RefCounted
## The fortune card deck for Grow & Trade. Pure logic, no nodes. A deck is a plain Array of card type
## strings, top card first (index 0). The order is host-only secret state: it never appears in a view,
## and a view may show only how many cards remain.
##
## DRAW ORDER (must stay stable; changing it breaks saves and replays and needs a state_version bump):
##   1. The unshuffled deck lists each entry of the config's "deck" list in file order, repeated "count" times.
##   2. shuffle() is a Fisher-Yates shuffle over the shared Prng: for i from n-1 down to 1 it draws
##      j = prng.range_int(0, i) (inclusive) and swaps cards i and j. That is exactly n-1 draws for n cards
##      (none for 0 or 1 cards).
##   3. draw() takes index 0 and consumes no randomness.
## The Prng passed in is the game's own (its state lives in the game state), so the caller keeps it afterwards.

const GUARD: String = "guard"
const TWO_PATHS: String = "two_paths"
const HARVEST: String = "harvest"
const SWEEP: String = "sweep"
const POINT: String = "point"
const CARD_TYPES: Array[String] = [GUARD, TWO_PATHS, HARVEST, SWEEP, POINT]

const DECK_EMPTY: String = "DECK_EMPTY"


## The unshuffled deck for a validated config (see GtBank.validate_config).
static func build(config: Dictionary) -> Array:
	var cards: Array = []
	for entry: Dictionary in config["deck"]:
		for i: int in int(entry["count"]):
			cards.append(entry["type"])
	return cards


## A shuffled copy of `cards`; the input is not changed. Uses exactly max(n - 1, 0) Prng draws.
static func shuffle(cards: Array, prng: Prng) -> Array:
	var out: Array = cards.duplicate()
	var i: int = out.size() - 1
	while i >= 1:
		var j: int = prng.range_int(0, i)
		var held: Variant = out[i]
		out[i] = out[j]
		out[j] = held
		i -= 1
	return out


## A freshly built and shuffled deck for a table.
static func new_deck(config: Dictionary, prng: Prng) -> Array:
	return shuffle(build(config), prng)


## Takes the top card. Returns {ok, card, deck} (deck without that card, input unchanged) or DECK_EMPTY.
static func draw(deck: Array) -> Dictionary:
	if deck.is_empty():
		return CoreResult.failure(DECK_EMPTY, "There are no fortune cards left.")
	return CoreResult.success({"card": deck[0], "deck": deck.slice(1)})


static func remaining(deck: Array) -> int:
	return deck.size()


## How many cards of each type a deck holds: {type: count}.
static func counts(deck: Array) -> Dictionary:
	var out: Dictionary = {}
	for card: Variant in deck:
		out[card] = int(out.get(card, 0)) + 1
	return out
