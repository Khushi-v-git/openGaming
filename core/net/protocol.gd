class_name Protocol
extends RefCounted
## Protocol constants. Bump PROTOCOL_VERSION on any incompatible message change.
## v2: game batches (game_batch) and resync requests, lobby game_settings, end_game.

const PROTOCOL_VERSION: int = 2
## Hard cap on one serialized message. Larger input is rejected before parsing.
const MAX_MESSAGE_BYTES: int = 65536

# Handshake
const T_HELLO: String = "hello"
const T_WELCOME: String = "welcome"
const T_REJECT: String = "reject"
const T_PENDING: String = "pending"  # host > client: not decided yet, the host is being asked
# Liveness
const T_PING: String = "ping"
const T_PONG: String = "pong"
# Lobby and session
const T_LOBBY_ACTION: String = "lobby_action"
const T_LOBBY_STATE: String = "lobby_state"
const T_LOBBY_ERROR: String = "lobby_error"
const T_SESSION_END: String = "session_end"
# Game traffic. Payloads are opaque to core.
const T_GAME_ACTION: String = "game_action"
const T_GAME_STATE: String = "game_state"
const T_GAME_BATCH: String = "game_batch"  # host > player: {seq, reason, events, view} (see GameController)
const T_GAME_ERROR: String = "game_error"  # host > player: {code, message, action}: an action was refused, nothing changed
const T_GAME_RESYNC: String = "game_resync"  # player > host: "I missed something, send me everything again"
