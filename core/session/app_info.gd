class_name AppInfo
extends RefCounted
## Where the app version comes from: Project Settings > Application > Config > Version.


static func app_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
