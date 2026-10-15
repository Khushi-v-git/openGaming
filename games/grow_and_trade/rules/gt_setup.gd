class_name GtSetup
extends RefCounted
## House rules and the start of a game: settings checking and `new_game`.

const MIN_PLAYERS: int = 3
const MAX_PLAYERS: int = 6

const TARGET_MIN: int = 8
const TARGET_MAX: int = 14
const HAND_LIMIT_MIN: int = 5
const HAND_LIMIT_MAX: int = 12
const BANK_RATES: Array[int] = [3, 4]


static func defaults() -> Dictionary:
	return {
		"target_points": 10,
		"hand_limit": 7,
		"bank_rate": 4,
		"friendly_blocker": false,
		"cancel_offers_on_absence": false,
	}


## Fills defaults and checks every value. Returns {ok, settings} or INVALID_SETTINGS.
static func normalize(settings: Dictionary) -> Dictionary:
	var out: Dictionary = defaults()
	for key: Variant in settings:
		if not out.has(key):
			return _bad_settings("Unknown setting '%s'." % str(key))
		if typeof(settings[key]) != typeof(out[key]):
			return _bad_settings("Setting '%s' has the wrong type." % str(key))
		out[key] = settings[key]
	if out["target_points"] < TARGET_MIN or out["target_points"] > TARGET_MAX:
		return _bad_settings("Target points must be %d to %d." % [TARGET_MIN, TARGET_MAX])
	if out["hand_limit"] < HAND_LIMIT_MIN or out["hand_limit"] > HAND_LIMIT_MAX:
		return _bad_settings("Hand limit must be %d to %d." % [HAND_LIMIT_MIN, HAND_LIMIT_MAX])
	if not BANK_RATES.has(out["bank_rate"]):
		return _bad_settings("Bank rate must be 3 or 4.")
	return CoreResult.success({"settings": out})


## The house rules in words, defaults filled in.
static func describe(settings: Dictionary) -> Array:
	var checked: Dictionary = normalize(settings)
	var chosen: Dictionary = checked["settings"] if CoreResult.is_ok(checked) else defaults()
	var lines: Array = ["First to %d points" % chosen["target_points"], "Hand limit %d" % chosen["hand_limit"]]
	if chosen["bank_rate"] == 3:
		lines.append("Bank trades 3 for 1")
	if chosen["friendly_blocker"]:
		lines.append("Blocker spares players with 2 points or fewer")
	if chosen["cancel_offers_on_absence"]:
		lines.append("Offers are cancelled when a player is away")
	return lines


## Starts a game. `player_ids` is the seat order, `board` the clean board data (GtBoard.validate
## output; GtBoard.load_file()["board"] is the default), `settings` any subset of the house rules.
## Draw order: board layout, then deck shuffle (see docs/grow-and-trade-design.md).
static func new_game(player_ids: Array, board: Dictionary, settings: Dictionary, seed_value: int) -> Dictionary:
	if player_ids.size() < MIN_PLAYERS or player_ids.size() > MAX_PLAYERS:
		return CoreResult.failure(GtErrors.BAD_PLAYERS, "Grow & Trade needs %d to %d players." % [MIN_PLAYERS, MAX_PLAYERS])
	var seen: Dictionary = {}
	var players: Array = []
	for i: int in player_ids.size():
		var id: Variant = player_ids[i]
		if typeof(id) != TYPE_STRING or (id as String).is_empty():
			return CoreResult.failure(GtErrors.BAD_PLAYERS, "Player ids must be non-empty text.")
		if seen.has(id):
			return CoreResult.failure(GtErrors.BAD_PLAYERS, "Player id '%s' appears twice." % id)
		seen[id] = true
		players.append({"player_id": id, "color": GtState.COLORS[i]})
	var checked_settings: Dictionary = normalize(settings)
	if not CoreResult.is_ok(checked_settings):
		return checked_settings
	var checked_board: Dictionary = GtBoard.validate(board)
	if not CoreResult.is_ok(checked_board):
		return checked_board
	var loaded: Dictionary = GtBank.load_config()
	if not CoreResult.is_ok(loaded):
		return loaded
	var config: Dictionary = loaded["config"]
	var supply: Dictionary = GtBank.supply_for(config, player_ids.size())
	if not CoreResult.is_ok(supply):
		return supply

	var prng: Prng = Prng.new(seed_value)
	var made: Dictionary = GtBoard.layout(checked_board["board"], prng)
	if not CoreResult.is_ok(made):
		return made
	var layout: Dictionary = made["layout"]
	var deck: Array = GtDeck.new_deck(config, prng)

	var hands: Dictionary = {}
	var cards: Dictionary = {}
	var guards: Dictionary = {}
	for id: String in _ids(player_ids):
		hands[id] = GtBank.empty_hand()
		cards[id] = {"held": [], "fresh": []}
		guards[id] = 0
	var order: Array = player_ids.duplicate()
	var reversed: Array = player_ids.duplicate()
	reversed.reverse()
	order.append_array(reversed)

	var state: Dictionary = {
		"state_version": GtState.STATE_VERSION,
		"game_id": GtState.GAME_ID,
		"phase": GtState.PHASE_FOUNDING,
		"settings": checked_settings["settings"],
		"config": config,
		"board": checked_board["board"],
		"layout": {"tiles": layout["tiles"], "harbors": layout["harbors"]},
		"blocker": layout["blocker"],
		"players": players,
		"hands": hands,
		"supply": supply["supply"],
		"buildings": {},
		"paths": {},
		"cards": cards,
		"guards_played": guards,
		"deck": deck,
		"bonuses": {"longest_path": "", "largest_guard": ""},
		"founding": {"order": order, "index": 0, "expect": "village", "last_village": ""},
		"turn": new_turn(),
		"offer": {},
		"current_player": player_ids[0],
		"turn_number": 1,
		"winner": "",
		"rng": {"seed": prng.seed_text(), "state": prng.state_text()},
	}
	return CoreResult.success({"state": state, "events": []})


## A fresh per-turn record.
static func new_turn() -> Dictionary:
	return {"rolled": false, "dice": [], "card_played": false, "free_paths": 0, "pending": "", "owed": {}, "source": ""}


static func _ids(player_ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in player_ids:
		out.append(str(id))
	return out


static func _bad_settings(message: String) -> Dictionary:
	return CoreResult.failure(GtErrors.INVALID_SETTINGS, message)
