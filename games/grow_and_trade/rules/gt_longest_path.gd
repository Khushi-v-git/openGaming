class_name GtLongestPath
extends RefCounted
## Longest Path and Largest Guard bonuses for Grow & Trade. Pure graph logic: it knows nothing about
## hex geometry. A corner id is any int or String; a path is the pair of corners it joins.

const PATH_MIN_LENGTH: int = 5
const GUARD_MIN_PLAYED: int = 3


## The longest trail (no path used twice, corners may repeat) in one player's paths. A trail cannot
## continue through a blocked corner (another player's building); it may start or end on one.
static func longest_path_length(edges: Array, blocked_corners: Array = []) -> int:
	var unique: Array = _unique_edges(edges)
	var incident: Dictionary = {}  # corner -> Array[int] of edge indexes
	for i: int in unique.size():
		for corner: Variant in unique[i]:
			if not incident.has(corner):
				incident[corner] = []
			incident[corner].append(i)
	var blocked: Dictionary = {}
	for corner: Variant in blocked_corners:
		blocked[corner] = true
	var used: Array[bool] = []
	used.resize(unique.size())
	used.fill(false)
	var best: int = 0
	for start: Variant in incident:
		best = maxi(best, _walk(start, 0, unique, incident, blocked, used))
	return best


## Who holds Longest Path after lengths change. `current_holder` is "" when nobody holds it.
## A holder keeps it on a tie and while no one strictly beats them; a holder that fell under the
## minimum (a rival cut their chain) loses it; with no holder, a tie at the top gives it to nobody.
static func holder_after(current_holder: String, lengths: Dictionary, min_length: int = PATH_MIN_LENGTH) -> String:
	var top: int = 0
	for player_id: Variant in lengths:
		top = maxi(top, int(lengths[player_id]))
	if top < min_length:
		return ""
	var leaders: Array[String] = []
	for player_id: Variant in lengths:
		if int(lengths[player_id]) == top:
			leaders.append(str(player_id))
	if leaders.has(current_holder):
		return current_holder
	return leaders[0] if leaders.size() == 1 else ""


## Largest Guard: same rule over each player's count of played Guard cards (never decreases).
static func largest_guard_holder_after(current_holder: String, played_counts: Dictionary, min_played: int = GUARD_MIN_PLAYED) -> String:
	return holder_after(current_holder, played_counts, min_played)


## Longest Path holder from each player's paths and the corners other players hold.
## `paths_by_player`: player_id -> Array of [corner_a, corner_b]; `buildings`: corner -> owner player_id.
static func holder_from_board(current_holder: String, paths_by_player: Dictionary, buildings: Dictionary, min_length: int = PATH_MIN_LENGTH) -> String:
	var lengths: Dictionary = {}
	for player_id: Variant in paths_by_player:
		var blocked: Array = []
		for corner: Variant in buildings:
			if str(buildings[corner]) != str(player_id):
				blocked.append(corner)
		lengths[player_id] = longest_path_length(paths_by_player[player_id], blocked)
	return holder_after(current_holder, lengths, min_length)


static func _walk(corner: Variant, length: int, edges: Array, incident: Dictionary, blocked: Dictionary, used: Array[bool]) -> int:
	var best: int = length
	for index: int in incident[corner]:
		if used[index]:
			continue
		var edge: Array = edges[index]
		var other: Variant = edge[1] if edge[0] == corner else edge[0]
		used[index] = true
		if blocked.has(other):
			best = maxi(best, length + 1)  # may end here, never pass through
		else:
			best = maxi(best, _walk(other, length + 1, edges, incident, blocked, used))
		used[index] = false
	return best


## Drops self-loops and repeated paths (a-b and b-a are the same path).
static func _unique_edges(edges: Array) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for edge: Variant in edges:
		var a: Variant = edge[0]
		var b: Variant = edge[1]
		if a == b or seen.has([a, b]) or seen.has([b, a]):
			continue
		seen[[a, b]] = true
		result.append([a, b])
	return result
