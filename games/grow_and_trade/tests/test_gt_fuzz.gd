extends GutTest
## Whole Grow & Trade games played to the end by random bots (GtBot), with random player counts, house
## rules and absences. After every action the cheap invariants are checked (conservation of resources and
## fortune cards, no leaks in views, queries agree between state and view); the full validate_state runs
## every few actions and at the end. A failure prints the replay of the game that broke (see GtReplay).
##
## GT_FUZZ_GAMES=<n> in the environment plays n games instead of the default (for a long manual run).

const DEFAULT_GAMES: int = 8
const ACTION_CAP: int = 5000
const VALIDATE_EVERY: int = 60
const VIEW_EVERY: int = 7
const ROUND_TRIP_EVERY: int = 90
const MASTER_SEED: int = 20260101
const PLAYER_IDS: Array = ["p1", "p2", "p3", "p4", "p5", "p6"]
const DECK_SIZE: int = 25
const ALLOWED_EVENTS: Array[String] = [
	"founding_placed", "rolled", "produced", "shortage", "nothing_produced", "discard_required", "discarded",
	"blocker_moved", "stole", "built", "card_bought", "card_played", "harvest_taken", "swept", "bank_traded",
	"offer_made", "offer_accepted", "offer_declined", "trade_done", "offer_cancelled", "bonus_changed",
	"turn_changed", "turn_skipped", "won",
]

var rules: GrowAndTradeRules
var board_data: Dictionary


func before_all() -> void:
	board_data = GtBoard.load_file()["board"]


func before_each() -> void:
	rules = GrowAndTradeRules.new()


func _random_active(prng: Prng, ids: Array) -> Array:
	var active: Array = []
	for id: Variant in ids:
		if prng.range_int(0, 3) != 0:
			active.append(id)
	if active.is_empty():
		active.append(ids[prng.range_int(0, ids.size() - 1)])
	return active


func _needs_settle(state: Dictionary, active: Array) -> bool:
	if state["phase"] == "finished":
		return false
	if not active.has(state["current_player"]):
		return true
	if state["phase"] == "playing" and state["turn"]["pending"] == "discard":
		for id: Variant in state["turn"]["owed"]:
			if not active.has(id):
				return true
	return false


## What settle() must have achieved for the players who are present.
func _check_settled(state: Dictionary, active: Array) -> String:
	if state["phase"] == "finished":
		return ""
	if not active.has(state["current_player"]):
		return "settle left the turn with an absent player"
	if state["phase"] == "playing":
		for id: Variant in state["turn"]["owed"]:
			if not active.has(id):
				return "settle left a discard owed by an absent player"
		var offer: Dictionary = state["offer"]
		if state["settings"]["cancel_offers_on_absence"] and not offer.is_empty():
			var involved: Array = [offer["from"]]
			involved.append_array(offer["to"])
			involved.append_array(offer["accepted"])
			for id: Variant in involved:
				if not active.has(id):
					return "settle kept an offer that involves an absent player although cancel_offers_on_absence is on"
	return ""


func _initial_totals(state: Dictionary) -> Dictionary:
	var totals: Dictionary = {}
	for resource: String in GtBank.RESOURCES:
		var sum: int = int(state["supply"][resource])
		for id: String in GtState.seat_order(state):
			sum += int(state["hands"][id][resource])
		totals[resource] = sum
	return totals


## Invariants that must hold after every successful action. Returns "" or a description.
func _check_step(game: Dictionary, next: Dictionary, events: Array) -> String:
	for resource: String in GtBank.RESOURCES:
		var sum: int = int(next["supply"][resource])
		if sum < 0:
			return "the bank holds %d %s" % [sum, resource]
		for id: String in game["players"]:
			var held: int = int(next["hands"][id][resource])
			if held < 0:
				return "%s holds %d %s" % [id, held, resource]
			sum += held
		if sum != game["totals"][resource]:
			return "%s was created or destroyed: %d now, %d at the start" % [resource, sum, game["totals"][resource]]
	var cards: int = (next["deck"] as Array).size()
	var guards: int = 0
	for id: String in game["players"]:
		cards += (next["cards"][id]["held"] as Array).size() + (next["cards"][id]["fresh"] as Array).size()
		guards += int(next["guards_played"][id])
	for event: Dictionary in events:
		if not ALLOWED_EVENTS.has(event["type"]):
			return "unknown event %s" % str(event["type"])
		game["event_counts"][event["type"]] = int(game["event_counts"].get(event["type"], 0)) + 1
		if event["type"] == "card_played" and event["card"] != "guard":
			game["played_other"] += 1
		if event["type"] == "won":
			game["won_events"] += 1
	if cards + guards + game["played_other"] != DECK_SIZE:
		return "fortune cards were created or destroyed (%d accounted for of %d)" % [cards + guards + game["played_other"], DECK_SIZE]
	if int(next["turn_number"]) < game["turn_number"]:
		return "turn_number went backwards"
	game["turn_number"] = int(next["turn_number"])
	var rank: int = ["founding", "playing", "finished"].find(next["phase"])
	if rank < game["rank"]:
		return "the phase went backwards"
	game["rank"] = rank
	if not game["players"].has(next["current_player"]):
		return "the turn went to a stranger"
	if next["phase"] == "finished":
		if game["won_events"] != 1:
			return "%d won events in a finished game" % game["won_events"]
		if next["winner"] == "" or next["winner"] != next["current_player"]:
			return "the winner is not the player whose turn it was"
		if GtScore.points(next, next["winner"], true) < int(next["settings"]["target_points"]):
			return "the winner is below the target"
	elif game["won_events"] != 0:
		return "a won event without a finished game"
	return ""


