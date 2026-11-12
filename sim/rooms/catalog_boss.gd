extends RefCounted
## Rooms batch: bosses. The exit at every SimConfig.BOSS_EVERY points leads
## into one of these (RoomCatalog.pick_boss); the usual picker never picks
## them. Each is one boss hazard (sim/hazards/boss.gd) in a cage with few wall
## spikes: the boss is the threat. Order is part of the rules (see RoomCatalog).

const BossWatcher := preload("res://sim/hazards/boss_watcher.gd")
const BossCrusher := preload("res://sim/hazards/boss_crusher.gd")
const BossSaw := preload("res://sim/hazards/boss_saw.gd")

## Wall spikes per wall at tier 1 (RoomRuntime.spike_bonus adds the tier's).
const SPIKES := 3


static func defs() -> Array[RoomDef]:
	var out: Array[RoomDef] = []
	out.append(_boss("boss_watcher", func() -> Hazard: return BossWatcher.new()))
	out.append(_boss("boss_crusher", func() -> Hazard: return BossCrusher.new()))
	out.append(_boss("boss_saw", func() -> Hazard: return BossSaw.new()))
	return out


static func _boss(id: String, make: Callable) -> RoomDef:
	var def := RoomDef.new(id, "boss", SimConfig.BOSS_EVERY)
	def.boss = true
	def.max_spikes = SPIKES
	def.hazards.append(make)
	return def
