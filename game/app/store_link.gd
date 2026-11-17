class_name StoreLink
extends RefCounted
## The game's page in the phone's app store, for "Update to play" (Battle and
## Duel run only on the newest gameplay version). Android: the Play Store page
## of the package id in export_presets.cfg. iOS: the App Store id in the project
## setting flapjaw/app_store_id once the app is listed; until then a store
## search for the game.

const ANDROID := "https://play.google.com/store/apps/details?id=com.mxndarijn.spikey"
const IOS_APP := "https://apps.apple.com/app/id%s"
const IOS_SEARCH := "https://apps.apple.com/search?term=flapjaw"


static func url(os_name: String = OS.get_name()) -> String:
	if os_name == "iOS":
		var id := str(ProjectSettings.get_setting("flapjaw/app_store_id", ""))
		return IOS_APP % id if not id.is_empty() else IOS_SEARCH
	return ANDROID


static func open() -> void:
	OS.shell_open(url())
