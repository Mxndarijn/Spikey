class_name AdsService
extends RefCounted
## Rewarded ads, the only ads in the game: the player chooses to watch one to
## revive (docs/REVIVE.md). This base class is "no ads": nothing is ever ready,
## so the game only offers its free revives. FakeAds stands in for a real ad in
## debug builds on desktop; AdmobAds is the real one on phones.
## Screens only talk to this class.

## show_rewarded() finished, with a Result.
signal rewarded_closed(result: int)

## How a rewarded ad ended.
enum Result {
	## Watched to the end: the reward is theirs.
	EARNED,
	## Closed early: no reward.
	DISMISSED,
	## It could not be shown after the player asked for it. The game gives the
	## reward anyway: a broken ad is never the player's problem.
	FAILED,
}

## AdMob ids (not secrets, they ship in the app). `revive` is the one rewarded
## ad unit.
const ADMOB := {
	"Android":
	{
		"app": "ca-app-pub-6064406000465979~6679947541",
		"revive": "ca-app-pub-6064406000465979/7728150383",
	},
	"iOS":
	{
		"app": "ca-app-pub-6064406000465979~2942727569",
		"revive": "ca-app-pub-6064406000465979/8849660366",
	},
}
## Google's public test units for rewarded ads. Debug builds use only these:
## real ads in a test build can get the AdMob account suspended.
const ADMOB_TEST := {
	"Android": "ca-app-pub-3940256099942544/5224354917",
	"iOS": "ca-app-pub-3940256099942544/1712485313",
}


## The rewarded ad unit for `platform` (OS.get_name()), or "" where there are
## no ads (desktop).
static func revive_unit(platform: String, debug: bool) -> String:
	if debug:
		return str(ADMOB_TEST.get(platform, ""))
	return str((ADMOB.get(platform, {}) as Dictionary).get("revive", ""))


## Called once when the game starts: asks for consent where the law wants it,
## then gets the ads going. Nothing to do without ads.
func start() -> void:
	pass


## An ad is loaded and can be shown right now.
func is_ready() -> bool:
	return false


## Starts loading the next ad, so one is ready when the player crashes.
func preload_rewarded() -> void:
	pass


## Shows the loaded ad; rewarded_closed follows. Without one it fails at once.
func show_rewarded() -> void:
	rewarded_closed.emit(Result.FAILED)


## The player must be able to change their ad privacy choice (Europe): the
## Settings sheet then shows a row for it.
func privacy_options_required() -> bool:
	return false


## Opens the ad privacy choices (Google's form).
func show_privacy_options() -> void:
	pass


## Switches to another ad unit (the debug screen: Google's test ads or the
## real unit). A loaded ad from the old unit is dropped.
func use_unit(_unit: String) -> void:
	pass


## The debug screen: what this service knows right now, as [name, value] rows.
func debug_rows() -> Array:
	return [["Ads", "none in this build"]]
