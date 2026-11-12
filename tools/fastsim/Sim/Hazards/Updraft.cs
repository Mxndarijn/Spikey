namespace FastSim;

/// Port of sim/hazards/updraft.gd.
public class Updraft : Hazard
{
    public const long SUB = SimConfig.SUB;
    public const long HALF_W = 60 * SUB;
    public const long LIFT = SimConfig.GRAVITY * 2 / 3;
    public const long HOVER = SimConfig.GRAVITY;
    public const long CHIMNEY = SimConfig.GRAVITY * 3 / 2;
    public const long STRONG = SimConfig.GRAVITY * 2;
    public const long GUST_OFF = 60;
    public const long GUST_WARN = SimConfig.ARRIVAL_BLIND;
    public const long GUST_ON = 90;
    public const long GUST_PERIOD = GUST_OFF + GUST_WARN + GUST_ON;

    public static class Gust { public const long NONE = 0, OFF = 1, WARN = 2, ON = 3; }

    public long x0 = 0;
    public long x1 = 0;
    public long half_w = HALF_W;
    public long lift = LIFT;
    public long drift_min = 0;
    public long drift_span = 0;
    public long gust = Gust.NONE;
    public long phase = 0;

    public Updraft(long p_center = SimConfig.WORLD_W / 2, long p_half_w = HALF_W, long p_lift = LIFT)
    {
        kind = "updraft";
        half_w = p_half_w;
        lift = p_lift;
        _place(p_center);
    }

    public Hazard drifting(long p_min, long p_span)
    {
        drift_min = p_min;
        drift_span = p_span;
        _place(p_min);
        return this;
    }

    public Hazard gusty()
    {
        gust = Gust.OFF;
        return this;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        if (drift_span > 0)
            phase = rng.next_below(_drift_period());
        else if (gust != Gust.NONE)
            phase = rng.next_below(GUST_OFF);
        _update();
    }

    public override void step(GameSim sim)
    {
        _update();
    }

    public bool blowing() => gust == Gust.NONE || gust == Gust.ON;

    public bool inside(GameSim sim) => sim.state.x >= x0 && sim.state.x <= x1;

    public override void touch(GameSim sim)
    {
        if (blowing() && inside(sim))
        {
            long vy = sim.state.vy - lift;
            sim.state.vy = G.clampi(vy, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY);
        }
    }

    public long gust_step() => G.posmod(t + phase, GUST_PERIOD);

    void _update()
    {
        if (drift_span > 0)
            _place(drift_min + SimTrig.ping_pong(t + phase, _drift_period(), drift_span));
        if (gust != Gust.NONE)
        {
            long m = gust_step();
            if (m < GUST_OFF)
                gust = Gust.OFF;
            else if (m < GUST_OFF + GUST_WARN)
                gust = Gust.WARN;
            else
                gust = Gust.ON;
        }
    }

    long _drift_period() => 2 * drift_span / SUB;

    void _place(long center)
    {
        x0 = center - half_w;
        x1 = center + half_w;
    }

    public override long checksum(long h) => mix_all(h, x0, x1, lift, drift_min, drift_span, gust, phase);

    public override void warnings(GameSim sim, List<long> out_)
    {
        if (gust != Gust.WARN) return;
        long eta = GUST_OFF + GUST_WARN - gust_step();
        add_warning(out_, x0, SimConfig.KILL_TOP, x1, SimConfig.KILL_BOTTOM, eta, GUST_ON, WARN_PUSH);
    }
}
