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

    public long center_x = CENTER_X;
    public long ring_min = RING_MIN;
    public long ring_max = RING_MAX;
    public long saw_radius = SAW_RADIUS;
    public long period = PERIOD;
    public long fixed_count = 0;
    public long ry_num = 1;
    public long ry_den = 1;
    public long inner_count = 0;
    public long inner_min = 0;
    public long inner_max = 0;
    public long inner_saw = 0;

    public long center_y = CENTER_Y;
    public long count = 4;
    public long phase = 0;
    public long dir = 1;
    public long radius = RING_MIN;
    public long inner_radius = 0;
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
        long clear = arrival_clear();
        if (sim.state.started && y - CENTER_Y > -clear && y - CENTER_Y < clear + HOP)
        {
            center_y = y + clear;
            if (center_y + reach_y() > SimConfig.KILL_BOTTOM) center_y = y - clear - HOP;
        }
        count = 4 + rng.next_below(2);
        phase = rng.next_below(SimTrig.TURN);
        dir = rng.next_below(2) == 0 ? 1 : -1;
        if (fixed_count > 0) count = fixed_count;
        _resize(xs, count + inner_count);
        _resize(ys, count + inner_count);
        _place();
    }

    public long reach_y()
    {
        long out_ = ring_max * ry_num / ry_den + saw_radius;
        if (inner_count > 0) out_ = G.maxi(out_, inner_max * ry_num / ry_den + inner_saw);
        return out_;
    }

    public long arrival_clear() => reach_y() + SimConfig.BIRD_RADIUS + 4 * SimConfig.SUB;

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

    public static long scaled(long tick, long lo, long hi) =>
        lo + (hi - lo) * (radius_at(tick) - RING_MIN) / (RING_MAX - RING_MIN);

    public void _place()
    {
        radius = scaled(t, ring_min, ring_max);
        angle = G.posmod(phase + dir * (t * SimTrig.TURN / period), SimTrig.TURN);
        for (long i = 0; i < count; i++)
        {
            long a = angle + i * SimTrig.TURN / count;
            xs[(int)i] = center_x + radius * SimTrig.cos_t(a) / SimTrig.ONE;
            ys[(int)i] = center_y + radius * SimTrig.sin_t(a) * ry_num / ry_den / SimTrig.ONE;
        }
        if (inner_count == 0) return;
        inner_radius = scaled(t, inner_min, inner_max);
        long back = G.posmod(phase - dir * (t * SimTrig.TURN / period), SimTrig.TURN);
        for (long i = 0; i < inner_count; i++)
        {
            long a = back + i * SimTrig.TURN / inner_count;
            xs[(int)(count + i)] = center_x + inner_radius * SimTrig.cos_t(a) / SimTrig.ONE;
            ys[(int)(count + i)] = center_y + inner_radius * SimTrig.sin_t(a) * ry_num / ry_den / SimTrig.ONE;
        }
    }

    public long saw_r(long i) => i < count ? saw_radius : inner_saw;

    public override bool kills(GameSim sim)
    {
        for (long i = 0; i < count + inner_count; i++)
            if (sim.bird_touches_circle(xs[(int)i], ys[(int)i], saw_r(i))) return true;
        return false;
    }

    public override long checksum(long h)
    {
        long out_ = mix_all(h, count, phase, dir, radius, angle, center_y);
        for (long i = 0; i < count; i++)
            out_ = mix_all(out_, xs[(int)i], ys[(int)i]);
        if (inner_count > 0 || center_x != CENTER_X || period != PERIOD || ry_num != ry_den)
        {
            out_ = mix_all(out_, center_x, period, ry_num, ry_den, inner_count, inner_radius);
            for (long i = 0; i < inner_count; i++)
                out_ = mix_all(out_, xs[(int)(count + i)], ys[(int)(count + i)]);
        }
        return out_;
    }
}
