class_name SimRng
extends RefCounted
## Deterministic xoshiro128** generator on 32-bit values held in 64-bit ints.
## Same seed gives the same sequence on every platform. Never use Godot's
## built-in random functions inside sim/.

const MASK := 0xFFFFFFFF

var _s0 := 0
var _s1 := 0
var _s2 := 0
var _s3 := 0


func _init(seed_value: int = 0) -> void:
	reseed(seed_value)


func reseed(seed_value: int) -> void:
	var x := (seed_value ^ 0x9E3779B9) & MASK
	x ^= (seed_value >> 32) & MASK
	if x == 0:
		x = 0x6D2B79F5
	x = _xorshift32(x)
	_s0 = x
	x = _xorshift32(x)
	_s1 = x
	x = _xorshift32(x)
	_s2 = x
	x = _xorshift32(x)
	_s3 = x


## Next value in [0, 2^32).
func next_u32() -> int:
	var result := (_rotl((_s1 * 5) & MASK, 7) * 9) & MASK
	var t := (_s1 << 9) & MASK
	_s2 ^= _s0
	_s3 ^= _s1
	_s1 ^= _s2
	_s0 ^= _s3
	_s2 ^= t
	_s3 = _rotl(_s3, 11)
	return result


## Next value in [0, n). n must be > 0.
func next_below(n: int) -> int:
	assert(n > 0, "next_below needs n > 0")
	return next_u32() % n


func state_checksum() -> int:
	return SimHash.mix(SimHash.mix(SimHash.mix(SimHash.mix(SimHash.SEED, _s0), _s1), _s2), _s3)


static func _xorshift32(v: int) -> int:
	var x := v
	x ^= (x << 13) & MASK
	x ^= x >> 17
	x ^= (x << 5) & MASK
	return x


static func _rotl(x: int, k: int) -> int:
	return ((x << k) | (x >> (32 - k))) & MASK
