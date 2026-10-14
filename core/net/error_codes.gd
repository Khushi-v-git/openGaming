class_name ErrorCodes
extends RefCounted
## Stable error codes shared by envelope parsing, the handshake and the lobby.
## Codes are plain strings so they survive JSON and can be shown or logged as-is.

# Envelope / protocol
const MALFORMED: String = "MALFORMED"
const TOO_LARGE: String = "TOO_LARGE"
const RATE_LIMITED: String = "RATE_LIMITED"
const UNEXPECTED_MESSAGE: String = "UNEXPECTED_MESSAGE"

# Handshake
const PROTOCOL_MISMATCH: String = "PROTOCOL_MISMATCH"
const APP_VERSION_MISMATCH: String = "APP_VERSION_MISMATCH"
const WRONG_GAME: String = "WRONG_GAME"
const ROOM_FULL: String = "ROOM_FULL"
const GAME_IN_PROGRESS: String = "GAME_IN_PROGRESS"
const NAME_INVALID: String = "NAME_INVALID"
const NAME_TAKEN: String = "NAME_TAKEN"
const BAD_TOKEN: String = "BAD_TOKEN"
const HANDSHAKE_TIMEOUT: String = "HANDSHAKE_TIMEOUT"
const TOO_MANY_PENDING: String = "TOO_MANY_PENDING"
const PING_TIMEOUT: String = "PING_TIMEOUT"
const KICKED: String = "KICKED"

# Lobby
const NOT_HOST: String = "NOT_HOST"
const NOT_IN_LOBBY: String = "NOT_IN_LOBBY"
const NOT_ALL_READY: String = "NOT_ALL_READY"
const NOT_ENOUGH_PLAYERS: String = "NOT_ENOUGH_PLAYERS"
const WRONG_PHASE: String = "WRONG_PHASE"
const UNKNOWN_ACTION: String = "UNKNOWN_ACTION"
const UNKNOWN_PLAYER: String = "UNKNOWN_PLAYER"
