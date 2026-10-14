class_name GameRules
extends RefCounted
## The contract every game's rules class fulfils (rule 2): pure logic, no nodes, no UI, no
## networking, no timers. The host, the hot-seat controller and the tests all talk to a game
## only through these methods, so core never needs to know which game it is running.
##
## Results are plain dicts: {ok: true, state, events} or {ok: false, error: {code, message}}.
## On error the state that was passed in is unchanged. `events` is an ordered list of plain
## dicts, each with a `type`, that tell a UI what happened so it never works rules out itself.
##
## A state is host-only. What players get is `view_for(state, player_id)`, a whitelist copy
## (rule 9), and a view carries enough for the three queries below (`is_finished`,
## `current_player`, `winner`), so a client with only a view can answer them.
##
## Subclasses override every method here except `settle`, which has a harmless default.

const NOT_IMPLEMENTED: String = "NOT_IMPLEMENTED"


## The `setup` data a new game normally starts with (for a board game, its standard board),
## so a menu can start any game without knowing what it needs.
func default_setup() -> Dictionary:
	return {}


## Starts a game. `player_ids` is the seat order. `setup` is game-specific data the game needs
## to begin (a board, a deck list, ...), `settings` the house rules, `seed_value` the seed for
## the game's Prng. Returns {ok, state, events} or a failure.
func new_game(_player_ids: Array, _setup: Dictionary, _settings: Dictionary, _seed_value: int) -> Dictionary:
	return _not_implemented("new_game")


## Applies one action by one player. `active_players` are the players present and still in the
## game, in seat order (empty means everybody); turn rotation must skip everyone else (see
## TurnOrder).
func apply(_state: Dictionary, _player_id: String, _action: Dictionary, _active_players: Array = []) -> Dictionary:
	return _not_implemented("apply")


## Hands the turn on if the current player is not among the active players (they dropped while
## it was their turn). The default does nothing, which is right for a game with no turns.
func settle(state: Dictionary, _active_players: Array = []) -> Dictionary:
	return CoreResult.success({"state": state.duplicate(true), "events": []})


## What one player may see of `state`. Never includes host-only data.
func view_for(_state: Dictionary, _player_id: String) -> Dictionary:
	return {}


## Checks every invariant of a state; the host uses it before trusting a loaded save.
## Returns {ok} or a failure.
func validate_state(_state: Dictionary) -> Dictionary:
	return _not_implemented("validate_state")


## True once the game is over. Works on a state or on a view.
func is_finished(_state_or_view: Dictionary) -> bool:
	return false


## The player whose action is awaited now ("" if none, for example when the game is over).
## Works on a state or on a view.
func current_player(_state_or_view: Dictionary) -> String:
	return ""


## The winning player's id once the game is over, "" otherwise. Works on a state or on a view.
func winner(_state_or_view: Dictionary) -> String:
	return ""


func _not_implemented(method: String) -> Dictionary:
	return CoreResult.failure(NOT_IMPLEMENTED, "%s does not implement %s()." % [get_script().resource_path, method])
