namespace FastSim;

/// Port of sim/hazards/orchard_spawner.gd.
public sealed class OrchardSpawner : Hazard
{
    public const long SUB = SimConfig.SUB;
    public const long SPAWN_EVERY = 36;
    public const long FALL = 2 * SUB;
    public const long SLOTS = 12;
    public const long START_Y = 24 * SUB;
    public static readonly long[] COLUMNS = { 80 * SUB, 130 * SUB, 180 * SUB, 230 * SUB, 280 * SUB };

    public List<long> xs = new();
    public List<long> ys = new();
    public List<bool> live = new();
    public SimRng _rng = new SimRng();

    public OrchardSpawner()
    {
        kind = "orchard_spawner";
        for (long i = 0; i < SLOTS; i++)
        {
            xs.Add(0);
            ys.Add(0);
            live.Add(false);
        }
    }

    public override Hazard clone_deep()
    {
        var c = (OrchardSpawner)MemberwiseClone();
        c.xs = new List<long>(xs);
        c.ys = new List<long>(ys);
        c.live = new List<bool>(live);
        c._rng = _rng.Clone();
        return c;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        _rng.reseed(rng.next_u32());
    }

    public override void step(GameSim sim)
    {
        for (int i = 0; i < SLOTS; i++)
        {
            if (live[i])
            {
                ys[i] += FALL;
                if (ys[i] > SimConfig.KILL_BOTTOM + SimConfig.COIN_RADIUS) live[i] = false;
            }
        }
        if (t % SPAWN_EVERY == 1)
        {
            for (int i = 0; i < SLOTS; i++)
            {
                if (!live[i])
                {
                    live[i] = true;
                    xs[i] = COLUMNS[_rng.next_below(COLUMNS.Length)];
                    ys[i] = START_Y;
                    break;
                }
            }
        }
    }

    public override void touch(GameSim sim)
    {
        for (int i = 0; i < SLOTS; i++)
        {
            if (live[i] && sim.bird_touches_circle(xs[i], ys[i], SimConfig.COIN_RADIUS))
            {
                live[i] = false;
                sim.collect_coin(xs[i], ys[i]);
            }
        }
    }

    public long live_count()
    {
        long n = 0;
        foreach (bool v in live) n += G.B(v);
        return n;
    }

    public override long checksum(long h)
    {
        long out_ = SimHash.mix(h, _rng.state_checksum());
        for (int i = 0; i < SLOTS; i++) out_ = mix_all(out_, xs[i], ys[i], G.B(live[i]));
        return out_;
    }
}
