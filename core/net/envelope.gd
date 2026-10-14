class_name Envelope
extends RefCounted
## Message envelope: {type: String, protocol_version: int, payload: Dictionary}.
## Messages are plain data only (rule 4): null, bool, int, float, String, Array,
## and Dictionary with String keys. No engine objects.

const _MAX_SAFE_INT: float = 9007199254740992.0  # 2^53


static func make(type: String, payload: Dictionary = {}) -> Dictionary:
	return {
		"type": type,
		"protocol_version": Protocol.PROTOCOL_VERSION,
		"payload": payload,
	}


static func to_text(message: Dictionary) -> String:
	return JSON.stringify(message)


## Parses wire text into a message. Returns {ok, message} or a failure with
## MALFORMED / TOO_LARGE. A protocol_version that differs from ours still parses,
## so the handshake can reject it with a clear code.
static func parse(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > Protocol.MAX_MESSAGE_BYTES:
		return CoreResult.failure(ErrorCodes.TOO_LARGE, "message exceeds %d bytes" % Protocol.MAX_MESSAGE_BYTES)
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return CoreResult.failure(ErrorCodes.MALFORMED, "invalid JSON: %s" % json.get_error_message())
	var data: Variant = normalize(json.data)
	if typeof(data) != TYPE_DICTIONARY:
		return CoreResult.failure(ErrorCodes.MALFORMED, "message must be an object")
	var checked: Dictionary = validate(data)
	if not CoreResult.is_ok(checked):
		return checked
	return CoreResult.success({"message": data})


## Structural check of an already-parsed message.
static func validate(message: Dictionary) -> Dictionary:
	if typeof(message.get("type")) != TYPE_STRING or (message["type"] as String).is_empty():
		return CoreResult.failure(ErrorCodes.MALFORMED, "missing or invalid 'type'")
	if typeof(message.get("protocol_version")) != TYPE_INT:
		return CoreResult.failure(ErrorCodes.MALFORMED, "missing or invalid 'protocol_version'")
	if typeof(message.get("payload")) != TYPE_DICTIONARY:
		return CoreResult.failure(ErrorCodes.MALFORMED, "missing or invalid 'payload'")
	return CoreResult.success()


## True if the value contains only JSON-safe plain data (rule 4).
static func is_plain_data(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for item: Variant in value:
				if not is_plain_data(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if typeof(key) != TYPE_STRING or not is_plain_data(value[key]):
					return false
			return true
		_:
			return false


## JSON has one number type and Godot parses every number as float. This turns
## integral floats back into ints (recursively) so ids, counts and versions
## round-trip. Code that needs a float must cast with float().
static func normalize(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var f: float = value
			if is_finite(f) and f == floorf(f) and absf(f) < _MAX_SAFE_INT:
				return int(f)
			return f
		TYPE_ARRAY:
			var out_array: Array = []
			for item: Variant in value:
				out_array.append(normalize(item))
			return out_array
		TYPE_DICTIONARY:
			var out_dict: Dictionary = {}
			for key: Variant in value:
				out_dict[key] = normalize(value[key])
			return out_dict
		_:
			return value
