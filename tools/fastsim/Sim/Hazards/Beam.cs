namespace FastSim;

/// Port of sim/hazards/beam.gd.
public class Beam : Hazard
{
    public static class State
    {
        public const long OFF = 0, WARN = 1, ON = 2;
    }

    public const long ROWS = 4;
    public const long PERIOD = 180;
    public const long WARN_TICKS = 40;
    public const long ON_TICKS = 50;
    public const long START_DELAY = 20;
    public const long BAND_TOP = 130 * SimConfig.SUB;
    public const long SPAN = 480 * SimConfig.SUB;
    public const long JITTER = 40 * SimConfig.SUB;
    public const long HALF_H = 6 * SimConfig.SUB;
    public const long YIELD_GAP = 2 * SimConfig.BIRD_RADIUS + 8 * SimConfig.SUB;
    public const long YIELD_LEAD = 20;

    public List<long> rows = new();
    public List<long> delays = new();
    public long warn_ticks = WARN_TICKS;
    public bool yields = false;
    public List<long> skip = new();

    public Beam(long count = ROWS, long p_warn = WARN_TICKS, bool p_yields = false)
    {
        kind = "beam";
        for (long i = 0; i < count; i++)
        {
            rows.Add(0);
            delays.Add(0);
            skip.Add(0);
        }
        warn_ticks = p_warn;
        yields = p_yields;
    }

    public override Hazard clone_deep()
    {
        var c = (Beam)MemberwiseClone();
        c.rows = new List<long>(rows);
        c.delays = new List<long>(delays);
        c.skip = new List<long>(skip);
        return c;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        long n = rows.Count;
        long band = SPAN / n;
        long stagger = PERIOD / n;
        var order = new List<long>();
        for (long i = 0; i < n; i++) order.Add(i);
        // Fisher-Yates: the order rows fire in.
        for (long i = n - 1; i > 0; i--)
        {
            long j = rng.next_below(i + 1);
            long tmp = order[(int)i];
            order[(int)i] = order[(int)j];
            order[(int)j] = tmp;
        }
        for (long i = 0; i < n; i++)
        {
            rows[(int)i] = BAND_TOP + i * band + rng.next_below(JITTER + 1);
            delays[(int)i] = START_DELAY + order[(int)i] * stagger;
        }
    }

    public long cycle_pos(long i)
    {
        if (t < delays[(int)i]) return -1;
        return G.posmod(t - delays[(int)i], PERIOD);
    }

    public long state(long i)
    {
        long p = cycle_pos(i);
        if (p < 0 || p >= warn_ticks + ON_TICKS || skip[(int)i] == 1) return State.OFF;
        return p < warn_ticks ? State.WARN : State.ON;
    }

    public override void step(GameSim sim)
    {
        if (!yields) return;
        for (long i = 0; i < rows.Count; i++)
        {
            if (cycle_pos(i) != 0) continue;
            skip[(int)i] = 0;
            foreach (Hazard h in sim.room.hazards)
            {
                if (h == this || !h.alive) continue;
                long half = HALF_H + YIELD_GAP;
                if (h.near_row(sim, rows[(int)i], half, warn_ticks - YIELD_LEAD, warn_ticks + ON_TICKS))
                    skip[(int)i] = 1;
            }
        }
    }

    public long warn_progress(long i)
    {
        if (state(i) != State.WARN) return 0;
        return SimTrig.ONE * cycle_pos(i) / warn_ticks;
    }

    public long live_count()
    {
        long n = 0;
        for (long i = 0; i < rows.Count; i++)
            if (state(i) == State.ON) n += 1;
        return n;
    }

    public long beam_left(GameSim sim, long i)
    {
        long left = sim.room.wall_left();
        if (ExitZone.side(sim) == 0 && _crosses_exit(sim, i)) return ExitZone.right(sim) + 1;
        return left;
    }

    public long beam_right(GameSim sim, long i)
    {
        long right = sim.room.wall_right();
        if (ExitZone.side(sim) == 1 && _crosses_exit(sim, i)) return ExitZone.left(sim) - 1;
        return right;
    }

    bool _crosses_exit(GameSim sim, long i) =>
        ExitZone.hits_rect(sim, sim.room.wall_left(), rows[(int)i] - HALF_H, sim.room.wall_right(), rows[(int)i] + HALF_H);

    public override bool kills(GameSim sim)
    {
        for (long i = 0; i < rows.Count; i++)
        {
            if (state(i) == State.ON)
            {
                long y0 = rows[(int)i] - HALF_H;
                long y1 = rows[(int)i] + HALF_H;
                if (sim.bird_touches_rect(beam_left(sim, i), y0, beam_right(sim, i), y1)) return true;
            }
        }
        return false;
    }

    public override long checksum(long h)
    {
        long out_ = mix_all(mix_all(h, rows), delays);
        if (yields) out_ = mix_all(out_, skip);
        return out_;
    }
}
