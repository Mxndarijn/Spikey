class_name DiamondPacks
extends RefCounted
## What real money buys: diamonds, in packs, and the Revive Pass. Gold is
## never sold directly (a player who wants gold converts, Checkout.convert).
## The price text is a placeholder until the app stores supply the local price
## (StoreService).

const STARTER := "starter"
## The Revive Pass (docs/REVIVE.md): bought once, every revive offer is free
## (no ad, no daily limit). Still one revive per run, so it never changes a
## score.
const REVIVE_PASS := "revive_pass"
const PASS: Dictionary = {
	"id": REVIVE_PASS,
	"name": "Revive Pass",
	"diamonds": 0,
	"gold": 0,
	"price": "€4.99",
	"note": "Once",
	"once": true,
	"kept": true,
}
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


## The diamond packs, in display order (not the pass).
static func ids() -> Array[String]:
	var out: Array[String] = []
	for p in PACKS:
		out.append(p.id)
	return out


## Every product the store sells: the packs, then the pass.
static func product_ids() -> Array[String]:
	var out := ids()
	out.append(REVIVE_PASS)
	return out


## The pack (or the pass), or {} for an unknown id.
static func find(id: String) -> Dictionary:
	if id == REVIVE_PASS:
		return PASS
	for p in PACKS:
		if p.id == id:
			return p
	return {}


## Bought once and kept for good (the pass, not a pack of diamonds): the
## store's restore hands it back.
static func is_kept(id: String) -> bool:
	return bool(find(id).get("kept", false))


static func has_revive_pass(profile: Profile) -> bool:
	return REVIVE_PASS in profile.packs_bought


## False for an unknown pack and for a once-only pack the player already has.
static func can_buy(profile: Profile, id: String) -> bool:
	var pack := find(id)
	if pack.is_empty():
		return false
	return not (bool(pack.get("once", false)) and id in profile.packs_bought)


## Hands out a paid pack (or the pass). Call only after the store confirmed
## the payment.
static func grant(profile: Profile, id: String) -> bool:
	if not can_buy(profile, id):
		return false
	var pack := find(id)
	profile.diamonds += int(pack.diamonds)
	profile.coins += int(pack.gold)
	if id not in profile.packs_bought:
		profile.packs_bought.append(id)
	return true


## The store gave back these earlier purchases (restore): hands out the kept
## ones the save is missing. Diamond packs are never restored, not even the
## once-only Starter: their diamonds were handed out when they were bought.
## Returns the ids handed out.
static func restore(profile: Profile, restored_ids: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for id in restored_ids:
		if is_kept(id) and grant(profile, id):
			out.append(id)
	return out
