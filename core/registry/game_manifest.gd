class_name GameManifest
extends RefCounted
## A game's manifest: plain data that tells the app everything it needs to list and
## start the game. It lives in the game's own folder as `manifest.json`, so adding a
## game never requires editing core/.
##
## {
##   "id": "climb_and_slither",            lowercase snake_case, equals the folder name
##   "display_name": "Climb and Slither",
##   "description": "...",                 optional
##   "icon": "res://games/<id>/assets/icon.svg",
##   "min_players": 2, "max_players": 4,
##   "min_active_players": 2,              optional: the fewest players present the game can
##                                         run with when someone drops; default = min_players
##   "online_only": false,                 optional: true hides "Play on this computer" (hot-seat)
##                                         for a game whose hidden information or trading needs
##                                         every player on their own screen; default false
##   "rules_class": "res://games/<id>/rules/<file>.gd",   extends RefCounted (rule 2)
##   "ui_scene": "res://games/<id>/ui/<file>.tscn"   optional while the game is in
##                                         development; without it the game is registered but
##                                         not playable, and the home screen leaves it out
##   "settings_scene": "res://games/<id>/ui/<file>.tscn"   optional: the game's own house-rules
##                                         panel, shown to the host before the game starts
## }
##
## Every path must be inside the game's own folder and must exist, so a manifest can
## never point at another game's files.

const MAX_PLAYERS_LIMIT: int = 16
const MAX_NAME_LENGTH: int = 40

const INVALID_MANIFEST: String = "INVALID_MANIFEST"
const DUPLICATE_GAME: String = "DUPLICATE_GAME"


## Validates parsed manifest data. `game_dir` is the game's folder, e.g. "res://games/ludo".
## Returns {ok, manifest} (a cleaned copy) or a failure with INVALID_MANIFEST.
static func validate(data: Dictionary, game_dir: String) -> Dictionary:
	var id: Variant = data.get("id")
	if typeof(id) != TYPE_STRING or not _is_valid_id(id):
		return _bad("'id' must be lowercase letters, digits and underscores, starting with a letter (2-32 characters).")
	var display_name: Variant = data.get("display_name")
	if typeof(display_name) != TYPE_STRING or (display_name as String).strip_edges().is_empty() or (display_name as String).length() > MAX_NAME_LENGTH:
		return _bad("'display_name' must be 1-%d characters." % MAX_NAME_LENGTH)
	var description: Variant = data.get("description", "")
	if typeof(description) != TYPE_STRING:
		return _bad("'description' must be text.")
	var min_players: Variant = data.get("min_players")
	var max_players: Variant = data.get("max_players")
	if typeof(min_players) != TYPE_INT or typeof(max_players) != TYPE_INT:
		return _bad("'min_players' and 'max_players' must be whole numbers.")
	if min_players < 1 or max_players < min_players or max_players > MAX_PLAYERS_LIMIT:
		return _bad("Player counts must satisfy 1 <= min_players <= max_players <= %d." % MAX_PLAYERS_LIMIT)

	var min_active: Variant = data.get("min_active_players", min_players)
	if typeof(min_active) != TYPE_INT or min_active < 1 or min_active > min_players:
		return _bad("'min_active_players' must be a whole number from 1 to min_players.")

	var online_only: Variant = data.get("online_only", false)
	if typeof(online_only) != TYPE_BOOL:
		return _bad("'online_only' must be true or false.")

	var icon: Dictionary = _check_path(data, "icon", game_dir, [])
	if not CoreResult.is_ok(icon):
		return icon
	var rules: Dictionary = _check_path(data, "rules_class", game_dir, ["gd"])
	if not CoreResult.is_ok(rules):
		return rules
	var ui: Dictionary = _optional_scene(data, "ui_scene", game_dir)
	if not CoreResult.is_ok(ui):
		return ui
	var settings_scene: Dictionary = _optional_scene(data, "settings_scene", game_dir)
	if not CoreResult.is_ok(settings_scene):
		return settings_scene
	var rules_check: Dictionary = _check_rules_script(rules["path"])
	if not CoreResult.is_ok(rules_check):
		return rules_check

	return CoreResult.success({"manifest": {
		"id": id,
		"display_name": (display_name as String).strip_edges(),
		"description": description,
		"icon": icon["path"],
		"min_players": min_players,
		"max_players": max_players,
		"min_active_players": min_active,
		"online_only": online_only,
		"rules_class": rules["path"],
		"ui_scene": ui["path"],  # "" = no UI yet
		"settings_scene": settings_scene["path"],  # "" = the game has no settings screen
	}})


## True if the game has a UI scene, i.e. it can actually be played.
static func has_ui(manifest: Dictionary) -> bool:
	return str(manifest.get("ui_scene", "")) != ""


## True if the game may be played hot-seat (everyone on this computer).
static func allows_hotseat(manifest: Dictionary) -> bool:
	return not bool(manifest.get("online_only", false))


static func supports_player_count(manifest: Dictionary, count: int) -> bool:
	return count >= int(manifest["min_players"]) and count <= int(manifest["max_players"])


static func _is_valid_id(id: String) -> bool:
	if id.length() < 2 or id.length() > 32:
		return false
	var first: int = id.unicode_at(0)
	if first < 97 or first > 122:
		return false
	for i: int in id.length():
		var c: int = id.unicode_at(i)
		var is_lower: bool = c >= 97 and c <= 122
		var is_digit: bool = c >= 48 and c <= 57
		if not (is_lower or is_digit or c == 95):
			return false
	return true


## An optional scene field: absent or "" gives path ""; anything else must be a real scene
## inside the game's folder.
static func _optional_scene(data: Dictionary, field: String, game_dir: String) -> Dictionary:
	if not data.has(field):
		return CoreResult.success({"path": ""})
	if typeof(data[field]) != TYPE_STRING:
		return _bad("'%s' must be a path or left out." % field)
	if data[field] == "":
		return CoreResult.success({"path": ""})
	return _check_path(data, field, game_dir, ["tscn", "scn"])


static func _check_path(data: Dictionary, field: String, game_dir: String, extensions: Array[String]) -> Dictionary:
	var path: Variant = data.get(field)
	if typeof(path) != TYPE_STRING or (path as String).is_empty():
		return _bad("'%s' is missing." % field)
	var text: String = path
	var prefix: String = game_dir.trim_suffix("/") + "/"
	if not text.begins_with(prefix) or text.contains(".."):
		return _bad("'%s' must point inside %s." % [field, prefix])
	if not extensions.is_empty() and not extensions.has(text.get_extension().to_lower()):
		return _bad("'%s' must be a .%s file." % [field, " or .".join(extensions)])
	if not ResourceLoader.exists(text) and not FileAccess.file_exists(text):
		return _bad("'%s' points at %s, which does not exist." % [field, text])
	return CoreResult.success({"path": text})


## The rules class must be a script that extends RefCounted (rule 2: pure logic).
static func _check_rules_script(path: String) -> Dictionary:
	var script: Resource = load(path)
	if not (script is GDScript):
		return _bad("'rules_class' is not a GDScript.")
	var gd: GDScript = script
	if not gd.can_instantiate():
		return _bad("'rules_class' cannot be instantiated (script error?).")
	if gd.get_instance_base_type() != "RefCounted":
		return _bad("'rules_class' must extend RefCounted (rules are pure logic).")
	return CoreResult.success()


static func _bad(message: String) -> Dictionary:
	return CoreResult.failure(INVALID_MANIFEST, message)
