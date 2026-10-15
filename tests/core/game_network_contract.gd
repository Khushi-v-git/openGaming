extends NetTestCase
## Shared tests for the networked game layer (GameHost + GameClient on top of the lobby), run
## with the count-to-N test game so nothing here depends on Climb and Slither. Not collected
## itself; test_game_network_<transport>.gd extends this and overrides make_env().
##
## Count to N: players take turns adding 1 to 3; whoever reaches the target wins. Its state
## carries a host-only `secret` that must never reach a player.

var rules: CountGameRules


func before_each() -> void:
	super.before_each()
	rules = CountGameRules.new()


func _table(guests: int = 2, target: int = 12, settings: Dictionary = {}) -> GameNetTable:
	return await GameNetTable.create(self, rules, {"target": target}, 77, guests, settings, "count_to", 2, 4, 2)


func _add(n: int) -> Dictionary:
	return {"type": "add", "n": n}


# --- starting -----------------------------------------------------------------------------------------

func test_start_gives_everyone_the_same_fresh_game_with_their_own_view() -> void:
	var table: GameNetTable = await _table(3)
	var result: Dictionary = await table.start_game()
	assert_true(CoreResult.is_ok(result))
	assert_eq(table.host_batches.size(), 1)
	assert_eq(table.host_batches[0]["reason"], "start")
	assert_eq(table.host_batches[0]["seq"], 1)
	assert_eq(table.host_batches[0]["view"]["you"], table.lobby.local_player_id)
	for guest: GameNetTable.Guest in table.guests:
		assert_eq(guest.batches.size(), 1, guest.name)
		assert_eq(guest.batches[0]["reason"], "start")
		assert_eq(guest.batches[0]["seq"], 1)
		assert_eq(guest.last_view()["you"], guest.player_id(), "each player gets their own view")
		assert_eq(guest.last_view()["current_player"], table.lobby.local_player_id)


func test_the_lobby_start_is_what_begins_the_game_and_not_before() -> void:
	var table: GameNetTable = await _table(2)
	assert_false(table.host.is_running())
	assert_eq(table.host_batches.size(), 0)
	await table.settle()
	for guest: GameNetTable.Guest in table.guests:
		assert_eq(guest.batches.size(), 0)


# --- playing ------------------------------------------------------------------------------------------------

func test_a_legal_action_reaches_everyone_with_events_and_the_next_seq() -> void:
	var table: GameNetTable = await _table(2)
	await table.start_game()
	assert_true(CoreResult.is_ok(table.host.submit_local(_add(2))))
	assert_true(await table.until(func() -> bool: return table.guests[0].batches.size() == 2 and table.guests[1].batches.size() == 2))
	for batch: Dictionary in [table.host_batches[1], table.guests[0].batches[1], table.guests[1].batches[1]]:
		assert_eq(batch["reason"], "action")
		assert_eq(batch["seq"], 2)
		assert_eq((batch["events"] as Array).map(func(e: Dictionary) -> String: return e["type"]), ["added", "turn_changed"])
		assert_eq(batch["view"]["total"], 2)
	assert_eq(table.guests[0].last_view()["current_player"], table.guests[0].player_id())


func test_a_guest_acts_on_their_turn_and_the_host_sees_it() -> void:
	var table: GameNetTable = await _table(2)
	await table.start_game()
	table.host.submit_local(_add(1))
	await table.until(func() -> bool: return table.guests[0].batches.size() == 2)
	table.guests[0].game.submit(_add(3))
	assert_true(await table.until(func() -> bool: return table.host_batches.size() == 3 and table.guests[1].batches.size() == 3))
	assert_eq(table.host_batches[2]["view"]["total"], 4)
	assert_eq(table.guests[1].last_view()["current_player"], table.guests[1].player_id())


func test_a_whole_game_plays_out_and_everyone_ends_on_the_same_result() -> void:
	var table: GameNetTable = await _table(2, 14)
	await table.start_game()
	var guard: int = 0
	while not rules.is_finished(table.host.local_view()) and guard < 30:
		table.act_as_current(_add(3))
		await table.settle()
		guard += 1
	assert_true(rules.is_finished(table.host.local_view()))
	var winner: String = rules.winner(table.host.local_view())
	assert_ne(winner, "")
	for guest: GameNetTable.Guest in table.guests:
		assert_true(rules.is_finished(guest.last_view()), guest.name)
		assert_eq(rules.winner(guest.last_view()), winner)
		assert_eq(guest.last_view()["total"], table.host_batches.back()["view"]["total"])
	var seqs: Array = table.guests[0].batches.map(func(b: Dictionary) -> int: return b["seq"])
	for i: int in range(1, seqs.size()):
		assert_eq(seqs[i], seqs[i - 1] + 1, "no gaps")


