namespace FastSim;

/// Port of sim/hazards/revving_bouncer.gd.
public class RevvingBouncer : Bouncer
{
    public const long MAX_LEVEL = 7;

    public long level = 0;

    public override void setup(GameSim sim, SimRng rng)
    {
        base.setup(sim, rng);
        level = 0;
        _set_speed();
    }

    public override void step(GameSim sim)
    {
        if (move(sim) && level < MAX_LEVEL)
        {
            level += 1;
            _set_speed();
        }
    }

    void _set_speed()
    {
        vx = G.signi(vx) * SPEED_X * (6 + level) / 10;
        vy = G.signi(vy) * SPEED_Y * (6 + level) / 10;
    }

    public override bool straight_path() => false;

    public override long checksum(long h) => mix_all(base.checksum(h), level);
}
