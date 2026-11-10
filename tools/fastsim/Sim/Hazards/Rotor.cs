namespace FastSim;

/// Port of sim/hazards/rotor.gd.
public class Rotor : Hazard
{
    public const long CENTER_X = 180 * SimConfig.SUB;
    public const long CENTER_Y = 320 * SimConfig.SUB;
    public const long BLADES = 4;
    public const long HUB_RADIUS = 16 * SimConfig.SUB;
    public const long BLADE_LENGTH = 80 * SimConfig.SUB;
    public const long BLADE_HALF_W = 8 * SimConfig.SUB;
    public const long SAMPLES = 5;
    public const long PERIOD = 360;
    public const long HUB_CLEAR = BLADE_LENGTH + BLADE_HALF_W + SimConfig.BIRD_RADIUS + 4 * SimConfig.SUB;
    public const long HOP = 64 * SimConfig.SUB;

    public long center_y = CENTER_Y;
    public long phase = 0;
    public long dir = 1;
    public long angle = 0;

    public Rotor()
    {
        kind = "rotor";
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        center_y = CENTER_Y;
        long dy = sim.state.y - CENTER_Y;
        if (sim.state.started && dy > -HUB_CLEAR && dy < HUB_CLEAR + HOP)
            center_y = sim.state.y + (dy < 0 ? HUB_CLEAR : -HUB_CLEAR - HOP);
        phase = rng.next_below(SimTrig.TURN);
        dir = rng.next_below(2) == 0 ? 1 : -1;
        _place();
    }

    public override void step(GameSim sim) => _place();

    public void _place()
    {
        angle = G.posmod(phase + dir * (t * SimTrig.TURN / PERIOD), SimTrig.TURN);
    }

    public long blade_angle(long i) => angle + i * SimTrig.TURN / BLADES;

    public override bool kills(GameSim sim)
    {
        if (sim.bird_touches_circle(CENTER_X, center_y, HUB_RADIUS)) return true;
        for (long i = 0; i < BLADES; i++)
        {
            long a = blade_angle(i);
            long c = SimTrig.cos_t(a);
            long s = SimTrig.sin_t(a);
            for (long k = 0; k < SAMPLES; k++)
            {
                long d = BLADE_LENGTH * (k + 1) / SAMPLES;
                long px = CENTER_X + d * c / SimTrig.ONE;
                long py = center_y + d * s / SimTrig.ONE;
                if (sim.bird_touches_circle(px, py, BLADE_HALF_W)) return true;
            }
        }
        return false;
    }

    public override long checksum(long h) => mix_all(h, phase, dir, angle, center_y);
}
