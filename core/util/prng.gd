class_name Prng
extends RefCounted
## A small seeded random number generator that gives the same numbers on every Godot
## version and platform (unlike RandomNumberGenerator, whose algorithm is engine-owned).
## Games keep its seed and state in their game state so rolls are reproducible and survive
## save/load (rules 2 and 8).
##
## Algorithm: xoshiro128** (four 32-bit words). Only 32-bit values are ever stored and
## every product is kept below 2^63, so no 64-bit overflow behaviour is involved.
## Seeding mixes the 64-bit seed into the four words with murmur3's finalizer.
## Ranges use rejection sampling, so they are unbiased.
##
## State is serialised as decimal strings ("seed" and "state"): JSON numbers are floats
## and would lose 64-bit values.

const _MASK: int = 0xFFFFFFFF
const _TWO_32: int = 0x100000000

var _seed: int = 0
var _s0: int = 0
var _s1: int = 0
var _s2: int = 0
var _s3: int = 0


func _init(seed_value: int = 0) -> void:
	_seed = seed_value
	var lo: int = seed_value & _MASK
	var hi: int = (seed_value >> 32) & _MASK
	_s0 = _fmix32(lo ^ 0x9E3779B9)
	_s1 = _fmix32(((hi + 0x7F4A7C15) & _MASK) ^ _s0)
	_s2 = _fmix32(_s1 ^ lo ^ 0xC2B2AE35)
	_s3 = _fmix32((_s2 + hi + 1) & _MASK)
	if (_s0 | _s1 | _s2 | _s3) == 0:
		_s0 = 1


## Rebuilds a generator from the strings produced by seed_text() and state_text().
## Returns null if they are not valid.
static func restore(seed_text: String, state_text: String) -> Prng:
	if not seed_text.is_valid_int():
		return null
	var words: PackedStringArray = state_text.split(",")
	if words.size() != 4:
		return null
	var values: Array[int] = []
	for word: String in words:
		if not word.is_valid_int():
			return null
		var value: int = word.to_int()
		if value < 0 or value > _MASK:
			return null
		values.append(value)
	if (values[0] | values[1] | values[2] | values[3]) == 0:
		return null
	var prng: Prng = Prng.new(seed_text.to_int())
	prng._s0 = values[0]
	prng._s1 = values[1]
	prng._s2 = values[2]
	prng._s3 = values[3]
	return prng


## For tests: a generator with exactly these four state words.
static func from_words(a: int, b: int, c: int, d: int) -> Prng:
	var prng: Prng = Prng.new(0)
	prng._s0 = a & _MASK
	prng._s1 = b & _MASK
	prng._s2 = c & _MASK
	prng._s3 = d & _MASK
	return prng


func seed_text() -> String:
	return str(_seed)


func state_text() -> String:
	return "%d,%d,%d,%d" % [_s0, _s1, _s2, _s3]


## Next 32 random bits as a non-negative int.
func next_u32() -> int:
	var result: int = _mul32(_rotl(_mul32(_s1, 5), 7), 9)
	var t: int = (_s1 << 9) & _MASK
	_s2 ^= _s0
	_s3 ^= _s1
	_s1 ^= _s2
	_s0 ^= _s3
	_s2 ^= t
	_s3 = _rotl(_s3, 11)
	return result


## Uniform integer in [low, high], both inclusive, without modulo bias.
func range_int(low: int, high: int) -> int:
	assert(high >= low and high - low < _TWO_32, "range_int needs low <= high and a span of at most 2^32")
	var span: int = high - low + 1
	if span == 1:
		return low
	var limit: int = _TWO_32 - (_TWO_32 % span)
	var value: int = next_u32()
	while value >= limit:
		value = next_u32()
	return low + value % span


# --- 32-bit helpers (everything stays below 2^63) ----------------------------------

static func _rotl(x: int, k: int) -> int:
	return ((x << k) | (x >> (32 - k))) & _MASK


## (a * b) mod 2^32 for 32-bit a and b, split so no intermediate product overflows.
static func _mul32(a: int, b: int) -> int:
	return ((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & _MASK


static func _fmix32(value: int) -> int:
	var h: int = value & _MASK
	h ^= h >> 16
	h = _mul32(h, 0x85EBCA6B)
	h ^= h >> 13
	h = _mul32(h, 0xC2B2AE35)
	h ^= h >> 16
	return h
