class_name VariantParams
extends RefCounted
## What a GENERATED room variant (RoomVariant.recipe) builds its layout from,
## when the room starts. Read-only for the recipe except `add`, which builds
## a hazard into the room. Gameplay data: integers only.
##
## The entry height is the PLANNED one (SimState.anchor_y out of a portal: the
## centre of the exit taken, from the seed), never the bird's own height, so
## every player of a seed gets the same layout (same-seed rule, 1v1). The bird
## comes out within SimConfig.EXIT_FIT of it.

## Margin kept between the hold band and anything deadly.
const MARGIN := 6 * SimConfig.SUB

var sim: GameSim
## The room's RNG: draw everything from it, in a fixed order.
var rng: SimRng
## Out of a portal (true) or at the start of a run / practice (false).
var arriving := false
## Planned entry height (anchor_y out of a portal, else FairLanes.entry_y).
var entry_y := 0
## How far from entry_y the bird may be (EXIT_FIT out of a portal, else 0).
var spread := 0
## Difficulty: the run's score at the room start, and its level (one per
## SimConfig.BOSS_EVERY points), so a recipe can scale.
var score := 0
var level := 0
## Which try this is (0 first); RoomRuntime retries with the next draws.
var attempt := 0
## The last try: build the recipe's safe layout, which is not checked.
var fallback := false


static func make(p_sim: GameSim, p_rng: SimRng) -> VariantParams:
	var p := VariantParams.new()
	p.sim = p_sim
	p.rng = p_rng
	p.arriving = p_sim.state.started
	p.entry_y = FairLanes.entry_y(p_sim)
	p.spread = SimConfig.EXIT_FIT if p.arriving else 0
	p.score = p_sim.state.score
	p.level = p.score / SimConfig.BOSS_EVERY
	return p


## Builds `h` into the room: added to its hazards and set up from the room RNG.
func add(h: Hazard) -> Hazard:
	sim.room.hazards.append(h)
	h.setup(sim, rng)
	return h


## Builds every factory's hazard into the room, in order (add).
func add_all(factories: Array[Callable]) -> Array[Hazard]:
	var out: Array[Hazard] = []
	for f in factories:
		out.append(add(f.call()))
	return out


## A centre height for something reaching `ext` up and down that keeps it off
## the hold band: `cy` itself if it already is, else the side (above or below
## the band) nearer `cy` that fits in the cage; -1 if neither does.
func clear_center(cy: int, ext: int) -> int:
	if cy - ext >= hold_bottom() or cy + ext <= hold_top():
		return cy
	var above := hold_top() - ext
	var below := hold_bottom() + ext
	var fits_above := above - ext >= SimConfig.KILL_TOP
	var fits_below := below + ext <= SimConfig.KILL_BOTTOM
	if fits_above and (not fits_below or absi(above - cy) <= absi(below - cy)):
		return above
	if fits_below:
		return below
	return -1


## The highest and lowest bird centre out of the exit (clamped like the bird,
## GameSim._arrival_y).
func bird_top() -> int:
	return GameSim._arrival_y(entry_y - spread)


func bird_bottom() -> int:
	return GameSim._arrival_y(entry_y + spread)


## The band a bird holding its height sweeps out of the exit, edges included
## (it hops FairLanes.FIRST_HOP over the height it holds): [top, bottom], with
## MARGIN. Gravity turned round (Flip) hops the other way.
func hold_top() -> int:
	if sim.room.gravity < 0:
		return bird_top() - SimConfig.BIRD_RADIUS - MARGIN
	return bird_top() - FairLanes.FIRST_HOP - SimConfig.BIRD_RADIUS - MARGIN


func hold_bottom() -> int:
	if sim.room.gravity < 0:
		return bird_bottom() + FairLanes.FIRST_HOP + SimConfig.BIRD_RADIUS + MARGIN
	return bird_bottom() + SimConfig.BIRD_RADIUS + MARGIN
