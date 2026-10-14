class_name ClimbAnimationPlan
extends RefCounted
## Turns one game event into the list of small steps that show it. Pure data in, pure data out
## (no nodes, no tweens), so it is tested without a window; ClimbBoardView and the game screen
## carry the steps out. Durations are in seconds at 1x speed.
##
## Steps:
##   {op: "dice", player_id, dice, total}      the dice tumble and settle on `dice`
##   {op: "hop", player_id, to}                the pawn hops to one square
##   {op: "shake", player_id}                  the roll was too big to move (exact finish)
##   {op: "slide", player_id, kind, from, to}  along a snake (down) or ladder (up)
##   {op: "banner", text}                      a short message over the board
##   {op: "turn", player_id}                   the turn marker moves
##   {op: "win", player_id}                    the winner celebrates
## Every step carries a "duration".

const HOP: float = 0.16
const DICE: float = 0.7
const SHAKE: float = 0.3
const SLIDE_LADDER: float = 0.9
const SLIDE_SNAKE: float = 0.75
const BANNER: float = 0.7
const TURN: float = 0.15
const WIN: float = 1.0

## Speeds the player can pick: label -> multiplier (0 = instant).
const SPEEDS: Dictionary = {"0.5x": 0.5, "1x": 1.0, "2x": 2.0, "Instant": 0.0}


## The steps for `event`. `names` maps player_id -> display name for banner texts.
static func steps_for(event: Dictionary, names: Dictionary = {}) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	var who: String = str(event.get("player_id", ""))
	var name: String = str(names.get(who, who))
	match str(event.get("type", "")):
		"rolled":
			steps.append({"op": "dice", "player_id": who, "dice": (event["dice"] as Array).duplicate(), "total": event["total"], "duration": DICE})
		"moved":
			for square: Variant in event["path"]:
				steps.append({"op": "hop", "player_id": who, "to": int(square), "duration": HOP})
		"overshoot":
			steps.append({"op": "shake", "player_id": who, "duration": SHAKE})
			steps.append({"op": "banner", "text": "%s needs exactly %d" % [name, int(event["needed"])], "duration": BANNER})
		"jumped":
			var up: bool = event["kind"] == "ladder"
			steps.append({"op": "slide", "player_id": who, "kind": event["kind"], "from": int(event["from"]), "to": int(event["to"]), "duration": SLIDE_LADDER if up else SLIDE_SNAKE})
		"extra_turn":
			steps.append({"op": "banner", "text": "%s rolls again" % name, "duration": BANNER})
		"turn_skipped":
			steps.append({"op": "banner", "text": "%s is away: turn skipped" % name, "duration": BANNER})
		"turn_changed":
			steps.append({"op": "turn", "player_id": who, "duration": TURN})
		"won":
			steps.append({"op": "win", "player_id": who, "duration": WIN})
	return steps


## Total time of a list of steps at a speed multiplier (0 = instant).
static func total_duration(steps: Array[Dictionary], speed: float) -> float:
	if speed <= 0.0:
		return 0.0
	var total: float = 0.0
	for step: Dictionary in steps:
		total += float(step["duration"]) / speed
	return total
