extends GutTest
## The abstract Transport: defaults must be safe, and the interface surface must exist.


func test_interface_has_required_signals() -> void:
	var t: Transport = Transport.new()
	for signal_name: String in ["message_received", "peer_connected", "peer_disconnected", "join_succeeded", "join_failed"]:
		assert_true(t.has_signal(signal_name), "missing signal %s" % signal_name)


func test_interface_has_required_methods() -> void:
	var t: Transport = Transport.new()
	for method_name: String in ["host_session", "join_session", "leave", "send", "broadcast", "disconnect_peer", "poll", "get_peer_ids", "is_active"]:
		assert_true(t.has_method(method_name), "missing method %s" % method_name)


func test_base_host_session_reports_not_implemented() -> void:
	var t: Transport = Transport.new()
	var result: Dictionary = t.host_session({})
	assert_false(CoreResult.is_ok(result))
	assert_eq(CoreResult.error_code(result), "NOT_IMPLEMENTED")


func test_base_join_fails_instead_of_hanging() -> void:
	var t: Transport = Transport.new()
	watch_signals(t)
	t.join_session("anything", {})
	assert_signal_emitted(t, "join_failed")


func test_host_peer_id_is_stable_constant() -> void:
	assert_eq(Transport.HOST_PEER_ID, 1)
