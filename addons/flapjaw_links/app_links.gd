extends RefCounted
## The App Links intent filter for the game's activity: invite links
## (https://HOST/battle/CODE and /duel/CODE) open the game when Android has
## checked the server's /.well-known/assetlinks.json (autoVerify), else the
## browser shows the server's page with the store buttons. docs/DUEL_MODE.md.

const HOST := "flapjaw.mn-platform.tech"
const PREFIXES: Array[String] = ["/battle/", "/duel/"]


static func intent_filter(host: String = HOST) -> String:
	var lines: Array[String] = [
		'<intent-filter android:autoVerify="true">',
		'\t<action android:name="android.intent.action.VIEW" />',
		'\t<category android:name="android.intent.category.DEFAULT" />',
		'\t<category android:name="android.intent.category.BROWSABLE" />',
		'\t<data android:scheme="https" />',
		'\t<data android:host="%s" />' % host,
	]
	for p in PREFIXES:
		lines.append('\t<data android:pathPrefix="%s" />' % p)
	lines.append("</intent-filter>")
	return "\n".join(lines) + "\n"
