extends "res://tests/core/transport_contract.gd"


func make_env() -> TransportEnv:
	return LoopbackEnv.new()


func test_two_hubs_are_isolated() -> void:
	var host: TransportRig = await start_host()
	var other: Transport = LoopbackTransport.new(LoopbackHub.new())
	var rec: TransportRecorder = TransportRecorder.new(other)
	other.join_session(host.address, {})
	other.poll()
	assert_eq(rec.join_failures.size(), 1)


func test_duplicate_address_is_rejected() -> void:
	var a: Transport = LoopbackTransport.new((env as LoopbackEnv).hub)
	var b: Transport = LoopbackTransport.new((env as LoopbackEnv).hub)
	assert_true(CoreResult.is_ok(a.host_session({"address": "room-1"})))
	assert_false(CoreResult.is_ok(b.host_session({"address": "room-1"})))
	a.leave()
