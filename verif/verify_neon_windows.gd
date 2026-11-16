extends Node

## Instantiation smoke test for the neon companion menu and about window.
## Boots headless, builds both windows, opens each, and reports PASS/FAIL.

const CompanionMenuScene := preload("res://scenes/ui/companion_menu.tscn")
const AboutWindowScene := preload("res://scenes/ui/about_window.tscn")
const SettingsWindowScene := preload("res://scenes/ui/settings_window.tscn")

var _menu: Window
var _about: Window
var _settings: Window
var _failed := false


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_menu = CompanionMenuScene.instantiate()
	get_tree().root.add_child(_menu)
	await get_tree().process_frame
	_menu.open_menu(Vector2i(500, 500))
	await get_tree().process_frame
	_check(_menu is CompanionMenu, "menu instantiated as CompanionMenu")
	_check(_menu.size.x > 100 and _menu.size.y > 100, "menu window sized (%s)" % _menu.size)
	_check(_menu.visible, "menu visible after open")

	_about = AboutWindowScene.instantiate()
	get_tree().root.add_child(_about)
	await get_tree().process_frame
	_about.open_about(Vector2i(700, 500))
	await get_tree().process_frame
	_check(_about is AboutWindow, "about instantiated as AboutWindow")
	_check(_about.size.x > 200, "about window sized (%s)" % _about.size)
	_check(_about.visible, "about visible after open")

	_menu.close_menu()
	_about.close_about()
	await get_tree().process_frame

	_settings = SettingsWindowScene.instantiate()
	get_tree().root.add_child(_settings)
	await get_tree().process_frame
	_check(_settings is SettingsWindow, "settings instantiated as SettingsWindow")
	_check(_settings.size.x >= 700, "settings window sized (%s)" % _settings.size)
	_check(_settings.get_node_or_null("Root/Panel") != null, "settings glass panel built")
	_settings.open_control_center()
	await get_tree().process_frame
	_check(_settings.visible, "settings visible after open")
	_settings.hide()

	print(_failed and "FAIL" or "PASS")
	get_tree().quit(_failed and 1 or 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("OK  ", what)
	else:
		_failed = true
		print("FAIL  ", what)
