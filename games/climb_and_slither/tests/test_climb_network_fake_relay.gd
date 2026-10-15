extends "res://games/climb_and_slither/tests/climb_network_contract.gd"


func make_env() -> TransportEnv:
	return FakeRelayEnv.new()
