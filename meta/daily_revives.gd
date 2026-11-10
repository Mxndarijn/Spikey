class_name DailyRevives
extends RefCounted
## Revives without an ad: PER_DAY of them per local day (docs/REVIVE.md).
## Saved with the Profile.

const PER_DAY := 3

## Free revives used on `day` ("YYYY-MM-DD", the phone's date).
var used := 0
var day := ""


## The phone's date, the day free revives count for.
static func today() -> String:
	return Time.get_date_string_from_system()


## Free revives still left on `on_day`; a new day starts with all of them.
func left(on_day: String) -> int:
	var spent := used if on_day == day else 0
	return maxi(PER_DAY - spent, 0)


## Spends one of `on_day`'s free revives. Returns false when none is left.
func use(on_day: String) -> bool:
	if left(on_day) <= 0:
		return false
	if on_day != day:
		day = on_day
		used = 0
	used += 1
	return true


func write_to(d: Dictionary) -> void:
	d["free_revives_used"] = used
	d["free_revives_day"] = day


func read_from(d: Dictionary) -> void:
	var saved_day: Variant = d.get("free_revives_day", "")
	if saved_day is String:
		day = saved_day
		used = clampi(int(d.get("free_revives_used", 0)), 0, PER_DAY)
