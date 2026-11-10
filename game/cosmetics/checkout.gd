class_name Checkout
extends RefCounted
## Buying: gold items straight from the save, premium items through the wallet
## (which may ask the server), and turning diamonds into gold. Screens call
## this and show the result; they never touch the money themselves. Calls that
## may wait for the server must be awaited.

## Gold, diamonds or owned items changed: the save should be written.
signal changed

enum Result { OK, ALREADY_OWNED, NOT_ENOUGH_COINS, NOT_ENOUGH_DIAMONDS, UNKNOWN_ITEM, FAILED }

var profile: Profile
var wallet: WalletService


func _init(p_profile: Profile, p_wallet: WalletService) -> void:
	profile = p_profile
	wallet = p_wallet


## A checkout on the local wallet (diamonds only in the save): no server.
static func offline(p_profile: Profile) -> Checkout:
	return Checkout.new(p_profile, WalletService.new(p_profile))


## Buys item `id` of `kind` for gold, or for diamonds when it is on the
## premium line (Shop.diamond_price). FAILED: the wallet could not spend
## (offline, or the server said no); nothing changed then.
func buy(kind: String, id: String) -> Result:
	var gems := Shop.diamond_price(kind, id)
	var gold := Shop.price(kind, id)
	if gold < 0 and gems == 0:
		return Result.UNKNOWN_ITEM
	if profile.owns(kind, id):
		return Result.ALREADY_OWNED
	if gems > 0:
		if profile.diamonds < gems:
			return Result.NOT_ENOUGH_DIAMONDS
		@warning_ignore("redundant_await")
		var ok: bool = await wallet.spend(gems, WalletService.ITEM, "%s:%s" % [kind, id])
		if not ok:
			return Result.FAILED
	else:
		if profile.coins < gold:
			return Result.NOT_ENOUGH_COINS
		profile.coins -= gold
	profile.grant(kind, id)
	changed.emit()
	return Result.OK


## Turns `diamonds` into gold (Economy.GOLD_PER_DIAMOND each), one way.
## False when it could not be spent; nothing changed then.
func convert(diamonds: int) -> bool:
	if diamonds <= 0 or profile.diamonds < diamonds:
		return false
	@warning_ignore("redundant_await")
	var ok: bool = await wallet.spend(diamonds, WalletService.CONVERT)
	if not ok:
		return false
	profile.coins += Economy.gold_for(diamonds)
	changed.emit()
	return true
