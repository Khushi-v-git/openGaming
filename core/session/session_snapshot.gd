class_name SessionSnapshot
extends RefCounted
## A saved session as plain data (rule 8): the lobby, every player's identity and
## secret rejoin token, and the game's own state (opaque to core).
##
## PRIVATE: a snapshot contains rejoin tokens, which let whoever holds the file act as
## those players. Keep saves in the user's own folder (user://), never post them, and
## share one only with people you would trust to host the game. (Tokens are rotated on
## each player's first rejoin after a resume, so a leaked save stops working once
## everyone has come back.)
##
## Shape:
##   {save_version, saved_by_app_version, game_id, saved_at,
##    lobby: {...LobbyLogic state...}, players: PlayerRegistry.to_dict(), game_state: {...}}
##
## `save_version` is the version of this file format and is independent of the app
## version, so upgrading the app does not orphan saves. A save loads if it has the same
## game_id and a save_version this code understands. There are no migrations yet: a save
## from a newer or older format is refused with UNSUPPORTED_SAVE. The game's own
## `game_state` should carry its own version number for the same reason.

const SAVE_VERSION: int = 1
const FILE_NOT_FOUND: String = "FILE_NOT_FOUND"
const FILE_ERROR: String = "FILE_ERROR"
const _PHASES: Array[String] = [LobbyLogic.PHASE_OPEN, LobbyLogic.PHASE_IN_GAME]


static func capture(app_version: String, game_id: String, lobby_state: Dictionary, registry: PlayerRegistry, game_state: Dictionary = {}) -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"saved_by_app_version": app_version,
		"game_id": game_id,
		"saved_at": int(Time.get_unix_time_from_system()),
		"lobby": lobby_state.duplicate(true),
		"players": registry.to_dict(),
		"game_state": game_state.duplicate(true),
	}


## The identity a saved player rejoins with ({player_id, rejoin_token}), or {} if the
## save has no such player. This is how a previous host comes back as a normal player
## after someone else resumes the game.
static func identity_of(snapshot: Dictionary, player_id: String) -> Dictionary:
	for entry: Dictionary in snapshot["players"]["players"]:
		if entry["player_id"] == player_id:
			return {"player_id": player_id, "rejoin_token": entry["token"]}
	return {}


static func to_text(snapshot: Dictionary) -> String:
	return JSON.stringify(snapshot, "  ")


