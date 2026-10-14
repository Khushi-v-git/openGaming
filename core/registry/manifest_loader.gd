class_name ManifestLoader
extends RefCounted
## Finds and validates game manifests on disk.

const MANIFEST_FILE: String = "manifest.json"


## Scans every subfolder of `games_root` (default res://games). A folder without a
## manifest.json is skipped (a game still in development). Returns
## {manifests: Array[Dictionary], errors: Array[{path, code, message}]}: one broken game
## never hides the others.
static func scan(games_root: String = "res://games") -> Dictionary:
	var manifests: Array[Dictionary] = []
	var errors: Array[Dictionary] = []
	var dir: DirAccess = DirAccess.open(games_root)
	if dir == null:
		return {"manifests": manifests, "errors": errors}
	var folders: PackedStringArray = dir.get_directories()
	folders.sort()
	for folder: String in folders:
		var game_dir: String = games_root.trim_suffix("/") + "/" + folder
		var manifest_path: String = game_dir + "/" + MANIFEST_FILE
		if not FileAccess.file_exists(manifest_path):
			continue
		var loaded: Dictionary = load_manifest(manifest_path, game_dir)
		if CoreResult.is_ok(loaded):
			manifests.append(loaded["manifest"])
		else:
			errors.append({"path": manifest_path, "code": CoreResult.error_code(loaded), "message": str(loaded["error"]["message"])})
	return {"manifests": manifests, "errors": errors}


## Reads and validates one manifest file. The id must equal the folder name.
static func load_manifest(manifest_path: String, game_dir: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return CoreResult.failure(GameManifest.INVALID_MANIFEST, "Cannot read %s." % manifest_path)
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return CoreResult.failure(GameManifest.INVALID_MANIFEST, "%s is not valid JSON (line %d: %s)." % [manifest_path, json.get_error_line(), json.get_error_message()])
	var data: Variant = Envelope.normalize(json.data)
	if typeof(data) != TYPE_DICTIONARY:
		return CoreResult.failure(GameManifest.INVALID_MANIFEST, "%s must contain a JSON object." % manifest_path)
	var checked: Dictionary = GameManifest.validate(data, game_dir)
	if not CoreResult.is_ok(checked):
		return checked
	if checked["manifest"]["id"] != game_dir.get_file():
		return CoreResult.failure(GameManifest.INVALID_MANIFEST, "The id '%s' must equal the folder name '%s'." % [checked["manifest"]["id"], game_dir.get_file()])
	return checked
