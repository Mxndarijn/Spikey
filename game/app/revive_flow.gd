class_name ReviveFlow
extends RefCounted
## The revive offer after a crash (docs/REVIVE.md): once per real run with a
## fair score, paid with one of the day's free revives or a rewarded ad. With
## the Revive Pass it is always free and the day's count is left alone. Skip,
## or an ad closed early, ends the run.

## The run is over for good: Main shows Game over.
signal ended(replay: Replay)
## The bird is back and the run waits, paused, for the player's tap.
signal revived

## No offer below this score: a quick crash restarts with one tap.
const MIN_SCORE := 5

## The score this run was revived at (-1: not revived).
var revived_at := -1

var _profile: Profile
var _run: RunController
var _ads: AdsService
var _offer: ReviveOffer
var _save: Callable
## The crashed run while the offer shows (null: no offer).
var _replay: Replay


## `save`: writes the profile (a free revive used is saved at once).
func _init(
	profile: Profile, run: RunController, ads: AdsService, offer: ReviveOffer, save: Callable
) -> void:
	_profile = profile
	_run = run
	_ads = ads
	_offer = offer
	_save = save
	_ads.rewarded_closed.connect(_on_ad_closed)
	_offer.revive_pressed.connect(_on_revive_pressed)
	_offer.skip_pressed.connect(skip)


## A new run: no offer, not revived.
func reset() -> void:
	_replay = null
	revived_at = -1


func is_offering() -> bool:
	return _replay != null


## A real run crashed: shows the offer when the run gets one, else ends it.
func on_crash(replay: Replay) -> void:
	if not _can_offer(replay):
		ended.emit(replay)
		return
	_replay = replay
	_offer.show_offer(replay.score, _profile.revives.left(DailyRevives.today()), _has_pass())


## Whether this crash gets the offer: the run has its revive left, the score
## is worth it, and the pass, a free revive or a loaded ad pays for it.
func _can_offer(replay: Replay) -> bool:
	if not _run.can_revive() or replay.score < MIN_SCORE:
		return false
	if _has_pass():
		return true
	return _profile.revives.left(DailyRevives.today()) > 0 or _ads.is_ready()


func _has_pass() -> bool:
	return DiamondPacks.has_revive_pass(_profile)


## Skip on the offer: the run ends.
func skip() -> void:
	if _replay == null:
		return
	var replay := _replay
	_replay = null
	ended.emit(replay)


## Revive on the offer: free with the pass, else a free one if the day has
## any left, else the ad.
func _on_revive_pressed() -> void:
	if _replay == null:
		return
	if _has_pass():
		_revive()
	elif _profile.revives.use(DailyRevives.today()):
		_save.call()
		_revive()
	elif _ads.is_ready():
		# No game sound under the ad; _on_ad_closed turns it back on.
		AudioServer.set_bus_mute(0, true)
		_ads.show_rewarded()
	else:
		# Nothing to pay with any more (the ad went away): the run just ends.
		skip()


## The rewarded ad closed. Watched: revive. Closed early: that is a Skip.
## An ad that broke after the player asked for it revives anyway.
func _on_ad_closed(result: int) -> void:
	AudioServer.set_bus_mute(0, false)
	if _replay == null:
		return
	if result == AdsService.Result.DISMISSED:
		skip()
	else:
		_revive()


func _revive() -> void:
	_replay = null
	revived_at = _run.sim.state.score
	if _run.revive():
		revived.emit()
