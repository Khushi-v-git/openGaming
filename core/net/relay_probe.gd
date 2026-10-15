class_name RelayProbe
extends RefCounted
## "Test this relay": opens a room on it, waits for the room code, and closes the room again.
## Used by the connection panel so a player can check a relay URL before hosting. Poll it every
## frame until `finished` fires. It talks to the relay only through RelayTransport.

signal finished(ok: bool, message: String)

const TIMEOUT_MSEC: int = 8000

var clock: Callable = func() -> int: return Time.get_ticks_msec()

var _transport: RelayTransport = null
var _deadline: int = 0
var _done: bool = true


func is_running() -> bool:
	return not _done


## Starts a probe of `url` (already normalized). `finished` fires from a later poll(), or at
## once if the URL cannot even be tried.
func start(url: String) -> void:
	stop()
	_done = false
	_transport = RelayTransport.new()
	_transport.session_ready.connect(func(info: Dictionary) -> void: _finish(true, "The relay works. A test room (%s) was opened and closed." % str(info.get("address", ""))))
	_transport.host_failed.connect(func(reason: String) -> void: _finish(false, reason))
	var started: Dictionary = _transport.host_session({"relay_url": url, "join_timeout_msec": TIMEOUT_MSEC})
	if not CoreResult.is_ok(started):
		_finish(false, str(started["error"]["message"]))
		return
	_deadline = int(clock.call()) + TIMEOUT_MSEC


func poll() -> void:
	if _done or _transport == null:
		return
	_transport.poll()
	if not _done and int(clock.call()) > _deadline:
		_finish(false, "The relay did not answer in time. Check the address and your connection.")


## Cancels a running probe without reporting.
func stop() -> void:
	if _transport != null:
		_transport.leave()
	_transport = null
	_done = true


func _finish(ok: bool, message: String) -> void:
	if _done:
		return
	_done = true
	if _transport != null:
		_transport.leave()
		_transport = null
	finished.emit(ok, message)
