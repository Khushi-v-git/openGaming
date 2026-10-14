class_name TransportFactory
extends RefCounted
## The only place that names concrete transports. Lobby, session and game code get a
## Transport from here by configuration and never import an implementation (rule 3a).
##
## config.transport: "direct_ws" (default), "loopback" (in-process), "fake_relay" (tests).
## Other keys are passed through to the transport, e.g. port, bind_address.

const KIND_DIRECT_WS: String = "direct_ws"
const KIND_LOOPBACK: String = "loopback"
const KIND_FAKE_RELAY: String = "fake_relay"


static func create(config: Dictionary) -> Transport:
	match str(config.get("transport", KIND_DIRECT_WS)):
		KIND_DIRECT_WS:
			return DirectWsTransport.new()
		KIND_LOOPBACK:
			return LoopbackTransport.new(config.get("hub", null))
		KIND_FAKE_RELAY:
			return FakeRelayTransport.new(config["relay"])
		_:
			push_error("Unknown transport kind '%s'" % str(config.get("transport")))
			return null


## Sensible default settings for a kind. UI code uses these to prefill fields.
static func default_config(kind: String = KIND_DIRECT_WS) -> Dictionary:
	match kind:
		KIND_DIRECT_WS:
			return {"transport": KIND_DIRECT_WS, "port": DirectWsTransport.DEFAULT_PORT, "bind_address": "*"}
		_:
			return {"transport": kind}
