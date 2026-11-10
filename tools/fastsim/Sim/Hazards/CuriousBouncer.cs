namespace FastSim;

/// Port of sim/hazards/curious_bouncer.gd.
public class CuriousBouncer : Bouncer
{
    public const long STEER = 4;
    public const long MAX_VY = 154;
    public const long START_VY = 38;
    public const long STEER_DIV = 512;

    public long look = 0;

    public override void setup(GameSim sim, SimRng rng)
    {
        base.setup(sim, rng);
        vy = G.signi(vy) * START_VY;
    }

    public override void step(GameSim sim)
    {
        long d = sim.state.y - y;
        look = G.signi(d);
        vy = G.clampi(vy + G.clampi(d / STEER_DIV, -STEER, STEER), -MAX_VY, MAX_VY);
        move(sim);
    }

    public override long checksum(long h) => mix_all(base.checksum(h), look);
}
