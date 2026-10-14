extends SceneTree
## Developer tool, not part of the game: starts a four-player hot-seat game through the real
## main menu, plays some turns and saves screenshots of the home screen, the game, and the
## game-over overlay. Needs a real renderer (not --headless):
##   godot --rendering-driver opengl3 --resolution 1280x720 -s games/climb_and_slither/tools/render_game_screen.gd -- <out_dir> [turns]

var _out: String = "."


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var turns: int = int(args[1]) if args.size() > 1 else 14
	DirAccess.make_dir_recursive_absolute(_out)
	await _run(turns)
	quit()


func _frames(count: int = 3) -> void:
	for _i: int in count:
		await process_frame


func _shot(name: String) -> void:
	await _frames()
	var size: Vector2i = get_root().size
	get_root().get_texture().get_image().save_png("%s/%s-%dx%d.png" % [_out, name, size.x, size.y])


func _run(turns: int) -> void:
	var menu: MainMenu = load("res://main/main.tscn").instantiate()
	get_root().add_child(menu)
	await _frames()
	await _shot("menu")
	menu.choose_game("climb_and_slither")
	menu.set_player_count(4)
	menu._name_fields[0].text = "Asha"
	menu._name_fields[1].text = "Ben"
	menu._name_fields[2].text = "Chandra"
	menu._name_fields[3].text = "Dev"
	await _shot("setup")
	menu.start_hotseat()
	var screen: ClimbGameScreen = menu._game_node
	screen.set_speed_by_label("Instant")
	await _frames()
	for _i: int in turns:
		if not screen.roll_button.disabled:
			screen.roll_button.pressed.emit()
		await _frames(1)
	await _shot("game")
	var guard: int = 0
	while not screen.overlay.visible and guard < 4000:
		if not screen.roll_button.disabled:
			screen.roll_button.pressed.emit()
		await _frames(1)
		guard += 1
	await _shot("gameover")
