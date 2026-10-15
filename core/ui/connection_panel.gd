class_name ConnectionPanel
extends VBoxContainer
## How this player connects: "Room code (relay)" or "Direct address", and which relay. Friends
## can use any relay by pasting its address here; nothing is edited in code. Choices are saved in
## the app settings and come back next time. Used by the lobby's start screen.
##
## apply_to(config) puts the choices into a transport config for TransportFactory.
## The relay address stays visible whichever way you host: joining a room code needs it too.

signal host_via_changed(host_via: String)

var via_picker: OptionButton  # the real choice; the two pills below are its face
var url_edit: LineEdit
var test_button: Button
var result_label: Label

## Shown in the address box instead of the saved one (a launcher can pre-fill it).
var initial_url: String = ""

var _probe: RelayProbe = RelayProbe.new()
var _segments: Array[Button] = []
var _result_row: HBoxContainer
var _result_icon: ResultIcon


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var heading: Label = Label.new()
	heading.text = "Connection"
	PaperStyle.title(heading, 24)
	add_child(heading)

	var via_row: HBoxContainer = HBoxContainer.new()
	via_row.add_theme_constant_override("separation", 14)
	var host_with: Label = _caption("Host with")
	host_with.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	via_row.add_child(host_with)
	via_picker = OptionButton.new()
	via_picker.add_item("Room code (relay)", 0)
	via_picker.add_item("Direct address", 1)
	via_picker.select(1 if AppSettings.host_via() == AppSettings.HOST_VIA_DIRECT else 0)
	via_picker.item_selected.connect(_on_via_selected)
	via_picker.visible = false
	via_row.add_child(via_picker)
	var track: PanelContainer = PanelContainer.new()
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.add_theme_stylebox_override("panel", PaperStyle.segment_track())
	var pills: HBoxContainer = HBoxContainer.new()
	pills.add_theme_constant_override("separation", 4)
	track.add_child(pills)
	for i: int in via_picker.item_count:
		var pill: Button = Button.new()
		pill.text = via_picker.get_item_text(i)
		pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pill.pressed.connect(func() -> void: _choose(i))
		pills.add_child(pill)
		_segments.append(pill)
	via_row.add_child(track)
	add_child(via_row)
	_refresh_segments()

	add_child(_caption("Relay address"))
	var url_row: HBoxContainer = HBoxContainer.new()
	url_row.add_theme_constant_override("separation", 10)
	url_edit = LineEdit.new()
	url_edit.placeholder_text = "e.g. my-relay.example.workers.dev"
	url_edit.text = initial_url if not initial_url.is_empty() else AppSettings.relay_url()
	url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	url_edit.clip_contents = true
	PaperStyle.inset_field(url_edit)
	url_edit.text_submitted.connect(func(_text: String) -> void: save())
	url_edit.focus_exited.connect(save)
	url_row.add_child(url_edit)
	test_button = Button.new()
	test_button.text = "Test"
	PaperStyle.small_button(test_button, &"PrimaryButton")
	test_button.custom_minimum_size = Vector2(88.0, 44.0)
	test_button.pressed.connect(test_relay)
	url_row.add_child(test_button)
	add_child(url_row)

	_result_row = HBoxContainer.new()
	_result_row.add_theme_constant_override("separation", 10)
	_result_row.visible = false  # takes no room until it has something to say
	_result_icon = ResultIcon.new()
	_result_row.add_child(_result_icon)
	result_label = _caption("")
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_label.visible = false
	_result_row.add_child(result_label)
	add_child(_result_row)
	_probe.finished.connect(_on_probe_finished)


func _process(_delta: float) -> void:
	_probe.poll()
	var has_text: bool = not result_label.text.is_empty()
	result_label.visible = has_text
	_result_row.visible = has_text


func host_via() -> String:
	return AppSettings.HOST_VIA_DIRECT if via_picker != null and via_picker.selected == 1 else AppSettings.HOST_VIA_RELAY


