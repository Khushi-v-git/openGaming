extends NetTestCase
## What only the networked controllers do: presence, host decisions, going back to the lobby, and
## losing the session. Not collected itself; test_network_controller_<transport>.gd extends it.

var rules: CountGameRules
var table: GameNetTable
var host: NetworkGameController
var guests: Array[NetworkGameController] = []
var guest_events: Array = []  # per guest: {ended, lost, presence}


func before_each() -> void:
	super.before_each()
	rules = CountGameRules.new()
	guests.clear()  # the test object is reused between tests
	guest_events.clear()


func _seat(guest_count: int = 2) -> void:
	table = await GameNetTable.create(self, rules, {"target": 12}, 5, guest_count, {}, "count_to", 2, 4, 2)
	host = NetworkGameController.for_host(table.host)
	for guest: GameNetTable.Guest in table.guests:
		var controller: NetworkGameController = NetworkGameController.for_client(guest.game, rules)
		var record: Dictionary = {"ended": 0, "lost": [], "presence": [], "links": []}
		controller.ended.connect(func() -> void: record["ended"] += 1)
		controller.lost.connect(func(error: Dictionary) -> void: record["lost"].append(error))
		controller.presence_changed.connect(func(info: Dictionary) -> void: record["presence"].append(info))
		controller.link_changed.connect(func(state: String) -> void: record["links"].append(state))
		guests.append(controller)
		guest_events.append(record)
	await table.start_game()


func test_players_lists_the_table_in_seat_order_with_names() -> void:
	await _seat(2)
	for controller: NetworkGameController in [host, guests[0], guests[1]]:
		assert_eq(controller.players().map(func(p: Dictionary) -> String: return p["name"]), ["Hosty", "Guest1", "Guest2"])
	assert_eq(host.local_player_id(), table.lobby.local_player_id)
	assert_eq(guests[1].local_player_id(), table.guests[1].player_id())
	assert_true(host.is_host())
	assert_false(guests[0].is_host())


func test_everyone_sees_who_is_away_and_that_the_game_is_paused() -> void:
	await _seat(2)
	var away_id: String = table.guests[1].player_id()
	table.guests[1].lobby.session.transport.leave()
	assert_true(await table.until(func() -> bool: return host.presence()["paused"] and guests[0].presence()["paused"]))
	for controller: NetworkGameController in [host, guests[0]]:
		var presence: Dictionary = controller.presence()
		assert_eq(presence["away"].map(func(p: Dictionary) -> String: return p["player_id"]), [away_id])
		assert_true(presence["can_continue"])
	assert_eq(host.presence()["is_host"], true)
	assert_eq(guests[0].presence()["is_host"], false)
	assert_false(guest_events[0]["presence"].is_empty(), "the guest's screen was told")
	assert_true(guest_events[0]["presence"].back()["paused"])


func test_the_host_can_continue_wait_again_and_remove() -> void:
	await _seat(3)
	var away_id: String = table.guests[2].player_id()
	table.guests[2].lobby.session.transport.leave()
	assert_true(await table.until(func() -> bool: return host.presence()["paused"]))
	assert_true(CoreResult.is_ok(host.continue_without_waiting()))
	assert_true(await table.until(func() -> bool: return not guests[0].presence()["paused"]))
	assert_eq(guests[0].presence()["away"].size(), 1, "still away, but play goes on")
	assert_true(CoreResult.is_ok(host.wait_again()))
	assert_true(await table.until(func() -> bool: return guests[0].presence()["paused"]))
	assert_true(CoreResult.is_ok(host.remove_player(away_id)))
	assert_true(await table.until(func() -> bool: return guests[0].presence()["away"].is_empty()))
	assert_false(guests[0].presence()["paused"], "two players are enough to carry on")
	assert_eq(guests[0].players().size(), 3, "four seats minus the removed player")


func test_continuing_is_refused_below_the_minimum() -> void:
	await _seat(1)  # host + 1 guest, the game needs 2 present
	table.guests[0].lobby.session.transport.leave()
	assert_true(await table.until(func() -> bool: return host.presence()["paused"]))
	assert_false(host.presence()["can_continue"])
	assert_eq(CoreResult.error_code(host.continue_without_waiting()), ErrorCodes.TOO_FEW_PLAYERS)


func test_end_game_tells_every_screen_to_go_back_to_the_lobby() -> void:
	await _seat(2)
	var host_ended: Array = [0]
	host.ended.connect(func() -> void: host_ended[0] += 1)
	assert_true(CoreResult.is_ok(host.end_game()))
	assert_true(await table.until(func() -> bool: return guest_events[0]["ended"] == 1 and guest_events[1]["ended"] == 1))
	assert_eq(host_ended[0], 1)
	assert_eq(host.latest_view(), {})
	assert_false(host.can_rematch())


func test_a_guest_who_leaves_is_told_the_session_is_over_for_them() -> void:
	await _seat(2)
	guests[0].leave()
	assert_true(await table.until(func() -> bool: return not guest_events[0]["lost"].is_empty()))
	assert_eq(guest_events[0]["lost"][0]["code"], ErrorCodes.LEFT)


func test_when_the_host_closes_every_guest_is_told() -> void:
	await _seat(2)
	host.leave()
	assert_true(await table.until(func() -> bool: return not guest_events[0]["lost"].is_empty() and not guest_events[1]["lost"].is_empty()))
	assert_eq(guest_events[0]["lost"][0]["code"], "HOST_CLOSED")


func test_a_removed_guest_is_told() -> void:
	await _seat(2)
	var id: String = table.guests[0].player_id()
	assert_true(CoreResult.is_ok(host.remove_player(id)))
	assert_true(await table.until(func() -> bool: return not guest_events[0]["lost"].is_empty()))
	assert_eq(guest_events[0]["lost"][0]["code"], ErrorCodes.KICKED)
