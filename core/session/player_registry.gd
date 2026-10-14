class_name PlayerRegistry
extends RefCounted
## Host-only table of players: stable player_id, display name, secret rejoin token and
## the transport peer currently bound to the player (0 = not connected).
## Tokens live only here and in saves; they are never put in a broadcast (rule 9).
##
## Tokens rotate on every rejoin. The token that was just replaced stays valid until
## confirm_token() (the player's first message on the new connection), so a welcome
## lost on a flaky connection cannot lock a player out.

var _players: Dictionary = {}  # player_id -> {player_id, name, token, peer_id}
var _next_index: int = 1


## Creates a player with a fresh id and token.
func create(player_name: String) -> Dictionary:
	var player_id: String = "p%d" % _next_index
	_next_index += 1
	_players[player_id] = {
		"player_id": player_id,
		"name": player_name,
		"token": _new_token(),
		"prev_token": "",
		"peer_id": 0,
	}
	return _players[player_id].duplicate()


func has_player(player_id: String) -> bool:
	return _players.has(player_id)


func remove(player_id: String) -> void:
	_players.erase(player_id)


func bind_peer(player_id: String, peer_id: int) -> void:
	if _players.has(player_id):
		_players[player_id]["peer_id"] = peer_id


## Clears the peer binding for whichever player holds peer_id. Returns that player_id or "".
func unbind_peer(peer_id: int) -> String:
	var player_id: String = player_of_peer(peer_id)
	if not player_id.is_empty():
		_players[player_id]["peer_id"] = 0
	return player_id


func player_of_peer(peer_id: int) -> String:
	if peer_id == 0:
		return ""
	for player_id: String in _players:
		if _players[player_id]["peer_id"] == peer_id:
			return player_id
	return ""


func peer_of(player_id: String) -> int:
	return int(_players.get(player_id, {}).get("peer_id", 0))


func name_of(player_id: String) -> String:
	return str(_players.get(player_id, {}).get("name", ""))


func set_name(player_id: String, player_name: String) -> void:
	if _players.has(player_id):
		_players[player_id]["name"] = player_name


func is_connected_player(player_id: String) -> bool:
	return peer_of(player_id) != 0


func player_ids() -> Array[String]:
	var ids: Array[String] = []
	for player_id: String in _players:
		ids.append(player_id)
	return ids


func count() -> int:
	return _players.size()


func verify_token(player_id: String, token: String) -> bool:
	if not _players.has(player_id) or token.is_empty():
		return false
	var p: Dictionary = _players[player_id]
	return p["token"] == token or p["prev_token"] == token


func token_of(player_id: String) -> String:
	return str(_players.get(player_id, {}).get("token", ""))


## Replaces the token and returns the new one. `keep_valid` (the token the player
## just presented) stays usable until confirm_token(); "" invalidates the old one now.
func rotate_token(player_id: String, keep_valid: String = "") -> String:
	if not _players.has(player_id):
		return ""
	var token: String = _new_token()
	_players[player_id]["token"] = token
	_players[player_id]["prev_token"] = keep_valid
	return token


## The player proved they received the current token: retire the previous one.
func confirm_token(player_id: String) -> void:
	if _players.has(player_id):
		_players[player_id]["prev_token"] = ""


## Plain data including secret tokens. Peer bindings are not saved.
func to_dict() -> Dictionary:
	var players: Array = []
	for player_id: String in _players:
		var p: Dictionary = _players[player_id]
		players.append({"player_id": p["player_id"], "name": p["name"], "token": p["token"]})
	return {"next_index": _next_index, "players": players}


static func from_dict(data: Dictionary) -> PlayerRegistry:
	var registry: PlayerRegistry = PlayerRegistry.new()
	registry._next_index = int(data.get("next_index", 1))
	for entry: Variant in data.get("players", []):
		var p: Dictionary = entry
		registry._players[p["player_id"]] = {
			"player_id": p["player_id"],
			"name": p["name"],
			"token": p["token"],
			"prev_token": "",
			"peer_id": 0,
		}
	return registry


static func _new_token() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()
