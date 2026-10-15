extends "res://tests/core/network_controller_extras.gd"


func make_env() -> TransportEnv:
	return DirectWsEnv.new()
