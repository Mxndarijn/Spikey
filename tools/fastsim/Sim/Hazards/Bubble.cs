namespace FastSim;

/// Port of sim/hazards/bubble.gd.
public sealed class Bubble : Hazard
{
    public const long SUB = SimConfig.SUB;
    public const long RADIUS = 22 * SUB;
    public const long RISE = 96;
    public const long POP_TOP = SimConfig.KILL_TOP + 10 * SUB;
    public const long MIN_X = 90 * SUB;
    public const long MAX_X = 270 * SUB;
    public const long REGRAB = 12;

    public long x = 0;
    public long y = 0;
    public long vy = -RISE;
    public long next_x = 0;
    public bool carrying = false;
    public long lane = 0;
    public long cooldown = 0;
    public long since_pop = 1000;

    public Bubble(long p_lane = 0)
    {
        kind = "bubble";
        lane = p_lane;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        x = MIN_X + rng.next_below(MAX_X - MIN_X + 1);
        next_x = MIN_X + rng.next_below(MAX_X - MIN_X + 1);
        y = (520 - lane * 170) * SUB;
    }

    public override void step(GameSim sim)
    {
        if (cooldown > 0) cooldown -= 1;
        since_pop = G.mini(since_pop + 1, 1000);
        y += vy;
        if (y - RADIUS <= POP_TOP) pop();
    }

    public void pop()
    {
        carrying = false;
        since_pop = 0;
        cooldown = REGRAB;
        x = next_x;
        y = SimConfig.WORLD_H + RADIUS;
    }

    public override void touch(GameSim sim)
    {
        if (carrying)
        {
            _hold(sim);
            return;
        }
        if (cooldown > 0 || !sim.bird_touches_circle(x, y, RADIUS - SimConfig.BIRD_RADIUS)) return;
        var hs = sim.room.hazards;
        for (int i = 0; i < hs.Count; i++)
        {
            var h = hs[i];
            if (h != this && h.alive && h.kind == "bubble" && ((Bubble)h).carrying) return;
        }
        carrying = true;
        _hold(sim);
    }

    public void _hold(GameSim sim)
    {
        x = sim.state.x;
        sim.state.y = y;
        sim.state.vy = vy;
    }

    public override void on_bounce(GameSim sim, SimRng rng)
    {
        next_x = MIN_X + rng.next_below(MAX_X - MIN_X + 1);
    }

    public override void on_flap(GameSim sim)
    {
        if (carrying) pop();
    }

    public override long checksum(long h) => mix_all(h, x, y, vy, next_x, G.B(carrying), lane, cooldown, since_pop);
}
