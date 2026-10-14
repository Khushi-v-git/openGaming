class_name ClimbDiceView
extends Control
## One or two dice on cream paper bodies. Shows what it is told: `show_faces` sets the faces,
## `tumble` flicks through random faces for a moment and lands on the real ones. The real values
## come from the game's events; the random faces while tumbling are only decoration.
##
## The die bodies are code-drawn placeholders (the shared art only has the pips); the faces are
## core/assets/die-1..6.svg.

const FACE_PATH: String = "res://core/assets/die-%d.svg"
const BODY_FRACTION: float = 0.94  # the body's size relative to its slot

var _faces: Array[TextureRect] = []
var _values: Array[int] = []
var _slots: HBoxContainer
var _flicker: float = 0.0
var _tumbling: bool = false
var _target: Array[int] = []
var _time_left: float = 0.0
var _done: Callable = Callable()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()  # decoration only, never rules


func _init() -> void:
	custom_minimum_size = Vector2(150, 80)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_slots = HBoxContainer.new()
	_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots.add_theme_constant_override("separation", Tokens.SPACE_M)
	_slots.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slots)
	set_process(false)
	_rebuild(_values.size())


## The faces now showing (1 to 6 each); empty before the first roll.
func values() -> Array[int]:
	return _values.duplicate()


func is_tumbling() -> bool:
	return _tumbling


## Shows these faces at once (a snapshot, or the start of a game with `[]`).
func show_faces(dice: Array) -> void:
	_stop_tumble()
	_set_values(dice)


## Tumbles for `seconds`, then lands on `dice` and calls `done`. 0 seconds lands at once.
func tumble(dice: Array, seconds: float, done: Callable) -> void:
	_stop_tumble()
	if seconds <= 0.0 or not is_inside_tree():
		_set_values(dice)
		done.call()
		return
	_target = _ints(dice)
	_tumbling = true
	_time_left = seconds
	_done = done
	_flicker = 0.0
	set_process(true)


func _process(delta: float) -> void:
	if not _tumbling:
		set_process(false)
		return
	_time_left -= delta
	_flicker -= delta
	if _time_left <= 0.0:
		var done: Callable = _done
		_stop_tumble()
		_set_values(_target)
		done.call()
		return
	if _flicker <= 0.0:
		_flicker = 0.06
		var random_faces: Array[int] = []
		for _i: int in _target.size():
			random_faces.append(_rng.randi_range(1, 6))
		_set_values(random_faces)


func _stop_tumble() -> void:
	_tumbling = false
	_done = Callable()
	set_process(false)


func _set_values(dice: Array) -> void:
	_values = _ints(dice)
	if _slots == null:
		return
	if _faces.size() != _values.size():
		_rebuild(_values.size())
	for i: int in _values.size():
		_faces[i].texture = load(FACE_PATH % clampi(_values[i], 1, 6))


func _rebuild(count: int) -> void:
	for face: TextureRect in _faces:
		face.get_parent().queue_free()
	_faces.clear()
	for _i: int in count:
		var body: PanelContainer = PanelContainer.new()
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Tokens.PAPER_CREAM.lightened(0.35)
		style.set_corner_radius_all(Tokens.RADIUS + 4)
		style.shadow_color = Color(Tokens.INK, 0.25)
		style.shadow_size = 4
		style.shadow_offset = Vector2(3, 4)
		body.add_theme_stylebox_override("panel", style)
		body.custom_minimum_size = Vector2(68, 68)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var face: TextureRect = TextureRect.new()
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.custom_minimum_size = Vector2(60, 60)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(face)
		_slots.add_child(body)
		_faces.append(face)


static func _ints(dice: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in dice:
		result.append(int(value))
	return result
