class_name TransportRig
extends RefCounted
## Test helper: a transport bundled with its event recorder and (for hosts) address.

var transport: Transport
var recorder: TransportRecorder
var address: String = ""


func _init(t: Transport) -> void:
	transport = t
	recorder = TransportRecorder.new(t)
