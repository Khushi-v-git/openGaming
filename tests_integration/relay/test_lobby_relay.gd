extends "res://tests/core/lobby_contract.gd"
## The lobby contract suite, unchanged, over RelayTransport and a real local relay.


## GUT skips the whole script (and says why) when there is no relay to talk to.
func should_skip_script():  # (GUT declares this without a return type)
	if RelayEnv.available():
		return false
	return "no relay: run scripts/run_integration_tests.sh (needs Node and relay/cloudflare/node_modules)"


func make_env() -> TransportEnv:
	return RelayEnv.new()


# --- relay-specific: a restarted host cannot resume its old room ---------------------------------------

func test_a_restarted_host_resumes_in_a_new_room_and_players_rejoin_with_their_session_tokens() -> void:
	var host: LobbyHostRig = await start_lobby()
	var old_code: String = host.address
	var a: LobbyClientRig = await join_player(host, "Asha")
	var b: LobbyClientRig = await join_player(host, "Bo")
	await _start_game_with(host, [a, b])
	var saved: Dictionary = SessionSnapshot.from_text(SessionSnapshot.to_text(host.lobby.snapshot({"turn": 7})))["snapshot"]
	var identities: Dictionary = {"a": a.client.identity(), "b": b.client.identity()}
	host.lobby.session.transport.leave()  # the host app is closed: its in-memory room key is gone
	await pump(func() -> bool: return a.recorder.left.size() >= 1 and b.recorder.left.size() >= 1)

	var resumed: Array = await resume_lobby(saved)
	var new_host: LobbyHostRig = resumed[0]
	assert_true(CoreResult.is_ok(resumed[1]))
	assert_true(RelayTransport.looks_like_code(new_host.address), "a room code, not an address")
	assert_ne(new_host.address, old_code, "a new room with a new code")

	# the old room is gone: nobody can sneak back into it
	var stray: RelayTransport = RelayTransport.new()
	var failures: Array[String] = []
	stray.join_failed.connect(func(reason: String) -> void: failures.append(reason))
	track(stray, stray)
	stray.join_session(old_code, env.join_config())
	assert_true(await pump(func() -> bool: return not failures.is_empty()))
	assert_eq(failures[0], RelayTransport.REASONS["ROOM_NOT_FOUND"])

	# the players come back to the NEW code with the identities they were given
	var a2: LobbyClientRig = await join_player(new_host, "Asha", identities["a"])
	var b2: LobbyClientRig = await join_player(new_host, "Bo", identities["b"])
	assert_eq(a2.recorder.joined, [identities["a"]["player_id"]] as Array[String], "the same player ids as before")
	assert_eq(b2.recorder.joined, [identities["b"]["player_id"]] as Array[String])
	assert_true(await converge(new_host, [a2, b2]))
