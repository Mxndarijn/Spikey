namespace FastSim;

/// Port of sim/hazards/pendulum.gd.
public class Pendulum : Hazard
{
    public const long PIVOT_X = 180 * SimConfig.SUB;
    public const long PIVOT_Y = SimConfig.KILL_TOP;
    public const long LENGTH = 280 * SimConfig.SUB;
    public const long RADIUS = 22 * SimConfig.SUB;
    public const long AMPLITUDE = 52;
    public const long PERIOD = 180;

    public long phase = 0;
    public long angle = 0;
    public long x = 0;
    public long y = 0;

    public Pendulum()
    {
        kind = "pendulum";
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        phase = rng.next_below(SimTrig.TURN);
        _place();
    }

    public override void step(GameSim sim) => _place();

    public void _place()
    {
        angle = AMPLITUDE * SimTrig.sin_t(phase + t * SimTrig.TURN / PERIOD) / SimTrig.ONE;
        x = PIVOT_X + LENGTH * SimTrig.sin_t(angle) / SimTrig.ONE;
        y = PIVOT_Y + LENGTH * SimTrig.cos_t(angle) / SimTrig.ONE;
    }

    public override bool kills(GameSim sim) => sim.bird_touches_circle(x, y, RADIUS);

    public override long checksum(long h) => mix_all(h, phase, angle, x, y);
}