## Parses saved text. Returns {ok, snapshot} or MALFORMED. Does not validate contents.
static func from_text(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return CoreResult.failure(ErrorCodes.MALFORMED, "The save file is not valid JSON.")
	var data: Variant = Envelope.normalize(json.data)
	if typeof(data) != TYPE_DICTIONARY:
		return CoreResult.failure(ErrorCodes.MALFORMED, "The save file has the wrong format.")
	return CoreResult.success({"snapshot": data})


## Writes via a temporary file and a rename so a crash cannot leave a half-written save.
static func save_file(path: String, snapshot: Dictionary) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temp_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return CoreResult.failure(FILE_ERROR, "Could not write %s (error %d)." % [path, FileAccess.get_open_error()])
	file.store_string(to_text(snapshot))
	file.close()
	var err: Error = DirAccess.rename_absolute(temp_path, path)
	if err != OK:
		return CoreResult.failure(FILE_ERROR, "Could not finish writing %s (%s)." % [path, error_string(err)])
	return CoreResult.success()


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return CoreResult.failure(FILE_NOT_FOUND, "No save file at %s." % path)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return CoreResult.failure(FILE_ERROR, "Could not read %s." % path)
	return from_text(file.get_as_text())


## Full check before loading: format version, structure, then game. The app version
## is deliberately not compared (see save_version).
static func validate(snapshot: Dictionary, game_id: String) -> Dictionary:
	var version: Variant = snapshot.get("save_version")
	if typeof(version) == TYPE_INT and version != SAVE_VERSION:
		if version > SAVE_VERSION:
			return CoreResult.failure(ErrorCodes.UNSUPPORTED_SAVE, "This save was made by a newer version of the app (save format %d, this app reads %d)." % [version, SAVE_VERSION])
		return CoreResult.failure(ErrorCodes.UNSUPPORTED_SAVE, "This save uses an old format (%d) and there is no converter yet." % version)
	var structure: Dictionary = validate_structure(snapshot)
	if not CoreResult.is_ok(structure):
		return structure
	if snapshot["game_id"] != game_id:
		return CoreResult.failure(ErrorCodes.WRONG_GAME, "This save is for '%s', not '%s'." % [snapshot["game_id"], game_id])
	return CoreResult.success()


## Shape and internal consistency only (no game/version comparison).
static func validate_structure(snapshot: Dictionary) -> Dictionary:
	if typeof(snapshot.get("save_version")) != TYPE_INT:
		return _bad("Missing 'save_version'.")
	if snapshot["save_version"] != SAVE_VERSION:
		return _bad("Unsupported save format version.")
	for field: String in ["saved_by_app_version", "game_id"]:
		if typeof(snapshot.get(field)) != TYPE_STRING:
			return _bad("Missing '%s'." % field)
	for field: String in ["lobby", "players", "game_state"]:
		if typeof(snapshot.get(field)) != TYPE_DICTIONARY:
			return _bad("Missing '%s'." % field)
	var players: Dictionary = snapshot["players"]
	if typeof(players.get("next_index")) != TYPE_INT or typeof(players.get("players")) != TYPE_ARRAY:
		return _bad("The player list is damaged.")
	var known: Dictionary = {}
	for entry: Variant in players["players"]:
		if typeof(entry) != TYPE_DICTIONARY:
			return _bad("The player list is damaged.")
		for field: String in ["player_id", "name", "token"]:
			if typeof(entry.get(field)) != TYPE_STRING or (entry[field] as String).is_empty():
				return _bad("A player is missing '%s'." % field)
		if known.has(entry["player_id"]):
			return _bad("Duplicate player id %s." % entry["player_id"])
		known[entry["player_id"]] = true
	return _validate_lobby(snapshot["lobby"], snapshot["game_id"], known)


static func _validate_lobby(lobby: Dictionary, game_id: String, known_players: Dictionary) -> Dictionary:
	if not _PHASES.has(lobby.get("phase")):
		return _bad("The lobby phase is invalid.")
	if lobby.get("game_id") != game_id:
		return _bad("The lobby belongs to a different game.")
	for field: String in ["min_players", "max_players", "revision"]:
		if typeof(lobby.get(field)) != TYPE_INT:
			return _bad("The lobby is missing '%s'." % field)
	if typeof(lobby.get("host_player_id")) != TYPE_STRING or typeof(lobby.get("slots")) != TYPE_ARRAY:
		return _bad("The lobby is damaged.")
	var slots: Array = lobby["slots"]
	if slots.size() > int(lobby["max_players"]):
		return _bad("The lobby has more players than allowed.")
	var seen: Dictionary = {}
	for slot: Variant in slots:
		if typeof(slot) != TYPE_DICTIONARY:
			return _bad("A lobby slot is damaged.")
		if typeof(slot.get("player_id")) != TYPE_STRING or typeof(slot.get("name")) != TYPE_STRING:
			return _bad("A lobby slot is damaged.")
		for flag: String in ["ready", "connected", "left"]:
			if typeof(slot.get(flag)) != TYPE_BOOL:
				return _bad("A lobby slot is damaged.")
		if not known_players.has(slot["player_id"]):
			return _bad("Slot %s has no matching player." % slot["player_id"])
		if seen.has(slot["player_id"]):
			return _bad("Duplicate lobby slot %s." % slot["player_id"])
		seen[slot["player_id"]] = true
	if not seen.has(lobby["host_player_id"]):
		return _bad("The host is not in the lobby.")
	return CoreResult.success()


static func _bad(message: String) -> Dictionary:
	return CoreResult.failure(ErrorCodes.MALFORMED, "Cannot load this save: %s" % message)
