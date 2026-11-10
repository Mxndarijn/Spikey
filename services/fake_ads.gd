class_name FakeAds
extends AdsService
## A stand-in for rewarded ads in debug builds and tests: always ready, and
## "watching" ends at once with `next_result`. Never used in release builds.

var next_result := Result.EARNED
## Nothing to show (no ad loaded, as when offline).
var ready := true
var shown := 0
var preloads := 0
## Pretend this player has ad privacy choices to change.
var privacy_required := false
var privacy_shown := 0


func is_ready() -> bool:
	return ready


func preload_rewarded() -> void:
	preloads += 1


func show_rewarded() -> void:
	shown += 1
	rewarded_closed.emit(next_result if ready else Result.FAILED)


func privacy_options_required() -> bool:
	return privacy_required


func show_privacy_options() -> void:
	privacy_shown += 1
