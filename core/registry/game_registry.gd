class_name GameRegistry
extends RefCounted
## The set of games this copy of the app has. The home screen is built from all(); the
## lobby uses has() to reject a host whose game this app does not have. Core never
## names a game: games arrive as manifests.

var _manifests: Dictionary = {}  # id -> manifest Dictionary


## Registers a validated manifest (from GameManifest.validate). Duplicate ids are refused.
func register(manifest: Dictionary) -> Dictionary:
	var id: String = str(manifest.get("id", ""))
	if id.is_empty():
		return CoreResult.failure(GameManifest.INVALID_MANIFEST, "The manifest has no id.")
	if _manifests.has(id):
		return CoreResult.failure(GameManifest.DUPLICATE_GAME, "A game with id '%s' is already registered." % id)
	_manifests[id] = manifest.duplicate(true)
	return CoreResult.success()


## Scans a games folder and registers what it finds. Returns {registered: Array[String],
## errors: Array[{path, code, message}]}.
func load_from(games_root: String = "res://games") -> Dictionary:
	var scanned: Dictionary = ManifestLoader.scan(games_root)
	var registered: Array[String] = []
	var errors: Array = (scanned["errors"] as Array).duplicate()
	for manifest: Dictionary in scanned["manifests"]:
		var result: Dictionary = register(manifest)
		if CoreResult.is_ok(result):
			registered.append(manifest["id"])
		else:
			errors.append({"path": "%s/%s/%s" % [games_root, manifest["id"], ManifestLoader.MANIFEST_FILE], "code": CoreResult.error_code(result), "message": str(result["error"]["message"])})
	return {"registered": registered, "errors": errors}


func has(game_id: String) -> bool:
	return _manifests.has(game_id)


## A copy of the manifest, or {} if unknown.
func get_manifest(game_id: String) -> Dictionary:
	return _manifests.get(game_id, {}).duplicate(true)


func display_name(game_id: String) -> String:
	return str(_manifests.get(game_id, {}).get("display_name", game_id))


## All games, sorted by display name (then id), for building menus.
func all() -> Array[Dictionary]:
	var games: Array[Dictionary] = []
	for id: String in _manifests:
		games.append(_manifests[id].duplicate(true))
	games.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var an: String = (a["display_name"] as String).to_lower()
		var bn: String = (b["display_name"] as String).to_lower()
		return an < bn if an != bn else a["id"] < b["id"])
	return games


## The games the home screen should list: those with a UI scene, sorted like all().
func playable() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for manifest: Dictionary in all():
		if GameManifest.has_ui(manifest):
			out.append(manifest)
	return out


func has_ui(game_id: String) -> bool:
	return has(game_id) and GameManifest.has_ui(_manifests[game_id])


func ids() -> Array[String]:
	var out: Array[String] = []
	for manifest: Dictionary in all():
		out.append(manifest["id"])
	return out


func count() -> int:
	return _manifests.size()


func supports_player_count(game_id: String, count_of_players: int) -> bool:
	return has(game_id) and GameManifest.supports_player_count(_manifests[game_id], count_of_players)


## A new instance of the game's rules class (pure logic, rule 2), or null.
func create_rules(game_id: String) -> RefCounted:
	if not has(game_id):
		return null
	var script: GDScript = load(_manifests[game_id]["rules_class"])
	return script.new() as RefCounted


func load_ui_scene(game_id: String) -> PackedScene:
	if not has_ui(game_id):
		return null
	return load(_manifests[game_id]["ui_scene"]) as PackedScene


## The game's own settings panel, or null if it has none.
func load_settings_scene(game_id: String) -> PackedScene:
	if not has(game_id) or str(_manifests[game_id].get("settings_scene", "")) == "":
		return null
	return load(_manifests[game_id]["settings_scene"]) as PackedScene


## For LobbyClient.game_validator. The lambda holds this registry alive: a plain
## Callable to a RefCounted method would not, and would break once the registry went out
## of scope elsewhere.
func validator() -> Callable:
	return func(game_id: String) -> bool: return has(game_id)