func uses_relay() -> bool:
	return host_via() == AppSettings.HOST_VIA_RELAY


## The relay URL as the box holds it, normalized; "" if empty or not a usable address.
func relay_url() -> String:
	return AppSettings.normalize_relay_url(url_edit.text) if url_edit != null else ""


## Saves the choices to the app settings and shows the cleaned-up URL.
func save() -> void:
	AppSettings.set_host_via(host_via())
	var cleaned: String = relay_url()
	if cleaned.is_empty() and not url_edit.text.strip_edges().is_empty():
		_say("That does not look like a relay address.", ResultIcon.ERROR)
		return
	AppSettings.set_relay_url(cleaned)
	if not cleaned.is_empty():
		url_edit.text = cleaned


## Puts the choices into a transport config (host_via, relay_url). Returns false, and says why in
## the panel, if the relay is needed but its address is missing or unusable.
func apply_to(config: Dictionary) -> bool:
	save()
	config["host_via"] = host_via()
	config["relay_url"] = relay_url()
	if uses_relay() and config["relay_url"] == "":
		_say("Enter the relay address first, or choose Direct address.", ResultIcon.ERROR)
		return false
	return true


## Joining a room code needs the relay whatever "Host with" says, so only the address matters.
func apply_for_joining(config: Dictionary) -> void:
	save()
	config["relay_url"] = relay_url()


func test_relay() -> void:
	var cleaned: String = relay_url()
	if cleaned.is_empty():
		_say("Enter the relay address first.", ResultIcon.ERROR)
		return
	save()
	_say("Testing %s ..." % cleaned, ResultIcon.NONE)
	test_button.disabled = true
	_probe.start(cleaned)


func _on_probe_finished(ok: bool, message: String) -> void:
	_say(message, ResultIcon.OK if ok else ResultIcon.ERROR)
	test_button.disabled = false


func _on_via_selected(_index: int) -> void:
	AppSettings.set_host_via(host_via())
	_refresh_segments()
	host_via_changed.emit(host_via())


func _choose(index: int) -> void:
	via_picker.select(index)
	_on_via_selected(index)


func _refresh_segments() -> void:
	for i: int in _segments.size():
		PaperStyle.segment(_segments[i], via_picker.selected == i)


func _say(text: String, kind: int) -> void:
	result_label.text = text
	var color: Color = Tokens.FOREST_GREEN if kind == ResultIcon.OK else (Tokens.TERRACOTTA if kind == ResultIcon.ERROR else Tokens.INK)
	result_label.add_theme_color_override("font_color", color)
	if _result_icon != null:
		_result_icon.kind = kind
	if _result_row != null:
		_result_row.visible = not text.is_empty()
	result_label.visible = not text.is_empty()


func _caption(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	PaperStyle.caption(label)
	return label


## The little mark before the result line: a green paper leaf for success, a rose "!" chip for
## trouble, nothing while a test is running.
class ResultIcon:
	extends Control

	const NONE: int = 0
	const OK: int = 1
	const ERROR: int = 2

	var kind: int = NONE:
		set(value):
			kind = value
			visible = value != NONE
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(28.0, 28.0)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func _draw() -> void:
		if kind == OK:
			var leaf: PackedVector2Array = PackedVector2Array()
			for i: int in range(13):
				var t: float = float(i) / 12.0
				leaf.append(Vector2(2.0 + t * 24.0, 14.0 - sin(t * PI) * 10.0))
			for i: int in range(13):
				var t: float = float(i) / 12.0
				leaf.append(Vector2(26.0 - t * 24.0, 14.0 + sin(t * PI) * 10.0))
			draw_colored_polygon(leaf, Tokens.FOREST_GREEN)
		elif kind == ERROR:
			draw_circle(Vector2(14.0, 14.0), 13.0, Tokens.ROSE)
			var font: Font = get_theme_default_font()
			draw_string(font, Vector2(9.0, 21.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Tokens.PAPER_CREAM)
