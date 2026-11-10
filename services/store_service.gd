class_name StoreService
extends RefCounted
## Real-money purchases, as the game sees them. Screens only talk to this
## interface. This base class is a closed store: every purchase fails with a
## plain reason. SampleStore completes them at once (debug builds and tests).
## Google Play Billing and StoreKit come later as two more subclasses; their
## receipts must be checked on the server before diamonds are granted.

## The payment went through: main grants the pack (DiamondPacks.grant).
signal purchased(pack_id: String)
signal failed(pack_id: String, reason: String)

const CLOSED := "Purchases open when Flapjaw is in the app stores."


## True when buy() can succeed.
func is_open() -> bool:
	return false


## Starts a purchase; purchased or failed fires (now or later).
func buy(pack_id: String) -> void:
	failed.emit(pack_id, CLOSED)


## The price to show on a pack's button (the store's local price, later).
func price_text(pack_id: String) -> String:
	return str(DiamondPacks.find(pack_id).get("price", ""))
