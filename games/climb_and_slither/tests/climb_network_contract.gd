extends NetTestCase
## Climb and Slither played over the network (GameHost + GameClient on a LobbyHost), on whatever
## transport the env builds. Not collected itself; test_climb_network_<transport>.gd extends this.
## The generic networked-game behaviour is covered with the count-to-N game in
## tests/core/game_network_contract.gd; these tests check the real game's rules ride the same layer.

const CLIMB_ID: String = "climb_and_slither"
const ROLL: Dictionary = {"type": "roll"}

var rules: ClimbAndSlitherRules


func before_each() -> void:
	super.before_each()
	rules = ClimbAndSlitherRules.new()


func _table(guests: int, seed_value: int, settings: Dictionary = {}) -> GameNetTable:
	return await GameNetTable.create(self, rules, ClimbRig.classic(), seed_value, guests, settings, CLIMB_ID, 2, 4, 2)


## Waits until every connected guest has seen the host's newest batch.
func _sync(table: GameNetTable) -> bool:
	return await table.until(func() -> bool:
		if table.host_batches.is_empty():
			return false
		var newest: int = int(table.host_batches[table.host_batches.size() - 1]["seq"])
		for guest: GameNetTable.Guest in table.guests:
			if guest.lobby.session.is_active() and (guest.batches.is_empty() or int(guest.batches[guest.batches.size() - 1]["seq"]) != newest):
				return false
		return true)


func _roll_until_over(table: GameNetTable, limit: int = 1500) -> int:
	var rolls: int = 0
	while not rules.is_finished(table.host.local_view()) and rolls < limit:
		table.act_as_current(ROLL)
		assert_true(await _sync(table), "a roll never reached everyone")
		rolls += 1
	return rolls


func _without_you(view: Dictionary) -> Dictionary:
	var copy: Dictionary = view.duplicate(true)
	copy.erase("you")
	return copy


# --- 1. a whole game ---------------------------------------------------------------------------------------

func test_a_whole_three_player_game_is_played_over_the_network() -> void:
	var table: GameNetTable = await _table(2, 123456789)
	await table.start_game()
	var rng_at_start: Dictionary = (table.host.state_for_save()["rng"] as Dictionary).duplicate()
	var rolls: int = await _roll_until_over(table)
	assert_true(rules.is_finished(table.host.local_view()), "the game finished after %d rolls" % rolls)
	var winner: String = rules.winner(table.host.local_view())
	assert_ne(winner, "")
	var final_view: Dictionary = _without_you(table.host.local_view())
	for guest: GameNetTable.Guest in table.guests:
		assert_true(rules.is_finished(guest.last_view()), guest.name)
		assert_eq(rules.winner(guest.last_view()), winner, guest.name)
		assert_eq(_without_you(guest.last_view()), final_view, "%s ends on the host's picture" % guest.name)
		var seqs: Array = guest.batches.map(func(b: Dictionary) -> int: return b["seq"])
		for i: int in range(1, seqs.size()):
			assert_eq(seqs[i], seqs[i - 1] + 1, "%s: no gaps in seq" % guest.name)
		assert_eq(guest.resyncs, 0, "%s never needed a resync" % guest.name)


func test_the_random_generator_and_seed_never_leave_the_host() -> void:
	var table: GameNetTable = await _table(2, 123456789)
	await table.start_game()
	var texts: Array[String] = [str(table.host.state_for_save()["rng"]["seed"]), str(table.host.state_for_save()["rng"]["state"])]
	for _i: int in 40:
		if rules.is_finished(table.host.local_view()):
			break
		table.act_as_current(ROLL)
		await _sync(table)
		texts.append(str(table.host.state_for_save()["rng"]["state"]))
	table.guests[0].game.request_resync()
	await table.settle()
	var wire: String = table.wire_text()
	assert_gt(table.wire.size(), 20, "plenty of traffic was inspected")
	assert_false(wire.contains("\"rng\""), "no host-only key on the wire")
	for text: String in texts:
		assert_false(wire.contains(text), "generator text %s must not appear" % text)
	for batch: Dictionary in table.host_batches:
		assert_false((batch["view"] as Dictionary).has("rng"))
		assert_false(JSON.stringify(batch).contains("\"rng\""))


# --- 2. views ------------------------------------------------------------------------------------------------

func test_every_player_gets_their_own_view_and_the_rest_is_identical() -> void:
	var table: GameNetTable = await _table(2, 31)
	await table.start_game()
	for _i: int in 5:
		table.act_as_current(ROLL)
		await _sync(table)
	var host_view: Dictionary = table.host.local_view()
	assert_eq(host_view["you"], table.lobby.local_player_id)
	var seen: Dictionary = {host_view["you"]: true}
	for guest: GameNetTable.Guest in table.guests:
		assert_eq(guest.last_view()["you"], guest.player_id())
		assert_false(seen.has(guest.last_view()["you"]), "each view names a different player")
		seen[guest.last_view()["you"]] = true
		assert_eq(_without_you(guest.last_view()), _without_you(host_view))


