@tool
extends EditorPlugin
## Adds the invite links' App Links intent filter to the Android export.

const AppLinks := preload("res://addons/flapjaw_links/app_links.gd")

var _export: LinksExport


func _enter_tree() -> void:
	_export = LinksExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class LinksExport:
	extends EditorExportPlugin

	func _get_name() -> String:
		return "FlapjawLinks"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_manifest_activity_element_contents(
		platform: EditorExportPlatform, _debug: bool
	) -> String:
		if not _supports_platform(platform):
			return ""
		return AppLinks.intent_filter()
