class_name ClimbArt
extends RefCounted
## What art the board uses and where its anchor points are, read from
## assets/art_anchors.json. Pure data: loading checks the files exist, the sizes are right and
## every anchor lies inside its image, so a changed sprite fails a test, not the screen.
##
## Catalog shape (all vectors in sprite pixels):
##   snakes: [{name, path, size, tail, head, body_width}]            sorted by name
##   ladder: {width, top_size, segment_size, bottom_size, top_anchor, foot_anchor}
##   ladder_sets: [{name, top, segment, bottom}]                      paths; sorted by name
## Pawns live in core/assets (shared by every game).

const ASSET_DIR: String = "res://games/climb_and_slither/assets/"
const ANCHORS_PATH: String = "res://games/climb_and_slither/assets/art_anchors.json"
const PAWN_PATH: String = "res://core/assets/pawn-%s.svg"
const CROWN_PATH: String = "res://core/assets/icon-crown.svg"

const INVALID_ART: String = "INVALID_ART"


static func pawn_path(color: String) -> String:
	return PAWN_PATH % color


## Returns {ok, catalog} or INVALID_ART with a message naming the problem.
static func load_catalog(path: String = ANCHORS_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _bad("There is no anchors file at %s." % path)
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return _bad("%s is not valid JSON: %s" % [path, json.get_error_message()])
	var data: Variant = Envelope.normalize(json.data)
	if typeof(data) != TYPE_DICTIONARY:
		return _bad("%s must contain an object." % path)

	var snakes: Array[Dictionary] = []
	var raw_snakes: Variant = data.get("snakes")
	if typeof(raw_snakes) != TYPE_DICTIONARY or (raw_snakes as Dictionary).is_empty():
		return _bad("'snakes' must list at least one snake sprite.")
	var names: Array = (raw_snakes as Dictionary).keys()
	names.sort()
	for sprite_name: String in names:
		var entry: Variant = raw_snakes[sprite_name]
		var checked: Dictionary = _check_sprite(sprite_name, entry, ["tail", "head"])
		if not CoreResult.is_ok(checked):
			return checked
		if typeof(entry.get("body_width")) not in [TYPE_INT, TYPE_FLOAT] or float(entry["body_width"]) <= 0.0:
			return _bad("%s needs a positive body_width." % sprite_name)
		snakes.append({
			"name": sprite_name,
			"path": ASSET_DIR + sprite_name + ".svg",
			"size": checked["size"],
			"tail": _vec(entry["tail"]),
			"head": _vec(entry["head"]),
			"body_width": float(entry["body_width"]),
		})
		if _vec(entry["tail"]).distance_to(_vec(entry["head"])) < 10.0:
			return _bad("%s: head and tail are the same place." % sprite_name)

	var ladder_raw: Variant = data.get("ladder")
	if typeof(ladder_raw) != TYPE_DICTIONARY:
		return _bad("'ladder' geometry is missing.")
	var ladder: Dictionary = {}
	for key: String in ["top_size", "segment_size", "bottom_size", "top_anchor", "foot_anchor"]:
		if not _is_vec2(ladder_raw.get(key)):
			return _bad("ladder.%s must be [x, y]." % key)
		ladder[key] = _vec(ladder_raw[key])
	if typeof(ladder_raw.get("width")) not in [TYPE_INT, TYPE_FLOAT] or float(ladder_raw["width"]) <= 0.0:
		return _bad("ladder.width must be positive.")
	ladder["width"] = float(ladder_raw["width"])
	if not _inside(ladder["top_anchor"], ladder["top_size"]) or not _inside(ladder["foot_anchor"], ladder["bottom_size"]):
		return _bad("A ladder anchor lies outside its piece.")

	var sets: Array[Dictionary] = []
	var raw_sets: Variant = data.get("ladder_sets")
	if typeof(raw_sets) != TYPE_DICTIONARY or (raw_sets as Dictionary).is_empty():
		return _bad("'ladder_sets' must list at least one set of ladder pieces.")
	var set_names: Array = (raw_sets as Dictionary).keys()
	set_names.sort()
	for set_name: String in set_names:
		var pieces: Variant = raw_sets[set_name]
		if typeof(pieces) != TYPE_DICTIONARY:
			return _bad("ladder set %s is damaged." % set_name)
		var set_entry: Dictionary = {"name": set_name}
		for kind: String in ["top", "segment", "bottom"]:
			var piece_name: Variant = pieces.get(kind)
			if typeof(piece_name) != TYPE_STRING:
				return _bad("ladder set %s has no %s piece." % [set_name, kind])
			var piece_path: String = ASSET_DIR + piece_name + ".svg"
			if not FileAccess.file_exists(piece_path):
				return _bad("Missing ladder piece %s." % piece_path)
			set_entry[kind] = piece_path
		sets.append(set_entry)
	return CoreResult.success({"catalog": {"snakes": snakes, "ladder": ladder, "ladder_sets": sets}})


static func _check_sprite(sprite_name: String, entry: Variant, anchor_keys: Array) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		return _bad("%s is damaged." % sprite_name)
	if not FileAccess.file_exists(ASSET_DIR + sprite_name + ".svg"):
		return _bad("The sprite file %s%s.svg does not exist." % [ASSET_DIR, sprite_name])
	if not _is_vec2(entry.get("size")):
		return _bad("%s needs a size [w, h]." % sprite_name)
	var size: Vector2 = _vec(entry["size"])
	for key: String in anchor_keys:
		if not _is_vec2(entry.get(key)):
			return _bad("%s needs a %s anchor [x, y]." % [sprite_name, key])
		if not _inside(_vec(entry[key]), size):
			return _bad("%s: the %s anchor lies outside the image." % [sprite_name, key])
	return CoreResult.success({"size": size})


static func _is_vec2(value: Variant) -> bool:
	return typeof(value) == TYPE_ARRAY and (value as Array).size() == 2 and typeof(value[0]) in [TYPE_INT, TYPE_FLOAT] and typeof(value[1]) in [TYPE_INT, TYPE_FLOAT]


static func _vec(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


static func _inside(point: Vector2, size: Vector2) -> bool:
	return point.x >= 0.0 and point.y >= 0.0 and point.x <= size.x and point.y <= size.y


static func _bad(message: String) -> Dictionary:
	return CoreResult.failure(INVALID_ART, message)
