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
    public const long ARRIVAL_TRIES = 32;

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
        if (sim.state.started)
        {
            var arrival = sim.arrival_path();
            long first = phase;
            long pick = phase;
            bool settled = false;
            for (long k = 0; k < ARRIVAL_TRIES; k++)
            {
                phase = (first + k * SimTrig.TURN / ARRIVAL_TRIES) % SimTrig.TURN;
                long clear = _arrival_clear(arrival);
                if (clear >= GameSim.ARRIVAL_PATH_TICKS)
                {
                    pick = phase;
                    break;
                }
                if (clear >= GameSim.ARRIVAL_PATH_MIN && !settled)
                {
                    pick = phase;
                    settled = true;
                }
            }
            phase = pick;
        }
        _place();
    }

    public long _arrival_clear(List<long> arrival)
    {
        long keep = t;
        long out_ = GameSim.ARRIVAL_PATH_TICKS;
        for (long k = 0; k < GameSim.ARRIVAL_PATH_TICKS; k++)
        {
            t = k;
            _place();
            if (GameSim.arrival_path_hits(arrival, k, x, y, RADIUS))
            {
                out_ = k;
                break;
            }
        }
        t = keep;
        _place();
        return out_;
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
