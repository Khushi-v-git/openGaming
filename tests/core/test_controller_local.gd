extends "res://tests/core/controller_contract.gd"
## The hot-seat controller satisfies the controller contract.


func make_env() -> TransportEnv:
	return TransportEnv.new()


func make_rig() -> Rig:
	var rig: Rig = Rig.new()
	rig.hotseat = true
	var controller: LocalGameController = LocalGameController.new(rules, ["p1", "p2", "p3"], {"target": TARGET}, {}, 5)
	_record(rig, controller)
	rig.start = func() -> void: controller.start()
	rig.settle = func() -> void: await get_tree().process_frame
	return rig
