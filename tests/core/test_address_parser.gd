extends GutTest


func test_host_and_port() -> void:
	var r: Dictionary = AddressParser.parse("192.168.1.5:4000", 1)
	assert_true(CoreResult.is_ok(r))
	assert_eq(r["host"], "192.168.1.5")
	assert_eq(r["port"], 4000)


func test_hostname_with_port() -> void:
	var r: Dictionary = AddressParser.parse("friend.example.net:555", 1)
	assert_eq(r["host"], "friend.example.net")
	assert_eq(r["port"], 555)


func test_missing_port_uses_default() -> void:
	var r: Dictionary = AddressParser.parse("10.0.0.2", 777)
	assert_eq(r["port"], 777)


func test_ws_prefix_and_whitespace_are_ignored() -> void:
	var r: Dictionary = AddressParser.parse("  ws://1.2.3.4:99/ ", 1)
	assert_eq(r["host"], "1.2.3.4")
	assert_eq(r["port"], 99)


func test_ipv6_in_brackets() -> void:
	var r: Dictionary = AddressParser.parse("[::1]:99", 1)
	assert_true(CoreResult.is_ok(r))
	assert_eq(r["host"], "[::1]")
	assert_eq(r["port"], 99)


func test_bare_ipv6_is_rejected_with_hint() -> void:
	assert_eq(CoreResult.error_code(AddressParser.parse("::1", 1)), AddressParser.BAD_ADDRESS)


func test_invalid_inputs() -> void:
	for bad: String in ["", "   ", ":99", "host:", "host:abc", "host:0", "host:70000", "ho st:5", "[::1", "[::1]x", "a/b:5"]:
		assert_false(CoreResult.is_ok(AddressParser.parse(bad, 1)), "should reject '%s'" % bad)
