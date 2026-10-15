class_name GtView
extends RefCounted
## What one player may see of a Grow & Trade state (rule 9). A whitelist copy: host-only data
## (the deck order, the random generator) and other players' hands and cards are never included,
## and anything added to the state later stays private until it is listed here.
##
## A view has the public keys below, plus:
##   you              the viewer's id
##   hand             the viewer's exact hand               (seated viewers only)
##   my_cards         {held, fresh}, the viewer's cards      (seated viewers only)
##   hand_counts      {pid: how many resource cards}
##   card_counts      {pid: how many fortune cards, held + fresh}
##   deck_remaining   how many fortune cards are left to buy
##   points           {pid: points}; others' point cards stay hidden until the game is over
##   revealed_cards   {pid: {held, fresh}}                   (only once the game is finished)
## A viewer who is not seated (a spectator) gets everything except `hand` and `my_cards`.
## The queries is_finished / current_player / winner can be answered from a view: it carries
## `phase`, `current_player` and `winner`.

## Everything in a state that every player may see.
const PUBLIC_KEYS: Array[String] = [
	"state_version", "game_id", "phase", "settings", "config", "board", "layout", "blocker",
	"players", "supply", "buildings", "paths", "guards_played", "bonuses", "founding", "turn",
	"offer", "current_player", "turn_number", "winner",
]
## Never in a view.
const HOST_ONLY_KEYS: Array[String] = ["deck", "rng"]
## In the state but shown to nobody else: each player's own copy is built by view_for.
const PRIVATE_KEYS: Array[String] = ["hands", "cards"]


static func view_for(state: Dictionary, player_id: String) -> Dictionary:
	var view: Dictionary = {}
	for key: String in PUBLIC_KEYS:
		if state.has(key):
			view[key] = _copy(state[key])
	view["you"] = player_id
	var ids: Array[String] = GtState.seat_order(state)
	var finished: bool = state.get("phase", "") == GtState.PHASE_FINISHED

	var hand_counts: Dictionary = {}
	var card_counts: Dictionary = {}
	var points: Dictionary = {}
	for id: String in ids:
		hand_counts[id] = GtBank.hand_count(state["hands"][id])
		var cards: Dictionary = state["cards"][id]
		card_counts[id] = (cards["held"] as Array).size() + (cards["fresh"] as Array).size()
		points[id] = GtScore.points(state, id, finished or id == player_id)
	view["hand_counts"] = hand_counts
	view["card_counts"] = card_counts
	view["points"] = points
	view["deck_remaining"] = (state["deck"] as Array).size()

	if ids.has(player_id):
		view["hand"] = _copy(state["hands"][player_id])
		view["my_cards"] = _copy(state["cards"][player_id])
	if finished:
		var revealed: Dictionary = {}
		for id: String in ids:
			revealed[id] = _copy(state["cards"][id])
		view["revealed_cards"] = revealed
	return view


static func _copy(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return value
