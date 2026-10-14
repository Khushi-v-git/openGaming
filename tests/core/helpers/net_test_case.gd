class_name NetTestCase
extends GutTest
## Base for tests that run over a TransportEnv: fake clock, things to poll, cleanup.
## Subclasses override make_env(); per-transport test files extend a contract file.

const APP: String = "1.0.0"
const GAME: String = "test_game"

var env: TransportEnv
var clock: FakeClock
var _pollers: Array = []
var _transports: Array[Transport] = []


func make_env() -> TransportEnv:
	return null


func before_each() -> void:
	env = make_env()
	clock = FakeClock.new()
	_pollers.clear()
	_transports.clear()
	MessageLog.enabled = false
	MessageLog.sink = Callable()


func after_each() -> void:
	for transport: Transport in _transports:
		transport.leave()
	_transports.clear()
	_pollers.clear()
	env.cleanup()
	MessageLog.enabled = OS.is_debug_build()
	MessageLog.sink = Callable()


## Registers something to poll every frame and a transport to leave at test end.
func track(poller: Variant, transport: Transport) -> void:
	_pollers.append(poller)
	_transports.append(transport)


func pump(condition: Callable, max_frames: int = NetWait.DEFAULT_MAX_FRAMES) -> bool:
	return await NetWait.until(self, _pollers, condition, max_frames)


func frames(count: int) -> void:
	await NetWait.frames(self, _pollers, count)
