class_name AdmobAds
extends AdsService
## Rewarded ads from AdMob, through the Poing Studios plugin (addons/admob).
## Phones only: Main loads this script when the plugin's native side is in the
## build, so desktop runs and tests never touch the plugin.
##
## start() asks Google's consent service what this player has to be asked
## (the consent form in Europe), shows that form when needed, and only then
## starts the ads SDK. No consent, no ads: the game then offers only its free
## revives. One rewarded ad is kept loaded for the revive offer.

var _unit := ""
var _started := false
## The player may be shown ads and the SDK is being started.
var _initialized := false
var _sdk_ready := false
var _wants_ad := false
var _loading := false
var _loader: RewardedAdLoader
var _ad: RewardedAd
var _earned := false
## A load for a unit that use_unit() has since replaced is still on its way.
var _stale := false
# For the debug screen.
var _consent_note := "asking"
var _load_note := "none yet"
var _show_note := "none yet"
var _loads := 0
var _loaded := 0


## `unit`: the rewarded ad unit (AdsService.revive_unit).
func _init(unit: String) -> void:
	_unit = unit


func start() -> void:
	if _started:
		return
	_started = true
	UserMessagingPlatform.consent_information.update(
		ConsentRequestParameters.new(), _on_consent_known, _on_consent_failed
	)


func is_ready() -> bool:
	return _ad != null


func preload_rewarded() -> void:
	_wants_ad = true
	if _sdk_ready:
		_load()


func show_rewarded() -> void:
	if _ad == null:
		rewarded_closed.emit(Result.FAILED)
		return
	_earned = false
	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = _on_earned
	_ad.show(listener)


func privacy_options_required() -> bool:
	var info := UserMessagingPlatform.consent_information
	return (
		info.get_privacy_options_requirement_status()
		== ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED
	)


func show_privacy_options() -> void:
	UserMessagingPlatform.show_privacy_options_form(_on_privacy_closed)


func use_unit(unit: String) -> void:
	if unit == _unit or unit.is_empty():
		return
	_unit = unit
	_drop_ad()
	# A load on its way is for the old unit: its answer is thrown away.
	_stale = _loading
	_load_note = "none yet"
	if _sdk_ready and not _loading:
		_load()


func debug_rows() -> Array:
	var info := UserMessagingPlatform.consent_information
	var test := _unit in AdsService.ADMOB_TEST.values()
	var sdk := "waiting for consent"
	if _sdk_ready:
		sdk = "ready"
	elif _initialized:
		sdk = "starting"
	var ad := "none"
	if _ad != null:
		ad = "loaded"
	elif _loading:
		ad = "loading"
	return [
		["Ads", "AdMob"],
		["Ad unit", "Google test ads" if test else "real ads (...%s)" % _unit.right(10)],
		["Consent", str(ConsentInformation.ConsentStatus.keys()[info.get_consent_status()])],
		["Consent form", "available" if info.get_is_consent_form_available() else "none"],
		["Consent check", _consent_note],
		["Ad choices", "needed" if privacy_options_required() else "not needed"],
		["Ad SDK", sdk],
		["Ad", ad],
		["Loads", "%d asked, %d loaded" % [_loads, _loaded]],
		["Last load", _load_note],
		["Last show", _show_note],
	]


## Google knows what this player must be asked: show the form if there is one
## to answer, else go on.
func _on_consent_known() -> void:
	_consent_note = "ok"
	var info := UserMessagingPlatform.consent_information
	var required := info.get_consent_status() == ConsentInformation.ConsentStatus.REQUIRED
	if required and info.get_is_consent_form_available():
		UserMessagingPlatform.load_consent_form(_on_form_loaded, _on_consent_failed)
	else:
		_initialize()


func _on_form_loaded(form: ConsentForm) -> void:
	form.show(_on_consent_failed)


## The consent check or form ended (`_error` is null when it went well). What
## the player answered before still counts, so the ads may start anyway.
func _on_consent_failed(error: FormError = null) -> void:
	if error != null:
		_consent_note = "error %d: %s" % [error.error_code, error.message]
	_initialize()


func _on_privacy_closed(_error: FormError = null) -> void:
	_initialize()


## Starts the ads SDK once, and only when ads may be requested for this player.
func _initialize() -> void:
	if _initialized:
		return
	var status := UserMessagingPlatform.consent_information.get_consent_status()
	var allowed := (
		status == ConsentInformation.ConsentStatus.OBTAINED
		or status == ConsentInformation.ConsentStatus.NOT_REQUIRED
	)
	if not allowed:
		return
	_initialized = true
	var config := RequestConfiguration.new()
	# Nothing rougher than "parental guidance" in a cartoon arcade game.
	config.max_ad_content_rating = RequestConfiguration.MAX_AD_CONTENT_RATING_PG
	MobileAds.set_request_configuration(config)
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = _on_sdk_ready
	MobileAds.initialize(listener)


func _on_sdk_ready(_status: InitializationStatus) -> void:
	_sdk_ready = true
	if _wants_ad:
		_load()


func _load() -> void:
	if _ad != null or _loading:
		return
	_loading = true
	_loads += 1
	var callback := RewardedAdLoadCallback.new()
	callback.on_ad_loaded = _on_loaded
	callback.on_ad_failed_to_load = _on_load_failed
	_loader = RewardedAdLoader.new()
	_loader.load(_unit, AdRequest.new(), callback)


func _on_loaded(ad: RewardedAd) -> void:
	_loading = false
	if _stale:
		_stale = false
		ad.destroy()
		_load()
		return
	_loaded += 1
	_load_note = "ok"
	_ad = ad
	var callback := FullScreenContentCallback.new()
	callback.on_ad_dismissed_full_screen_content = _on_dismissed
	callback.on_ad_failed_to_show_full_screen_content = _on_show_failed
	ad.full_screen_content_callback = callback


## No ad right now (offline, nothing to show). The next run asks again.
func _on_load_failed(error: LoadAdError) -> void:
	_loading = false
	if _stale:
		_stale = false
		_load()
		return
	_load_note = "no ad"
	if error != null:
		_load_note = "error %d: %s" % [error.code, error.message]


func _on_earned(_item: RewardedItem) -> void:
	_earned = true


## The ad closed. The answer waits one more step, so a reward that arrives in
## the same moment is counted.
func _on_dismissed() -> void:
	_finish.call_deferred(false)


func _on_show_failed(error: AdError) -> void:
	_show_note = "failed"
	if error != null:
		_show_note = "error %d: %s" % [error.code, error.message]
	_finish.call_deferred(true)


func _finish(failed: bool) -> void:
	_drop_ad()
	if failed:
		rewarded_closed.emit(Result.FAILED)
		return
	_show_note = "watched to the end" if _earned else "closed early"
	rewarded_closed.emit(Result.EARNED if _earned else Result.DISMISSED)


func _drop_ad() -> void:
	if _ad != null:
		_ad.destroy()
		_ad = null
