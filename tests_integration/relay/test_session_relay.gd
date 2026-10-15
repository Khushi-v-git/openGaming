extends "res://tests/core/session_contract.gd"
## The session contract suite, unchanged, over RelayTransport and a real local relay.


## GUT skips the whole script (and says why) when there is no relay to talk to.
func should_skip_script():  # (GUT declares this without a return type)
	if RelayEnv.available():
		return false
	return "no relay: run scripts/run_integration_tests.sh (needs Node and relay/cloudflare/node_modules)"


func make_env() -> TransportEnv:
	return RelayEnv.new()
