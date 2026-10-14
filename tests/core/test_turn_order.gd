extends GutTest

const ORDER: Array[String] = ["p1", "p2", "p3", "p4"]


func _ids(ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in ids:
		out.append(str(id))
	return out


func test_everyone_present_rotates_normally() -> void:
	var all: Array[String] = ORDER
	assert_eq(TurnOrder.next_active(ORDER, "p1", all), "p2")
	assert_eq(TurnOrder.next_active(ORDER, "p4", all), "p1", "wraps around")


func test_absent_players_are_skipped() -> void:
	var active: Array[String] = _ids(["p1", "p4"])
	assert_eq(TurnOrder.next_active(ORDER, "p1", active), "p4")
	assert_eq(TurnOrder.next_active(ORDER, "p4", active), "p1")


func test_a_returning_player_gets_their_turn_again_in_their_own_seat() -> void:
	assert_eq(TurnOrder.next_active(ORDER, "p1", _ids(["p1", "p4"])), "p4")
	assert_eq(TurnOrder.next_active(ORDER, "p1", _ids(["p1", "p2", "p4"])), "p2")


func test_the_current_player_dropping_hands_the_turn_on() -> void:
	# it was p2's turn and p2 dropped: the next present player after p2's seat
	assert_eq(TurnOrder.next_active(ORDER, "p2", _ids(["p1", "p3", "p4"])), "p3")


func test_only_one_player_active_gets_the_turn_back() -> void:
	assert_eq(TurnOrder.next_active(ORDER, "p3", _ids(["p3"])), "p3")


func test_nobody_active_returns_empty() -> void:
	assert_eq(TurnOrder.next_active(ORDER, "p1", _ids([])), "")
	assert_eq(TurnOrder.first_active(ORDER, _ids([])), "")


func test_unknown_current_player_starts_from_the_first_seat() -> void:
	assert_eq(TurnOrder.next_active(ORDER, "nobody", _ids(["p2", "p3"])), "p2")


func test_first_active_from_an_index() -> void:
	var active: Array[String] = _ids(["p2", "p4"])
	assert_eq(TurnOrder.first_active(ORDER, active), "p2")
	assert_eq(TurnOrder.first_active(ORDER, active, 2), "p4")
	assert_eq(TurnOrder.first_active(ORDER, active, 5), "p2", "index 5 wraps to seat 1")
	assert_eq(TurnOrder.first_active(ORDER, active, 3), "p4")


func test_empty_order() -> void:
	var none: Array[String] = []
	assert_eq(TurnOrder.next_active(none, "p1", ORDER), "")
	assert_eq(TurnOrder.first_active(none, ORDER), "")


func test_in_order_keeps_seat_order_not_activity_order() -> void:
	assert_eq(TurnOrder.in_order(ORDER, _ids(["p4", "p2"])), _ids(["p2", "p4"]))
	assert_eq(TurnOrder.in_order(ORDER, _ids(["zzz"])), _ids([]))


func test_works_with_the_lobby_state() -> void:
	var s: Dictionary = LobbyLogic.create("g", 2, 4, "p1", "Host", 2)
	for entry: Array in [["p2", "Bo"], ["p3", "Cy"]]:
		s = LobbyLogic.apply(s, entry[0], {"type": "join", "name": entry[1]})["state"]
		s = LobbyLogic.apply(s, entry[0], {"type": "set_ready", "ready": true})["state"]
	s = LobbyLogic.apply(s, "p1", {"type": "start"})["state"]
	s = LobbyLogic.apply(s, "p2", {"type": "disconnected"})["state"]
	assert_eq(TurnOrder.next_active(_ids(["p1", "p2", "p3"]), "p1", LobbyLogic.active_players(s)), "p3")
