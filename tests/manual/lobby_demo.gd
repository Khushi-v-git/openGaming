extends Control
## Developer launcher for the manual network tests (docs/manual-network-test.md).
## Opens the real lobby screen on the real direct-WebSocket transport, with a dummy game.
## Not part of the shipped app. Run it with:
##   godot --path . res://tests/manual/lobby_demo.tscn -- --name=Asha
## Options after "--": --name=<player name>  --port=<listen port, default 24680>
##   --transport=auto   use the app's relay-or-direct choice (TransportFactory.network_config())
##   --relay_url=<url>  relay to use (implies --transport=auto), e.g. ws://127.0.0.1:8787

const GAME_ID: String = "manual_test"


func _ready() -> void:
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	if args.has("relay_url") or str(args.get("transport", "")) == "auto":
		# the demo must not overwrite the player's real saved relay choice with a local one
		AppSettings.path = "user://lobby_demo_settings_%s.cfg" % str(args.get("name", "demo")).validate_filename()
	var transport: Dictionary = TransportFactory.default_config()
	if str(args.get("transport", "")) == "auto" or args.has("relay_url"):
		transport = TransportFactory.network_config()
		if args.has("relay_url"):
			transport["relay_url"] = str(args["relay_url"])
	if args.has("port"):
		transport["port"] = int(args["port"])
	var lobby: LobbyScene = LobbyScene.new()
	lobby.setup({
		"game_id": GAME_ID,
		"game_title": "Network test lobby",
		"app_version": AppInfo.app_version(),
		"min_players": 2,
		"max_players": 4,
		"transport": transport,
		"player_name": str(args.get("name", "")),
	})
	lobby.game_started.connect(func(state: Dictionary) -> void: print("[manual] game_started revision=%d players=%d" % [state["revision"], state["slots"].size()]))
	add_child(lobby)
	DisplayServer.window_set_title("openGaming network test - %s" % str(args.get("name", "(no name)")))
	print("[manual] app_version=%s godot=%s os=%s" % [AppInfo.app_version(), Engine.get_version_info()["string"], OS.get_name()])


static func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for arg: String in raw:
		if arg.begins_with("--") and arg.contains("="):
			var parts: PackedStringArray = arg.substr(2).split("=", true, 1)
			out[parts[0]] = parts[1]
	return out
