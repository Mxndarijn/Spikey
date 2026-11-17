extends TestCase
## What the phone opened the game with, on iOS: the native piece
## (tools/ios/FlapjawIntents.m) leaves it in a file; AppIntents hands it on once.

const PATH := "user://test_flapjaw_intent.json"


func test_the_ios_handoff_is_handed_on_once_and_deleted() -> void:
	SafeFile.remove(PATH)
	var intents := AppIntents.new()
	intents.handoff_path = PATH
	var pushes: Array[Dictionary] = []
	var links: Array[String] = []
	intents.push_opened.connect(func(d: Dictionary) -> void: pushes.append(d))
	intents.link_opened.connect(func(u: String) -> void: links.append(u))
	intents.check()
	assert_eq(pushes.size() + links.size(), 0, "no file: nothing")
	var link := "https://flapjaw.mn-platform.tech/battle/KD7WQ3"
	SafeFile.write_json(PATH, {"push": {"kind": "battle_alert", "battle": "12"}, "link": link})
	intents.check()
	assert_eq(pushes, [{"kind": "battle_alert", "battle": "12"}])
	assert_eq(links, [link])
	assert_false(SafeFile.exists(PATH), "read once, then gone")
	intents.check()
	assert_eq(pushes.size(), 1, "never twice")
	SafeFile.write_json(PATH, ["not", "a", "handoff"])
	intents.check()
	assert_eq(pushes.size() + links.size(), 2, "anything else is ignored")
	assert_false(SafeFile.exists(PATH))
	intents.free()
	SafeFile.remove(PATH)
