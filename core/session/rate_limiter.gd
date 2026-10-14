class_name RateLimiter
extends RefCounted
## Token bucket. Pure: the caller passes the current time in milliseconds, so it is
## trivial to test and independent of the engine clock.

var capacity: float
var refill_per_sec: float
var _tokens: float
var _last_msec: int


func _init(burst: float, per_second: float, now_msec: int) -> void:
	capacity = burst
	refill_per_sec = per_second
	_tokens = burst
	_last_msec = now_msec


## Consumes one token. Returns false if the bucket is empty (message should be dropped).
func allow(now_msec: int) -> bool:
	var elapsed_sec: float = maxf(0.0, float(now_msec - _last_msec) / 1000.0)
	_last_msec = now_msec
	_tokens = minf(capacity, _tokens + elapsed_sec * refill_per_sec)
	if _tokens >= 1.0:
		_tokens -= 1.0
		return true
	return false
