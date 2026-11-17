class_name ShareSheet
extends RefCounted
## The phone's own share sheet (WhatsApp, Messages, mail, anything) for an
## invite. Android: an ACTION_SEND text intent in a chooser, through
## JavaClassWrapper (like AppIntents, no plugin). iOS: our native piece
## (tools/ios/FlapjawIntents.m) catches the address IOS_SCHEME opened with
## OS.shell_open and shows UIActivityViewController. Elsewhere (desktop, the
## editor) there is no sheet: share() says so and the caller copies instead.

const IOS_SCHEME := "flapjaw-share"
const CHOOSER_TITLE := "Share"


## Opens the share sheet with `text`; false when this platform has none.
static func share(text: String, os_name: String = OS.get_name()) -> bool:
	match os_name:
		"Android":
			return _android(text)
		"iOS":
			return OS.shell_open(ios_url(text)) == OK
	return false


## The address the iOS piece reads: flapjaw-share:?text=<the text, encoded>.
static func ios_url(text: String) -> String:
	return "%s:?text=%s" % [IOS_SCHEME, text.uri_encode()]


static func _android(text: String) -> bool:
	if not Engine.has_singleton(AppIntents.RUNTIME):
		return false
	var activity: Object = Engine.get_singleton(AppIntents.RUNTIME).call(&"getActivity")
	var intent_class: Object = JavaClassWrapper.wrap("android.content.Intent")
	if activity == null or intent_class == null:
		return false
	# A Java constructor is the method named like its class.
	var send: Object = intent_class.call(&"Intent", "android.intent.action.SEND")
	if send == null:
		return false
	send.call(&"setType", "text/plain")
	send.call(&"putExtra", "android.intent.extra.TEXT", text)
	var chooser: Object = intent_class.call(&"createChooser", send, CHOOSER_TITLE)
	if chooser == null:
		return false
	activity.call(&"startActivity", chooser)
	return true
