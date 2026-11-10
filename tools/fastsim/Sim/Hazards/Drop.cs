namespace FastSim;

/// Port of sim/hazards/drop.gd.
public sealed class Drop : Hazard
{
    public static class Phase { public const long WAIT = 0, WARN = 1, FALL = 2; }

    public const long SUB = SimConfig.SUB;
    public const long RADIUS = 10 * SUB;
    public const long WARN = 45;
    public const long MIN_X = 50 * SUB;
    public const long MAX_X = 310 * SUB;
    public const long TOP = SimConfig.KILL_TOP;

    public long x = 0;
    public long y = TOP;
    public long phase = Phase.WAIT;
    public long timer = 0;
    public long speed = 10 * SUB;
    public long gap = 25;
    public long delay = 0;

    public SimRng _rng = new SimRng();

    public Drop(long p_delay = 0, long p_speed = 10 * SUB, long p_gap = 25)
    {
        kind = "drop";
        delay = p_delay;
        speed = p_speed;
        gap = p_gap;
    }

    public override Hazard clone_deep()
    {
        var c = (Drop)MemberwiseClone();
        c._rng = _rng.Clone();
        return c;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        _rng.reseed(rng.next_u32());
        phase = Phase.WAIT;
        timer = delay;
        y = TOP;
    }

    public override void step(GameSim sim)
    {
        switch (phase)
        {
            case Phase.WAIT:
                timer -= 1;
                if (timer <= 0)
                {
                    phase = Phase.WARN;
                    timer = WARN;
                    x = MIN_X + _rng.next_below(MAX_X - MIN_X + 1);
                    y = TOP;
                }
                break;
            case Phase.WARN:
                timer -= 1;
                if (timer <= 0)
                {
                    phase = Phase.FALL;
                    y = TOP;
                }
                break;
            case Phase.FALL:
                y += speed;
                if (y - RADIUS > SimConfig.WORLD_H)
                {
                    phase = Phase.WAIT;
                    timer = gap;
                }
                break;
        }
    }

    public bool warning() => phase == Phase.WARN;

    public bool falling() => phase == Phase.FALL;

    public long warn_progress()
    {
        if (phase != Phase.WARN) return 0;
        return SimTrig.ONE * (WARN - timer) / WARN;
    }

    public override bool kills(GameSim sim) => phase == Phase.FALL && sim.bird_touches_circle(x, y, RADIUS);

    public override long checksum(long h) => mix_all(h, x, y, phase, timer, speed, gap, delay, _rng.state_checksum());
}
