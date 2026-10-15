class_name ConnectionPanel
extends VBoxContainer
## How this player connects: "Room code (relay)" or "Direct address", and which relay. Friends
## can use any relay by pasting its address here; nothing is edited in code. Choices are saved in
## the app settings and come back next time. Used by the lobby's start screen.
##
## apply_to(config) puts the choices into a transport config for TransportFactory.

signal host_via_changed(host_via: String)

var via_picker: OptionButton
var url_edit: LineEdit
var test_button: Button
var result_label: Label

## Shown in the address box instead of the saved one (a launcher can pre-fill it).
var initial_url: String = ""

var _probe: RelayProbe = RelayProbe.new()


func _ready() -> void:
	add_child(_caption("Connection"))
	var via_row: HBoxContainer = HBoxContainer.new()
	via_row.add_child(_caption("Host with"))
	via_picker = OptionButton.new()
	via_picker.add_item("Room code (relay)", 0)
	via_picker.add_item("Direct address", 1)
	via_picker.select(1 if AppSettings.host_via() == AppSettings.HOST_VIA_DIRECT else 0)
	via_picker.item_selected.connect(_on_via_selected)
	via_row.add_child(via_picker)
	add_child(via_row)

	var url_row: HBoxContainer = HBoxContainer.new()
	url_edit = LineEdit.new()
	url_edit.placeholder_text = "Relay address, e.g. my-relay.example.workers.dev"
	url_edit.text = initial_url if not initial_url.is_empty() else AppSettings.relay_url()
	url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	url_edit.text_submitted.connect(func(_text: String) -> void: save())
	url_edit.focus_exited.connect(save)
	url_row.add_child(url_edit)
	test_button = Button.new()
	test_button.text = "Test"
	test_button.pressed.connect(test_relay)
	url_row.add_child(test_button)
	add_child(url_row)

	result_label = _caption("")
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(result_label)
	_probe.finished.connect(_on_probe_finished)


func _process(_delta: float) -> void:
	_probe.poll()


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
		result_label.text = "That does not look like a relay address."
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
		result_label.text = "Enter the relay address first, or choose Direct address."
		return false
	return true


## Joining a room code needs the relay whatever "Host with" says, so only the address matters.
func apply_for_joining(config: Dictionary) -> void:
	save()
	config["relay_url"] = relay_url()


func test_relay() -> void:
	var cleaned: String = relay_url()
	if cleaned.is_empty():
		result_label.text = "Enter the relay address first."
		return
	save()
	result_label.add_theme_color_override("font_color", Tokens.INK)
	result_label.text = "Testing %s ..." % cleaned
	test_button.disabled = true
	_probe.start(cleaned)


func _on_probe_finished(ok: bool, message: String) -> void:
	result_label.text = message
	result_label.add_theme_color_override("font_color", Tokens.FOREST_GREEN if ok else Tokens.TERRACOTTA)
	test_button.disabled = false


func _on_via_selected(_index: int) -> void:
	AppSettings.set_host_via(host_via())
	host_via_changed.emit(host_via())


func _caption(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	return label
