class_name SupabaseWallet
extends WalletService
## Diamonds kept on Supabase (supabase/migrations/20261110100000_diamonds.sql).
## The server holds the balance, pays the daily top-10 prizes and checks every
## spend; `Profile.diamonds` is only a copy for the screens. Uses the
## leaderboard's session, so a phone is the same player on both.
## Offline, or on a database without the migration yet: the copy stays as it
## is, nothing can be spent and no prizes show.

var _api: SupabaseLeaderboard


func _init(profile: Profile, api: SupabaseLeaderboard) -> void:
	super(profile)
	_api = api


func is_online() -> bool:
	return true


func sync() -> void:
	var res := await _api.call_db("get_wallet", {})
	if not res.ok:
		return
	var wallet := parse_wallet(res.data)
	if wallet.is_empty():
		return
	_profile.diamonds = wallet.diamonds
	synced.emit(wallet.diamonds, wallet.prizes)


func spend(amount: int, reason: String, ref: String = "") -> bool:
	if amount <= 0:
		return false
	var res := await _api.call_db("spend_diamonds", spend_body(amount, reason, ref))
	if not res.ok or not res.data is Dictionary:
		return false
	_profile.diamonds = maxi(int((res.data as Dictionary).get("diamonds", 0)), 0)
	return true


func claim() -> int:
	var res := await _api.call_db("claim_prizes", {})
	if not res.ok or not res.data is Dictionary:
		return 0
	var d := res.data as Dictionary
	_profile.diamonds = maxi(int(d.get("diamonds", _profile.diamonds)), 0)
	return maxi(int(d.get("claimed", 0)), 0)


## The arguments of spend_diamonds in supabase/migrations/.
static func spend_body(amount: int, reason: String, ref: String) -> Dictionary:
	return {"p_amount": amount, "p_reason": reason, "p_ref": ref}


## get_wallet's answer as {"diamonds": int, "prizes": Array[Dictionary]} with
## numbers as ints, or {} when it is not a wallet. Daily prizes come first,
## then the bonuses (best-score milestones and 7-day streaks); each has a
## "kind" (WalletService.DAILY, MILESTONE or STREAK). Prizes that pay nothing
## or, for a daily one, have no top-10 rank are dropped.
static func parse_wallet(data: Variant) -> Dictionary:
	if not data is Dictionary or not (data as Dictionary).has("diamonds"):
		return {}
	var d := data as Dictionary
	var prizes: Array[Dictionary] = []
	var raw: Variant = d.get("prizes", [])
	if raw is Array:
		for item: Variant in raw:
			if not item is Dictionary:
				continue
			var row := item as Dictionary
			var prize := {
				"kind": WalletService.DAILY,
				"day": str(row.get("day", "")),
				"rank": int(row.get("rank", 0)),
				"score": int(row.get("score", 0)),
				"diamonds": int(row.get("diamonds", 0)),
			}
			if prize.rank >= 1 and prize.diamonds > 0:
				prizes.append(prize)
	var bonuses: Variant = d.get("bonuses", [])
	if bonuses is Array:
		for item: Variant in bonuses:
			if not item is Dictionary:
				continue
			var row := item as Dictionary
			var bonus := {
				"kind": str(row.get("kind", "")),
				"ref": str(row.get("ref", "")),
				"diamonds": int(row.get("diamonds", 0)),
			}
			if bonus.kind in [WalletService.MILESTONE, WalletService.STREAK] and bonus.diamonds > 0:
				prizes.append(bonus)
	return {"diamonds": maxi(int(d.get("diamonds", 0)), 0), "prizes": prizes}
