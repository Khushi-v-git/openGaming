class_name LocalGameController
extends GameController
## Runs a whole game on this computer for everyone sitting at it (hot-seat). It is the host
## and every client in one: it owns the state, applies each action as the player whose turn it
## is, and hands the screen the same batches a network client would receive.

var _rules: GameRules
var _player_ids: Array
var _setup: Dictionary
var _settings: Dictionary
var _state: Dictionary = {}
var _seq: int = 0
var _games_started: int = 0
var _seed_source: int


func _init(game_rules: GameRules, player_ids: Array, setup: Dictionary, settings: Dictionary, seed_value: int) -> void:
	_rules = game_rules
	_player_ids = player_ids.duplicate()
	_setup = setup
	_settings = settings
	_seed_source = seed_value


func rules() -> GameRules:
	return _rules


## Starts the first game. Returns the failure if the rules refuse the setup.
func start() -> Dictionary:
	return _begin(REASON_START)


func can_rematch() -> bool:
	return true


## A new game with the same players and settings (host-only in a network game). Every screen
## jumps to the fresh game rather than replaying anything.
func rematch() -> Dictionary:
	return _begin(REASON_REMATCH)


func submit_action(action: Dictionary) -> void:
	if _state.is_empty():
		action_rejected.emit({"code": ErrorCodes.WRONG_PHASE, "message": "The game has not started."})
		return
	var acting: String = _rules.current_player(_state)
	var result: Dictionary = _rules.apply(_state, acting, action, _player_ids)
	if not CoreResult.is_ok(result):
		action_rejected.emit(result["error"])
		return
	_state = result["state"]
	_emit(REASON_ACTION, result["events"])


func latest_view() -> Dictionary:
	return {} if _state.is_empty() else _rules.view_for(_state, _rules.current_player(_state))


## The full state, for saving. Hot-seat only: a real client never has this.
func state_for_save() -> Dictionary:
	return _state.duplicate(true)


func _begin(reason: String) -> Dictionary:
	var created: Dictionary = _rules.new_game(_player_ids, _setup, _settings, _seed_source + _games_started)
	if not CoreResult.is_ok(created):
		return created
	_games_started += 1
	_state = created["state"]
	_emit(reason, created["events"])
	return created


func _emit(reason: String, events: Array) -> void:
	_seq += 1
	batch_ready.emit({
		"seq": _seq,
		"reason": reason,
		"events": events,
		"view": _rules.view_for(_state, _rules.current_player(_state)),
	})
