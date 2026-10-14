class_name NetWait
extends RefCounted
## Test helper: poll transports until a condition holds or a frame budget runs out.
## Usage: var ok: bool = await NetWait.until(self, [host, client], func() -> bool: return done)
## Each iteration polls every transport, checks the condition, then waits one real
## frame plus a short delay so socket-based transports get time to do I/O.

const DEFAULT_MAX_FRAMES: int = 600
const FRAME_DELAY_MSEC: int = 1


static func until(test: Node, transports: Array, condition: Callable, max_frames: int = DEFAULT_MAX_FRAMES) -> bool:
	for _i: int in max_frames:
		for transport: Variant in transports:
			(transport as Transport).poll()
		if condition.call():
			return true
		OS.delay_msec(FRAME_DELAY_MSEC)
		await test.get_tree().process_frame
	return false


## Polls for a fixed number of frames (for asserting that something does NOT happen).
static func frames(test: Node, transports: Array, count: int) -> void:
	for _i: int in count:
		for transport: Variant in transports:
			(transport as Transport).poll()
		OS.delay_msec(FRAME_DELAY_MSEC)
		await test.get_tree().process_frame