# --- 3. illegal actions ------------------------------------------------------------------------------------------

func test_illegal_actions_are_refused_and_change_nothing() -> void:
	var table: GameNetTable = await _table(2, 47)
	await table.start_game()
	var before: Dictionary = table.host.local_view().duplicate(true)
	var batches_before: int = table.host_batches.size()
	var guest: GameNetTable.Guest = table.guests[0]
	var other: GameNetTable.Guest = table.guests[1]

	guest.game.submit(ROLL)  # it is the host's turn
	assert_true(await table.until(func() -> bool: return not guest.rejections.is_empty()))
	assert_eq(guest.rejections[0]["code"], ClimbErrors.NOT_YOUR_TURN)

	var extra: Dictionary = table.host.submit_local({"type": "roll", "dice": [6]})  # the dice are never the caller's to choose
	assert_false(CoreResult.is_ok(extra))
	assert_eq(table.host_rejections.size(), 1)
	assert_false(CoreResult.is_ok(table.host.submit_local({"type": "teleport"})))

	other.game.submit({"type": "roll", "dice": [6]})
	guest.lobby.act({"type": "end_game"})
	guest.lobby.session.send(Envelope.make("game_rematch", {}))
	assert_true(await table.until(func() -> bool: return not guest.rec.action_failures.is_empty() and guest.rejections.size() >= 2 and not other.rejections.is_empty()))
	assert_eq(guest.rec.action_failures[0]["code"], ErrorCodes.NOT_HOST)
	assert_eq(guest.rejections[1]["code"], ErrorCodes.UNKNOWN_ACTION)
	await table.settle()
	assert_eq(table.host_batches.size(), batches_before, "no batch was produced")
	assert_eq(table.host.local_view(), before, "the game is exactly as it was")
	assert_eq(guest.batches.size(), 1)
	assert_eq(other.batches.size(), 1)
	assert_eq(table.lobby.state["phase"], LobbyLogic.PHASE_IN_GAME)


# --- 4. settle on presence --------------------------------------------------------------------------------------------

func test_the_turn_moves_on_when_the_player_to_move_drops_and_the_host_continues() -> void:
	var table: GameNetTable = await _table(2, 11)
	await table.start_game()
	table.act_as_current(ROLL)  # the host rolls; the turn passes to guest 1
	assert_true(await _sync(table))
	var dropper: GameNetTable.Guest = table.guests[0]
	var third: GameNetTable.Guest = table.guests[1]
	assert_eq(rules.current_player(table.host.local_view()), dropper.player_id(), "it is guest 1's turn")
	var identity: Dictionary = dropper.lobby.identity()
	dropper.lobby.session.transport.leave()
	assert_true(await table.until(func() -> bool: return table.lobby.is_game_paused()))
	var seq_before: int = table.host_batches.back()["seq"]
	assert_true(CoreResult.is_ok(table.lobby.act({"type": "set_paused", "paused": false})))
	assert_true(await table.until(func() -> bool: return third.batches.back()["reason"] == "settle"))
	for batch: Dictionary in [table.host_batches.back(), third.batches.back()]:
		assert_eq(batch["reason"], "settle")
		assert_eq(batch["seq"], seq_before + 1)
		assert_eq(ClimbRig.event_types(batch["events"]), ["turn_skipped", "turn_changed"])
		assert_eq(batch["view"]["current_player"], third.player_id())

	# the skipped player comes back: a snapshot, and they are in the rotation again
	var back: GameNetTable.Guest = await table.add_guest("Guest1", identity)
	assert_true(await table.until(func() -> bool: return back.reasons().has("rejoin")))
	assert_eq(back.batches[0]["reason"], "rejoin")
	assert_eq(back.batches[0]["events"], [])
	assert_eq(back.last_view()["you"], dropper.player_id())
	assert_eq(back.last_view()["current_player"], third.player_id())
	var turns: Array[String] = []
	for _i: int in 3:
		turns.append(table.act_as_current(ROLL))
		assert_true(await table.until(func() -> bool: return back.batches.back()["seq"] == table.host_batches.back()["seq"]))
	assert_true(turns.has(dropper.player_id()), "the returned player got a turn again: %s" % str(turns))


# --- 5. pause ----------------------------------------------------------------------------------------------------------------

