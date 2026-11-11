class_name RunHistory
extends RefCounted
## The player's own runs on this phone (Your runs): the last LATEST_MAX runs,
## plus up to SAVED_MAX saved runs that stay until the player removes them.
## A new run pushes the oldest unsaved run past LATEST_MAX out; a saved run is
## never dropped. Runs are kept newest first. RunStore reads and writes it.

const LATEST_MAX := 100
const SAVED_MAX := 20
const FORMAT_VERSION := 1

## Newest first.
var records: Array[RunRecord] = []
var _next_id := 1


## Adds a finished run as the newest and drops what no longer fits.
func add(record: RunRecord) -> RunRecord:
	record.id = _next_id
	_next_id += 1
	records.push_front(record)
	_trim()
	return record


## The last LATEST_MAX runs (saved ones among them), newest first.
func latest() -> Array[RunRecord]:
	return records.slice(0, LATEST_MAX)


## The saved runs, newest first.
func saved() -> Array[RunRecord]:
	return records.filter(func(r: RunRecord) -> bool: return r.saved)


func saved_count() -> int:
	return saved().size()


func is_saved_full() -> bool:
	return saved_count() >= SAVED_MAX


## The newest run, or null when there is none yet.
func last() -> RunRecord:
	return records[0] if not records.is_empty() else null


func find(id: int) -> RunRecord:
	for r in records:
		if r.id == id:
			return r
	return null


## Saves a run. False when there is no such run or Saved is full.
func save_run(id: int) -> bool:
	var r := find(id)
	if r == null:
		return false
	if r.saved:
		return true
	if is_saved_full():
		return false
	r.saved = true
	return true


## Takes a run out of Saved. A run older than the last LATEST_MAX goes then.
func unsave_run(id: int) -> bool:
	var r := find(id)
	if r == null or not r.saved:
		return false
	r.saved = false
	_trim()
	return true


## Keeps the newest LATEST_MAX runs and every saved one.
func _trim() -> void:
	var kept: Array[RunRecord] = []
	for i in records.size():
		if i < LATEST_MAX or records[i].saved:
			kept.append(records[i])
	records = kept


func to_dict() -> Dictionary:
	var list := []
	for r in records:
		list.append(r.to_dict())
	return {"format_version": FORMAT_VERSION, "next_id": _next_id, "runs": list}


static func from_dict(d: Dictionary) -> RunHistory:
	var h := RunHistory.new()
	var list: Variant = d.get("runs", [])
	if list is Array:
		for item: Variant in list:
			if item is Dictionary:
				h.records.append(RunRecord.from_dict(item as Dictionary))
	h.records.sort_custom(func(a: RunRecord, b: RunRecord) -> bool: return a.id > b.id)
	var top := h.records[0].id if not h.records.is_empty() else 0
	h._next_id = maxi(int(d.get("next_id", 1)), top + 1)
	h._trim()
	return h
