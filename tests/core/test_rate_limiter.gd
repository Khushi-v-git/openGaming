extends GutTest


func test_burst_then_blocked() -> void:
	var rl: RateLimiter = RateLimiter.new(3, 1, 0)
	assert_true(rl.allow(0))
	assert_true(rl.allow(0))
	assert_true(rl.allow(0))
	assert_false(rl.allow(0))


func test_refills_over_time() -> void:
	var rl: RateLimiter = RateLimiter.new(2, 2, 0)
	rl.allow(0)
	rl.allow(0)
	assert_false(rl.allow(100))  # 0.2 token
	assert_true(rl.allow(600))  # ~1.2 tokens by now


func test_never_exceeds_capacity() -> void:
	var rl: RateLimiter = RateLimiter.new(2, 100, 0)
	assert_true(rl.allow(10000))
	assert_true(rl.allow(10000))
	assert_false(rl.allow(10000))


func test_clock_going_backwards_is_harmless() -> void:
	var rl: RateLimiter = RateLimiter.new(1, 1, 5000)
	assert_true(rl.allow(5000))
	assert_false(rl.allow(1000))