func test_while_paused_everyone_gets_game_paused_and_nothing_changes() -> void:
	var table: GameNetTable = await _table(2, 19)
	await table.start_game()
	table.guests[1].lobby.session.transport.leave()
	assert_true(await table.until(func() -> bool: return table.lobby.is_game_paused()))
	var before: Dictionary = table.host.local_view().duplicate(true)
	var count: int = table.host_batches.size()
	assert_eq(table.host.submit_local(ROLL)["error"]["code"], ErrorCodes.GAME_PAUSED)
	table.guests[0].game.submit(ROLL)
	assert_true(await table.until(func() -> bool: return not table.guests[0].rejections.is_empty()))
	assert_eq(table.guests[0].rejections[0]["code"], ErrorCodes.GAME_PAUSED)
	await table.settle()
	assert_eq(table.host_batches.size(), count)
	assert_eq(table.host.local_view(), before)


# --- 6. settings -----------------------------------------------------------------------------------------------------------

## The first seed (from 1) whose first roll is not a 1, so "need a 1" shows its refusal.
func _seed_with_a_non_one_first_roll() -> int:
	for candidate: int in range(1, 41):
		var game: Dictionary = rules.new_game(["a", "b"], ClimbRig.classic(), {"need_one_to_start": true}, candidate)
		var rolled: Dictionary = rules.apply(game["state"], "a", ROLL)
		if ClimbRig.event_types(rolled["events"]).has("needs_one"):
			return candidate
	return -1


func test_the_hosts_settings_are_shared_and_drive_the_game() -> void:
	var seed_value: int = _seed_with_a_non_one_first_roll()
	assert_ne(seed_value, -1)
	var table: GameNetTable = await _table(2, seed_value, {"need_one_to_start": true})
	for guest: GameNetTable.Guest in table.guests:
		assert_eq(guest.lobby.state["game_settings"], {"need_one_to_start": true}, "guests can read the settings in the lobby")
	await table.start_game()
	assert_true(table.host.local_view()["settings"]["need_one_to_start"])
	for guest: GameNetTable.Guest in table.guests:
		assert_true(guest.last_view()["settings"]["need_one_to_start"])
	table.act_as_current(ROLL)
	assert_true(await _sync(table))
	for batch: Dictionary in [table.host_batches.back(), table.guests[0].batches.back(), table.guests[1].batches.back()]:
		assert_true(ClimbRig.event_types(batch["events"]).has("needs_one"), "everyone saw the refusal")
		assert_false(ClimbRig.event_types(batch["events"]).has("moved"))


func test_invalid_settings_are_refused_by_the_host_and_guests_cannot_set_any() -> void:
	var table: GameNetTable = await _table(2, 5)
	var refused: Dictionary = table.lobby.act({"type": "set_game_settings", "settings": {"exact_finish": true, "dice_count": 2}})
	assert_eq(CoreResult.error_code(refused), ClimbErrors.INVALID_SETTINGS)
	assert_eq(table.lobby.state["game_settings"], {}, "nothing was stored")
	table.guests[0].lobby.act({"type": "set_game_settings", "settings": {"dice_count": 2}})
	assert_true(await table.until(func() -> bool: return not table.guests[0].rec.action_failures.is_empty()))
	assert_eq(table.guests[0].rec.action_failures[0]["code"], ErrorCodes.NOT_HOST)
	assert_eq(table.lobby.state["game_settings"], {})
	assert_true(CoreResult.is_ok(table.lobby.act({"type": "set_game_settings", "settings": {"dice_count": 2, "extra_turn_on_six": true}})))
	await table.start_game()
	assert_eq(table.host.local_view()["settings"]["dice_count"], 2)


# --- 7. rematch and end_game ----------------------------------------------------------------------------------------------

func test_a_rematch_resets_the_board_for_everyone_and_only_the_host_can_call_it() -> void:
	var table: GameNetTable = await _table(2, 23)
	await table.start_game()
	for _i: int in 8:
		table.act_as_current(ROLL)
		await _sync(table)
	var seq_before: int = table.host_batches.back()["seq"]
	assert_true(CoreResult.is_ok(table.host.rematch()))
	assert_true(await _sync(table))
	for batch: Dictionary in [table.host_batches.back(), table.guests[0].batches.back(), table.guests[1].batches.back()]:
		assert_eq(batch["reason"], "rematch")
		assert_eq(batch["seq"], seq_before + 1)
		assert_eq(batch["events"], [])
		for id: String in batch["view"]["positions"]:
			assert_eq(batch["view"]["positions"][id], 0, "everyone back at the start")
		assert_eq(batch["view"]["rolls"], 0)
		assert_eq(batch["view"]["winner"], "")
	# a guest cannot do it
	table.guests[0].lobby.session.send(Envelope.make("game_rematch", {}))
	assert_true(await table.until(func() -> bool: return not table.guests[0].rejections.is_empty()))
	assert_eq(table.guests[0].rejections.back()["code"], ErrorCodes.UNKNOWN_ACTION)
	assert_eq(table.host_batches.back()["seq"], seq_before + 1)


