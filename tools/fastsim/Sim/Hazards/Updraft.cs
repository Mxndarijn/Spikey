namespace FastSim;

/// Port of sim/hazards/updraft.gd.
public class Updraft : Hazard
{
    public const long SUB = SimConfig.SUB;
    public const long HALF_W = 60 * SUB;
    public const long LIFT = SimConfig.GRAVITY * 2 / 3;

    public long x0 = 0;
    public long x1 = 0;
    public long lift = LIFT;

    public Updraft()
    {
        kind = "updraft";
        x0 = SimConfig.WORLD_W / 2 - HALF_W;
        x1 = SimConfig.WORLD_W / 2 + HALF_W;
    }

    public bool inside(GameSim sim) => sim.state.x >= x0 && sim.state.x <= x1;

    public override void touch(GameSim sim)
    {
        if (inside(sim))
        {
            long vy = sim.state.vy - lift;
            sim.state.vy = G.clampi(vy, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY);
        }
    }

    public override long checksum(long h) => mix_all(h, x0, x1, lift);
}
