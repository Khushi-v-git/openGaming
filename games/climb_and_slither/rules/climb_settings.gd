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
##
## exact_finish needs dice_count 1. With two dice the smallest total is 2, so a player on the
## square just before the last could never roll the 1 they need: they could neither finish nor
## leave, and a game where everyone gets there never ends (the fuzz test found this). That
## combination is refused instead of silently allowed.

const MAX_DICE: int = 2
const DIE_SIDES: int = 6


static func defaults() -> Dictionary:
	return {"exact_finish": false, "extra_turn_on_six": false, "dice_count": 1}


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


static func _bad(message: String) -> Dictionary:
	return CoreResult.failure(ClimbErrors.INVALID_SETTINGS, message)
