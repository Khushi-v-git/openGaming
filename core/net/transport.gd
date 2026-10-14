class_name Transport
extends RefCounted
## The one networking interface (rules 3 and 3a). Session-oriented, not socket-oriented.
##
## Roles: a host calls host_session(); a client calls join_session(). The host sees
## each client as an opaque peer_id assigned by the transport. A client sees the host
## as HOST_PEER_ID. Nothing here exposes sockets, IPs or Godot RPC.
##
## Contract every implementation must honour:
## - Events (signals) are emitted only from poll(), never from send() or other calls,
##   so callers can rely on one consistent, non-reentrant delivery point.
## - For one peer, peer_connected comes first, then its messages in send order, and
##   peer_disconnected comes last. A peer_id is never reused within a session.
## - join_session() reports exactly one of join_succeeded / join_failed. After
##   join_succeeded the host's peer_connected(HOST_PEER_ID) is NOT emitted; the join
##   itself is the connection event. If the host goes away, a client gets
##   peer_disconnected(HOST_PEER_ID).
## - send() to an unknown or gone peer is silently dropped.
## - Messages are plain-data envelopes (see Envelope). Implementations must deliver
##   the receiver an independent copy, as if it had crossed a wire.
## - leave() is idempotent. Afterwards the transport can be reused.

const HOST_PEER_ID: int = 1

signal message_received(peer_id: int, message: Dictionary)
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal join_succeeded()
signal join_failed(reason: String)


## Starts hosting. Returns {ok, address, kind}: `address` is what joiners enter
## (host:port for direct, a room code for relays); `kind` names the transport.
func host_session(_config: Dictionary) -> Dictionary:
	return _not_implemented()


## Starts joining. Result arrives via join_succeeded / join_failed from poll().
func join_session(_address_or_code: String, _config: Dictionary) -> void:
	join_failed.emit("join_session not implemented")


## Leaves or closes the session. Idempotent.
func leave() -> void:
	pass


func send(_peer_id: int, _message: Dictionary) -> void:
	pass


## Sends to every connected peer (host: all clients; client: just the host).
func broadcast(message: Dictionary) -> void:
	for peer_id: int in get_peer_ids():
		send(peer_id, message)


## Closes one peer's connection. On the host this kicks a client; the transport
## still emits peer_disconnected for it from a later poll(). Messages sent to the
## peer just before this call must still be delivered (that is how a reject reaches
## the peer), though a transport may give the peer a brief grace period to close
## first, so the disconnect can take a few polls.
func disconnect_peer(_peer_id: int) -> void:
	pass


## Drives I/O and emits signals. The owner calls this every frame.
func poll() -> void:
	pass


## Currently connected peers. Host: its clients. Client: [HOST_PEER_ID] once joined.
func get_peer_ids() -> Array[int]:
	return []


## True while hosting or joined/joining.
func is_active() -> bool:
	return false


# --- helpers for implementations -------------------------------------------------

func _not_implemented() -> Dictionary:
	return CoreResult.failure("NOT_IMPLEMENTED", "transport does not implement this operation")


## Message -> wire text. In-memory transports use this too, so they behave like
## a real wire (independent copies, int normalization, size cap).
func _encode(message: Dictionary) -> String:
	assert(Envelope.is_plain_data(message), "transport messages must be plain data")
	return Envelope.to_text(message)


## Wire text -> {ok, message} or failure (MALFORMED / TOO_LARGE).
func _decode(text: String) -> Dictionary:
	return Envelope.parse(text)
