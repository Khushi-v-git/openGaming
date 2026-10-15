class_name PresenceOverlay
extends Control
## Shows who is missing from a networked game and what the host can do about it (rule 7), plus the
## state of the connection. It is driven only by a GameController (presence_changed, link_changed,
## lost) and sends the host's decisions back to it; it decides nothing itself (rule 12).
##
##   paused, you are the host   a card naming who is away: Keep waiting / Continue without waiting
##                              (disabled with a reason below the minimum) / Remove <name> for good
##   paused, you are a guest    a read-only card: the host is deciding
##   host continued, someone    a slim banner "Waiting for X is off: play continues" with Wait again
##   still away
##   link degraded              a slim banner (waiting for the host's connection / reconnecting)
##   session lost               a card "Disconnected: <why>" with a way back to the menu
## Hot-seat controllers are never paused, so for them this overlay never shows anything.

signal leave_requested
signal kept_waiting  # the host chose "Keep waiting" (nothing changes, the card stays)

var controller: GameController

## The blocking card (paused) and what is inside it.
var pause_layer: Control
var pause_title: Label
var pause_body: Label
var keep_button: Button
var continue_button: Button
var continue_note: Label
var remove_box: VBoxContainer
## The slim banners.
var banner_box: VBoxContainer
var continued_panel: PanelContainer
var continued_label: Label
var wait_again_button: Button
var link_label: Label
## The "disconnected" card.
var lost_layer: Control
var lost_title: Label
var lost_body: Label
var lost_button: Button

var _lost: Dictionary = {}
var _link: String = Transport.LINK_OK


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_banners()
	pause_layer = _build_pause_layer()
	lost_layer = _build_lost_layer()
	_refresh()


## Starts following `game_controller`.
func setup(game_controller: GameController) -> void:
	controller = game_controller
	controller.presence_changed.connect(func(_info: Dictionary) -> void: _refresh())
	controller.link_changed.connect(_on_link_changed)
	controller.lost.connect(_on_lost)
	_refresh()


## True while the blocking card is up.
func is_blocking() -> bool:
	return pause_layer.visible or lost_layer.visible


# --- building --------------------------------------------------------------------------------------------

func _build_banners() -> void:
	banner_box = VBoxContainer.new()
	banner_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_box.add_theme_constant_override("separation", Tokens.SPACE_S)
	banner_box.position.y = Tokens.SPACE_M
	add_child(banner_box)

	continued_panel = PanelContainer.new()
	continued_panel.add_theme_stylebox_override("panel", _banner_style(Tokens.SAFFRON.lerp(Tokens.PAPER_CREAM, 0.35)))
	var continued_row: HBoxContainer = HBoxContainer.new()
	continued_panel.add_child(continued_row)
	continued_label = Label.new()
	continued_row.add_child(continued_label)
	wait_again_button = Button.new()
	wait_again_button.text = "Wait again"
	wait_again_button.theme_type_variation = "CreamButton"
	wait_again_button.pressed.connect(func() -> void: controller.wait_again())
	continued_row.add_child(wait_again_button)
	banner_box.add_child(continued_panel)

	var link_panel: PanelContainer = PanelContainer.new()
	link_panel.add_theme_stylebox_override("panel", _banner_style(Tokens.INDIGO))
	link_label = Label.new()
	link_label.add_theme_color_override("font_color", Tokens.PAPER_CREAM)
	link_panel.add_child(link_label)
	link_panel.set_meta("is_link_panel", true)
	banner_box.add_child(link_panel)


func _build_pause_layer() -> Control:
	var layer: Control = _dim_layer()
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var card: PaperCard = PaperCard.new()
	card.back_color = Tokens.SAFFRON
	card.back_offset = Vector2(10, 12)
	center.add_child(card)
	var box: VBoxContainer = VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override("separation", Tokens.SPACE_S)
	card.add_child(box)
	pause_title = _title("Game paused")
	box.add_child(pause_title)
	pause_body = Label.new()
	pause_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pause_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(pause_body)
	keep_button = Button.new()
	keep_button.text = "Keep waiting"
	keep_button.theme_type_variation = "PrimaryButton"
	keep_button.pressed.connect(func() -> void: kept_waiting.emit())
	box.add_child(keep_button)
	continue_button = Button.new()
	continue_button.text = "Continue without waiting"
	continue_button.theme_type_variation = "CreamButton"
	continue_button.pressed.connect(func() -> void: controller.continue_without_waiting())
	box.add_child(continue_button)
	continue_note = Label.new()
	continue_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	continue_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	continue_note.add_theme_color_override("font_color", Tokens.TERRACOTTA)
	box.add_child(continue_note)
	remove_box = VBoxContainer.new()
	box.add_child(remove_box)
	add_child(layer)
	return layer


