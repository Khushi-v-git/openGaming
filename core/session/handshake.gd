class_name Handshake
extends RefCounted
## Handshake message builders and the host-side validation of a hello (rule 6).
## All three of protocol_version, game_id and app_version must match exactly in v1.
##
## hello   (client -> host): {app_version, game_id, player_name, player_id?, rejoin_token?}
## welcome (host -> client): {player_id, rejoin_token, ...extra}
## reject  (host -> client): {code, message}, then the host closes the connection.

const MAX_NAME_LENGTH: int = 24


static func hello(app_version: String, game_id: String, player_name: String, player_id: String = "", rejoin_token: String = "") -> Dictionary:
	var payload: Dictionary = {
		"app_version": app_version,
		"game_id": game_id,
		"player_name": player_name,
	}
	if not player_id.is_empty():
		payload["player_id"] = player_id
		payload["rejoin_token"] = rejoin_token
	return Envelope.make(Protocol.T_HELLO, payload)


static func welcome(player_id: String, rejoin_token: String, extra: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = extra.duplicate(true)
	payload["player_id"] = player_id
	payload["rejoin_token"] = rejoin_token
	return Envelope.make(Protocol.T_WELCOME, payload)


static func reject(code: String, message: String) -> Dictionary:
	return Envelope.make(Protocol.T_REJECT, {"code": code, "message": message})


## Checks a hello. On success: {ok, player_name, player_id, rejoin_token} (the last
## two are "" for a fresh join). On failure: a Result whose error code says why.
static func validate_hello(message: Dictionary, host_app_version: String, host_game_id: String) -> Dictionary:
	var their_protocol: int = int(message.get("protocol_version", -1))
	if their_protocol != Protocol.PROTOCOL_VERSION:
		return CoreResult.failure(ErrorCodes.PROTOCOL_MISMATCH, "This host uses protocol %d but you use protocol %d. Update the app." % [Protocol.PROTOCOL_VERSION, their_protocol])
	var payload: Dictionary = message.get("payload", {})
	for field: String in ["app_version", "game_id", "player_name"]:
		if typeof(payload.get(field)) != TYPE_STRING:
			return CoreResult.failure(ErrorCodes.MALFORMED, "hello is missing '%s'" % field)
	for optional: String in ["player_id", "rejoin_token"]:
		if payload.has(optional) and typeof(payload[optional]) != TYPE_STRING:
			return CoreResult.failure(ErrorCodes.MALFORMED, "hello field '%s' must be a string" % optional)
	if payload["game_id"] != host_game_id:
		return CoreResult.failure(ErrorCodes.WRONG_GAME, "This host is running '%s' but you are running '%s'." % [host_game_id, payload["game_id"]])
	if payload["app_version"] != host_app_version:
		return CoreResult.failure(ErrorCodes.APP_VERSION_MISMATCH, "This host runs app version %s but you run %s. Everyone must use the same version." % [host_app_version, payload["app_version"]])
	var cleaned: Dictionary = clean_name(payload["player_name"])
	if not CoreResult.is_ok(cleaned):
		return cleaned
	return CoreResult.success({
		"player_name": cleaned["name"],
		"player_id": payload.get("player_id", ""),
		"rejoin_token": payload.get("rejoin_token", ""),
	})


## Trims and validates a display name: 1..MAX_NAME_LENGTH characters, no control characters.
static func clean_name(raw: String) -> Dictionary:
	var name: String = raw.strip_edges()
	if name.is_empty():
		return CoreResult.failure(ErrorCodes.NAME_INVALID, "Please enter a name.")
	if name.length() > MAX_NAME_LENGTH:
		return CoreResult.failure(ErrorCodes.NAME_INVALID, "Names can be at most %d characters." % MAX_NAME_LENGTH)
	for i: int in name.length():
		var code: int = name.unicode_at(i)
		if code < 32 or code == 127:
			return CoreResult.failure(ErrorCodes.NAME_INVALID, "Names cannot contain control characters.")
	return CoreResult.success({"name": name})
