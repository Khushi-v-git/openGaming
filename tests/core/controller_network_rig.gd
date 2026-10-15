extends "res://tests/core/controller_contract.gd"
## The networked controllers (the host's own and each guest's) satisfy the controller contract.
## Not collected itself; test_controller_network_<transport>.gd extends it.


func make_rig() -> Rig:
	var rig: Rig = Rig.new()
	var table: GameNetTable = await GameNetTable.create(self, rules, {"target": TARGET}, 5, 2, {}, "count_to", 2, 4, 2)
	_record(rig, NetworkGameController.for_host(table.host))
	for guest: GameNetTable.Guest in table.guests:
		_record(rig, NetworkGameController.for_client(guest.game, rules))
	rig.start = func() -> void: await table.start_game()
	rig.settle = func() -> void: await table.settle()
	return rig
