extends "res://tests/core/lobby_contract.gd"


func make_env() -> TransportEnv:
	return FakeRelayEnv.new()
