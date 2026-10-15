class_name RelayEnv
extends TransportEnv
## Integration tier: the shared transport, session and lobby contract suites against a REAL relay
## (relay/cloudflare run locally with `wrangler dev`). scripts/run_integration_tests.sh starts the
## relay and sets RELAY_URL; without it these tests skip themselves.

const ENV_VAR: String = "RELAY_URL"


static func url() -> String:
	return OS.get_environment(ENV_VAR)


static func available() -> bool:
	return not url().is_empty()


func make_transport() -> Transport:
	return RelayTransport.new()


func host_config() -> Dictionary:
	return {"relay_url": url()}


func join_config() -> Dictionary:
	return {"relay_url": url(), "join_timeout_msec": 4000}


## A real relay answers a few milliseconds later than the same poll.
func settle_frames() -> int:
	return 25
