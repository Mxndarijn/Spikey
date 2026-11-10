extends TestCase
## The debug screen in the settings sheet: how it opens, what it reports and
## what its buttons do. The server side of the test notification is in
## supabase/tests/40_test_test_push.sql.

const MIGRATION := "res://supabase/migrations/20261110130000_test_push.sql"


## A phone with push: records what the debug screen asks of it.
class FakePush:
	extends PushService
	var asked := 0
	var started := 0

	func is_available() -> bool:
		return true

	func request_permission() -> void:
		asked += 1

	func start() -> void:
		started += 1


## The services the page gets; tests swap in their fakes.
var _svc: AppServices


## Fresh offline services, and DevMode (a static other tests also use) as asked.
func _reset(dev_mode: int = -1) -> void:
	_svc = AppServices.offline(Profile.new())
	DevMode.override = dev_mode


func _sheet(profile: Profile) -> SettingsSheet:
	var sheet := SettingsSheet.new(profile, _svc)
	(Engine.get_main_loop() as SceneTree).root.add_child(sheet)
	return sheet


func test_seven_taps_on_the_title_open_it() -> void:
	_reset(0)
	var sheet := _sheet(Profile.new())
	assert_true(sheet.find_child("Debug", true, false) == null, "no Debug row for players")
	for i in DebugPage.TAPS_TO_OPEN - 1:
		sheet.tap_title()
	assert_true(sheet.debug_page() == null, "six taps are not enough")
	sheet.tap_title()
	assert_true(sheet.debug_page() != null, "the seventh opens it")
	sheet.show_debug(false)
	assert_true(sheet.debug_page() == null, "Back returns to the settings")
	assert_false(sheet.is_showing_credits())
	sheet.free()
	_reset()


func test_developer_mode_has_a_debug_row() -> void:
	_reset(1)
	var sheet := _sheet(Profile.new())
	var row := sheet.find_child("Debug", true, false) as Button
	assert_true(row != null, "developer mode shows the row")
	row.pressed.emit()
	var page := sheet.debug_page()
	assert_true(page != null)
	assert_true(page.find_child("GiveRevives", true, false) != null, "and may give revives back")
	sheet.free()
	_reset()


func test_report_lists_app_ads_and_notifications() -> void:
	_reset(0)
	var ads := FakeAds.new()
	_svc.ads = ads
	var push := FakePush.new()
	push.accept_token("abcdef-a-long-push-token-wxyz", PushService.IOS)
	push.last_error = "no APNs token"
	_svc.push = push
	var profile := Profile.new()
	profile.best_score = 56
	var page := DebugPage.new(profile, _svc)
	var text := page.report()
	assert_true(text.contains("Gameplay: version %d" % SimConfig.GAMEPLAY_VERSION))
	assert_true(text.contains("Best score: 56"))
	assert_true(text.contains("Ads: stand-in"), "the ad service reports itself")
	assert_true(text.contains("Free revives: 3 of 3 left today"))
	assert_true(text.contains("Token: abcdef...wxyz (29 characters)"), "never the whole token")
	assert_false(text.contains("a-long-push-token"))
	assert_true(text.contains("Last error: no APNs token"))
	assert_true(text.contains("Board alerts: on"))
	page.free()
	_reset()


func test_report_without_services() -> void:
	_reset(0)
	var page := DebugPage.new(Profile.new(), _svc)
	var text := page.report()
	assert_true(text.contains("Ads: none in this build"))
	assert_true(text.contains("Push: not in this build"))
	assert_true(page.find_child("GiveRevives", true, false) == null, "players can't add revives")
	page.free()
	assert_eq(AdsService.new().debug_rows(), [["Ads", "none in this build"]])
	assert_eq(PushService.short_token(""), "none yet")
	assert_eq(PushService.short_token("short"), "5 characters")
	_reset()


func test_ad_buttons() -> void:
	_reset(0)
	var ads := FakeAds.new()
	ads.ready = false
	_svc.ads = ads
	var page := DebugPage.new(Profile.new(), _svc)
	page.press("ShowAd")
	assert_eq(ads.shown, 0, "nothing to show")
	assert_eq(page.note(DebugPage.ADS), "No ad is loaded")
	page.press("LoadAd")
	assert_eq(ads.preloads, 1)
	ads.ready = true
	page.press("ShowAd")
	assert_eq(ads.shown, 1)
	assert_eq(page.note(DebugPage.ADS), "The ad was watched to the end")
	assert_false(AudioServer.is_bus_mute(0), "the sound is back after the ad")
	ads.next_result = AdsService.Result.DISMISSED
	page.press("ShowAd")
	assert_eq(page.note(DebugPage.ADS), "The ad was closed early")
	page.press("AdChoicesForm")
	assert_eq(ads.privacy_shown, 1)
	page.free()
	_reset()


func test_using_up_free_revives_is_saved() -> void:
	_reset(0)
	var profile := Profile.new()
	var page := DebugPage.new(profile, _svc)
	var saves := [0]
	page.changed.connect(func() -> void: saves[0] += 1)
	page.press("UseRevives")
	assert_eq(profile.revives.left(DailyRevives.today()), 0)
	assert_eq(saves[0], 1, "main saves the profile")
	assert_true(page.report().contains("Free revives: 0 of 3 left today"))
	page.free()
	_reset()


func test_test_ads_switch_is_saved_and_switches_the_unit() -> void:
	_reset(0)
	var ads := FakeAds.new()
	_svc.ads = ads
	var profile := Profile.new()
	assert_false(profile.settings.test_ads, "real ads by default")
	var page := DebugPage.new(profile, _svc)
	var saves := [0]
	page.changed.connect(func() -> void: saves[0] += 1)
	(page.find_child("TestAds", true, false) as SettingSwitch).button_pressed = true
	assert_true(profile.settings.test_ads)
	assert_eq(saves[0], 1)
	assert_eq(ads.units.size(), 1, "the ad service is told at once")
	page.free()
	assert_true(
		Profile.from_dict(profile.to_dict()).settings.test_ads, "the switch survives a restart"
	)
	assert_false(Profile.from_dict({"version": 3}).settings.test_ads)
	assert_eq(AdsService.revive_unit("iOS", true), AdsService.ADMOB_TEST["iOS"])
	assert_eq(AdsService.revive_unit("iOS", false), AdsService.ADMOB["iOS"]["revive"])
	_reset()


func test_notification_buttons() -> void:
	_reset(0)
	var profile := Profile.new()
	var page := DebugPage.new(profile, _svc)
	page.press("AskPush")
	assert_eq(page.note(DebugPage.PUSH), "Push is not in this build")
	assert_false(profile.push_asked)
	var push := FakePush.new()
	_svc.push = push
	page.press("AskPush")
	assert_eq(push.asked, 1)
	assert_true(profile.push_asked, "so the next start fetches the token again")
	page.press("FetchToken")
	assert_eq(push.started, 1)
	page.press("TestPush")
	assert_eq(page.note(DebugPage.PUSH), "No server in this build", "no server: says so")
	page.free()
	_reset()


func test_migration_matches_the_game() -> void:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(sql.contains("function public.send_test_push() returns text"))
	assert_true(
		sql.contains("grant execute on function public.send_test_push() to authenticated"),
		"the game may call it"
	)
	assert_true(sql.contains("revoke all on function public.send_test_push() from public, anon"))
	for answer: String in PushService.TEST_ANSWERS:
		assert_true(sql.contains("'%s'" % answer), "the game knows the answer %s" % answer)
