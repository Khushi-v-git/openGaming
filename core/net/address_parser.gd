class_name AddressParser
extends RefCounted
## Parses the join address a player types: "host:port", "1.2.3.4:port", "[::1]:port",
## optionally prefixed with ws://. A missing port falls back to default_port.
## Returns {ok, host, port} or failure NAME_INVALID-style code "BAD_ADDRESS".

const BAD_ADDRESS: String = "BAD_ADDRESS"


static func parse(text: String, default_port: int) -> Dictionary:
	var s: String = text.strip_edges()
	if s.begins_with("ws://"):
		s = s.substr(5)
	if s.ends_with("/"):
		s = s.left(s.length() - 1)
	if s.is_empty():
		return CoreResult.failure(BAD_ADDRESS, "address is empty")
	var host: String = s
	var port: int = default_port
	if s.begins_with("["):
		var close: int = s.find("]")
		if close < 0:
			return CoreResult.failure(BAD_ADDRESS, "unclosed [ in address")
		host = s.substr(0, close + 1)
		var rest: String = s.substr(close + 1)
		if not rest.is_empty():
			if not rest.begins_with(":"):
				return CoreResult.failure(BAD_ADDRESS, "unexpected text after ]")
			var parsed_port: Dictionary = _parse_port(rest.substr(1))
			if not CoreResult.is_ok(parsed_port):
				return parsed_port
			port = parsed_port["port"]
	elif s.count(":") == 1:
		var parts: PackedStringArray = s.split(":")
		host = parts[0]
		var parsed_port: Dictionary = _parse_port(parts[1])
		if not CoreResult.is_ok(parsed_port):
			return parsed_port
		port = parsed_port["port"]
	elif s.count(":") > 1:
		return CoreResult.failure(BAD_ADDRESS, "IPv6 addresses need brackets, e.g. [::1]:1234")
	if host.is_empty() or host.contains(" ") or host.contains("/"):
		return CoreResult.failure(BAD_ADDRESS, "invalid host")
	if port < 1 or port > 65535:
		return CoreResult.failure(BAD_ADDRESS, "port out of range")
	return CoreResult.success({"host": host, "port": port})


static func _parse_port(text: String) -> Dictionary:
	if not text.is_valid_int():
		return CoreResult.failure(BAD_ADDRESS, "port must be a number")
	var value: int = text.to_int()
	if value < 1 or value > 65535:
		return CoreResult.failure(BAD_ADDRESS, "port out of range")
	return CoreResult.success({"port": value})
