class_name AppServices
extends RefCounted
## The services the app runs on, made once by Main and handed to the screens
## that need them, so no screen looks a service up through a global.
## Each picks the real one when this build and setup can use it, else a
## stand-in: sample boards, a local wallet, no push, fake or no ads.

## The AdMob provider and the native plugin it needs (addons/admob).
const ADMOB_ADS := "res://services/admob_ads.gd"
const ADMOB_SINGLETON := "PoingGodotAdMob"
## The Firebase push service and the native plugin it needs (addons/godotx_firebase).
const FIREBASE_PUSH := "res://services/firebase_push.gd"
const FIREBASE_SINGLETON := "GodotxFirebaseMessaging"

var leaderboard: LeaderboardService
var wallet: WalletService
var store: StoreService
var push: PushService
var ads: AdsService
## The server's copy of the save (does nothing without a server).
var profile_sync: ProfileSync
## Buying and converting, through `wallet`.
var checkout: Checkout
## The music and sounds; null in tests that build screens on their own.
var audio: AudioDirector


## Everything offline: sample boards, the local wallet, a closed store, no
## push and no ads. For screens built on their own (tests, tools).
static func offline(profile: Profile) -> AppServices:
	var s := AppServices.new()
	s.leaderboard = SampleLeaderboard.new(profile)
	s.wallet = WalletService.new(profile)
	s.store = StoreService.new()
	s.push = PushService.new()
	s.ads = AdsService.new()
	s.profile_sync = ProfileSync.new(profile, null)
	s.checkout = Checkout.new(profile, s.wallet)
	return s


## Supabase when its config file is there (docs/LEADERBOARD_SETUP.md), else
## samples. `host`: a node in the tree for the HTTP requests.
static func make_leaderboard(
	profile: Profile, host: Node, config_path: String
) -> LeaderboardService:
	var config := SupabaseClient.load_config(config_path)
	if config.is_empty():
		return SampleLeaderboard.new(profile)
	var online := SupabaseLeaderboard.new(
		profile, SupabaseClient.new(host, config.url, config.anon_key)
	)
	online.restore()
	return online


## The Supabase connection the leaderboards use, shared with the wallet and
## push alerts; null when the boards are samples (no server).
static func supabase_of(leaderboard: LeaderboardService) -> SupabaseClient:
	var online := leaderboard as SupabaseLeaderboard
	return online.client if online != null else null


## Diamonds on the server when the leaderboards are (Supabase), else in the save.
static func make_wallet(profile: Profile, api: SupabaseClient) -> WalletService:
	return SupabaseWallet.new(profile, api) if api != null else WalletService.new(profile)


## A pretend store in debug builds with a local wallet, else a closed one
## until the app-store billing is in (services/store_service.gd). With the
## diamonds on the server a pretend purchase would be undone by the next sync.
static func make_store(wallet: WalletService) -> StoreService:
	if OS.is_debug_build() and not wallet.is_online():
		return SampleStore.new()
	return StoreService.new()


## Firebase push in a phone build that carries the plugin, else no push.
static func make_push(api: SupabaseClient) -> PushService:
	if Engine.has_singleton(FIREBASE_SINGLETON):
		# Loaded by path, like the ads: naming the class here crashes Godot 4.6
		# beta 2 on exit when every script is loaded (tools/ci/load_all.gd).
		return (load(FIREBASE_PUSH) as GDScript).new(api)
	return PushService.new(api)


## AdMob on a phone whose build has the plugin's native side (debug builds
## ask for Google's test ads). Elsewhere: a stand-in ad in debug builds, so
## the ad path can be played on a PC, and no ads at all in release builds.
static func make_ads(profile: Profile) -> AdsService:
	var test_ads := OS.is_debug_build() or profile.settings.test_ads
	var unit := AdsService.revive_unit(OS.get_name(), test_ads)
	if not unit.is_empty() and Engine.has_singleton(ADMOB_SINGLETON):
		# Loaded by path: naming the class would load the plugin on every PC too.
		return (load(ADMOB_ADS) as GDScript).new(unit)
	return FakeAds.new() if OS.is_debug_build() else AdsService.new()
