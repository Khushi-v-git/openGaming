class_name AppSettings
extends RefCounted
## Per-user app settings in user://settings.cfg (a ConfigFile). Small and boring on purpose:
## one place to read and write what a player can change, with project defaults underneath.
##
## The relay URL has one committed default, the project setting `onlygaming/network/relay_url`
## in project.godot (see the README's release checklist). A player can override it here so other
## people can run their own relay.

const SECTION_NETWORK: String = "network"
const KEY_RELAY_URL: String = "relay_url"
const KEY_HOST_VIA: String = "host_via"
const PROJECT_RELAY_URL: String = "onlygaming/network/relay_url"

const HOST_VIA_RELAY: String = "relay"
const HOST_VIA_DIRECT: String = "direct"

## Where the file lives. Tests point this at a throwaway path.
static var path: String = "user://settings.cfg"


static func get_value(section: String, key: String, default_value: Variant = null) -> Variant:
	var file: ConfigFile = ConfigFile.new()
	if file.load(path) != OK:
		return default_value
	return file.get_value(section, key, default_value)


static func set_value(section: String, key: String, value: Variant) -> bool:
	var file: ConfigFile = ConfigFile.new()
	file.load(path)  # a missing file is fine: we create it
	file.set_value(section, key, value)
	return file.save(path) == OK


static func clear_value(section: String, key: String) -> void:
	var file: ConfigFile = ConfigFile.new()
	if file.load(path) != OK:
		return
	if file.has_section_key(section, key):
		file.erase_section_key(section, key)
		file.save(path)


## The relay to use: the player's own setting if there is one, otherwise the project default.
## "" means no relay is configured.
static func relay_url() -> String:
	var own: String = str(get_value(SECTION_NETWORK, KEY_RELAY_URL, "")).strip_edges()
	if not own.is_empty():
		return own
	return str(ProjectSettings.get_setting(PROJECT_RELAY_URL, "")).strip_edges()


static func set_relay_url(url: String) -> bool:
	return set_value(SECTION_NETWORK, KEY_RELAY_URL, url.strip_edges())


## How this player hosts: "relay" (a room code) or "direct" (an address).
static func host_via() -> String:
	var value: String = str(get_value(SECTION_NETWORK, KEY_HOST_VIA, HOST_VIA_RELAY))
	return value if value == HOST_VIA_DIRECT else HOST_VIA_RELAY


static func set_host_via(value: String) -> bool:
	return set_value(SECTION_NETWORK, KEY_HOST_VIA, HOST_VIA_DIRECT if value == HOST_VIA_DIRECT else HOST_VIA_RELAY)
