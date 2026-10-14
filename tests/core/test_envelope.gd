extends GutTest


func test_make_has_required_fields() -> void:
	var msg: Dictionary = Envelope.make(Protocol.T_PING, {"n": 1})
	assert_eq(msg["type"], "ping")
	assert_eq(msg["protocol_version"], Protocol.PROTOCOL_VERSION)
	assert_eq(msg["payload"], {"n": 1})


func test_round_trip_restores_ints() -> void:
	var msg: Dictionary = Envelope.make("x", {"id": 7, "list": [1, 2, 3], "nested": {"a": 5}, "ratio": 0.5})
	var parsed: Dictionary = Envelope.parse(Envelope.to_text(msg))
	assert_true(CoreResult.is_ok(parsed))
	var out: Dictionary = parsed["message"]
	assert_eq(typeof(out["protocol_version"]), TYPE_INT)
	assert_eq(typeof(out["payload"]["id"]), TYPE_INT)
	assert_eq(typeof(out["payload"]["list"][0]), TYPE_INT)
	assert_eq(typeof(out["payload"]["nested"]["a"]), TYPE_INT)
	assert_eq(typeof(out["payload"]["ratio"]), TYPE_FLOAT)
	assert_eq(out, msg)


func test_invalid_json_is_malformed() -> void:
	assert_eq(CoreResult.error_code(Envelope.parse("{not json")), ErrorCodes.MALFORMED)


func test_non_object_is_malformed() -> void:
	assert_eq(CoreResult.error_code(Envelope.parse("[1,2]")), ErrorCodes.MALFORMED)
	assert_eq(CoreResult.error_code(Envelope.parse("42")), ErrorCodes.MALFORMED)


func test_missing_fields_are_malformed() -> void:
	assert_eq(CoreResult.error_code(Envelope.parse('{"protocol_version":1,"payload":{}}')), ErrorCodes.MALFORMED)
	assert_eq(CoreResult.error_code(Envelope.parse('{"type":"a","payload":{}}')), ErrorCodes.MALFORMED)
	assert_eq(CoreResult.error_code(Envelope.parse('{"type":"a","protocol_version":1}')), ErrorCodes.MALFORMED)
	assert_eq(CoreResult.error_code(Envelope.parse('{"type":"","protocol_version":1,"payload":{}}')), ErrorCodes.MALFORMED)


func test_wrong_field_types_are_malformed() -> void:
	assert_eq(CoreResult.error_code(Envelope.parse('{"type":5,"protocol_version":1,"payload":{}}')), ErrorCodes.MALFORMED)
	assert_eq(CoreResult.error_code(Envelope.parse('{"type":"a","protocol_version":"1","payload":{}}')), ErrorCodes.MALFORMED)
	assert_eq(CoreResult.error_code(Envelope.parse('{"type":"a","protocol_version":1.5,"payload":{}}')), ErrorCodes.MALFORMED)
	assert_eq(CoreResult.error_code(Envelope.parse('{"type":"a","protocol_version":1,"payload":[]}')), ErrorCodes.MALFORMED)


func test_oversized_is_rejected() -> void:
	var big: String = "x".repeat(Protocol.MAX_MESSAGE_BYTES + 1)
	assert_eq(CoreResult.error_code(Envelope.parse(big)), ErrorCodes.TOO_LARGE)


func test_message_at_limit_is_not_too_large() -> void:
	var overhead: int = Envelope.to_text(Envelope.make("x", {"s": ""})).length()
	var msg: Dictionary = Envelope.make("x", {"s": "a".repeat(Protocol.MAX_MESSAGE_BYTES - overhead)})
	assert_true(CoreResult.is_ok(Envelope.parse(Envelope.to_text(msg))))


func test_different_protocol_version_still_parses() -> void:
	var parsed: Dictionary = Envelope.parse('{"type":"hello","protocol_version":999,"payload":{}}')
	assert_true(CoreResult.is_ok(parsed))
	assert_eq(parsed["message"]["protocol_version"], 999)


func test_is_plain_data() -> void:
	assert_true(Envelope.is_plain_data({"a": [1, 2.5, "s", null, true, {"b": 1}]}))
	var node: Node = autofree(Node.new())
	assert_false(Envelope.is_plain_data({"a": node}))
	assert_false(Envelope.is_plain_data({1: "int key"}))
	assert_false(Envelope.is_plain_data([Vector2.ZERO]))


func test_normalize_keeps_huge_and_fractional_floats() -> void:
	assert_eq(typeof(Envelope.normalize(1e30)), TYPE_FLOAT)
	assert_eq(typeof(Envelope.normalize(2.5)), TYPE_FLOAT)
	assert_eq(typeof(Envelope.normalize(3.0)), TYPE_INT)
