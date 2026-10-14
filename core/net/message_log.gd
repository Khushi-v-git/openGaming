class_name MessageLog
extends RefCounted
## Debug-build log of every message sent and received: timestamp, direction,
## player id, peer id and message type. Payloads are never logged (they may hold
## tokens or hidden information). Off in release builds.

static var enabled: bool = OS.is_debug_build()
## Replaceable sink, e.g. by tests. Default prints to the console.
static var sink: Callable = Callable()


static func log_out(peer_id: int, player_id: String, type: String) -> void:
	_write("->", peer_id, player_id, type)


static func log_in(peer_id: int, player_id: String, type: String) -> void:
	_write("<-", peer_id, player_id, type)


static func _write(direction: String, peer_id: int, player_id: String, type: String) -> void:
	if not enabled:
		return
	var who: String = player_id if not player_id.is_empty() else "-"
	var line: String = "[net %s] %s player=%s peer=%d type=%s" % [_timestamp(), direction, who, peer_id, type]
	if sink.is_valid():
		sink.call(line)
	else:
		print(line)


static func _timestamp() -> String:
	var unix: float = Time.get_unix_time_from_system()
	return "%s.%03d" % [Time.get_time_string_from_unix_time(int(unix)), int(fmod(unix, 1.0) * 1000.0)]
