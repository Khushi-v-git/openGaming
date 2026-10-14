extends GutTest
## The manual-test launcher must at least build the real lobby screen.


func test_launcher_scene_builds_the_lobby_on_the_direct_transport() -> void:
	var node: Control = autofree(load("res://tests/manual/lobby_demo.tscn").instantiate())
	add_child(node)
	await get_tree().process_frame
	var lobby: LobbyScene = null
	for child: Node in node.get_children():
		if child is LobbyScene:
			lobby = child
	assert_not_null(lobby)
	assert_true(lobby.start_view.visible)
	assert_not_null(lobby.port_spin, "direct transport shows the port field")
	assert_eq(int(lobby.port_spin.value), DirectWsTransport.DEFAULT_PORT)


func test_argument_parsing() -> void:
	var parsed: Dictionary = load("res://tests/manual/lobby_demo.gd")._parse_args(PackedStringArray(["--name=Asha", "--port=25000", "--junk", "plain"]))
	assert_eq(parsed, {"name": "Asha", "port": "25000"})


func test_app_version_is_never_empty() -> void:
	assert_ne(AppInfo.app_version(), "")
