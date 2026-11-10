extends SceneTree
## Adds the AdMob plugin's Swift package (Google's ad SDK) to an exported Xcode
## project:
##   godot --headless --path . -s res://tools/ci/patch_ios_spm.gd -- <project.pbxproj>
## The plugin does this itself at the end of an export, but as a deferred call,
## and a command-line export quits before that call runs. The export then has
## admob_spm/Package.swift next to a project that never mentions it, and the
## app fails to link (every GAD... and UMP... symbol is missing). This runs the
## plugin's own patcher on the project file. Safe to run twice.

const PATCHER := "res://addons/admob/internal/services/pbxproj_service.gd"
const DEFAULT_PROJECT := "res://build/ios/Flapjaw.xcodeproj/project.pbxproj"
const MARK := "admob_spm"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if not args.is_empty() else DEFAULT_PROJECT
	if not FileAccess.file_exists(path):
		printerr("patch_ios_spm: no project file at %s" % path)
		quit(1)
		return
	var patcher := load(PATCHER) as GDScript
	if patcher == null:
		printerr("patch_ios_spm: the AdMob plugin's patcher is missing (%s)" % PATCHER)
		quit(1)
		return
	var already := FileAccess.get_file_as_string(path).contains(MARK)
	patcher.call(&"patch", path)
	if not FileAccess.get_file_as_string(path).contains(MARK):
		printerr("patch_ios_spm: %s was not changed" % path)
		quit(1)
		return
	print("patch_ios_spm: %s" % ("already had the package" if already else "added the package"))
	quit(0)
