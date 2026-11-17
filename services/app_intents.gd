class_name AppIntents
extends Node
## What the phone opened the game with: a tapped push (its data, such as
## {"kind": "battle_alert", "battle": "12"}) or a link (an invite,
## https://flapjaw.mn-platform.tech/battle/KD7WQ3). Looked at when the game
## starts and each time it comes back to the front; each one is handed on once.
##
## Android: read from the activity's intent through Godot's AndroidRuntime
## singleton and JavaClassWrapper (no plugin of our own): a tapped Firebase
## notification puts its data in the intent's extras, an App Link its address
## in the intent's data. iOS: Godot shows neither, so our native piece
## (tools/ios/FlapjawIntents.m, built into the iOS export by CI) writes what the
## phone opened the game with to HANDOFF ({"push": {...}} and/or {"link": "..."});
## it is read and deleted here, so each one is handed on once.

## A tapped push's data (string values).
signal push_opened(data: Dictionary)
## A link the game was opened with.
signal link_opened(url: String)

const RUNTIME := "AndroidRuntime"
## Written by tools/ios/FlapjawIntents.m (user:// is the app's Documents on iOS).
const HANDOFF := "user://flapjaw_intent.json"
## How often the handoff is looked for besides start and resume: on iOS a tap's
## data can arrive just after the app is back in front.
const HANDOFF_EVERY := 1.0
## The push data keys the server sends (backend/src/push.rs).
const KEYS: Array[String] = ["kind", "battle"]

## Where the native piece leaves its handoff (tests point it elsewhere).
var handoff_path := HANDOFF
## The intent handled last (its hash), so one is never handed on twice.
var _handled := 0
var _since := 0.0


func _ready() -> void:
	name = "AppIntents"
	call_deferred(&"check")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		check()


func _process(delta: float) -> void:
	_since += delta
	if _since >= HANDOFF_EVERY:
		_since = 0.0
		if not Engine.has_singleton(RUNTIME):
			_check_handoff()


## Looks for a new push or link and hands it on.
func check() -> void:
	if Engine.has_singleton(RUNTIME):
		_check_android()
	else:
		_check_handoff()


func _check_handoff() -> void:
	if not FileAccess.file_exists(handoff_path):
		return
	var found: Variant = SafeFile.read_json(handoff_path)
	SafeFile.remove(handoff_path)
	deliver(found)


func _check_android() -> void:
	var runtime: Object = Engine.get_singleton(RUNTIME)
	var activity: Object = runtime.call(&"getActivity")
	if activity == null:
		return
	var intent: Object = activity.call(&"getIntent")
	if intent == null:
		return
	var id := int(intent.call(&"hashCode"))
	if id == _handled:
		return
	_handled = id
	var found := {}
	var extras: Object = intent.call(&"getExtras")
	if extras != null:
		var push := {}
		for k in KEYS:
			var v: Variant = extras.call(&"getString", k)
			if v is String and not (v as String).is_empty():
				push[k] = v
		if not push.is_empty():
			found["push"] = push
	var link: Variant = intent.call(&"getDataString")
	if link is String and not (link as String).is_empty():
		found["link"] = link
	deliver(found)


## Hands on what the phone opened the game with ({"push": {...}} and/or
## {"link": "..."}; anything else is ignored).
func deliver(found: Variant) -> void:
	if not found is Dictionary:
		return
	var d := found as Dictionary
	if d.get("push") is Dictionary and not (d.get("push") as Dictionary).is_empty():
		push_opened.emit(d.get("push") as Dictionary)
	if d.get("link") is String and not str(d.get("link")).is_empty():
		link_opened.emit(str(d.get("link")))
