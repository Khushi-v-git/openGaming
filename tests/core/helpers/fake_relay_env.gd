class_name FakeRelayEnv
extends TransportEnv

var relay: FakeRelay = FakeRelay.new()


func make_transport() -> Transport:
	return FakeRelayTransport.new(relay)
