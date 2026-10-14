class_name AppInfo
extends RefCounted
## Where the app version comes from: Project Settings > Application > Config > Version.


const FALLBACK_VERSION: String = "0.0.0"


## Never empty: an unset (or blank) project version reads as "0.0.0", so the exact-match
## handshake compares something meaningful and error messages can show it.
static func app_version() -> String:
	var version: String = str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	return version if not version.is_empty() else FALLBACK_VERSION
