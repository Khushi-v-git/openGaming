extends NetTestCase
## The GameController contract: what a game screen may rely on, whatever kind of controller it is
## given (hot-seat, the host's own, or a guest's). Run with the count-to-N test game. Not collected
## itself; test_controller_<kind>.gd extends this and overrides make_rig().

const TARGET: int = 10

class Rig:
	extends RefCounted
	var controllers: Array[GameController] = []
	var batches: Array = []  # per controller: Array of batches
	var rejections: Array = []  # per controller: Array of errors
	var hotseat: bool = false  # one controller plays for everybody
	var start: Callable  # async: starts the game
	var settle: Callable  # async: lets messages land

var rules: CountGameRules


func before_each() -> void:
	super.before_each()
	rules = CountGameRules.new()


## Override: build a rig of controllers for a 3-seat game of count-to-TARGET. Controllers must be
## wired up (signals recorded in the rig) before start() is called.
func make_rig() -> Rig:
	return null


func _record(rig: Rig, controller: GameController) -> void:
	var index: int = rig.controllers.size()
	rig.controllers.append(controller)
	rig.batches.append([])
	rig.rejections.append([])
	controller.batch_ready.connect(func(batch: Dictionary) -> void: rig.batches[index].append(batch))
	controller.action_rejected.connect(func(error: Dictionary) -> void: rig.rejections[index].append(error))


## The controller that may act now: the hot-seat one, or whoever's turn the rules say it is.
func _acting(rig: Rig) -> int:
	for i: int in rig.controllers.size():
		var controller: GameController = rig.controllers[i]
		var view: Dictionary = controller.latest_view()
		if view.is_empty():
			continue
		if controller.local_player_id() == "" or controller.local_player_id() == rules.current_player(view):
			return i
	return -1


func _add(n: int) -> Dictionary:
	return {"type": "add", "n": n}


# --- the contract --------------------------------------------------------------------------------------------

func test_every_controller_gets_a_start_batch_and_its_own_view() -> void:
	var rig: Rig = await make_rig()
	await rig.start.call()
	for i: int in rig.controllers.size():
		assert_eq(rig.batches[i].size(), 1, "controller %d" % i)
		var batch: Dictionary = rig.batches[i][0]
		assert_eq(batch["reason"], "start")
		assert_true(batch.has("seq") and batch.has("events") and batch.has("view"))
		assert_eq(rig.controllers[i].latest_view(), batch["view"])
		assert_eq(batch["view"]["total"], 0)
		if not rig.hotseat:
			assert_eq(batch["view"]["you"], rig.controllers[i].local_player_id(), "its own view")


func test_rules_are_available_for_read_only_questions() -> void:
	var rig: Rig = await make_rig()
	await rig.start.call()
	for controller: GameController in rig.controllers:
		assert_not_null(controller.rules())
		assert_false(controller.rules().is_finished(controller.latest_view()))
		assert_ne(controller.rules().current_player(controller.latest_view()), "")


func test_a_legal_action_gives_every_controller_the_next_batch() -> void:
	var rig: Rig = await make_rig()
	await rig.start.call()
	var who: int = _acting(rig)
	assert_gte(who, 0)
	rig.controllers[who].submit_action(_add(2))
	await rig.settle.call()
	for i: int in rig.controllers.size():
		assert_eq(rig.batches[i].size(), 2, "controller %d" % i)
		var batch: Dictionary = rig.batches[i][1]
		assert_eq(batch["reason"], "action")
		assert_eq(batch["seq"], rig.batches[i][0]["seq"] + 1)
		assert_eq(batch["view"]["total"], 2)
		assert_eq((batch["events"] as Array).map(func(e: Dictionary) -> String: return e["type"]), ["added", "turn_changed"])
		assert_eq(rig.controllers[i].latest_view()["total"], 2)
	assert_eq(rig.rejections[who].size(), 0)


func test_an_illegal_action_is_rejected_and_nothing_changes() -> void:
	var rig: Rig = await make_rig()
	await rig.start.call()
	var who: int = _acting(rig)
	rig.controllers[who].submit_action(_add(9))
	await rig.settle.call()
	assert_eq(rig.rejections[who].size(), 1)
	assert_eq(rig.rejections[who][0]["code"], ErrorCodes.BAD_ACTION)
	for i: int in rig.controllers.size():
		assert_eq(rig.batches[i].size(), 1, "no new batch for controller %d" % i)
		assert_eq(rig.controllers[i].latest_view()["total"], 0)


