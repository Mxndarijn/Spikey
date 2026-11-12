namespace FastSim;

/// Port of sim/hazards/wind.gd.
public class Wind : Hazard
{
    public static class Mode { public const long STEADY = 0, SPLIT = 1, GUSTY = 2; }

    public const long SUB = SimConfig.SUB;
    public const long PUSH = SimConfig.SPEED_X / 4;
    public const long GUST_PERIOD = 320;
    public const long GUST_CALM = 110;
    public const long GUST_WARN = 60;

    public long mode = Mode.STEADY;
    public long a_y0 = 250 * SUB;
    public long a_y1 = 370 * SUB;
    public long a_dir = 1;
    public long b_y0 = 0;
    public long b_y1 = 0;
    public long b_dir = 0;

    public Wind(long p_mode = -1)
    {
        kind = "wind";
        mode = p_mode;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        if (mode < 0)
        {
            switch (sim.room.variant_id())
            {
                case "split": mode = Mode.SPLIT; break;
                case "gusty": mode = Mode.GUSTY; break;
                default: mode = Mode.STEADY; break;
            }
        }
        a_dir = rng.next_below(2) == 0 ? 1 : -1;
        if (mode == Mode.SPLIT)
        {
            a_y0 = 180 * SUB;
            a_y1 = 280 * SUB;
            b_y0 = 400 * SUB;
            b_y1 = 500 * SUB;
            b_dir = -a_dir;
        }
    }

    public bool blowing()
    {
        if (mode != Mode.GUSTY) return true;
        return G.posmod(t, GUST_PERIOD) >= GUST_CALM + GUST_WARN;
    }

    public bool warning()
    {
        if (mode != Mode.GUSTY) return false;
        long p = G.posmod(t, GUST_PERIOD);
        return p >= GUST_CALM && p < GUST_CALM + GUST_WARN;
    }

    public override void touch(GameSim sim)
    {
        if (!blowing()) return;
        long y = sim.state.y;
        if (y >= a_y0 && y <= a_y1) sim.state.x += a_dir * PUSH;
        else if (b_dir != 0 && y >= b_y0 && y <= b_y1) sim.state.x += b_dir * PUSH;
    }

    public override long checksum(long h) => mix_all(h, mode, a_y0, a_y1, a_dir, b_y0, b_y1, b_dir);

    public override void warnings(GameSim sim, List<long> out_)
    {
        if (!warning()) return;
        long eta = GUST_CALM + GUST_WARN - G.posmod(t, GUST_PERIOD);
        long dur = GUST_PERIOD - GUST_CALM - GUST_WARN;
        add_warning(out_, 0, a_y0, SimConfig.WORLD_W, a_y1, eta, dur, WARN_PUSH);
        if (b_dir != 0) add_warning(out_, 0, b_y0, SimConfig.WORLD_W, b_y1, eta, dur, WARN_PUSH);
    }
}
