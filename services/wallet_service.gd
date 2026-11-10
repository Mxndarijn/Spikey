class_name WalletService
extends RefCounted
## The player's diamonds, as the game sees them. Screens spend through this
## interface and read the balance from `Profile.diamonds`, which every wallet
## keeps up to date.
## This base class is the local wallet: the balance lives only in the save
## file (no Supabase project set up, and tests). SupabaseWallet keeps it on
## the server, where a save file can't change it, and the save holds a copy.
## spend() and claim() may wait for the server: call them with `await`.

## The balance (and any unclaimed prizes) arrived after sync(). prizes:
## [{"kind": DAILY, "day": "2026-11-09", "rank": 2, "score": 87, "diamonds": 2},
##  {"kind": MILESTONE, "ref": "50", "diamonds": 1},
##  {"kind": STREAK, "ref": "2026-11-09", "diamonds": 1}, ...]
signal synced(diamonds: int, prizes: Array)

const ITEM := "item"
const CONVERT := "convert"
## Kinds of prize: a daily top-10 finish, a best score reached for the first
## time (25, 50, 75, 100), and a real run on 7 days in a row.
const DAILY := "daily"
const MILESTONE := "milestone"
const STREAK := "streak"

var _profile: Profile


func _init(profile: Profile) -> void:
	_profile = profile


## True when the balance lives on a server.
func is_online() -> bool:
	return false


## Asks for the balance and unclaimed prizes; synced fires when they arrive
## (not at all while offline).
func sync() -> void:
	synced.emit(_profile.diamonds, [])


## Takes diamonds for `reason` (ITEM or CONVERT; `ref` names the item).
## False when there are not enough or the server can't be reached.
func spend(amount: int, _reason: String, _ref: String = "") -> bool:
	if amount <= 0 or _profile.diamonds < amount:
		return false
	_profile.diamonds -= amount
	return true


## Claims every unclaimed prize. Returns the diamonds added (0: none, or
## the server can't be reached).
func claim() -> int:
	return 0
