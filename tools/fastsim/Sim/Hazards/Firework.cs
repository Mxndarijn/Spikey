namespace FastSim;

/// Port of sim/hazards/firework.gd.
public sealed class Firework : Hazard
{
    public static class Phase { public const long PAD = 0, CLIMB = 1, BURST = 2, REST = 3; }

    public const long SUB = SimConfig.SUB;
    public const long ROCKET_RADIUS = 8 * SUB;
    public const long SPARK_RADIUS = 6 * SUB;
    public const long SPARKS = 8;
    public const long PAD = 60;
    public const long CLIMB_VY = 8 * SUB;
    public const long SPARK_SPEED = 4 * SUB;
    public const long BURST = 44;
    public const long SPARK_DEADLY = 30;
    public const long REST = 20;
    public const long MIN_X = 80 * SUB;
    public const long MAX_X = 280 * SUB;
    public const long MIN_BURST_Y = 170 * SUB;
    public const long MAX_BURST_Y = 380 * SUB;
    public const long PAD_Y = SimConfig.KILL_BOTTOM - ROCKET_RADIUS;

    public long x = 0;
    public long y = PAD_Y;
    public long burst_y = 0;
    public long phase = Phase.PAD;
    public long timer = 0;
    public long spread = 0;
    public long delay = 0;
    public SimRng _rng = new SimRng();

    public Firework(long p_delay = 0)
    {
        kind = "firework";
        delay = p_delay;
    }

    public override Hazard clone_deep()
    {
        var c = (Firework)MemberwiseClone();
        c._rng = _rng.Clone();
        return c;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        _rng.reseed(rng.next_u32());
        _load();
        timer += delay;
    }

    public void _load()
    {
        phase = Phase.PAD;
        timer = PAD;
        spread = 0;
        x = MIN_X + _rng.next_below(MAX_X - MIN_X + 1);
        burst_y = MIN_BURST_Y + _rng.next_below(MAX_BURST_Y - MIN_BURST_Y + 1);
        y = PAD_Y;
    }

    public override void step(GameSim sim)
    {
        switch (phase)
        {
            case Phase.PAD:
                timer -= 1;
                if (timer <= 0) phase = Phase.CLIMB;
                break;
            case Phase.CLIMB:
                y -= CLIMB_VY;
                if (y <= burst_y)
                {
                    y = burst_y;
                    phase = Phase.BURST;
                    timer = 0;
                    spread = 0;
                }
                break;
            case Phase.BURST:
                timer += 1;
                spread += SPARK_SPEED;
                if (timer >= BURST)
                {
                    phase = Phase.REST;
                    timer = REST;
                }
                break;
            case Phase.REST:
                timer -= 1;
                if (timer <= 0) _load();
                break;
        }
    }

    public long spark_alpha()
    {
        if (phase != Phase.BURST) return 0;
        if (timer < SPARK_DEADLY) return SimTrig.ONE;
        return SimTrig.ONE * (BURST - timer) / (BURST - SPARK_DEADLY);
    }

    public long fuse_progress()
    {
        if (phase != Phase.PAD) return 0;
        return SimTrig.ONE - SimTrig.ONE * G.mini(timer, PAD) / PAD;
    }

    public long spark_x(long i) => x + spread * SimTrig.cos_t(i * SimTrig.TURN / SPARKS) / SimTrig.ONE;

    public long spark_y(long i) => y + spread * SimTrig.sin_t(i * SimTrig.TURN / SPARKS) / SimTrig.ONE;

    public override bool kills(GameSim sim)
    {
        if (phase == Phase.CLIMB) return sim.bird_touches_circle(x, y, ROCKET_RADIUS);
        if (phase == Phase.BURST && timer < SPARK_DEADLY)
        {
            for (long i = 0; i < SPARKS; i++)
                if (sim.bird_touches_circle(spark_x(i), spark_y(i), SPARK_RADIUS)) return true;
        }
        return false;
    }

    public override long checksum(long h) => mix_all(h, x, y, burst_y, phase, timer, spread, delay, _rng.state_checksum());
}
