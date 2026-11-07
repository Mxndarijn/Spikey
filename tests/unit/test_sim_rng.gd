extends TestCase


## Reference values from an independent Python implementation of the same
## seeding + xoshiro128**. If this fails, every replay ever recorded breaks.
func test_matches_reference_sequence() -> void:
	var rng := SimRng.new(12345)
	var got: Array[int] = []
	for i in 5:
		got.append(rng.next_u32())
	assert_eq(got, [3793928492, 3686016036, 1114097809, 3620992470, 197472287])


func test_seed_zero_is_valid() -> void:
	var rng := SimRng.new(0)
	assert_eq(rng.next_u32(), 310244528)
	assert_eq(rng.next_u32(), 2906165450)


func test_same_seed_same_sequence() -> void:
	var a := SimRng.new(987654321)
	var b := SimRng.new(987654321)
	for i in 100:
		assert_eq(a.next_u32(), b.next_u32())


func test_values_stay_32_bit() -> void:
	var rng := SimRng.new(-42)
	for i in 1000:
		assert_between(rng.next_u32(), 0, SimRng.MASK)


func test_next_below_in_range_and_covers_all() -> void:
	var rng := SimRng.new(7)
	var seen := {}
	for i in 2000:
		var v := rng.next_below(13)
		assert_between(v, 0, 12)
		seen[v] = true
	assert_eq(seen.size(), 13)
