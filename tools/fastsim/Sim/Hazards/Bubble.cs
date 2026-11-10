namespace FastSim;

/// Port of sim/hazards/bubble.gd.
public sealed class Bubble : Hazard
{
    public const long SUB = SimConfig.SUB;
    public const long RADIUS = 22 * SUB;
    public const long RISE = 96;
    public const long GIANT_RADIUS = 38 * SUB;
    public const long GIANT_RISE = 56;
    public const long SPIKED_RADIUS = 24 * SUB;
    public const long WARN = 60;
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
    public long radius = RADIUS;
    public bool spiked = false;
    public long wait = 0;
    public long delay = 0;
    public bool coin_bubble = false;
    public bool has_coin = false;

    public Bubble(long p_lane = 0, long p_radius = RADIUS, long p_rise = RISE)
    {
        kind = "bubble";
        lane = p_lane;
        radius = p_radius;
        vy = -p_rise;
    }

    public Hazard spiky(long p_delay)
    {
        spiked = true;
        radius = SPIKED_RADIUS;
        delay = p_delay;
        return this;
    }

    public Hazard with_coin()
    {
        coin_bubble = true;
        return this;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        x = MIN_X + rng.next_below(MAX_X - MIN_X + 1);
        next_x = MIN_X + rng.next_below(MAX_X - MIN_X + 1);
        y = (520 - lane * 170) * SUB;
        has_coin = coin_bubble;
        if (spiked)
        {
            y = SimConfig.WORLD_H + radius;
            wait = WARN + delay;
        }
    }

    public override void step(GameSim sim)
    {
        if (cooldown > 0) cooldown -= 1;
        since_pop = G.mini(since_pop + 1, 1000);
        if (wait > 0)
        {
            wait -= 1;
            return;
        }
        y += vy;
        if (y - radius <= POP_TOP) pop();
    }

    public void pop()
    {
        carrying = false;
        since_pop = 0;
        cooldown = REGRAB;
        x = next_x;
        y = SimConfig.WORLD_H + radius;
        has_coin = coin_bubble;
        if (spiked) wait = WARN;
    }

    public override bool kills(GameSim sim) => spiked && wait == 0 && sim.bird_touches_circle(x, y, radius);

    public override void touch(GameSim sim)
    {
        if (spiked) return;
        if (carrying)
        {
            _hold(sim);
        }
        else if (cooldown == 0 && sim.bird_touches_circle(x, y, radius - SimConfig.BIRD_RADIUS))
        {
            if (!_other_carrying(sim))
            {
                carrying = true;
                _hold(sim);
            }
        }
        _take_coin(sim);
    }

    public bool _other_carrying(GameSim sim)
    {
        var hs = sim.room.hazards;
        for (int i = 0; i < hs.Count; i++)
        {
            var h = hs[i];
            if (h != this && h.alive && h.kind == "bubble" && ((Bubble)h).carrying) return true;
        }
        return false;
    }

    public void _take_coin(GameSim sim)
    {
        if (!has_coin || !coin_in_reach()) return;
        if (sim.bird_touches_circle(x, y, SimConfig.COIN_RADIUS))
        {
            has_coin = false;
            sim.collect_coin(x, y);
        }
    }

    public bool coin_in_reach() => y >= SimConfig.COIN_MIN_Y && y <= SimConfig.COIN_MAX_Y;

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

    public override long checksum(long h) =>
        mix_all(h, x, y, vy, next_x, G.B(carrying), lane, cooldown, since_pop, radius, G.B(spiked), wait, G.B(has_coin));
}
