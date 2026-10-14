class_name LoopbackEnv
extends TransportEnv

var hub: LoopbackHub = LoopbackHub.new()


func make_transport() -> Transport:
	return LoopbackTransport.new(hub)
