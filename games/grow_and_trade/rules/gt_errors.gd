class_name GtErrors
extends RefCounted
## Error codes specific to Grow & Trade. Generic ones (UNKNOWN_ACTION, BAD_ACTION, UNKNOWN_PLAYER)
## come from core's ErrorCodes so every game reports them the same way.

# Setup and state
const INVALID_STATE: String = "INVALID_STATE"
const INVALID_SETTINGS: String = "INVALID_SETTINGS"
const BAD_PLAYERS: String = "BAD_PLAYERS"

# Who may act
const NOT_YOUR_TURN: String = "NOT_YOUR_TURN"
const GAME_OVER: String = "GAME_OVER"
const PLAYER_INACTIVE: String = "PLAYER_INACTIVE"  # not in the active (present) players
const NO_ACTIVE_PLAYERS: String = "NO_ACTIVE_PLAYERS"
const WRONG_PHASE: String = "WRONG_PHASE"  # this action is not allowed right now
const ALREADY_ROLLED: String = "ALREADY_ROLLED"
const NOT_ROLLED: String = "NOT_ROLLED"

# Building
const BAD_PLACEMENT: String = "BAD_PLACEMENT"
const NO_PIECES: String = "NO_PIECES"
const CANNOT_AFFORD: String = "CANNOT_AFFORD"

# Cards
const CARD_NOT_AVAILABLE: String = "CARD_NOT_AVAILABLE"
const CARD_ALREADY_PLAYED: String = "CARD_ALREADY_PLAYED"
const NO_SUCH_CARD: String = "NO_SUCH_CARD"

# Trading
const OFFER_INVALID: String = "OFFER_INVALID"
const NO_OFFER: String = "NO_OFFER"
const NOT_ADDRESSED: String = "NOT_ADDRESSED"
const ALREADY_ANSWERED: String = "ALREADY_ANSWERED"
const NOT_AN_ACCEPTER: String = "NOT_AN_ACCEPTER"

# After a 7
const MUST_DISCARD: String = "MUST_DISCARD"
const BAD_DISCARD: String = "BAD_DISCARD"
const BAD_BLOCKER_MOVE: String = "BAD_BLOCKER_MOVE"
const BAD_VICTIM: String = "BAD_VICTIM"
