namespace FastSim;

/// Port of sim/hazards/stalker.gd.
public class Stalker : Hazard
{
    public const long DEPTH = SimConfig.SPIKE_DEPTH;
    public const long HALF_BASE = SimConfig.SPIKE_HALF_BASE;
    public const long HALF_H = 2 * SimConfig.SPIKE_HALF_BASE;
    public const long MAX_SPEED = 80;
    public const long MIN_Y = SimConfig.SLOT_TOP + HALF_H;
    public const long MAX_Y = SimConfig.SLOT_TOP + SimConfig.SLOT_COUNT * SimConfig.SLOT_SIZE - HALF_H;

    public long side = 1;
    public long y = 0;
    public long x = 0;

    public Stalker()
    {
        kind = "stalker";
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        side = sim.state.vx > 0 ? 1 : 0;
        y = MIN_Y + rng.next_below(MAX_Y - MIN_Y + 1);
        x = base_x(sim);
    }

    public override void step(GameSim sim)
    {
        side = sim.state.vx > 0 ? 1 : 0;
        long target = G.clampi(sim.state.y, MIN_Y, MAX_Y);
        y += G.clampi(target - y, -MAX_SPEED, MAX_SPEED);
        if (side == ExitZone.side(sim))
            y = ExitZone.clear_y(sim, y, HALF_H, MIN_Y, MAX_Y);
        x = base_x(sim);
    }

    public long base_x(GameSim sim) => side == 0 ? sim.room.wall_left() : sim.room.wall_right();

    public long dir() => side == 0 ? 1 : -1;

    public override bool kills(GameSim sim)
    {
        long bx = x;
        long tip = bx + dir() * DEPTH;
        long r = SimConfig.BIRD_RADIUS;
        long cy = y - HALF_BASE;
        if (SimMath.circle_hits_triangle(
                sim.state.x, sim.state.y, r, bx, cy - HALF_BASE, bx, cy + HALF_BASE, tip, cy))
            return true;
        cy = y + HALF_BASE;
        if (SimMath.circle_hits_triangle(
                sim.state.x, sim.state.y, r, bx, cy - HALF_BASE, bx, cy + HALF_BASE, tip, cy))
            return true;
        return false;
    }

    public override long checksum(long h) => mix_all(h, side, y, x);
}
