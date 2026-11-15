class_name HomePopups
extends RefCounted
## The popups Home shows by itself: the prize popup for unclaimed diamonds
## (WalletService.synced), once after a reset, yesterday's Daily Run when
## the player had a try on it but won nothing (a prize says it instead), and
## the notices (NoticePopup: fresh start, please update, moved to another
## phone), which wait for Home when they arrive elsewhere.

## Watch yesterday's winner (its LeaderboardBoard.Entry.run_id).
signal watch_requested(run_id: int)

var _profile: Profile
var _wallet: WalletService
var _menus: MenuLayer
## Writes the profile.
var _save: Callable
## Opens the Wallet's Earn free tab.
var _show_earn: Callable
## Notices (NoticePopup ids) waiting for Home, oldest first, and the one shown.
var _pending: Array[String] = []
var _card: NoticePopup


func _init(
	profile: Profile, wallet: WalletService, menus: MenuLayer, save: Callable, show_earn: Callable
) -> void:
	_profile = profile
	_wallet = wallet
	_menus = menus
	_save = save
	_show_earn = show_earn
	# The wallet answered: keep the copy in the save, then show it.
	wallet.synced.connect(
		func(_diamonds: int, prizes: Array) -> void:
			save.call()
			on_wallet_synced(prizes)
	)


func _home() -> HomeScreen:
	return _menus.current() as HomeScreen


## The wallet answered: show the balance on Home and offer any prize that
## waits to be claimed.
func on_wallet_synced(prizes: Array) -> void:
	var home := _home()
	if home == null:
		return
	home.wallet().show_balance(_profile)
	if prizes.is_empty() or home.prize_popup() != null:
		return
	var popup := home.show_prizes(prizes)
	popup.claim_pressed.connect(_claim.bind(popup))
	popup.earn_pressed.connect(
		func() -> void:
			home.close_prizes()
			_show_earn.call()
	)


func _claim(popup: DailyPrizePopup) -> void:
	@warning_ignore("redundant_await")
	var won: int = await _wallet.claim()
	_save.call()
	if not is_instance_valid(popup):
		return
	if won <= 0:
		popup.show_failed()
		return
	AudioDirector.sound("purchase")
	var home := _home()
	if home != null:
		home.wallet().show_balance(_profile)
		home.close_prizes()


## Today's Daily Run arrived: the pill on Home, and yesterday's result once.
func on_daily(info: DailyRunInfo) -> void:
	var home := _home()
	if home == null:
		return
	home.set_daily_info(info)
	var past := info.yesterday
	if past == null or past.rank <= 0 or not past.settled or _profile.daily_run_seen == past.day:
		return
	_profile.daily_run_seen = past.day
	_save.call()
	# A prize place is told by the prize popup (with Claim).
	if Economy.daily_run_prize(past.rank) > 0 or home.prize_popup() != null:
		return
	var popup := home.show_daily_result(past)
	popup.watch_requested.connect(watch_requested.emit)


## Shows a notice (NoticePopup id) on Home now, or the next time Home shows.
func notice(id: String) -> void:
	if id in _pending or (_has_card() and _card.id == id):
		return
	_pending.append(id)
	show_pending()


## The next waiting notice, when Home is up and none is showing.
func show_pending() -> void:
	var home := _home()
	if home == null or _has_card() or _pending.is_empty():
		return
	var card := NoticePopup.new(_pending.pop_front())
	_card = card
	card.closed.connect(
		func() -> void:
			card.queue_free()
			_card = null
			show_pending()
	)
	home.add_child(card)


## Whether Home is the screen showing.
func home_open() -> bool:
	return _home() != null


## The notice on Home now, or null.
func notice_card() -> NoticePopup:
	return _card if _has_card() else null


func _has_card() -> bool:
	return _card != null and is_instance_valid(_card) and not _card.is_queued_for_deletion()
