class_name LaunchOptions
extends RefCounted
## Command-line options after "--" for manual and scripted tests, e.g.
##   godot --path . -- --name=Asha --auto=host --via=relay --relay_url=ws://127.0.0.1:8787
##
##   --name=<player name>         the name used in the lobby
##   --relay_url=<url>            relay for this run only (settings are isolated, see isolate_settings)
##   --via=relay|direct           how this player hosts
##   --port=<n>                   direct listen port
##   --auto=host|join             open the host or join lobby and start it (the host still presses Start)
##   --game=<game id>             the game to host (default: the first playable game)
##   --join=<address or code>     with --auto=join: what to join
##   --share_file=<path>          as host: write the address / room code here once hosting is live
##   --join_from_file=<path>      as guest: wait for this file, read the code from it, then join
##   --auto_ready                 as guest: tick "I'm ready" in the lobby
##
## parse() returns {ok, options} or a failure naming the first bad argument; unknown arguments are
## reported too, so a typo never silently does nothing.

const KEYS_WITH_VALUE: Array[String] = ["name", "relay_url", "via", "port", "auto", "game", "join", "share_file", "join_from_file"]
const FLAGS: Array[String] = ["auto_ready"]
const BAD_OPTION: String = "BAD_OPTION"


static func parse(args: PackedStringArray) -> Dictionary:
	var options: Dictionary = {}
	for arg: String in args:
		if not arg.begins_with("--"):
			continue  # not ours (the engine and the user may pass others)
		var body: String = arg.substr(2)
		var key: String = body
		var value: String = ""
		var has_value: bool = false
		if body.contains("="):
			key = body.get_slice("=", 0)
			value = body.substr(key.length() + 1)
			has_value = true
		if FLAGS.has(key):
			options[key] = true
			continue
		if not KEYS_WITH_VALUE.has(key):
			return _bad("Unknown option --%s." % key)
		if not has_value or value.is_empty():
			return _bad("--%s needs a value, like --%s=..." % [key, key])
		options[key] = value
	if options.has("via") and not ["relay", "direct"].has(options["via"]):
		return _bad("--via must be relay or direct.")
	if options.has("auto") and not ["host", "join"].has(options["auto"]):
		return _bad("--auto must be host or join.")
	if options.has("port"):
		var port: String = options["port"]
		if not port.is_valid_int() or port.to_int() < 1 or port.to_int() > 65535:
			return _bad("--port must be a number from 1 to 65535.")
		options["port"] = port.to_int()
	if options.get("auto", "") == "join" and not (options.has("join") or options.has("join_from_file")):
		return _bad("--auto=join needs --join=<address or code> or --join_from_file=<path>.")
	return CoreResult.success({"options": options})


## A run that sets its own relay or name must not touch the player's real saved settings:
## settings go to a file named after the player instead.
static func isolate_settings(options: Dictionary) -> void:
	if options.has("relay_url") or options.has("name") or options.has("auto"):
		AppSettings.path = "user://settings_%s.cfg" % str(options.get("name", "run")).validate_filename().replace(" ", "_")


## Writes the launch choices into the (isolated) app settings.
static func apply_to_settings(options: Dictionary) -> void:
	if options.has("name"):
		AppSettings.set_player_name(options["name"])
	if options.has("relay_url"):
		AppSettings.set_relay_url(AppSettings.normalize_relay_url(options["relay_url"]))
	if options.has("via"):
		AppSettings.set_host_via(options["via"])


static func _bad(message: String) -> Dictionary:
	return CoreResult.failure(BAD_OPTION, message)
