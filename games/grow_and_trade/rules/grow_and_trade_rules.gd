class_name GrowAndTradeRules
extends GameRules
## Grow & Trade: the rules, as pure logic (rule 2). This class only checks who is asking and routes
## each action to its module; the modules hold the rules:
##   GtFounding (the two founding rounds)      GtBuild (paths, villages, towns)
##   GtTurn (roll, 7, blocker, cards, end turn, settle)      GtTrade (bank and player trades)
## State, actions, events and views are specified in docs/grow-and-trade-design.md.

const GAME_ID: String = GtState.GAME_ID
const STATE_VERSION: int = GtState.STATE_VERSION

## action type -> the module that handles it
const _ROUTES: Dictionary = {
	"place_village": "founding", "place_path": "founding",
	"build_path": "build", "build_village": "build", "build_town": "build",
	"roll": "turn", "buy_card": "turn", "play_card": "turn", "move_blocker": "turn",
	"discard": "turn", "end_turn": "turn",
	"bank_trade": "trade", "offer_trade": "trade", "accept_trade": "trade", "decline_trade": "trade",
	"choose_trade_partner": "trade", "withdraw_offer": "trade",
}

const _REQUIRED_KEYS: Array[String] = [
	"state_version", "game_id", "phase", "settings", "config", "board", "layout", "blocker", "players",
	"hands", "supply", "buildings", "paths", "cards", "guards_played", "deck", "bonuses", "founding",
	"turn", "offer", "current_player", "turn_number", "winner", "rng",
]


func validate_settings(settings: Dictionary) -> Dictionary:
	var checked: Dictionary = GtSetup.normalize(settings)
	return checked if not CoreResult.is_ok(checked) else CoreResult.success()


func describe_settings(settings: Dictionary) -> Array:
	return GtSetup.describe(settings)


## The standard large board (clean, validated data from the data file).
func default_setup() -> Dictionary:
	var loaded: Dictionary = GtBoard.load_file()
	return loaded["board"] if CoreResult.is_ok(loaded) else {}


## `setup` is the clean board data (see default_setup). Fails with BAD_PLAYERS, INVALID_SETTINGS or INVALID_BOARD.
func new_game(player_ids: Array, setup: Dictionary, settings: Dictionary, seed_value: int) -> Dictionary:
	return GtSetup.new_game(player_ids, setup, settings, seed_value)


## Applies one action by one player and returns {ok, state, events} or a failure; the state passed
## in is never changed. `active_players` are the players present and in the game, in seat order
## (empty means everybody). Most actions belong to the turn owner; the modules say which do not
## (answering an offer, discarding after a 7).
func apply(state: Dictionary, player_id: String, action: Dictionary, active_players: Array = []) -> Dictionary:
	if typeof(action.get("type")) != TYPE_STRING:
		return CoreResult.failure(ErrorCodes.BAD_ACTION, "An action needs a text type.")
	var route: Variant = _ROUTES.get(action["type"])
	if route == null:
		return CoreResult.failure(ErrorCodes.UNKNOWN_ACTION, "Unknown action %s." % action["type"])
	var shape: Dictionary = _quick_check(state)
	if not CoreResult.is_ok(shape):
		return shape
	if GtState.is_finished(state):
		return CoreResult.failure(GtErrors.GAME_OVER, "The game is over.")
	if not GtState.seat_order(state).has(player_id):
		return CoreResult.failure(ErrorCodes.UNKNOWN_PLAYER, "%s is not playing in this game." % player_id)
	var active: Array[String] = _strings(active_players)
	if not active.is_empty() and not active.has(player_id):
		return CoreResult.failure(GtErrors.PLAYER_INACTIVE, "You are not in the game right now.")
	var board: GtBoard = GtBoard.new(state["board"])
	match route:
		"founding":
			return GtFounding.apply(state, board, player_id, action)
		"build":
			return GtBuild.apply(state, board, player_id, action)
		"turn":
			return GtTurn.apply(state, board, player_id, action, active)
		_:
			return GtTrade.apply(state, board, player_id, action)


## Hands the turn on when the current player (or a placer during founding) is not present, does
## the random discards absent players owe, and drops offers if the house rule says so. Nothing
## happens if the game is over or `active_players` is empty (= everybody).
func settle(state: Dictionary, active_players: Array = []) -> Dictionary:
	var shape: Dictionary = _quick_check(state)
	if not CoreResult.is_ok(shape):
		return shape
	var active: Array[String] = _strings(active_players)
	if GtState.is_finished(state) or active.is_empty():
		return CoreResult.success({"state": state.duplicate(true), "events": []})
	return GtTurn.settle(state, GtBoard.new(state["board"]), active)


func view_for(state: Dictionary, player_id: String) -> Dictionary:
	return GtView.view_for(state, player_id)


func validate_state(state: Dictionary) -> Dictionary:
	return GtValidate.validate_state(state)


## The GameRules queries, answered from a state or from a view.
func is_finished(state_or_view: Dictionary) -> bool:
	return state_or_view.get("phase", "") == GtState.PHASE_FINISHED


## The turn owner (the placer during founding); "" once the game is over.
func current_player(state_or_view: Dictionary) -> String:
	return "" if is_finished(state_or_view) else String(state_or_view.get("current_player", ""))


func winner(state_or_view: Dictionary) -> String:
	return String(state_or_view.get("winner", ""))


## A cheap sanity check on the fields apply() reads. Full checking is validate_state().
func _quick_check(state: Dictionary) -> Dictionary:
	for key: String in _REQUIRED_KEYS:
		if not state.has(key):
			return CoreResult.failure(GtErrors.INVALID_STATE, "The state has no %s." % key)
	if typeof(state["phase"]) != TYPE_STRING or typeof(state["current_player"]) != TYPE_STRING \
			or typeof(state["players"]) != TYPE_ARRAY or typeof(state["rng"]) != TYPE_DICTIONARY:
		return CoreResult.failure(GtErrors.INVALID_STATE, "The state is damaged.")
	return CoreResult.success()


func _strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value: Variant in values:
		out.append(str(value))
	return out