func test_after_the_game_is_over_nobody_can_act() -> void:
	var table: GameNetTable = await _table(2, 3)
	await table.start_game()
	table.act_as_current(_add(3))
	await table.settle()
	assert_true(rules.is_finished(table.host.local_view()))
	var before: int = table.host_batches.size()
	table.guests[0].game.submit(_add(1))
	await table.settle()
	assert_eq(table.guests[0].rejections.back()["code"], "GAME_OVER")
	assert_eq(table.host.submit_local(_add(1))["error"]["code"], "GAME_OVER")
	assert_eq(table.host_batches.size(), before)


# --- illegal actions: an error to that player only, nothing changes ---------------------------------------------

func test_a_guest_acting_out_of_turn_is_refused_and_nothing_changes() -> void:
	var table: GameNetTable = await _table(2)
	await table.start_game()
	var before_host: int = table.host_batches.size()
	table.guests[1].game.submit(_add(1))  # it is the host's turn
	assert_true(await table.until(func() -> bool: return not table.guests[1].rejections.is_empty()))
	assert_eq(table.guests[1].rejections[0]["code"], "NOT_YOUR_TURN")
	assert_eq(table.guests[1].rejections[0]["action"], "add")
	await table.settle()
	assert_eq(table.host_batches.size(), before_host, "the host saw no change")
	assert_eq(table.guests[0].batches.size(), 1, "nor did the other player")
	assert_eq(table.guests[0].rejections.size(), 0, "and only the offender was told")
	assert_eq(table.host.local_view()["total"], 0)


func test_a_bad_move_and_a_malformed_message_get_errors_and_change_nothing() -> void:
	var table: GameNetTable = await _table(2)
	await table.start_game()
	table.host.submit_local(_add(1))
	await table.until(func() -> bool: return table.guests[0].batches.size() == 2)
	var guest: GameNetTable.Guest = table.guests[0]
	guest.game.submit(_add(99))
	guest.lobby.session.send(Envelope.make(Protocol.T_GAME_ACTION, {"action": "not an object"}))
	guest.lobby.session.send(Envelope.make(Protocol.T_GAME_ACTION, {}))
	guest.lobby.session.send(Envelope.make("game_something_else", {}))
	assert_true(await table.until(func() -> bool: return guest.rejections.size() == 4))
	assert_eq(guest.rejections.map(func(e: Dictionary) -> String: return e["code"]), [ErrorCodes.BAD_ACTION, ErrorCodes.MALFORMED, ErrorCodes.MALFORMED, ErrorCodes.UNKNOWN_ACTION])
	await table.settle()
	assert_eq(table.host.local_view()["total"], 1, "state unchanged")
	assert_eq(table.host_batches.size(), 2)
	assert_eq(table.guests[1].batches.size(), 2)


func test_a_rejected_host_action_is_reported_to_the_host_only() -> void:
	var table: GameNetTable = await _table(2)
	await table.start_game()
	var result: Dictionary = table.host.submit_local(_add(7))
	assert_false(CoreResult.is_ok(result))
	assert_eq(table.host_rejections.size(), 1)
	assert_eq(table.host_rejections[0]["code"], ErrorCodes.BAD_ACTION)
	await table.settle()
	assert_eq(table.guests[0].batches.size(), 1)


func test_actions_before_the_game_starts_are_refused() -> void:
	var table: GameNetTable = await _table(2)
	table.guests[0].game.submit(_add(1))
	assert_true(await table.until(func() -> bool: return not table.guests[0].rejections.is_empty()))
	assert_eq(table.guests[0].rejections[0]["code"], ErrorCodes.WRONG_PHASE)


# --- hidden information stays on the host -----------------------------------------------------------------------------------

func test_the_hosts_secret_and_random_state_never_cross_the_wire() -> void:
	var table: GameNetTable = await _table(3)
	await table.start_game()
	for _i: int in 4:
		table.act_as_current(_add(1))
		await table.settle()
	table.guests[0].game.request_resync()
	await table.settle()
	var text: String = table.wire_text()
	assert_gt(table.wire.size(), 8, "plenty of traffic was inspected")
	assert_false(text.contains("secret"), "no host-only key")
	assert_false(text.contains("seed-77"), "no host-only value")
	assert_false(text.contains("\"rng\""))
	for batch: Dictionary in table.host_batches:
		assert_false((batch["view"] as Dictionary).has("secret"))
	assert_true(table.host.state_for_save().has("secret"), "the host does hold it")


