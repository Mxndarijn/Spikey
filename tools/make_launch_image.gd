extends SceneTree
## Renders the app icon into the iOS launch screen images (export preset "iOS", storyboard).
##   godot --headless --path . -s res://tools/make_launch_image.gd
## Rerun after changing icon.svg.

const ICON := "res://icon.svg"
const OUT_DIR := "res://assets/launch"
## Logo width on the launch screen, in iOS points. @2x and @3x are this times 2 and 3.
const SIZE_PT := 160


func _initialize() -> void:
	var svg := FileAccess.get_file_as_string(ICON)
	var probe := Image.new()
	probe.load_svg_from_string(svg, 1.0)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for density: int in [2, 3]:
		var image := Image.new()
		var scale := float(SIZE_PT * density) / float(probe.get_width())
		var err := image.load_svg_from_string(svg, scale)
		if err != OK:
			push_error("Could not render %s: %s" % [ICON, error_string(err)])
			quit(1)
			return
		var path := OUT_DIR.path_join("ios_launch@%dx.png" % density)
		image.save_png(path)
		print("%s  %dx%d" % [path, image.get_width(), image.get_height()])
	quit(0)
