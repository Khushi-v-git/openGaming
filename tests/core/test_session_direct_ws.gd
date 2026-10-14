extends "res://tests/core/session_contract.gd"


func make_env() -> TransportEnv:
	return DirectWsEnv.new()
