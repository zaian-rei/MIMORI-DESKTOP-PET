extends Plugin

func initialize() -> bool:
	var theme := ThemeResource.new()
	theme.id = "fixture_theme_plugin"
	theme.display_name = "Fixture Theme Plugin"
	theme.version = "1.0.0"
	theme.author = "Discovery Harness"
	theme.description = "Theme shipped as a plugin."
	return ThemeManager.register_theme_resource(theme)