# --- seq gaps, resync and rejoin ----------------------------------------------------------------------------------------------

func test_a_gap_in_the_sequence_makes_the_guest_ask_for_a_full_snapshot() -> void:
	var table: GameNetTable = await _table(2)
	await table.start_game()
	var guest: GameNetTable.Guest = table.guests[0]
	# the host's next batches (seq 2, 3) never reach this guest: it sees seq 4 first
	var lost: Dictionary = {"seq": 4, "reason": "action", "events": [], "view": {"stale": true}}
	guest.game._on_message(Envelope.make(Protocol.T_GAME_BATCH, lost))
	assert_eq(guest.resyncs, 1)
	assert_true(await table.until(func() -> bool: return guest.reasons().has("resync")))
	var snapshot: Dictionary = guest.batches.back()
	assert_eq(snapshot["reason"], "resync")
	assert_eq(snapshot["events"], [])
	assert_eq(snapshot["view"]["you"], guest.player_id())
	assert_false(snapshot["view"].has("stale"))
	assert_eq(snapshot["view"]["total"], 0)


func test_old_and_duplicate_batches_are_ignored_by_the_guest() -> void:
	var table: GameNetTable = await _table(2)
	await table.start_game()
	var guest: GameNetTable.Guest = table.guests[0]
	var again: Dictionary = {"seq": 1, "reason": "action", "events": [], "view": {}}
	guest.game._on_message(Envelope.make(Protocol.T_GAME_BATCH, again))
	assert_eq(guest.batches.size(), 1)
	assert_eq(guest.resyncs, 0)


func test_a_player_who_rejoins_gets_a_snapshot_at_the_current_seq() -> void:
	var table: GameNetTable = await _table(2)
	await table.start_game()
	table.host.submit_local(_add(2))
	await table.settle()
	var leaver: GameNetTable.Guest = table.guests[1]
	var identity: Dictionary = leaver.lobby.identity()
	leaver.lobby.session.transport.leave()
	assert_true(await table.until(func() -> bool: return table.lobby.is_game_paused()))
	var back: GameNetTable.Guest = await table.add_guest("Guest2", identity)
	assert_true(await table.until(func() -> bool: return not back.batches.is_empty()))
	assert_eq(back.batches[0]["reason"], "rejoin")
	assert_eq(back.batches[0]["seq"], 2)
	assert_eq(back.batches[0]["events"], [])
	assert_eq(back.last_view()["total"], 2)
	assert_eq(back.last_view()["you"], leaver.player_id(), "the same seat as before")
	assert_true(await table.until(func() -> bool: return not table.lobby.is_game_paused()))
	table.guests[0].game.submit(_add(1))  # play goes on with seq 3
	assert_true(await table.until(func() -> bool: return not back.batches.is_empty() and back.batches.back()["seq"] == 3))


func test_a_resync_request_gets_a_fresh_snapshot_and_changes_nothing() -> void:
	var table: GameNetTable = await _table(2)
	await table.start_game()
	table.guests[0].game.request_resync()
	assert_true(await table.until(func() -> bool: return table.guests[0].reasons().has("resync")))
	assert_eq(table.guests[1].batches.size(), 1, "nobody else is sent anything")
	assert_eq(table.host_batches.size(), 1)


# --- pause and presence ------------------------------------------------------------------------------------------------------------

func test_while_paused_the_host_refuses_actions_from_everyone_including_itself() -> void:
	var table: GameNetTable = await _table(2)
	await table.start_game()
	table.guests[1].lobby.session.transport.leave()
	assert_true(await table.until(func() -> bool: return table.lobby.is_game_paused()))
	assert_eq(table.host.submit_local(_add(1))["error"]["code"], ErrorCodes.GAME_PAUSED)
	table.guests[0].game.submit(_add(1))
	assert_true(await table.until(func() -> bool: return not table.guests[0].rejections.is_empty()))
	assert_eq(table.guests[0].rejections[0]["code"], ErrorCodes.GAME_PAUSED)
	assert_eq(table.host.local_view()["total"], 0)


func test_continuing_without_waiting_lets_play_go_on_and_the_absent_player_is_skipped() -> void:
	var table: GameNetTable = await _table(2, 12)
	await table.start_game()
	table.host.submit_local(_add(1))  # now guest 1's turn
	await table.settle()
	table.guests[0].lobby.session.transport.leave()  # the player to move drops
	assert_true(await table.until(func() -> bool: return table.lobby.is_game_paused()))
	assert_true(CoreResult.is_ok(table.lobby.act({"type": "set_paused", "paused": false})))
	await table.settle()
	# the test game's settle() is the base default (it does nothing), so no settle batch is sent
	assert_false(table.lobby.is_game_paused())
	assert_false(table.host_batches.any(func(b: Dictionary) -> bool: return b["reason"] == "settle"))
	assert_eq(table.host.local_view()["current_player"], table.guests[0].player_id(), "still the absent player's turn")


