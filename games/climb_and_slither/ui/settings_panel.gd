class_name ClimbSettingsPanel
extends VBoxContainer
## The house-rules panel the host sees before a game starts. It shows ClimbSettings.option_states()
## and decides nothing: an option the rules say cannot be combined with another is greyed out with
## the rules' own tooltip. `settings()` is what to pass to new_game.

signal changed(settings: Dictionary)

var _exact: CheckButton
var _extra: CheckButton
var _two_dice: CheckButton
var _need_one: CheckButton
var _current: Dictionary = ClimbSettings.defaults()


func _ready() -> void:
	_exact = _option("Exact finish", "You must roll the exact number to land on the last square.")
	_extra = _option("Roll again after a 6", "Rolling a 6 (on either die) gives another turn.")
	_two_dice = _option("Two dice", "Roll two dice and move by the total.")
	_exact.toggled.connect(func(on: bool) -> void: _edit("exact_finish", on))
	_extra.toggled.connect(func(on: bool) -> void: _edit("extra_turn_on_six", on))
	_two_dice.toggled.connect(func(on: bool) -> void: _edit("dice_count", 2 if on else 1))
	_need_one = _option("Need a 1 to start", "A pawn stays off the board until its player rolls a 1.")
	_need_one.toggled.connect(func(on: bool) -> void: _edit("need_one_to_start", on))
	_refresh()


## The settings as chosen (always valid: the panel never lets a refused combination through).
func settings() -> Dictionary:
	return _current.duplicate()


## Sets the shown settings (invalid input falls back to the defaults).
func set_settings(values: Dictionary) -> void:
	var normalized: Dictionary = ClimbSettings.normalize(values)
	_current = normalized["settings"] if CoreResult.is_ok(normalized) else ClimbSettings.defaults()
	if _exact != null:
		_refresh()


func _option(text: String, tip: String) -> CheckButton:
	var button: CheckButton = CheckButton.new()
	button.text = text
	button.tooltip_text = tip
	add_child(button)
	return button


func _edit(key: String, value: Variant) -> void:
	var next: Dictionary = _current.duplicate()
	next[key] = value
	var normalized: Dictionary = ClimbSettings.normalize(next)
	if CoreResult.is_ok(normalized):
		_current = normalized["settings"]
	_refresh()
	changed.emit(settings())


func _refresh() -> void:
	var states: Dictionary = ClimbSettings.option_states(_current)
	_exact.set_pressed_no_signal(bool(_current["exact_finish"]))
	_extra.set_pressed_no_signal(bool(_current["extra_turn_on_six"]))
	_two_dice.set_pressed_no_signal(int(_current["dice_count"]) == 2)
	_need_one.set_pressed_no_signal(bool(_current["need_one_to_start"]))
	_apply(_exact, states["exact_finish"], "You must roll the exact number to land on the last square.")
	_apply(_two_dice, states["two_dice"], "Roll two dice and move by the total.")


func _apply(button: CheckButton, state: Dictionary, normal_tip: String) -> void:
	button.disabled = not bool(state["enabled"])
	button.tooltip_text = normal_tip if bool(state["enabled"]) else str(state["tooltip"])
