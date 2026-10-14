class_name ClimbErrors
extends RefCounted
## Error codes specific to Climb and Slither. Generic ones (UNKNOWN_ACTION, BAD_ACTION,
## UNKNOWN_PLAYER) come from core's ErrorCodes so every game reports them the same way.

# Board data
const INVALID_BOARD: String = "INVALID_BOARD"
const INVALID_SETTINGS: String = "INVALID_SETTINGS"
const BAD_PLAYERS: String = "BAD_PLAYERS"

# Playing
const NOT_YOUR_TURN: String = "NOT_YOUR_TURN"
const GAME_OVER: String = "GAME_OVER"
const PLAYER_INACTIVE: String = "PLAYER_INACTIVE"  # not in the active (present) players
const NO_ACTIVE_PLAYERS: String = "NO_ACTIVE_PLAYERS"
const INVALID_STATE: String = "INVALID_STATE"
