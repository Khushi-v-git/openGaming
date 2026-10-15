extends "res://tests/core/game_network_contract.gd"


func make_env() -> TransportEnv:
	return DirectWsEnv.new()
