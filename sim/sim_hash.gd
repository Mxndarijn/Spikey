class_name SimHash
extends RefCounted
## 32-bit FNV-1a style mixing for state checksums.

const SEED := 0x811C9DC5
const PRIME := 16777619
const MASK := 0xFFFFFFFF


static func mix(h: int, value: int) -> int:
	return ((h ^ (value & MASK)) * PRIME) & MASK
