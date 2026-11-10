class_name TestCase
extends RefCounted
## Base class for tests. Methods starting with "test_" are run by tests/run_tests.gd.
## Any engine or script error logged during a test also fails it.

var failures: Array[String] = []
## What one part of a split test found, for its combine_ check (tests/run_tests.gd).
var report := {}


func fail(message: String) -> void:
	failures.append(message)


func assert_true(condition: bool, message: String = "expected true") -> void:
	if not condition:
		fail(message)


func assert_false(condition: bool, message: String = "expected false") -> void:
	if condition:
		fail(message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if not _same(actual, expected):
		fail("%sexpected %s, got %s" % [_prefix(message), str(expected), str(actual)])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	if _same(actual, unexpected):
		fail("%sdid not expect %s" % [_prefix(message), str(unexpected)])


func assert_between(value: int, low: int, high: int, message: String = "") -> void:
	if value < low or value > high:
		fail("%sexpected %d..%d, got %d" % [_prefix(message), low, high, value])


static func _same(a: Variant, b: Variant) -> bool:
	var numeric := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) != typeof(b) and not (typeof(a) in numeric and typeof(b) in numeric):
		return false
	return a == b


static func _prefix(message: String) -> String:
	return "" if message.is_empty() else message + ": "
