extends TestCase
## The device key's copy in the iOS Keychain (SupabaseClient.keychain), which
## outlives a reinstall that deletes the app's files. A stand-in plays the
## FlapjawKeychain singleton.

const SESSION := "user://test_keychain_session.json"
const DEVICE := "user://test_keychain_device_key.json"
const EMAIL := "x@device.flapjaw.invalid"


## The FlapjawKeychain engine singleton's two methods, in memory.
class FakeKeychain:
	extends RefCounted
	var items := {}
	var refuse := false

	func read(name: String) -> String:
		return str(items.get(name, ""))

	func write(name: String, value: String) -> bool:
		if refuse:
			return false
		items[name] = value
		return true


func _clean() -> void:
	SafeFile.remove(SESSION)
	SafeFile.remove(DEVICE)


func _api(keychain: FakeKeychain) -> SupabaseClient:
	var api := SupabaseClient.new(null, "https://example.supabase.co", "k")
	api.session_path = SESSION
	api.device_path = DEVICE
	api.keychain = keychain
	return api


func _kept(keychain: FakeKeychain) -> Dictionary:
	return SupabaseClient.device_entry(
		SupabaseClient.parse(keychain.read(SupabaseClient.KEYCHAIN_ITEM))
	)


func test_no_keychain_off_ios() -> void:
	var api := SupabaseClient.new(null, "https://example.supabase.co", "k")
	assert_eq(api.keychain, null, "only the iOS engine has the FlapjawKeychain singleton")


## The iOS reinstall: the file is gone, the Keychain still has the key.
func test_a_reinstall_signs_in_with_the_keychain_key() -> void:
	_clean()
	var keychain := FakeKeychain.new()
	var key := SupabaseClient.new_device_key()
	keychain.write(SupabaseClient.KEYCHAIN_ITEM, JSON.stringify({"key": key, "email": EMAIL}))
	var api := _api(keychain)
	api.restore()
	assert_true(api.has_device_login())
	assert_eq(SafeFile.read_json(DEVICE), {"key": key, "email": EMAIL}, "the file is back")
	_clean()


## A key saved before the Keychain was used goes into it at the next start.
func test_the_file_key_is_copied_into_the_keychain() -> void:
	_clean()
	var key := SupabaseClient.new_device_key()
	SafeFile.write_json(DEVICE, {"key": key, "email": EMAIL})
	var keychain := FakeKeychain.new()
	_api(keychain).restore()
	assert_eq(_kept(keychain), {"key": key, "email": EMAIL})
	_clean()


func test_the_file_wins_over_the_keychain() -> void:
	_clean()
	var key := SupabaseClient.new_device_key()
	SafeFile.write_json(DEVICE, {"key": key, "email": EMAIL})
	var keychain := FakeKeychain.new()
	keychain.write(
		SupabaseClient.KEYCHAIN_ITEM,
		JSON.stringify(
			{"key": SupabaseClient.new_device_key(), "email": "y@device.flapjaw.invalid"}
		)
	)
	var api := _api(keychain)
	api.restore()
	assert_eq(SafeFile.read_json(DEVICE).key, key)
	assert_eq(_kept(keychain).key, key, "the Keychain follows the file")
	_clean()


func test_a_broken_keychain_value_is_not_used() -> void:
	_clean()
	for value: String in ["", "not json", JSON.stringify({"key": "Fj-short", "email": EMAIL})]:
		var keychain := FakeKeychain.new()
		keychain.write(SupabaseClient.KEYCHAIN_ITEM, value)
		var api := _api(keychain)
		api.restore()
		assert_false(api.has_device_login(), value)
		assert_false(FileAccess.file_exists(DEVICE), "nothing to put back: " + value)
	_clean()


## A Keychain that says no leaves the file's copy, and is tried again next start.
func test_a_refusing_keychain_keeps_the_file() -> void:
	_clean()
	var key := SupabaseClient.new_device_key()
	SafeFile.write_json(DEVICE, {"key": key, "email": EMAIL})
	var keychain := FakeKeychain.new()
	keychain.refuse = true
	var api := _api(keychain)
	api.restore()
	assert_true(api.has_device_login())
	keychain.refuse = false
	_api(keychain).restore()
	assert_eq(_kept(keychain).key, key)
	_clean()


func test_nothing_saved_writes_nothing() -> void:
	_clean()
	var keychain := FakeKeychain.new()
	var api := _api(keychain)
	api.restore()
	assert_false(api.has_device_login())
	assert_true(keychain.items.is_empty())
	assert_false(FileAccess.file_exists(DEVICE))
	_clean()
