class_name CoreResult
extends RefCounted
## Plain-dict Result helpers shared by core code.
## Success: {ok: true, <key>: <value>}. Failure: {ok: false, error: {code, message}}.


static func success(fields: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"ok": true}
	result.merge(fields)
	return result


static func failure(code: String, message: String = "") -> Dictionary:
	return {"ok": false, "error": {"code": code, "message": message}}


static func is_ok(result: Dictionary) -> bool:
	return result.get("ok", false) == true


static func error_code(result: Dictionary) -> String:
	var err: Dictionary = result.get("error", {})
	return str(err.get("code", ""))
