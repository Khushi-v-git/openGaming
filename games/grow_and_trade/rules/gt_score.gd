class_name GtScore
extends RefCounted
## Points, bonuses and the win check. Pure functions; `refresh_bonuses` and `check_win` work on a
## state the caller already copied.

const VILLAGE_POINTS: int = 1
const TOWN_POINTS: int = 2
const BONUS_POINTS: int = 2
const POINT_CARD: String = "point"


## Points a player has. `with_point_cards` includes their unrevealed point cards (the owner's own
## view and the win check); views of other players leave them out.
static func points(state: Dictionary, player_id: String, with_point_cards: bool) -> int:
	var total: int = GtState.building_count(state, player_id, "village") * VILLAGE_POINTS
	total += GtState.building_count(state, player_id, "town") * TOWN_POINTS
	for bonus: Variant in state["bonuses"]:
		if state["bonuses"][bonus] == player_id:
			total += BONUS_POINTS
	if with_point_cards:
		var cards: Dictionary = state["cards"][player_id]
		for card: Variant in cards["held"] + cards["fresh"]:
			if card == POINT_CARD:
				total += 1
	return total


## Recomputes who holds Longest Path and Largest Guard. Appends `bonus_changed {bonus, from, to}`
## to `events` for each change and updates state["bonuses"].
static func refresh_bonuses(state: Dictionary, events: Array) -> void:
	var path_holder: String = GtLongestPath.holder_from_board(
		state["bonuses"]["longest_path"], GtState.paths_by_player(state), GtState.building_owners(state))
	_set_bonus(state, "longest_path", path_holder, events)
	var guard_holder: String = GtLongestPath.largest_guard_holder_after(
		state["bonuses"]["largest_guard"], state["guards_played"])
	_set_bonus(state, "largest_guard", guard_holder, events)


## True if the player has reached the target. Only ever asked about the turn owner (rules doc).
static func has_won(state: Dictionary, player_id: String) -> bool:
	return points(state, player_id, true) >= int(state["settings"]["target_points"])


## If the turn owner has reached the target, finishes the game: phase, winner, a `won` event. Nothing is
## left to do afterwards: the offer and any pending blocker move (a Guard card can win with one pending)
## are dropped.
static func finish_if_won(state: Dictionary, player_id: String, events: Array) -> void:
	if state["phase"] == GtState.PHASE_PLAYING and has_won(state, player_id):
		state["phase"] = GtState.PHASE_FINISHED
		state["winner"] = player_id
		if not (state["offer"] as Dictionary).is_empty():
			state["offer"] = {}
			events.append({"type": "offer_cancelled", "reason": "game_over"})
		state["turn"]["pending"] = GtState.PENDING_NONE
		state["turn"]["source"] = ""
		state["turn"]["owed"] = {}
		events.append({"type": "won", "player_id": player_id})


static func _set_bonus(state: Dictionary, bonus: String, holder: String, events: Array) -> void:
	var before: String = state["bonuses"][bonus]
	if before != holder:
		state["bonuses"][bonus] = holder
		events.append({"type": "bonus_changed", "bonus": bonus, "from": before, "to": holder})
