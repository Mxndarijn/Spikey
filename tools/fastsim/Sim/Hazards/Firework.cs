namespace FastSim;

/// Port of sim/hazards/firework.gd.
public sealed class Firework : Hazard
{
    public static class Phase { public const long PAD = 0, CLIMB = 1, BURST = 2, REST = 3; }
    public static class Style { public const long RING = 0, DOUBLE = 1, CROSS = 2; }

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
    public const long ECHO = 16;
    public const long ARMS = 4;
    public const long ARM_SPARKS = 3;
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
    public long style = Style.RING;
    public long spent = 0;
    public SimRng _rng = new SimRng();

    public Firework(long p_delay = 0, long p_style = Style.RING)
    {
        kind = "firework";
        delay = p_delay;
        style = p_style;
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
        spent = 0;
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
                for (long i = 0; i < spark_count(); i++)
                    if (spark_live(i) && ExitZone.hits_circle(sim, spark_x(i), spark_y(i), SPARK_RADIUS))
                        spent |= 1L << (int)i;
                if (timer >= burst_steps())
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

    public long burst_steps() => style == Style.DOUBLE ? BURST + ECHO : BURST;

    public long spark_count()
    {
        switch (style)
        {
            case Style.DOUBLE: return 2 * SPARKS;
            case Style.CROSS: return ARMS * ARM_SPARKS;
        }
        return SPARKS;
    }

    public long spark_start(long i) => style == Style.DOUBLE && i >= SPARKS ? ECHO : 0;

    public long spark_age(long i) => timer - spark_start(i);

    public long spark_alpha() => spark_alpha_of(0);

    public long spark_alpha_of(long i)
    {
        long age = spark_age(i);
        if (phase != Phase.BURST || age < 0 || (spent & (1L << (int)i)) != 0) return 0;
        if (age < SPARK_DEADLY) return SimTrig.ONE;
        return G.maxi(0, SimTrig.ONE * (BURST - age) / (BURST - SPARK_DEADLY));
    }

    public bool spark_live(long i)
    {
        long age = spark_age(i);
        return phase == Phase.BURST && age >= 0 && age < SPARK_DEADLY && (spent & (1L << (int)i)) == 0;
    }

    public long spark_angle(long i)
    {
        switch (style)
        {
            case Style.DOUBLE: return (2 * (i % SPARKS) + (i >= SPARKS ? 1 : 0)) * SimTrig.TURN / (2 * SPARKS);
            case Style.CROSS: return (i / ARM_SPARKS) * SimTrig.TURN / ARMS;
        }
        return i * SimTrig.TURN / SPARKS;
    }

    public long spark_dist(long i)
    {
        switch (style)
        {
            case Style.DOUBLE: return G.maxi(0, spark_age(i)) * SPARK_SPEED;
            case Style.CROSS: return spread * (i % ARM_SPARKS + 1) / ARM_SPARKS;
        }
        return spread;
    }

    public long fuse_progress()
    {
        if (phase != Phase.PAD) return 0;
        return SimTrig.ONE - SimTrig.ONE * G.mini(timer, PAD) / PAD;
    }

    public long spark_x(long i) => x + spark_dist(i) * SimTrig.cos_t(spark_angle(i)) / SimTrig.ONE;

    public long spark_y(long i) => y + spark_dist(i) * SimTrig.sin_t(spark_angle(i)) / SimTrig.ONE;

    public override bool kills(GameSim sim)
    {
        if (phase == Phase.CLIMB) return sim.bird_touches_circle(x, y, ROCKET_RADIUS);
        if (phase == Phase.BURST)
        {
            for (long i = 0; i < spark_count(); i++)
                if (spark_live(i) && sim.bird_touches_circle(spark_x(i), spark_y(i), SPARK_RADIUS)) return true;
        }
        return false;
    }

    public override long checksum(long h)
    {
        long out_ = mix_all(h, x, y, burst_y, phase, timer, spread, delay, _rng.state_checksum(), spent);
        if (style != Style.RING) out_ = mix_all(out_, style);
        return out_;
    }

    public override void warnings(GameSim sim, List<long> out_)
    {
        if (phase != Phase.PAD && phase != Phase.CLIMB) return;
        long climb = (y - burst_y + CLIMB_VY - 1) / CLIMB_VY;
        long eta = climb;
        if (phase == Phase.PAD)
        {
            eta += timer;
            add_warning(out_, x - ROCKET_RADIUS, burst_y - ROCKET_RADIUS, x + ROCKET_RADIUS, PAD_Y + ROCKET_RADIUS, timer, climb + 1, WARN_KILL);
        }
        long far = SPARK_DEADLY * SPARK_SPEED + SPARK_RADIUS;
        long dur = SPARK_DEADLY + (style == Style.DOUBLE ? ECHO : 0);
        add_warning(out_, x - far, burst_y - far, x + far, burst_y + far, eta, dur, WARN_KILL);
    }
}
