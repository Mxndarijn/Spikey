class_name DiamondPacks
extends RefCounted
## What real money buys: diamonds, in packs. Gold is never sold directly (a
## player who wants gold converts, Checkout.convert). The price text is a
## placeholder until the app stores supply the local price (StoreService).

const STARTER := "starter"
## In display order. "once": can be bought a single time per player.
const PACKS: Array[Dictionary] = [
	{
		"id": STARTER,
		"name": "Starter pack",
		"diamonds": 20,
		"gold": 500,
		"price": "€1.99",
		"note": "Once",
		"once": true,
	},
	{"id": "handful", "name": "Handful", "diamonds": 10, "gold": 0, "price": "€0.99", "note": ""},
	{
		"id": "pouch",
		"name": "Pouch",
		"diamonds": 55,
		"gold": 0,
		"price": "€4.99",
		"note": "10% extra",
	},
	{
		"id": "chest",
		"name": "Chest",
		"diamonds": 120,
		"gold": 0,
		"price": "€9.99",
		"note": "20% extra",
	},
	{
		"id": "vault",
		"name": "Vault",
		"diamonds": 260,
		"gold": 0,
		"price": "€19.99",
		"note": "30% extra",
	},
]


static func ids() -> Array[String]:
	var out: Array[String] = []
	for p in PACKS:
		out.append(p.id)
	return out


## The pack, or {} for an unknown id.
static func find(id: String) -> Dictionary:
	for p in PACKS:
		if p.id == id:
			return p
	return {}


## False for an unknown pack and for a once-only pack the player already has.
static func can_buy(profile: Profile, id: String) -> bool:
	var pack := find(id)
	if pack.is_empty():
		return false
	return not (pack.get("once", false) and id in profile.packs_bought)


## Hands out a paid pack. Call only after the store confirmed the payment.
static func grant(profile: Profile, id: String) -> bool:
	if not can_buy(profile, id):
		return false
	var pack := find(id)
	profile.diamonds += int(pack.diamonds)
	profile.coins += int(pack.gold)
	if id not in profile.packs_bought:
		profile.packs_bought.append(id)
	return true
