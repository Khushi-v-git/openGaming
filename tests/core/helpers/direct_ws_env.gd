class_name DirectWsEnv
extends TransportEnv
## Direct WebSocket on localhost with an OS-assigned port.


func make_transport() -> Transport:
	return DirectWsTransport.new()


func host_config() -> Dictionary:
	return {"port": 0, "bind_address": "127.0.0.1"}


## WebSocketPeer never reports a refused connection on Windows (it stays CONNECTING),
## so the transport's own join timeout is the failure detector. Keep it short in tests.
func join_config() -> Dictionary:
	return {"join_timeout_msec": 1500}
