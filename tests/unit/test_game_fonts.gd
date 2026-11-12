extends TestCase
## The design kit's one font, Archivo, is bundled and loads as a variable font
## with its weight and width axes.


func test_font_file_and_license_are_bundled() -> void:
	assert_true(ResourceLoader.exists(GameFonts.FILE), "%s exists" % GameFonts.FILE)
	assert_true(FileAccess.file_exists(GameFonts.LICENSE), "the license ships with the font")


func test_fonts_use_the_bundled_file_with_both_axes() -> void:
	var display := GameFonts.display()
	assert_true(display is FontVariation, "display font is the bundled Archivo")
	assert_true(GameFonts.ui(800) is FontVariation, "UI font is the bundled Archivo")
	assert_ne(GameFonts.ui(600), GameFonts.ui(800), "each weight is its own variation")
	assert_eq(GameFonts.ui(700), GameFonts.ui(700), "variations are cached")
	if not display is FontVariation:
		return
	var v := display as FontVariation
	assert_true(v.base_font.get_font_name().begins_with(GameFonts.FAMILY), "the Archivo file")
	var ts := TextServerManager.get_primary_interface()
	assert_eq(int(v.variation_opentype[ts.name_to_tag("wght")]), 900, "display is weight 900")
	assert_eq(int(v.variation_opentype[ts.name_to_tag("wdth")]), 125, "display is wide (125)")
	var axes := (v.base_font as FontFile).get_supported_variation_list()
	assert_true(axes.has(ts.name_to_tag("wght")), "the file has a weight axis")
	assert_true(axes.has(ts.name_to_tag("wdth")), "the file has a width axis")
	var ui := GameFonts.ui(600) as FontVariation
	assert_eq(int(ui.variation_opentype[ts.name_to_tag("wdth")]), 100, "UI text is normal width")
