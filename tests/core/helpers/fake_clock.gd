class_name FakeClock
extends RefCounted
## Test clock: time only moves when the test says so.

var now: int = 0


func get_msec() -> int:
	return now


func as_callable() -> Callable:
	return Callable(self, "get_msec")