func test_end_game_returns_everyone_to_the_lobby_and_a_new_game_can_start() -> void:
	var table: GameNetTable = await _table(2, 29)
	await table.start_game()
	table.act_as_current(ROLL)
	await _sync(table)
	assert_true(CoreResult.is_ok(table.lobby.act({"type": "end_game"})))
	assert_true(await table.converge())
	assert_eq(table.host_ended, 1)
	for guest: GameNetTable.Guest in table.guests:
		assert_eq(guest.lobby.state["phase"], LobbyLogic.PHASE_OPEN)
	for guest: GameNetTable.Guest in table.guests:
		guest.lobby.set_ready(true)
	assert_true(await table.converge())
	assert_true(CoreResult.is_ok(table.lobby.act({"type": "start"})))
	assert_true(CoreResult.is_ok(table.host.start()))
	assert_true(await _sync(table))
	assert_eq(table.guests[0].batches.back()["reason"], "start")
	for id: String in table.guests[0].last_view()["positions"]:
		assert_eq(table.guests[0].last_view()["positions"][id], 0)


# --- 8. save and resume -----------------------------------------------------------------------------------------------------

func test_a_saved_game_resumes_and_players_rejoin_with_their_identities() -> void:
	var seed_value: int = 777
	var table: GameNetTable = await _table(2, seed_value)
	await table.start_game()
	for _i: int in 6:
		table.act_as_current(ROLL)
		await _sync(table)
	var saved_view: Dictionary = table.host.local_view().duplicate(true)
	var game_state: Dictionary = table.host.state_for_save()
	var text: String = SessionSnapshot.to_text(table.lobby.snapshot(game_state))  # through text, as a save file travels
	var saved: Dictionary = SessionSnapshot.from_text(text)["snapshot"]
	var identities: Array[Dictionary] = [table.guests[0].lobby.identity(), table.guests[1].lobby.identity()]
	var host_id: String = table.lobby.local_player_id
	table.lobby.session.transport.leave()  # the host app is gone
	assert_true(await table.until(func() -> bool: return table.guests[0].rec.left.size() >= 1 and table.guests[1].rec.left.size() >= 1))

	var resumed: GameNetTable = GameNetTable.new()
	resumed.test = self
	resumed.rules = rules
	resumed.game_id = CLIMB_ID
	resumed.lobby = LobbyHost.new(env.make_transport(), GameNetTable.APP, CLIMB_ID, "placeholder", 2, 4, {}, 2)
	resumed.lobby.session.clock = clock.as_callable()
	resumed.host_rec = LobbyHostRecorder.new(resumed.lobby)
	resumed.host = GameHost.new(resumed.lobby, rules, ClimbRig.classic(), seed_value)
	resumed.host.batch_ready.connect(func(batch: Dictionary) -> void: resumed.host_batches.append(batch))
	var restored: Dictionary = resumed.lobby.restore(saved)
	assert_true(CoreResult.is_ok(restored), str(restored))
	assert_true(CoreResult.is_ok(resumed.host.adopt_state(restored["game_state"])))
	assert_eq(resumed.lobby.local_player_id, host_id)
	assert_true(CoreResult.is_ok(resumed.lobby.start(env.host_config())))
	track(resumed.lobby, resumed.lobby.session.transport)
	await pump(func() -> bool: return not resumed.host_rec.hosting.is_empty())
	resumed.address = str(resumed.host_rec.hosting[0].get("address", ""))

	var names: Array[String] = ["Guest1", "Guest2"]
	for i: int in 2:
		var back: GameNetTable.Guest = await resumed.add_guest(names[i], identities[i])
		assert_true(await resumed.until(func() -> bool: return not back.batches.is_empty()), "%s got no snapshot" % names[i])
		assert_eq(back.batches[0]["reason"], "rejoin")
		assert_eq(back.batches[0]["events"], [])
		assert_eq(back.last_view()["you"], identities[i]["player_id"], "the same seat as before")
		assert_eq(back.last_view()["positions"], saved_view["positions"], "the saved board")
		assert_eq(back.last_view()["current_player"], saved_view["current_player"])
		assert_eq(back.last_view()["rolls"], saved_view["rolls"])
	assert_eq(resumed.host.local_view()["positions"], saved_view["positions"])
	assert_true(await resumed.until(func() -> bool: return not resumed.lobby.is_game_paused()), "the game resumes once everyone is back")
	# and play carries on from where it stopped
	var who: String = resumed.act_as_current(ROLL)
	assert_ne(who, "")
	assert_true(await resumed.until(func() -> bool: return resumed.guests[0].batches.size() >= 2 and resumed.guests[0].batches.back()["reason"] == "action"))