func test_acting_out_of_turn_is_rejected_when_the_controller_has_its_own_seat() -> void:
	var rig: Rig = await make_rig()
	await rig.start.call()
	if rig.hotseat:
		assert_eq(rig.controllers.size(), 1, "a hot-seat controller always acts for whoever is to move")
		return
	var who: int = _acting(rig)
	var other: int = 0 if who != 0 else 1
	rig.controllers[other].submit_action(_add(1))
	await rig.settle.call()
	assert_eq(rig.rejections[other].size(), 1)
	assert_eq(rig.rejections[other][0]["code"], "NOT_YOUR_TURN")
	for i: int in rig.controllers.size():
		assert_eq(rig.batches[i].size(), 1)


func test_a_finished_game_locks_further_actions() -> void:
	var rig: Rig = await make_rig()
	await rig.start.call()
	var guard: int = 0
	while not rules.is_finished(rig.controllers[0].latest_view()) and guard < 20:
		rig.controllers[_acting(rig)].submit_action(_add(3))
		await rig.settle.call()
		guard += 1
	for controller: GameController in rig.controllers:
		assert_true(rules.is_finished(controller.latest_view()))
		assert_eq(rules.winner(controller.latest_view()), rules.winner(rig.controllers[0].latest_view()))
	var count: int = rig.batches[0].size()
	rig.controllers[0].submit_action(_add(1))
	await rig.settle.call()
	assert_eq(rig.rejections[0].back()["code"], "GAME_OVER")
	assert_eq(rig.batches[0].size(), count)


func test_only_the_host_or_hot_seat_can_rematch_and_everyone_jumps_to_the_new_game() -> void:
	var rig: Rig = await make_rig()
	await rig.start.call()
	rig.controllers[_acting(rig)].submit_action(_add(2))
	await rig.settle.call()
	var allowed: Array[int] = []
	for i: int in rig.controllers.size():
		if rig.controllers[i].can_rematch():
			allowed.append(i)
		else:
			assert_eq(CoreResult.error_code(rig.controllers[i].rematch()), ErrorCodes.NOT_HOST)
	assert_eq(allowed.size(), 1, "exactly one controller may start a rematch")
	assert_true(CoreResult.is_ok(rig.controllers[allowed[0]].rematch()))
	await rig.settle.call()
	for i: int in rig.controllers.size():
		var batch: Dictionary = rig.batches[i].back()
		assert_eq(batch["reason"], "rematch", "controller %d" % i)
		assert_eq(batch["events"], [])
		assert_eq(batch["view"]["total"], 0)
		assert_gt(batch["seq"], rig.batches[i][1]["seq"])


func test_an_action_before_the_game_starts_is_rejected() -> void:
	var rig: Rig = await make_rig()
	rig.controllers[0].submit_action(_add(1))
	await rig.settle.call()
	assert_eq(rig.rejections[0].size(), 1)
	assert_eq(rig.rejections[0][0]["code"], ErrorCodes.WRONG_PHASE)
	assert_eq(rig.controllers[0].latest_view(), {})


func test_with_everyone_present_nothing_is_paused() -> void:
	var rig: Rig = await make_rig()
	await rig.start.call()
	for controller: GameController in rig.controllers:
		var presence: Dictionary = controller.presence()
		assert_false(presence["paused"])
		assert_eq(presence["away"], [])


func test_host_decisions_belong_to_the_host_only() -> void:
	var rig: Rig = await make_rig()
	await rig.start.call()
	assert_true(rig.controllers.any(func(c: GameController) -> bool: return c.can_rematch()), "somebody is the host")
	for controller: GameController in rig.controllers:
		if controller.can_rematch():
			continue
		assert_eq(CoreResult.error_code(controller.continue_without_waiting()), ErrorCodes.NOT_HOST)
		assert_eq(CoreResult.error_code(controller.wait_again()), ErrorCodes.NOT_HOST)
		assert_eq(CoreResult.error_code(controller.remove_player("x")), ErrorCodes.NOT_HOST)
		assert_eq(CoreResult.error_code(controller.end_game()), ErrorCodes.NOT_HOST)