## No hidden data in a view; the three queries agree between state and view.
func _check_view(state: Dictionary, player_id: String) -> String:
	var view: Dictionary = rules.view_for(state, player_id)
	for key: String in ["hands", "cards", "deck", "rng"]:
		if view.has(key):
			return "the view of %s has '%s'" % [player_id, key]
	var text: String = JSON.stringify(view)
	if text.contains(state["rng"]["state"]):
		return "the random generator state is in the view of %s" % player_id
	if (state["deck"] as Array).size() >= 6 and text.contains(JSON.stringify(state["deck"])):  # a short deck's text ("[]") is everywhere
		return "the deck order is in the view of %s" % player_id
	if view["hand"] != state["hands"][player_id] or view["my_cards"] != state["cards"][player_id]:
		return "the view of %s does not carry their own hand and cards" % player_id
	for id: String in GtState.seat_order(state):
		var hand: Dictionary = state["hands"][id]
		if id != player_id and GtBank.hand_count(hand) > 0 and hand != state["hands"][player_id] and text.contains(JSON.stringify(hand)):
			return "the hand of %s is in the view of %s" % [id, player_id]
		if int(view["hand_counts"][id]) != GtBank.hand_count(hand):
			return "hand_counts is wrong for %s" % id
	if rules.is_finished(view) != rules.is_finished(state) or rules.current_player(view) != rules.current_player(state) or rules.winner(view) != rules.winner(state):
		return "the queries disagree between the state and the view of %s" % player_id
	return ""


