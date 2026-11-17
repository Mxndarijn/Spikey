extends TestCase
## The Android notification channels: the same ids the server sends to, and
## nothing happens off Android.

const SENDER := "res://backend/src/push.rs"


func test_channels_match_what_the_server_sends() -> void:
	var rs := FileAccess.get_file_as_string(SENDER)
	assert_true(
		rs.contains('pub const CHANNEL: &str = "%s";' % AndroidChannels.BOARD),
		"board alerts go to the board channel"
	)
	assert_true(
		rs.contains('pub const BATTLE_CHANNEL: &str = "%s";' % AndroidChannels.BATTLES),
		"battle alerts go to the battles channel"
	)
	var ids: Array = []
	for c: Array in AndroidChannels.channels():
		ids.append(c[0])
		assert_false(str(c[1]).is_empty(), "every channel has a name")
		assert_false(str(c[2]).is_empty(), "and a description")
	assert_eq(ids, [AndroidChannels.BOARD, AndroidChannels.BATTLES])


func test_channels_exist_from_android_8() -> void:
	assert_true(AndroidChannels.has_channels("Android", "8.0.0"))
	assert_true(AndroidChannels.has_channels("Android", "14"))
	assert_false(AndroidChannels.has_channels("Android", "7.1.2"))
	assert_false(AndroidChannels.has_channels("iOS", "17.0"))
	assert_false(AndroidChannels.has_channels("Windows", "10"))


func test_nothing_is_made_off_android() -> void:
	assert_eq(AndroidChannels.create(), 0)
