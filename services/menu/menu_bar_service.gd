extends Node

## Installs a small native Pet menu with Settings and Quit. The menu is
## optional and degrades silently when the platform has no system menu bar.

var _submenu: RID = RID()


func _ready() -> void:
	call_deferred("_setup_native_menu")


func _setup_native_menu() -> void:
	if OS.has_feature("headless"):
		return
	if not NativeMenu.has_system_menu(NativeMenu.MAIN_MENU_ID):
		LoggerGlobal.info("MenuBar: no system menu bar, skipping native menu.")
		return

	var main := NativeMenu.get_system_menu(NativeMenu.MAIN_MENU_ID)
	_submenu = NativeMenu.create_menu()
	NativeMenu.add_item(
		_submenu, "Settings...", Callable(self, "_on_menu_action"), Callable(), "SETTINGS"
	)
	NativeMenu.add_separator(_submenu)
	NativeMenu.add_item(
		_submenu, "Quit", Callable(self, "_on_menu_action"), Callable(), "QUIT"
	)
	NativeMenu.add_submenu_item(main, "Pet", _submenu)
	LoggerGlobal.info("MenuBar: native menu installed.")


func _on_menu_action(tag: Variant) -> void:
	match String(tag):
		"SETTINGS":
			EventBus.settings_requested.emit()
		"QUIT":
			get_tree().quit()