func _build_lost_layer() -> Control:
	var layer: Control = _dim_layer()
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var card: PaperCard = PaperCard.new()
	card.back_color = Tokens.ROSE
	card.back_offset = Vector2(10, 12)
	center.add_child(card)
	var box: VBoxContainer = VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override("separation", Tokens.SPACE_S)
	card.add_child(box)
	lost_title = _title("Disconnected")
	box.add_child(lost_title)
	lost_body = Label.new()
	lost_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lost_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lost_body)
	lost_button = Button.new()
	lost_button.text = "Back to menu"
	lost_button.theme_type_variation = "PrimaryButton"
	lost_button.pressed.connect(func() -> void: leave_requested.emit())
	box.add_child(lost_button)
	add_child(layer)
	return layer


func _dim_layer() -> Control:
	var layer: Control = Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.visible = false
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(Tokens.INK, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)  # stops clicks reaching the game underneath
	return layer


func _title(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_TITLE)
	label.add_theme_color_override("font_color", Tokens.INDIGO)
	return label


func _banner_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(Tokens.RADIUS)
	style.set_content_margin_all(Tokens.SPACE_S)
	style.shadow_color = Color(Tokens.INK, 0.3)
	style.shadow_size = 4
	style.shadow_offset = Vector2(2, 3)
	return style


# --- following the controller ---------------------------------------------------------------------------------

func _on_link_changed(state: String) -> void:
	_link = state
	_refresh()


func _on_lost(error: Dictionary) -> void:
	_lost = error
	_refresh()


func _refresh() -> void:
	var presence: Dictionary = controller.presence() if controller != null else {"paused": false, "away": [], "can_continue": true, "is_host": false, "min_active": 1}
	var away: Array = presence["away"]
	var is_host: bool = bool(presence["is_host"])
	var paused: bool = bool(presence["paused"])

	lost_layer.visible = not _lost.is_empty()
	if lost_layer.visible:
		lost_body.text = str(_lost.get("message", "The connection to the game was lost."))

	pause_layer.visible = paused and _lost.is_empty() and controller != null
	if pause_layer.visible:
		var names_text: String = _names(away)
		keep_button.visible = is_host
		continue_button.visible = is_host
		continue_note.visible = is_host and not bool(presence["can_continue"])
		remove_box.visible = is_host
		if is_host:
			pause_title.text = "Waiting for players"
			pause_body.text = "Waiting for %s to come back." % names_text if not away.is_empty() else "Waiting for players to come back."
			continue_button.disabled = not bool(presence["can_continue"])
			continue_note.text = "The game needs at least %d players." % int(presence.get("min_active", 1))
			_rebuild_remove_buttons(away)
		else:
			pause_title.text = "Game paused"
			pause_body.text = "The host is deciding what to do about %s." % names_text if not away.is_empty() else "The host is deciding what to do."

	# the host chose to continue while someone is still away
	continued_panel.visible = is_host and not paused and not away.is_empty() and _lost.is_empty()
	if continued_panel.visible:
		continued_label.text = "Waiting for %s is off: play continues." % _names(away)

	var link_panel: Control = link_label.get_parent()
	link_panel.visible = _link != Transport.LINK_OK and _lost.is_empty()
	match _link:
		Transport.LINK_HOST_AWAY:
			link_label.text = "Waiting for the host's connection..."
		Transport.LINK_RECONNECTING:
			link_label.text = "Reconnecting..."


func _rebuild_remove_buttons(away: Array) -> void:
	for child: Node in remove_box.get_children():
		remove_box.remove_child(child)
		child.queue_free()
	for entry: Dictionary in away:
		var button: Button = Button.new()
		button.text = "Remove %s for good" % str(entry["name"])
		button.theme_type_variation = "CreamButton"
		var id: String = str(entry["player_id"])
		button.set_meta("player_id", id)
		button.pressed.connect(func() -> void: controller.remove_player(id))
		remove_box.add_child(button)


func _names(away: Array) -> String:
	var names: Array[String] = []
	for entry: Dictionary in away:
		names.append(str(entry["name"]))
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1]
