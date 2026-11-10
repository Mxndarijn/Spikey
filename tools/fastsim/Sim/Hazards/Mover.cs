namespace FastSim;

/// Port of sim/hazards/mover.gd.
public class Mover : Hazard
{
    public const long SUB = SimConfig.SUB;
    public const long RADIUS = 12 * SUB;
    public const long START_MARGIN = 10 * SUB;
    public const long PHASE_TRIES = 16;
    public const long ARRIVAL_TRIES = 60;
    public const long CENTER_X = 180 * SUB;
    public const long CENTER_Y = 320 * SUB;
    // Figure-eight.
    public const long LOOP_W = 80 * SUB;
    public const long LOOP_H = 90 * SUB;
    public const long LOOP_PERIOD = 480;
    // Wave.
    public const long WAVE_MIN_X = 96 * SUB;
    public const long WAVE_MAX_X = 264 * SUB;
    public const long WAVE_PERIOD = 300;
    public const long WAVE_AMP = 70 * SUB;
    public const long WAVE_TURNS = 3;
    public const long WAVE_SPACING = 22;
    public const long CHASE_DEN = 10;
    public const long CHASE_STEP = 1;
    public const long CHASE_LAPS = 3;

    public string mode = "figure8";
    public long count = 3;
    public long loop_w = LOOP_W;
    public long loop_h = LOOP_H;
    public long loop_period = LOOP_PERIOD;
    public bool chase = false;
    public long phase = 0;
    public List<long> xs = new();
    public List<long> ys = new();
    public List<long> facing = new();

    public Mover(string p_mode = "figure8", long p_count = 3)
    {
        kind = "mover";
        mode = p_mode;
        count = p_count;
        for (long i = 0; i < count; i++)
        {
            xs.Add(0);
            ys.Add(0);
            facing.Add(1);
        }
    }

    public override Hazard clone_deep()
    {
        var c = (Mover)MemberwiseClone();
        c.xs = new List<long>(xs);
        c.ys = new List<long>(ys);
        c.facing = new List<long>(facing);
        return c;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        phase = rng.next_below(period());
        var path = FairLanes.start_path(sim);
        var arrival = sim.state.started ? FairLanes.arrival_path(sim) : new List<long>();
        long first = phase;
        long tries = sim.state.started ? ARRIVAL_TRIES : PHASE_TRIES;
        long pick = phase;
        bool settled = false;
        for (long k = 0; k < tries; k++)
        {
            phase = (first + k * period() / tries) % period();
            if (sim.state.started)
            {
                long clear = _arrival_clear(arrival);
                if (clear >= FairLanes.ARRIVAL_PATH_TICKS)
                {
                    pick = phase;
                    break;
                }
                if (clear >= FairLanes.ARRIVAL_PATH_MIN && !settled)
                {
                    pick = phase;
                    settled = true;
                }
            }
            else if (!_meets_path(path)) break;
        }
        if (sim.state.started) phase = pick;
        _place();
    }

    public long _arrival_clear(List<long> arrival)
    {
        long keep = t;
        long out_ = FairLanes.ARRIVAL_PATH_TICKS;
        for (long k = 0; k < FairLanes.ARRIVAL_PATH_TICKS; k++)
        {
            t = k;
            _place();
            for (long c = 0; c < count; c++)
                if (FairLanes.arrival_path_hits(arrival, k, xs[(int)c], ys[(int)c], RADIUS)) out_ = k;
            if (out_ < FairLanes.ARRIVAL_PATH_TICKS) break;
        }
        t = keep;
        return out_;
    }

    public bool _meets_path(List<long> path)
    {
        long keep = t;
        long reach = SimConfig.BIRD_RADIUS + RADIUS + START_MARGIN;
        bool hit = false;
        for (long i = 0; i < path.Count; i += 2)
        {
            t = i / 2 + 1;
            _place();
            for (long c = 0; c < count; c++)
            {
                long dx = xs[(int)c] - path[(int)i];
                long dy = ys[(int)c] - path[(int)i + 1];
                if (dx * dx + dy * dy < reach * reach) hit = true;
            }
            if (hit) break;
        }
        t = keep;
        return hit;
    }

    public long period() => mode == "figure8" ? loop_period : WAVE_PERIOD;

    public override void step(GameSim sim) => _place();

    public long chase_tenths(long tick)
    {
        long start = 0;
        for (long k = 0; k < CHASE_LAPS; k++)
        {
            long num = CHASE_DEN + k * CHASE_STEP;
            long lap = (loop_period * CHASE_DEN + num - 1) / num;
            if (tick < start + lap) return k * loop_period * CHASE_DEN + (tick - start) * num;
            start += lap;
        }
        long top = CHASE_DEN + CHASE_LAPS * CHASE_STEP;
        return CHASE_LAPS * loop_period * CHASE_DEN + (tick - start) * top;
    }

    public void _place()
    {
        for (long i = 0; i < count; i++)
        {
            long nx = 0;
            long ny = 0;
            if (mode == "figure8")
            {
                long k = (t + phase) * CHASE_DEN;
                if (chase && i == count - 1) k = chase_tenths(t) + phase * CHASE_DEN;
                long a = k * SimTrig.TURN / (loop_period * CHASE_DEN) + i * SimTrig.TURN / count;
                nx = CENTER_X + loop_w * SimTrig.sin_t(a) / SimTrig.ONE;
                ny = CENTER_Y + loop_h * SimTrig.sin_t(2 * a) / SimTrig.ONE;
            }
            else
            {
                long k = t + phase - i * WAVE_SPACING;
                nx = WAVE_MIN_X + SimTrig.ping_pong(k, WAVE_PERIOD, WAVE_MAX_X - WAVE_MIN_X);
                long a = k * SimTrig.TURN * WAVE_TURNS / WAVE_PERIOD;
                ny = CENTER_Y + WAVE_AMP * SimTrig.sin_t(a) / SimTrig.ONE;
            }
            if (nx != xs[(int)i]) facing[(int)i] = nx > xs[(int)i] ? 1 : -1;
            xs[(int)i] = nx;
            ys[(int)i] = ny;
        }
    }

    public override bool kills(GameSim sim)
    {
        for (long i = 0; i < count; i++)
            if (sim.bird_touches_circle(xs[(int)i], ys[(int)i], RADIUS)) return true;
        return false;
    }

    public override long checksum(long h)
    {
        long out_ = mix_all(h, count, phase, G.B(mode == "figure8"));
        if (chase || loop_w != LOOP_W || loop_h != LOOP_H || loop_period != LOOP_PERIOD)
            out_ = mix_all(out_, G.B(chase), loop_w, loop_h, loop_period);
        for (long i = 0; i < count; i++)
            out_ = mix_all(out_, xs[(int)i], ys[(int)i], facing[(int)i]);
        return out_;
    }
}
