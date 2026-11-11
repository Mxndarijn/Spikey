class_name QuickSearch
extends SurvivalSearch
## SurvivalSearch with a coarse (fast) first pass. A line it finds is a real
## way through; only when it finds none does the full search run. Used by the
## Floating Isles check (tools/fastsim/Checks.cs Isles, C# run_quick).


func run(sim: GameSim, ticks: int) -> bool:
	level = -1
	_bucket_h = 10 * SimConfig.SUB
	_bucket_vy = -SimConfig.FLAP_VY / 2
	_speed_buckets = 4
	if _run_once(sim, ticks):
		return true
	return super.run(sim, ticks)