# --- rematch, end_game, settings: host only -------------------------------------------------------------------------------------------

func test_the_host_can_start_a_rematch_and_everyone_jumps_to_the_fresh_game() -> void:
	var table: GameNetTable = await _table(2, 3)
	await table.start_game()
	table.act_as_current(_add(3))
	await table.settle()
	assert_true(rules.is_finished(table.host.local_view()))
	assert_true(CoreResult.is_ok(table.host.rematch()))
	assert_true(await table.until(func() -> bool: return table.guests[0].reasons().has("rematch") and table.guests[1].reasons().has("rematch")))
	for guest: GameNetTable.Guest in table.guests:
		assert_eq(guest.batches.back()["events"], [])
		assert_eq(guest.last_view()["total"], 0)
		assert_false(rules.is_finished(guest.last_view()))
		assert_gt(guest.batches.back()["seq"], guest.batches[guest.batches.size() - 2]["seq"])


func test_a_guest_cannot_rematch_or_end_the_game() -> void:
	var table: GameNetTable = await _table(2, 3)
	await table.start_game()
	table.guests[0].lobby.act({"type": "end_game"})
	table.guests[0].lobby.session.send(Envelope.make("game_rematch", {}))
	table.guests[0].game.submit({"type": "rematch"})
	assert_true(await table.until(func() -> bool: return table.guests[0].rejections.size() >= 2 and not table.guests[0].rec.action_failures.is_empty()))
	assert_eq(table.guests[0].rec.action_failures[0]["code"], ErrorCodes.NOT_HOST)
	await table.settle()
	assert_true(table.host.is_running())
	assert_eq(table.lobby.state["phase"], LobbyLogic.PHASE_IN_GAME)
	assert_eq(table.host_batches.size(), 1)


func test_end_game_sends_everyone_back_to_the_lobby_with_fresh_ready_flags() -> void:
	var table: GameNetTable = await _table(2, 12)
	await table.start_game()
	assert_true(CoreResult.is_ok(table.lobby.act({"type": "end_game"})))
	assert_true(await table.converge())
	assert_eq(table.host_ended, 1)
	assert_false(table.host.is_running())
	assert_eq(table.lobby.state["phase"], LobbyLogic.PHASE_OPEN)
	for guest: GameNetTable.Guest in table.guests:
		assert_eq(guest.lobby.state["phase"], LobbyLogic.PHASE_OPEN)
	for slot: Dictionary in table.lobby.state["slots"]:
		assert_eq(slot["ready"], slot["player_id"] == table.lobby.local_player_id)
	# they can play again from the lobby
	for guest: GameNetTable.Guest in table.guests:
		guest.lobby.set_ready(true)
	await table.converge()
	assert_true(CoreResult.is_ok(table.lobby.act({"type": "start"})))
	assert_true(CoreResult.is_ok(table.host.start()))
	assert_true(await table.until(func() -> bool: return table.guests[0].reasons().has("start") and table.guests[0].batches.size() >= 2))


func test_game_settings_are_set_by_the_host_and_every_guest_can_read_them() -> void:
	var table: GameNetTable = await _table(2, 12, {"flavour": "spicy", "n": 3})
	for guest: GameNetTable.Guest in table.guests:
		assert_eq(guest.lobby.state["game_settings"], {"flavour": "spicy", "n": 3})
	table.guests[0].lobby.act({"type": "set_game_settings", "settings": {"flavour": "mild"}})
	assert_true(await table.until(func() -> bool: return not table.guests[0].rec.action_failures.is_empty()))
	assert_eq(table.guests[0].rec.action_failures[0]["code"], ErrorCodes.NOT_HOST)
	assert_eq(table.lobby.state["game_settings"]["flavour"], "spicy")
	assert_eq(CoreResult.error_code(table.lobby.act({"type": "set_game_settings", "settings": "nope"})), ErrorCodes.BAD_ACTION)
	assert_eq(CoreResult.error_code(table.lobby.act({"type": "set_game_settings", "settings": {"big": "x".repeat(5000)}})), ErrorCodes.BAD_ACTION)
	await table.start_game()
	assert_eq(CoreResult.error_code(table.lobby.act({"type": "set_game_settings", "settings": {}})), ErrorCodes.WRONG_PHASE, "not once the game has started")
