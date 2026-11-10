class_name SampleStore
extends StoreService
## A pretend store for debug builds and tests: every purchase succeeds at
## once and no money moves. Never used in a release build (main picks).
## It remembers the kept products bought through it (the Revive Pass), so
## restore() can hand them back.

## Kept products this pretend account owns.
var kept: Array[String] = []


func is_open() -> bool:
	return true


func buy(pack_id: String) -> void:
	if DiamondPacks.find(pack_id).is_empty():
		failed.emit(pack_id, "That pack doesn't exist.")
		return
	if DiamondPacks.is_kept(pack_id) and pack_id not in kept:
		kept.append(pack_id)
	purchased.emit(pack_id)


func restore() -> void:
	restored.emit(kept.duplicate())
