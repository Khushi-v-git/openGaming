class_name ClimbSettings
extends RefCounted
## House rules for Climb and Slither. They are settings, not hardcoded rules, and they
## live in the game state so every player (and every saved game) plays by the same ones.
##
##   exact_finish        true: the last square must be reached with an exact roll, a roll
##                       that would overshoot it does not move the player.
##                       false: overshooting lands on the last square and wins.
##   extra_turn_on_six   true: after a roll that includes a 6 the same player rolls again
##                       (with two dice, either die showing 6 counts). There is no cap.
##   dice_count          1 or 2 dice, added together.
##   need_one_to_start   true: a player who is not on the board yet (square 0) only enters it
##                       with a 1 (with two dice, either die showing 1). Entering moves to
##                       square 1, not by the total. Any other roll does nothing.
##
## exact_finish needs dice_count 1. With two dice the smallest total is 2, so a player on the
## square just before the last could never roll the 1 they need: they could neither finish nor
## leave, and a game where everyone gets there never ends (the fuzz test found this). That
## combination is refused instead of silently allowed.

const MAX_DICE: int = 2
const DIE_SIDES: int = 6

## Tooltips for the greyed-out option (see option_states).
const EXACT_FINISH_NEEDS_ONE_DIE: String = "Exact finish needs a single die."
const TWO_DICE_NEEDS_NO_EXACT_FINISH: String = "Two dice can't be used with exact finish."


static func defaults() -> Dictionary:
	return {"exact_finish": false, "extra_turn_on_six": false, "dice_count": 1, "need_one_to_start": false}


## Fills in defaults for anything missing and checks the rest. Returns {ok, settings} or
## INVALID_SETTINGS. Unknown keys are refused so a typo cannot silently do nothing.
static func normalize(input: Dictionary) -> Dictionary:
	var given: Dictionary = Envelope.normalize(input)
	var settings: Dictionary = defaults()
	for key: Variant in given:
		if not settings.has(key):
			return _bad("Unknown setting '%s'." % str(key))
	for key: String in settings:
		if not given.has(key):
			continue
		var value: Variant = given[key]
		if typeof(value) != typeof(settings[key]):
			return _bad("Setting '%s' has the wrong type." % key)
		settings[key] = value
	var dice: int = settings["dice_count"]
	if dice < 1 or dice > MAX_DICE:
		return _bad("'dice_count' must be 1 or %d." % MAX_DICE)
	if settings["exact_finish"] and dice > 1:
		return _bad("Exact finish needs a single die: with two dice a player on the square before the last could never finish.")
	return CoreResult.success({"settings": settings})


## Every combination of the rules that change how a roll moves a player, as {dice_count,
## exact_finish}, listing only the ones normalize() accepts: one die with exact finish, one die
## without it, two dice without it. The board validator checks a board is winnable under each,
## so it follows whatever the settings allow.
static func allowed_combinations() -> Array[Dictionary]:
	var combos: Array[Dictionary] = []
	for exact: bool in [true, false]:
		for dice: int in range(1, MAX_DICE + 1):
			if CoreResult.is_ok(normalize({"exact_finish": exact, "dice_count": dice})):
				combos.append({"dice_count": dice, "exact_finish": exact})
	return combos


## What a settings screen should offer given the current choices, so the UI greys things out
## without knowing any rule (rule 12). "Exact finish" and "two dice" exclude each other: while one
## is chosen the other is disabled, with a short tooltip. An option that is already chosen stays
## enabled, so it can always be switched off again.
## Returns {exact_finish: {enabled, tooltip}, two_dice: {enabled, tooltip}}, where `exact_finish`
## is the on/off toggle and `two_dice` is the "2 dice" choice (1 die is always available).
static func option_states(current: Dictionary) -> Dictionary:
	var exact_raw: Variant = current.get("exact_finish", false)
	var dice_raw: Variant = current.get("dice_count", 1)
	var exact_on: bool = typeof(exact_raw) == TYPE_BOOL and exact_raw
	var two_dice: bool = typeof(dice_raw) == TYPE_INT and dice_raw == 2
	return {
		"exact_finish": {
			"enabled": not two_dice,
			"tooltip": EXACT_FINISH_NEEDS_ONE_DIE if two_dice else "",
		},
		"two_dice": {
			"enabled": not exact_on,
			"tooltip": TWO_DICE_NEEDS_NO_EXACT_FINISH if exact_on else "",
		},
	}


static func _bad(message: String) -> Dictionary:
	return CoreResult.failure(ClimbErrors.INVALID_SETTINGS, message)
