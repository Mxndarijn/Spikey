namespace FastSim;

/// Port of sim/hazards/echo.gd.
public class Echo : Hazard
{
    public static class Mode { public const long ECHO = 0, MIRROR = 1; }

    public const long DELAY = SimConfig.TICKS_PER_SECOND;
    public const long RADIUS = 10 * SimConfig.SUB;

    public long mode = Mode.ECHO;
    public long x = 0;
    public long y = 0;
    public bool shown = false;
    public long facing = 1;
    public List<long> xs = new();
    public List<long> ys = new();
    public long head = 0;

    public Echo(long p_mode = -1)
    {
        kind = "echo";
        mode = p_mode;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        if (mode < 0)
            mode = sim.room.variant_id() == "mirror" ? Mode.MIRROR : Mode.ECHO;
        xs = new List<long>();
        ys = new List<long>();
        for (long i = 0; i < DELAY; i++)
        {
            xs.Add(sim.state.x);
            ys.Add(sim.state.y);
        }
        head = 0;
        x = sim.state.x;
        y = sim.state.y;
    }

    public override void step(GameSim sim)
    {
        shown = t > DELAY;
        if (mode == Mode.MIRROR)
        {
            x = SimConfig.WORLD_W - sim.state.x;
            y = SimConfig.WORLD_H - sim.state.y;
            facing = sim.state.vx > 0 ? -1 : 1;
            return;
        }
        long old_x = xs[(int)head];
        facing = old_x >= x ? 1 : -1;
        x = old_x;
        y = ys[(int)head];
        xs[(int)head] = sim.state.x;
        ys[(int)head] = sim.state.y;
        head = (head + 1) % DELAY;
    }

    public override bool kills(GameSim sim) => shown && sim.bird_touches_circle(x, y, RADIUS);

    public override long checksum(long h)
    {
        long out_ = mix_all(h, mode, x, y, G.B(shown), facing, head);
        for (int i = 0; i < xs.Count; i++) out_ = SimHash.mix(SimHash.mix(out_, xs[i]), ys[i]);
        return out_;
    }

    public override Hazard clone_deep()
    {
        var c = (Echo)MemberwiseClone();
        c.xs = new List<long>(xs);
        c.ys = new List<long>(ys);
        return c;
    }
}
