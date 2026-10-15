class_name GameNetTable
extends RefCounted
## Test helper: a whole networked table. A host (LobbyHost + GameHost) and N guests (LobbyClient +
## GameClient) over whatever transport the test's env builds, with everything they receive
## recorded. Build one with `await GameNetTable.create(test, ...)`, then call `await start_game()`.
##
## Guests are seated in join order: the host is seat 0, `guests[0]` is seat 1, and so on.

const APP: String = "1.0.0"

class Guest:
	extends RefCounted
	var name: String
	var lobby: LobbyClient
	var game: GameClient
	var rec: LobbyClientRecorder
	var batches: Array[Dictionary] = []
	var rejections: Array[Dictionary] = []
	var resyncs: int = 0
	var identity: Dictionary = {}

	func player_id() -> String:
		return lobby.player_id

	func last_view() -> Dictionary:
		return {} if batches.is_empty() else batches[batches.size() - 1]["view"]

	func reasons() -> Array:
		return batches.map(func(b: Dictionary) -> String: return b["reason"])


var test: NetTestCase
var rules: GameRules
var lobby: LobbyHost
var host: GameHost
var host_rec: LobbyHostRecorder
var host_batches: Array[Dictionary] = []
var host_rejections: Array[Dictionary] = []
var host_ended: int = 0
var guests: Array[Guest] = []
## Every message any guest received from the host: exactly what crossed the wire to players.
var wire: Array[Dictionary] = []
var address: String = ""
var game_id: String = "test_game"


## Builds a table with `guest_count` guests, all ready. The game has not started yet.
static func create(test_case: NetTestCase, game_rules: GameRules, setup: Dictionary, seed_value: int, guest_count: int, game_settings: Dictionary = {}, id: String = "test_game", min_players: int = 2, max_players: int = 4, min_active: int = 0) -> GameNetTable:
	var table: GameNetTable = GameNetTable.new()
	table.test = test_case
	table.rules = game_rules
	table.game_id = id
	table.lobby = LobbyHost.new(test_case.env.make_transport(), APP, id, "Hosty", min_players, max_players, {}, min_active)
	table.lobby.session.clock = test_case.clock.as_callable()
	table.host_rec = LobbyHostRecorder.new(table.lobby)
	table.host = GameHost.new(table.lobby, game_rules, setup, seed_value)
	table.host.batch_ready.connect(func(batch: Dictionary) -> void: table.host_batches.append(batch))
	table.host.action_rejected.connect(func(error: Dictionary) -> void: table.host_rejections.append(error))
	table.host.ended.connect(func() -> void: table.host_ended += 1)
	var started: Dictionary = table.lobby.start(test_case.env.host_config())
	test_case.assert_true(CoreResult.is_ok(started), "hosting could not start: %s" % str(started))
	test_case.track(table.lobby, table.lobby.session.transport)
	await test_case.pump(func() -> bool: return not table.host_rec.hosting.is_empty() or not table.host_rec.host_failures.is_empty())
	test_case.assert_true(table.host_rec.host_failures.is_empty() and not table.host_rec.hosting.is_empty(), "hosting never became ready")
	table.address = str(table.host_rec.hosting[0].get("address", ""))
	if not game_settings.is_empty():
		var chosen: Dictionary = table.lobby.act({"type": "set_game_settings", "settings": game_settings})
		test_case.assert_true(CoreResult.is_ok(chosen), "settings refused: %s" % str(chosen))
	for i: int in guest_count:
		await table.add_guest("Guest%d" % (i + 1))
	for guest: Guest in table.guests:
		guest.lobby.set_ready(true)
	await table.converge()
	return table


## Joins one more guest (before the game starts, or as a returning player with `identity`).
func add_guest(player_name: String, identity: Dictionary = {}) -> Guest:
	var guest: Guest = Guest.new()
	guest.name = player_name
	guest.lobby = LobbyClient.new(test.env.make_transport(), APP)
	guest.lobby.session.clock = test.clock.as_callable()
	guest.rec = LobbyClientRecorder.new(guest.lobby)
	guest.game = GameClient.new(guest.lobby)
	guest.game.batch_ready.connect(func(batch: Dictionary) -> void: guest.batches.append(batch))
	guest.game.action_rejected.connect(func(error: Dictionary) -> void: guest.rejections.append(error))
	guest.game.resync_requested.connect(func() -> void: guest.resyncs += 1)
	guest.lobby.session.transport.message_received.connect(func(_peer: int, message: Dictionary) -> void: wire.append(message))
	test.track(guest.lobby, guest.lobby.session.transport)
	guests.append(guest)
	guest.lobby.join(address, player_name, test.env.join_config(), identity)
	var ok: bool = await test.pump(func() -> bool:
		return not guest.rec.join_failures.is_empty() or (not guest.rec.joined.is_empty() and not guest.rec.states.is_empty()), 3000)
	test.assert_true(ok, "guest %s got no outcome" % player_name)
	if not guest.rec.joined.is_empty():
		guest.identity = guest.lobby.identity()
	return guest


## Waits until every connected guest mirrors the host's lobby revision.
func converge() -> bool:
	var settled: Callable = func() -> bool:
		for guest: Guest in guests:
			if guest.lobby.session.is_active() and (guest.lobby.state.is_empty() or guest.lobby.state["revision"] != lobby.state["revision"]):
				return false
		return true
	var ok: bool = await test.pump(settled)
	if ok and test.env.settle_frames() > 0:
		await test.frames(test.env.settle_frames())
		ok = await test.pump(settled)
	return ok


## Starts the lobby game and the game itself. Returns the GameHost.start() result.
func start_game() -> Dictionary:
	var started: Dictionary = lobby.act({"type": "start"})
	test.assert_true(CoreResult.is_ok(started), "lobby start refused: %s" % str(started))
	var result: Dictionary = host.start()
	await converge()
	await settle()
	return result


## Polls long enough for messages in flight to land.
func settle() -> void:
	await test.frames(10 + test.env.settle_frames())


## Waits until `condition` holds (polling the table).
func until(condition: Callable, max_frames: int = 600) -> bool:
	return await test.pump(condition, max_frames)


func all_views() -> Array[Dictionary]:
	var views: Array[Dictionary] = []
	if not host_batches.is_empty():
		views.append(host_batches[host_batches.size() - 1]["view"])
	for guest: Guest in guests:
		if not guest.batches.is_empty():
			views.append(guest.last_view())
	return views


## Everything that crossed the wire to players, as one string (to prove what never did).
func wire_text() -> String:
	return JSON.stringify(wire)


func guest_by_id(player_id: String) -> Guest:
	for guest: Guest in guests:
		if guest.player_id() == player_id:
			return guest
	return null


## Plays `action` as whoever the rules say is to move (host or guest). Returns who acted.
func act_as_current(action: Dictionary) -> String:
	var who: String = rules.current_player(host.local_view())
	if who == lobby.local_player_id:
		host.submit_local(action)
	else:
		guest_by_id(who).game.submit(action)
	return who
