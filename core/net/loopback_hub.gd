class_name LoopbackHub
extends RefCounted
## Registry that lets in-memory LoopbackTransports find each other by address.
## Tests make their own hub for isolation; hot-seat or demo code can use shared().

static var _shared: LoopbackHub = null

var _hosts: Dictionary = {}
var _counter: int = 0


static func shared() -> LoopbackHub:
	if _shared == null:
		_shared = LoopbackHub.new()
	return _shared


func allocate_address() -> String:
	_counter += 1
	return "loopback:%d" % _counter


## Returns false if the address is already taken.
func register(address: String, transport: Transport) -> bool:
	if _hosts.has(address):
		return false
	_hosts[address] = transport
	return true


func unregister(address: String) -> void:
	_hosts.erase(address)


func find_host(address: String) -> Transport:
	return _hosts.get(address, null)
