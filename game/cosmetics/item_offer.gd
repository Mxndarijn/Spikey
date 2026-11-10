class_name ItemOffer
extends RefCounted
## What an item's one action is for this player: Use, Get for free, Unlock for
## N (gold or diamonds), Turn diamonds into gold, or Need N more. Rules only;
## Checkout does the buying.

## The action when gold is short but diamonds can cover it: opens the convert sheet.
const CONVERT := "Turn diamonds into gold"
const IN_USE := "In use"
## The kind with no items yet (Customize shows it as coming).
const HATS := "hats"


## [button text, enabled] for item `id` of `kind`.
static func label(profile: Profile, kind: String, id: String) -> Array:
	if kind == HATS:
		return ["Hats are coming", false]
	if id.is_empty():
		return ["Pick one", false]
	if profile.equipped_id(kind) == id:
		return [IN_USE, false]
	if profile.owns(kind, id):
		# The popup's title already names the item.
		return ["Use", true]
	var gems := Shop.diamond_price(kind, id)
	if gems > 0:
		if profile.diamonds >= gems:
			return ["Unlock for %d" % gems, true]
		return ["Need %d more diamonds" % (gems - profile.diamonds), false]
	var cost := Shop.price(kind, id)
	if cost == 0:
		return ["Get for free", true]
	if profile.coins >= cost:
		return ["Unlock for %d" % cost, true]
	# Short on gold, but diamonds can make up for it.
	if profile.diamonds > 0:
		return [CONVERT, true]
	return ["Need %d more gold" % (cost - profile.coins), false]


## Gold missing for item `id` (0 when it isn't a gold item, is owned or is
## affordable).
static func gold_short(profile: Profile, kind: String, id: String) -> int:
	if id.is_empty() or profile.owns(kind, id):
		return 0
	if Shop.diamond_price(kind, id) > 0:
		return 0
	return maxi(Shop.price(kind, id) - profile.coins, 0)
