extends TestCase
## The design kit's fonts are bundled and load as weighted variable fonts.


func test_font_files_and_licenses_are_bundled() -> void:
	for path in [GameFonts.DISPLAY_FILE, GameFonts.UI_FILE]:
		assert_true(ResourceLoader.exists(path), "%s exists" % path)
	for lic in ["res://assets/fonts/Baloo2-OFL.txt", "res://assets/fonts/Nunito-OFL.txt"]:
		assert_true(FileAccess.file_exists(lic), "%s ships with the font" % lic)


func test_fonts_use_the_bundled_files() -> void:
	var display := GameFonts.display()
	assert_true(display is FontVariation, "display font is the bundled Baloo 2")
	assert_true(GameFonts.ui(800) is FontVariation, "UI font is the bundled Nunito")
	assert_ne(GameFonts.ui(600), GameFonts.ui(800), "each weight is its own variation")
	if display is FontVariation:
		assert_eq((display as FontVariation).base_font.get_font_name(), "Baloo 2")
