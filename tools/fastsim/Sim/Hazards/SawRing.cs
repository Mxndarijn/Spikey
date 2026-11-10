namespace FastSim;

/// Port of sim/hazards/saw_ring.gd.
public class SawRing : Hazard
{
    public const long CENTER_X = 180 * SimConfig.SUB;
    public const long CENTER_Y = 320 * SimConfig.SUB;
    public const long SAW_RADIUS = 18 * SimConfig.SUB;
    public const long RING_MIN = 50 * SimConfig.SUB;
    public const long RING_MAX = 92 * SimConfig.SUB;
    public const long HOLD = 60;
    /// Grow and shrink take 1.5 s each (playtest: 1 s came back too fast).
    public const long MOVE = 90;
    public const long CYCLE = 2 * (HOLD + MOVE);
    public const long PERIOD = 300;
    public const long ARRIVAL_CLEAR = RING_MAX + SAW_RADIUS + SimConfig.BIRD_RADIUS + 4 * SimConfig.SUB;
    public const long HOP = 64 * SimConfig.SUB;

    public long center_y = CENTER_Y;
    public long count = 4;
    public long phase = 0;
    public long dir = 1;
    public long radius = RING_MIN;
    public long angle = 0;
    public List<long> xs = new();
    public List<long> ys = new();

    public SawRing()
    {
        kind = "saw_ring";
    }

    public override Hazard clone_deep()
    {
        var c = (SawRing)MemberwiseClone();
        c.xs = new List<long>(xs);
        c.ys = new List<long>(ys);
        return c;
    }

    static void _resize(List<long> xs, long n)
    {
        while (xs.Count > n) xs.RemoveAt(xs.Count - 1);
        while (xs.Count < n) xs.Add(0);
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        center_y = CENTER_Y;
        long y = sim.state.y;
        if (sim.state.started && y - CENTER_Y > -ARRIVAL_CLEAR && y - CENTER_Y < ARRIVAL_CLEAR + HOP)
        {
            center_y = y + ARRIVAL_CLEAR;
            if (center_y + RING_MAX + SAW_RADIUS > SimConfig.KILL_BOTTOM) center_y = y - ARRIVAL_CLEAR - HOP;
        }
        count = 4 + rng.next_below(2);
        phase = rng.next_below(SimTrig.TURN);
        dir = rng.next_below(2) == 0 ? 1 : -1;
        _resize(xs, count);
        _resize(ys, count);
        _place();
    }

    public override void step(GameSim sim) => _place();

    public static long radius_at(long tick)
    {
        long p = G.posmod(tick, CYCLE);
        long span = RING_MAX - RING_MIN;
        if (p < HOLD) return RING_MIN;
        p -= HOLD;
        if (p < MOVE) return RING_MIN + span * p / MOVE;
        p -= MOVE;
        if (p < HOLD) return RING_MAX;
        p -= HOLD;
        return RING_MAX - span * p / MOVE;
    }

    public void _place()
    {
        radius = radius_at(t);
        angle = G.posmod(phase + dir * (t * SimTrig.TURN / PERIOD), SimTrig.TURN);
        for (long i = 0; i < count; i++)
        {
            long a = angle + i * SimTrig.TURN / count;
            xs[(int)i] = CENTER_X + radius * SimTrig.cos_t(a) / SimTrig.ONE;
            ys[(int)i] = center_y + radius * SimTrig.sin_t(a) / SimTrig.ONE;
        }
    }

    public override bool kills(GameSim sim)
    {
        for (long i = 0; i < count; i++)
            if (sim.bird_touches_circle(xs[(int)i], ys[(int)i], SAW_RADIUS)) return true;
        return false;
    }

    public override long checksum(long h)
    {
        long out_ = mix_all(h, count, phase, dir, radius, angle, center_y);
        for (long i = 0; i < count; i++)
            out_ = mix_all(out_, xs[(int)i], ys[(int)i]);
        return out_;
    }
}
