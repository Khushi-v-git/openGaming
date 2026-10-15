class_name TransportEnv
extends RefCounted
## Test helper: how to build transports of one kind. One subclass per transport.
## The contract and lobby suites run unchanged against every TransportEnv.


## A fresh transport instance sharing this env's "network".
func make_transport() -> Transport:
	return null


func host_config() -> Dictionary:
	return {}


func join_config() -> Dictionary:
	return {}


## Called after each test.
func cleanup() -> void:
	pass


## Extra frames the lobby tests keep polling after everything looks settled. A transport with
## real network latency (a relay) needs a few, because "nothing has changed yet" looks the same
## as "everything has arrived" until the messages in flight land. In-memory and localhost
## transports deliver within the same poll, so the default is 0.
func settle_frames() -> int:
	return 0
