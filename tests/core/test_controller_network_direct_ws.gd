extends "res://tests/core/controller_network_rig.gd"


func make_env() -> TransportEnv:
	return DirectWsEnv.new()
