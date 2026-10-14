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
const UNKNOWN_GAME: String = "UNKNOWN_GAME"  # the host plays a game this app does not have (client-side)
const UNSUPPORTED_SAVE: String = "UNSUPPORTED_SAVE"
const ROOM_FULL: String = "ROOM_FULL"
const GAME_IN_PROGRESS: String = "GAME_IN_PROGRESS"
const NAME_INVALID: String = "NAME_INVALID"
const NAME_TAKEN: String = "NAME_TAKEN"
const BAD_TOKEN: String = "BAD_TOKEN"
const HANDSHAKE_TIMEOUT: String = "HANDSHAKE_TIMEOUT"
const TOO_MANY_PENDING: String = "TOO_MANY_PENDING"
const PING_TIMEOUT: String = "PING_TIMEOUT"
const KICKED: String = "KICKED"
const REPLACED: String = "REPLACED"
const CLAIM_DENIED: String = "CLAIM_DENIED"  # the host declined to let a returning player back in
const LEFT: String = "LEFT"  # the player asked to leave

# Lobby
const NOT_HOST: String = "NOT_HOST"
const NOT_IN_LOBBY: String = "NOT_IN_LOBBY"
const NOT_ALL_READY: String = "NOT_ALL_READY"
const NOT_ENOUGH_PLAYERS: String = "NOT_ENOUGH_PLAYERS"
const WRONG_PHASE: String = "WRONG_PHASE"
const UNKNOWN_ACTION: String = "UNKNOWN_ACTION"
const UNKNOWN_PLAYER: String = "UNKNOWN_PLAYER"
const ALREADY_JOINED: String = "ALREADY_JOINED"
const HOST_CANNOT_LEAVE: String = "HOST_CANNOT_LEAVE"
const PLAYER_LEFT: String = "PLAYER_LEFT"
const BAD_ACTION: String = "BAD_ACTION"
const GAME_PAUSED: String = "GAME_PAUSED"  # the host is waiting for a player who is away
const NOTHING_TO_WAIT_FOR: String = "NOTHING_TO_WAIT_FOR"
const TOO_FEW_PLAYERS: String = "TOO_FEW_PLAYERS"  # the game cannot run with only the players present

# Client-side only (never sent on the wire)
const CONNECT_FAILED: String = "CONNECT_FAILED"
const HOST_LOST: String = "HOST_LOST"
