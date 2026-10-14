class_name Protocol
extends RefCounted
## Protocol constants. Bump PROTOCOL_VERSION on any incompatible message change.

const PROTOCOL_VERSION: int = 1
## Hard cap on one serialized message. Larger input is rejected before parsing.
const MAX_MESSAGE_BYTES: int = 65536

# Handshake
const T_HELLO: String = "hello"
const T_WELCOME: String = "welcome"
const T_REJECT: String = "reject"
# Liveness
const T_PING: String = "ping"
const T_PONG: String = "pong"
# Lobby and session
const T_LOBBY_ACTION: String = "lobby_action"
const T_LOBBY_STATE: String = "lobby_state"
const T_SESSION_END: String = "session_end"
# Game traffic. Payloads are opaque to core.
const T_GAME_ACTION: String = "game_action"
const T_GAME_STATE: String = "game_state"
