extends SceneTree
## Developer tool, not part of the game: saves screenshots of the pause card (host and guest views),
## the "Reconnecting..." banner and the "Disconnected" card, over a plain cream background with the
## leaf border. Needs a real renderer (not --headless):
##   godot --rendering-driver opengl3 --resolution 1280x720 -s games/climb_and_slither/tools/render_cards.gd -- <out_dir>


## A controller whose presence and link state the tool sets by hand.
class ScriptedController extends GameController:
	var info: Dictionary = {"paused": false, "away": [], "can_continue": true, "is_host": true, "min_active": 2}

	func presence() -> Dictionary:
		return info

	func continue_without_waiting() -> Dictionary:
		return CoreResult.success()


var _out: String = "."


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	await _run()
	quit()


func _frames(count: int = 4) -> void:
	for _i: int in count:
		await process_frame


func _shot(name: String) -> void:
	await _frames()
	var size: Vector2i = get_root().size
	get_root().get_texture().get_image().save_png("%s/%s-%dx%d.png" % [_out, name, size.x, size.y])


func _stage() -> Array:
	var holder: Control = Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.theme = AppTheme.build()
	var back: ColorRect = ColorRect.new()
	back.color = Tokens.PAPER_CREAM
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(back)
	holder.add_child(LeafBorder.new())
	var controller: ScriptedController = ScriptedController.new()
	var overlay: PresenceOverlay = PresenceOverlay.new()
	holder.add_child(overlay)
	get_root().add_child(holder)
	overlay.setup(controller)
	return [holder, overlay, controller]


func _run() -> void:
	await _frames()
	var away: Array = [{"player_id": "p2", "name": "Ben"}]
	var staged: Array = _stage()
	var controller: ScriptedController = staged[2]
	controller.info = {"paused": true, "away": away, "can_continue": true, "is_host": true, "min_active": 2}
	controller.presence_changed.emit(controller.info)
	await _shot("card-pause-host")
	controller.info = {"paused": true, "away": away, "can_continue": true, "is_host": false, "min_active": 2}
	controller.presence_changed.emit(controller.info)
	await _shot("card-pause-guest")
	controller.info = {"paused": false, "away": away, "can_continue": true, "is_host": true, "min_active": 2}
	controller.presence_changed.emit(controller.info)
	controller.link_changed.emit(Transport.LINK_RECONNECTING)
	await _shot("card-reconnecting")
	controller.link_changed.emit(Transport.LINK_OK)
	controller.lost.emit({"code": "HOST_LOST", "message": "Lost connection to the host."})
	await _shot("card-disconnected")
