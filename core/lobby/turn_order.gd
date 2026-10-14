class_name TurnOrder
extends RefCounted
## Pure helpers for rules code (rule 2): who plays next when some players are absent.
## `order` is the fixed seating order (player ids). `active_players` is what the host
## passes to the rules (LobbyLogic.active_players): the players present and still in the
## game. Absent players keep their seat and their place in the order; they are skipped
## while away and get their turn again when they return.


## The first player at or after `from_index` (wrapping) who is active, or "" if none is.
static func first_active(order: Array[String], active_players: Array[String], from_index: int = 0) -> String:
	if order.is_empty():
		return ""
	for step: int in order.size():
		var candidate: String = order[(from_index + step) % order.size()]
		if active_players.has(candidate):
			return candidate
	return ""


## The next active player after `current` in seat order, wrapping around. If `current`
## is not in the order, starts from the first seat. Returns `current` itself if nobody
## else is active, and "" if nobody is.
static func next_active(order: Array[String], current: String, active_players: Array[String]) -> String:
	if order.is_empty():
		return ""
	var index: int = order.find(current)
	return first_active(order, active_players, index + 1 if index >= 0 else 0)


## Active players in seat order, for rules that need the whole list.
static func in_order(order: Array[String], active_players: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for player_id: String in order:
		if active_players.has(player_id):
			out.append(player_id)
	return out
