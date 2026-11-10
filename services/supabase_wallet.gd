class_name SupabaseWallet
extends WalletService
## Diamonds kept on Supabase (supabase/migrations/20261110100000_diamonds.sql).
## The server holds the balance, pays the daily top-10 prizes and checks every
## spend; `Profile.diamonds` is only a copy for the screens. Shares the
## SupabaseClient with the leaderboards, so a phone is the same player on both.
## Offline, or on a database without the migration yet: the copy stays as it
## is, nothing can be spent and no prizes show.

## Tries when the answer doesn't arrive (no internet, timeout): the same
## request id every time, so the server charges once at most.
const SPEND_TRIES := 3

var _api: SupabaseClient


func _init(profile: Profile, api: SupabaseClient) -> void:
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


## Each spend carries a request id; the server answers a repeat of it with the
## first answer instead of charging again (spend_requests migration). So when
## the answer is lost on the way back, asking again is safe.
func spend(amount: int, reason: String, ref: String = "") -> bool:
	if amount <= 0:
		return false
	var body := spend_body(amount, reason, ref, new_request_id())
	var res := {}
	for attempt in SPEND_TRIES:
		res = await _api.call_db("spend_diamonds", body)
		if res.code == 404 and body.has("p_request"):
			# A database without the spend_requests migration: send it plain, once.
			body.erase("p_request")
			res = await _api.call_db("spend_diamonds", body)
			break
		if res.code != 0:
			break
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
static func spend_body(amount: int, reason: String, ref: String, request: String) -> Dictionary:
	return {"p_amount": amount, "p_reason": reason, "p_ref": ref, "p_request": request}


## A random UUID (version 4) for one spend.
static func new_request_id() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0F) | 0x40
	b[8] = (b[8] & 0x3F) | 0x80
	var h := b.hex_encode()
	return (
		"%s-%s-%s-%s-%s"
		% [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20)]
	)


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