## Plays one game with every check on. Returns "" if all was well, otherwise the first problem plus the replay.
func _play_one(index: int, master: Prng, stats: Dictionary) -> String:
	var player_count: int = master.range_int(3, 6)
	var players: Array = PLAYER_IDS.slice(0, player_count)
	var settings: Dictionary = {
		"target_points": [8, 8, 10][master.range_int(0, 2)],
		"hand_limit": [5, 7, 9][master.range_int(0, 2)],
		"bank_rate": [3, 4][master.range_int(0, 1)],
		"friendly_blocker": master.range_int(0, 1) == 1,
		"cancel_offers_on_absence": master.range_int(0, 1) == 1,
	}
	var seed_value: int = (master.next_u32() << 31) ^ master.next_u32()
	var wobbly: bool = master.range_int(0, 2) == 0
	var created: Dictionary = rules.new_game(players, board_data, settings, seed_value)
	if not CoreResult.is_ok(created):
		return "new_game refused a valid setup: %s" % str(created)
	var state: Dictionary = created["state"]
	var replay: Dictionary = GtReplay.make(players, board_data, settings, seed_value)
	var bot: GtBot = GtBot.new(master.next_u32())
	var game: Dictionary = {
		"players": players, "totals": _initial_totals(state), "turn_number": 1, "rank": 0,
		"played_other": 0, "won_events": 0, "event_counts": stats["events"],
	}
	var active: Array = players.duplicate()
	var step: int = 0
	var problem: String = ""

	while state["phase"] != "finished":
		step += 1
		if step > ACTION_CAP:
			problem = "the game did not finish within %d actions" % ACTION_CAP
			break
		var changed: bool = false
		if wobbly and master.range_int(0, 25) == 0:
			active = _random_active(master, players)
			changed = true
		if _needs_settle(state, active) or (wobbly and changed):
			var settled: Dictionary = rules.settle(state, active)
			if not CoreResult.is_ok(settled):
				problem = "settle failed: %s" % str(settled)
				break
			GtReplay.add_settle(replay, active)
			state = settled["state"]
			problem = _check_step(game, state, settled["events"])
			if problem == "":
				problem = _check_settled(state, active)
			if problem != "":
				break
			continue

		if master.range_int(0, 14) == 0:
			var junk: Dictionary = bot.junk(state)
			var before_hash: int = state.hash()
			var refused: Dictionary = GtReplay.apply_and_record(rules, replay, state, junk["player_id"], junk["action"], active if wobbly else [])
			if CoreResult.is_ok(refused):
				problem = "an illegal action was accepted: %s" % str(junk)
			elif CoreResult.error_code(refused) == "" or str(refused["error"]["message"]).is_empty():
				problem = "a refusal without a code and a message: %s" % str(refused)
			elif state.hash() != before_hash:
				problem = "a refused action changed the state it was given"
			if problem != "":
				break
			continue

		var picked: Dictionary = bot.pick(state, active)
		if picked.is_empty():
			problem = "nobody present could act (phase %s, pending %s)" % [state["phase"], str(state.get("turn", {}).get("pending"))]
			break
		var before_hash: int = state.hash()
		var result: Dictionary = GtReplay.apply_and_record(rules, replay, state, picked["player_id"], picked["action"], active if wobbly else [])
		if not CoreResult.is_ok(result):
			problem = "a legal action was refused: %s by %s -> %s" % [str(picked["action"]), picked["player_id"], str(result)]
			break
		if state.hash() != before_hash:
			problem = "apply changed the state it was given"
			break
		var next: Dictionary = result["state"]
		problem = _check_step(game, next, result["events"])
		if problem != "":
			break
		if step % VIEW_EVERY == 0:
			problem = _check_view(next, players[step % players.size()])
			if problem != "":
				break
		if step % VALIDATE_EVERY == 0:
			var full: Dictionary = rules.validate_state(next)
			if not CoreResult.is_ok(full):
				problem = "validate_state: %s" % str(full)
				break
		if step % ROUND_TRIP_EVERY == 0:
			var through_json: Dictionary = Envelope.normalize(JSON.parse_string(JSON.stringify(next)))
			if through_json != next:
				problem = "the state changed when written as JSON and read back"
				break
			next = through_json
		state = next

	if problem == "":
		var final_check: Dictionary = rules.validate_state(state)
		if not CoreResult.is_ok(final_check):
			problem = "final state: %s" % str(final_check)
		elif state["phase"] != "finished" or state["winner"] == "":
			problem = "the game ended without a winner"
		else:
			problem = _check_view(state, players[0])
	if problem == "" and index % 3 == 0:
		var replayed: Dictionary = GtReplay.run(replay)
		if not CoreResult.is_ok(replayed) or JSON.stringify(replayed["state"]) != JSON.stringify(state):
			problem = "the recorded replay did not reproduce the game: %s" % (str(replayed) if not CoreResult.is_ok(replayed) else "different state")
	stats["actions"] += step
	stats["max_actions"] = maxi(stats["max_actions"], step)
	stats["wobbly"] += 1 if wobbly else 0
	(stats["counts"] as Dictionary)[player_count] = true
	if problem != "":
		return "game %d (seed %d, %d players, %s): %s\nREPLAY:\n%s" % [index, seed_value, player_count, str(settings), problem, GtReplay.to_text(replay)]
	return ""


func _games() -> int:
	var from_env: String = OS.get_environment("GT_FUZZ_GAMES")
	return from_env.to_int() if from_env.is_valid_int() and from_env.to_int() > 0 else DEFAULT_GAMES


func test_random_games_all_finish_and_stay_valid() -> void:
	var master: Prng = Prng.new(MASTER_SEED)
	var games: int = _games()
	var stats: Dictionary = {"actions": 0, "max_actions": 0, "wobbly": 0, "counts": {}, "events": {}}
	var failures: Array[String] = []
	var started: int = Time.get_ticks_msec()
	for index: int in games:
		var problem: String = _play_one(index, master, stats)
		if problem != "":
			failures.append(problem)
			if failures.size() >= 2:
				break
	for failure: String in failures:
		gut.p(failure)
	assert_eq(failures, [], "fuzz failures (paste a REPLAY into GtReplay.from_text to reproduce)")
	gut.p("fuzz: %d games, %d actions (longest %d), %d with players coming and going, %.1f s" % [games, stats["actions"], stats["max_actions"], stats["wobbly"], (Time.get_ticks_msec() - started) / 1000.0])
	gut.p("events: %s" % str(stats["events"]))
	if games >= DEFAULT_GAMES:
		for type: String in ["rolled", "produced", "built", "bank_traded", "offer_made", "trade_done", "card_bought", "turn_changed", "won"]:
			assert_gt(int(stats["events"].get(type, 0)), 0, "the bots exercised %s" % type)
