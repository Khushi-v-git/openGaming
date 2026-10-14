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
