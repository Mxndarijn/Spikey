namespace FastSim;

/// Port of sim/hazards/edge_pad.gd.
public class EdgePad : Hazard
{
    public const long WIDTH = 96 * SimConfig.SUB;
    public const long X_MIN = 30 * SimConfig.SUB;
    public const long X_MAX = SimConfig.WORLD_W - 30 * SimConfig.SUB - WIDTH;
    public const long GRACE = SimConfig.BIRD_RADIUS / 2;
    public const long CEILING_VY = -SimConfig.FLAP_VY * 3 / 5;
    public const long FLOOR_VY = -SimConfig.FLAP_VY * 6 / 5;

    public bool top = true;
    public long period = 300;
    public long phase = 0;
    public long since_bump = 1000;

    public EdgePad(bool p_top = true, long p_period = 300)
    {
        kind = "edge_pad";
        top = p_top;
        period = p_period;
    }

    public override void setup(GameSim _sim, SimRng rng)
    {
        phase = rng.next_below(period);
    }

    public override void step(GameSim _sim)
    {
        since_bump += 1;
    }

    public long x0() => X_MIN + SimTrig.ping_pong(t + phase, period, X_MAX - X_MIN);

    public long x1() => x0() + WIDTH;

    public long line_y() => top ? SimConfig.KILL_TOP : SimConfig.KILL_BOTTOM;

    public bool covers(long x) => x >= x0() - GRACE && x <= x1() + GRACE;

    public override bool guards_edge(GameSim sim, bool p_top)
    {
        if (p_top != top || !covers(sim.state.x)) return false;
        long r = SimConfig.BIRD_RADIUS;
        if (top)
        {
            sim.state.y = G.maxi(sim.state.y, SimConfig.KILL_TOP + r + 1);
            sim.state.vy = CEILING_VY;
        }
        else
        {
            sim.state.y = G.mini(sim.state.y, SimConfig.KILL_BOTTOM - r - 1);
            sim.state.vy = -FLOOR_VY;
        }
        since_bump = 0;
        return true;
    }

    public override long checksum(long h) => mix_all(h, G.B(top), period, phase, since_bump);
}
