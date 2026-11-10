namespace FastSim;

/// Port of sim/hazards/heavy_bouncer.gd.
public class HeavyBouncer : Bouncer
{
    public const long HEAVY_RADIUS = 22 * SimConfig.SUB;
    public const long HEAVY_SPEED_X = 160;
    public const long GRAVITY = 8;
    public static readonly long[] LAUNCH = { 479, 594 };

    public long bounces = 0;

    public HeavyBouncer() : base(HEAVY_RADIUS) { }

    public override void setup(GameSim sim, SimRng rng)
    {
        base.setup(sim, rng);
        vx = G.signi(vx) * HEAVY_SPEED_X;
        vy = 0;
    }

    public override void step(GameSim sim)
    {
        vy += GRAVITY;
        x += vx;
        y += vy;
        bounce_sides(sim);
        bounce_top();
        if (y > bottom_y())
        {
            y = bottom_y();
            vy = -LAUNCH[bounces % 2];
            bounces += 1;
        }
    }

    public override bool straight_path() => false;

    public override long checksum(long h) => mix_all(base.checksum(h), bounces);
}
