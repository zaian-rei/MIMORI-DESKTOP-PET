extends Node

## Verbose (DEBUG-level) output is gated behind the debug.verbose_logging
## setting. INFO/WARN/ERROR always print. SettingsManager may not be ready on
## very early startup, so an empty registry just means "not verbose" - safe.

func debug(message: String) -> void:
	if SettingsManager != null and not bool(SettingsManager.get_setting("debug.verbose_logging", false)):
		return
	print("[DEBUG] ", message)

func info(message: String) -> void:
	print("[INFO] ", message)

func warn(message: String) -> void:
	print("[WARN] ", message)

func error(message: String) -> void:
	print("[ERROR] ", message)
