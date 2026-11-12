namespace FastSim;

/// Port of sim/hazards/splitting_bouncer.gd.
public class SplittingBouncer : Bouncer
{
    public const long BIG_RADIUS = 24 * SimConfig.SUB;
    public const long BIG_SPEED_X = 154;
    public const long BIG_SPEED_Y = 2 * SimConfig.SUB;
    public const long SMALL_RADIUS = 14 * SimConfig.SUB;
    public const long SPLIT_AT = 240;
    public const long WARN = 60;
    public const long CLEAR = 120 * SimConfig.SUB;

    public long warn = 0;
    public Bouncer other = null;

    public SplittingBouncer() : base(BIG_RADIUS) { }

    public override void setup(GameSim sim, SimRng rng)
    {
        base.setup(sim, rng);
        vx = G.signi(vx) * BIG_SPEED_X;
        vy = G.signi(vy) * BIG_SPEED_Y;
    }

    public override void step(GameSim sim)
    {
        move(sim);
        if (other != null)
        {
            other.move(sim);
            return;
        }
        if (t < SPLIT_AT)
            return;
        warn = G.mini(t - SPLIT_AT, WARN);
        if (warn < WARN)
            return;
        long dx = x - sim.state.x;
        long dy = y - sim.state.y;
        if (dx * dx + dy * dy < CLEAR * CLEAR)
            return;
        _split();
    }

    void _split()
    {
        radius = SMALL_RADIUS;
        vx = G.signi(vx) * SPEED_X;
        vy = -SPEED_Y;
        other = new Bouncer(SMALL_RADIUS);
        other.x = x;
        other.y = y;
        other.vx = vx;
        other.vy = SPEED_Y;
    }

    public bool is_split() => other != null;

    public override bool kills(GameSim sim)
    {
        if (base.kills(sim))
            return true;
        return other != null && other.kills(sim);
    }

    public override bool straight_path() => false;

    public override long checksum(long h)
    {
        long out_ = mix_all(base.checksum(h), radius, warn);
        if (other != null)
            out_ = other.checksum(out_);
        return out_;
    }

    public override Hazard clone_deep()
    {
        var c = (SplittingBouncer)MemberwiseClone();
        if (other != null)
            c.other = (Bouncer)other.clone_deep();
        return c;
    }

    public override void warnings(GameSim sim, List<long> out_)
    {
        if (other != null || t < SPLIT_AT) return;
        add_warning(out_, x - radius, y - radius, x + radius, y + radius, WARN - warn, 1, WARN_KILL);
    }
}
