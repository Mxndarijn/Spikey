class_name SampleStore
extends StoreService
## A pretend store for debug builds and tests: every purchase succeeds at
## once and no money moves. Never used in a release build (main picks).


func is_open() -> bool:
	return true


func buy(pack_id: String) -> void:
	if DiamondPacks.find(pack_id).is_empty():
		failed.emit(pack_id, "That pack doesn't exist.")
		return
	purchased.emit(pack_id)
