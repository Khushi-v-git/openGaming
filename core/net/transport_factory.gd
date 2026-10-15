class_name TransportFactory
extends RefCounted
## The only place that names concrete transports. Lobby, session and game code get a
## Transport from here by configuration and never import an implementation (rule 3a).
##
## config.transport: "direct_ws" (default), "relay", "auto", "loopback" (in-process),
## "fake_relay" (tests). Other keys are passed through to the transport, e.g. port,
## bind_address, relay_url.
##
## "auto" is what the app uses: hosting follows config.host_via ("relay", the default, or
## "direct"), and joining looks at what the player typed: a room code (6 letters and digits)
## goes to the relay, anything with a "." or ":" (or a ws:// prefix) is a direct address, and a
## "relay:" prefix forces the relay. A bare word that is not a room code is refused with a
## message, never guessed at.

const KIND_DIRECT_WS: String = "direct_ws"
const KIND_RELAY: String = "relay"
const KIND_AUTO: String = "auto"
const KIND_LOOPBACK: String = "loopback"
const KIND_FAKE_RELAY: String = "fake_relay"


static func create(config: Dictionary) -> Transport:
	match str(config.get("transport", KIND_DIRECT_WS)):
		KIND_DIRECT_WS:
			return DirectWsTransport.new()
		KIND_RELAY:
			return RelayTransport.new()
		KIND_AUTO:
			return AutoTransport.new()
		KIND_LOOPBACK:
			return LoopbackTransport.new(config.get("hub", null))
		KIND_FAKE_RELAY:
			return FakeRelayTransport.new(config["relay"])
		_:
			push_error("Unknown transport kind '%s'" % str(config.get("transport")))
			return null


## Sensible default settings for a kind. UI code uses these to prefill fields.
static func default_config(kind: String = KIND_DIRECT_WS) -> Dictionary:
	match kind:
		KIND_DIRECT_WS:
			return {"transport": KIND_DIRECT_WS, "port": DirectWsTransport.DEFAULT_PORT, "bind_address": "*"}
		_:
			return {"transport": kind}


## The configuration the app uses for real play: "auto", with the relay URL and the host's
## choice (relay or direct) read from the app settings. The port is the direct listen port.
static func network_config() -> Dictionary:
	return {
		"transport": KIND_AUTO,
		"host_via": AppSettings.host_via(),
		"relay_url": AppSettings.relay_url(),
		"port": DirectWsTransport.DEFAULT_PORT,
		"bind_address": "*",
	}


## What a joiner typed: which kind of transport it is for, and the address to hand to it.
## Returns {ok, kind, address} or a failure with BAD_ADDRESS.
static func classify_join_text(text: String) -> Dictionary:
	var typed: String = text.strip_edges()
	if typed.to_lower().begins_with("relay:"):
		var code: String = RelayTransport.normalize_code(typed.substr(6))
		if code.is_empty():
			return CoreResult.failure(AddressParser.BAD_ADDRESS, "That is not a room code. Room codes have 6 letters and digits.")
		return CoreResult.success({"kind": KIND_RELAY, "address": code})
	if typed.begins_with("ws://") or typed.contains(".") or typed.contains(":") or typed.begins_with("["):
		return CoreResult.success({"kind": KIND_DIRECT_WS, "address": typed})
	if RelayTransport.looks_like_code(typed):
		return CoreResult.success({"kind": KIND_RELAY, "address": RelayTransport.normalize_code(typed)})
	return CoreResult.failure(AddressParser.BAD_ADDRESS, "Enter a room code (6 letters and digits) or an address like 192.168.1.20:24680.")


## Chooses between the relay and the direct transport. Hosting follows config.host_via; joining
## follows what was typed (see classify_join_text). Everything else is the chosen transport's.
class AutoTransport extends Transport:
	var _inner: Transport = null
	var _early_failure: String = ""

	func host_session(config: Dictionary) -> Dictionary:
		if _inner != null:
			return CoreResult.failure("ALREADY_ACTIVE", "transport is already hosting or joined")
		var via: String = str(config.get("host_via", "relay"))
		_adopt(RelayTransport.new() if via == "relay" else DirectWsTransport.new())
		var result: Dictionary = _inner.host_session(config)
		if not CoreResult.is_ok(result):
			_drop()
		return result

	func join_session(address_or_code: String, config: Dictionary) -> void:
		if _inner != null:
			_early_failure = "transport is already active"
			return
		var verdict: Dictionary = TransportFactory.classify_join_text(address_or_code)
		if not CoreResult.is_ok(verdict):
			_early_failure = str(verdict["error"]["message"])
			return
		_adopt(RelayTransport.new() if verdict["kind"] == TransportFactory.KIND_RELAY else DirectWsTransport.new())
		_inner.join_session(verdict["address"], config)

	func leave() -> void:
		_early_failure = ""
		if _inner != null:
			var inner: Transport = _inner
			_drop()
			inner.leave()

	func send(peer_id: int, message: Dictionary) -> void:
		if _inner != null:
			_inner.send(peer_id, message)

	func disconnect_peer(peer_id: int) -> void:
		if _inner != null:
			_inner.disconnect_peer(peer_id)

	func poll() -> void:
		if not _early_failure.is_empty():
			var reason: String = _early_failure
			_early_failure = ""
			join_failed.emit(reason)
			return
		if _inner != null:
			_inner.poll()

	func get_peer_ids() -> Array[int]:
		return _inner.get_peer_ids() if _inner != null else ([] as Array[int])

	func is_active() -> bool:
		return _inner != null and _inner.is_active()

	func keepalive_policy() -> Dictionary:
		return _inner.keepalive_policy() if _inner != null else super.keepalive_policy()

	func _adopt(transport: Transport) -> void:
		_inner = transport
		transport.message_received.connect(func(peer_id: int, message: Dictionary) -> void: message_received.emit(peer_id, message))
		transport.peer_connected.connect(func(peer_id: int) -> void: peer_connected.emit(peer_id))
		transport.peer_disconnected.connect(func(peer_id: int) -> void: peer_disconnected.emit(peer_id))
		transport.join_succeeded.connect(func() -> void: join_succeeded.emit())
		transport.join_failed.connect(func(reason: String) -> void: join_failed.emit(reason))
		transport.session_ready.connect(func(info: Dictionary) -> void: session_ready.emit(info))
		transport.host_failed.connect(func(reason: String) -> void: host_failed.emit(reason))
		transport.link_state_changed.connect(func(state: String) -> void: link_state_changed.emit(state))

	func _drop() -> void:
		_inner = null
