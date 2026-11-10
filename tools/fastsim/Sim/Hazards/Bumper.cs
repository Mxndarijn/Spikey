namespace FastSim;

/// Port of sim/hazards/bumper.gd.
public class Bumper : Hazard
{
    public const long RADIUS = 28 * SimConfig.SUB;
    public const long CENTER_X = 180 * SimConfig.SUB;
    public const long CENTER_Y = 320 * SimConfig.SUB;
    public const long LOOP_RX = 80 * SimConfig.SUB;
    public const long LOOP_RY = 140 * SimConfig.SUB;
    public const long PERIOD = 600;

    public long x = 0;
    public long y = 0;
    public long phase = 0;
    public long dir = 1;
    public bool follows = false;

    public Bumper(bool p_follows = false)
    {
        kind = "bumper";
        follows = p_follows;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        if (follows)
        {
            var hs = sim.room.hazards;
            for (int i = 0; i < hs.Count; i++)
            {
                var h = hs[i];
                if (h != this && h.kind == kind)
                {
                    var b = (Bumper)h;
                    phase = b.phase + SimTrig.TURN / 2;
                    dir = b.dir;
                    _place();
                    return;
                }
            }
        }
        phase = rng.next_below(SimTrig.TURN);
        dir = rng.next_below(2) == 0 ? 1 : -1;
        _place();
    }

    public override void step(GameSim _sim) { _place(); }

    public void _place()
    {
        long a = phase + dir * (t * SimTrig.TURN / PERIOD);
        x = CENTER_X + LOOP_RX * SimTrig.cos_t(a) / SimTrig.ONE;
        y = CENTER_Y + LOOP_RY * SimTrig.sin_t(a) / SimTrig.ONE;
    }

    public override void touch(GameSim sim)
    {
        if (sim.bird_touches_circle(x, y, RADIUS)) sim.bump_bird_from(x, y);
    }

    public override long checksum(long h) => mix_all(h, x, y, phase, dir, G.B(follows));
}
