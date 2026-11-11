namespace FastSim;

/// Port of sim/hazards/drop.gd.
public sealed class Drop : Hazard
{
    public static class Phase { public const long WAIT = 0, WARN = 1, FALL = 2, STAKE = 3; }
    public static class Style { public const long PLAIN = 0, SHATTER = 1, WOBBLE = 2, STAKE = 3; }

    public const long SUB = SimConfig.SUB;
    public const long RADIUS = 10 * SUB;
    public const long WARN = 45;
    public const long MIN_X = 50 * SUB;
    public const long MAX_X = 310 * SUB;
    public const long TOP = SimConfig.KILL_TOP;

    public const long SWAY = 22 * SUB;
    public const long SWAY_PERIOD = 40;

    public const long SHARD_RADIUS = 6 * SUB;
    public const long SHARD_START = 10 * SUB;
    public const long SHARD_VX = 5 * SUB;
    public const long SHARD_VY = -4 * SUB;
    public const long SHARD_GRAVITY = 19;
    public const long SHARD_FLOOR = SimConfig.KILL_BOTTOM - 6 * SUB;
    public const long SHARD_LIFE = 26;

    public const long FLOOR_SPIKES = 9;
    public const long FLOOR_SPIKE_W = SimConfig.WORLD_W / FLOOR_SPIKES;
    public const long FLOOR_BASE = SimConfig.WORLD_H - 8 * SUB;
    public const long STAKE_HEIGHT = 40 * SUB;
    public const long STAKE_GROW = 8;
    public const long STAKE_SINK = 15;
    public const long STAKE_STEPS = 135;

    public long x = 0;
    public long y = TOP;
    public long phase = Phase.WAIT;
    public long timer = 0;
    public long speed = 10 * SUB;
    public long gap = 25;
    public long delay = 0;
    public long warn = WARN;
    public long radius = RADIUS;
    public long style = Style.PLAIN;
    public long column = -1;
    public long base_x = 0;
    public long fall_t = 0;
    public long shard_t = 0;
    public long shard_x = 0;
    public long shard_dx = 0;
    public long shard_y = 0;
    public long shard_vy = 0;

    public SimRng _rng = new SimRng();

    public Drop(
        long p_delay = 0,
        long p_speed = 10 * SUB,
        long p_gap = 25,
        long p_warn = WARN,
        long p_radius = RADIUS,
        long p_style = Style.PLAIN,
        long p_column = -1)
    {
        kind = "drop";
        delay = p_delay;
        speed = p_speed;
        gap = p_gap;
        warn = p_warn;
        radius = p_radius;
        style = p_style;
        column = p_column;
    }

    public override Hazard clone_deep()
    {
        var c = (Drop)MemberwiseClone();
        c._rng = _rng.Clone();
        return c;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        _rng.reseed(rng.next_u32());
        phase = Phase.WAIT;
        timer = delay;
        y = TOP;
    }

    public override void step(GameSim sim)
    {
        if (shard_t > 0)
        {
            _step_shards();
            long sx = shard_x - shard_dx;
            long sx2 = shard_x + shard_dx;
            if (ExitZone.hits_circle(sim, sx, shard_y, SHARD_RADIUS) || ExitZone.hits_circle(sim, sx2, shard_y, SHARD_RADIUS))
                shard_t = 0;
        }
        switch (phase)
        {
            case Phase.WAIT:
                timer -= 1;
                if (timer <= 0)
                {
                    phase = Phase.WARN;
                    timer = warn;
                    base_x = _next_column();
                    x = base_x;
                    y = TOP;
                    fall_t = 0;
                }
                break;
            case Phase.WARN:
                timer -= 1;
                if (timer <= 0)
                {
                    phase = Phase.FALL;
                    y = TOP;
                }
                break;
            case Phase.FALL:
                y += speed;
                fall_t += 1;
                if (style == Style.WOBBLE)
                    x = base_x + SWAY * SimTrig.sin_t(fall_t * SimTrig.TURN / SWAY_PERIOD) / SimTrig.ONE;
                if (style == Style.SHATTER && y + radius >= SimConfig.KILL_BOTTOM)
                {
                    shard_t = SHARD_LIFE;
                    shard_x = x;
                    shard_dx = 0;
                    shard_y = SimConfig.KILL_BOTTOM - SHARD_START;
                    shard_vy = SHARD_VY;
                    phase = Phase.WAIT;
                    timer = gap;
                }
                else if (style == Style.STAKE && y + radius >= SimConfig.KILL_BOTTOM)
                {
                    y = SimConfig.KILL_BOTTOM - radius;
                    phase = Phase.STAKE;
                    timer = STAKE_STEPS;
                }
                else if (y - radius > SimConfig.WORLD_H || ExitZone.hits_circle(sim, x, y, radius))
                {
                    phase = Phase.WAIT;
                    timer = gap;
                }
                break;
            case Phase.STAKE:
                timer -= 1;
                if (timer <= 0)
                {
                    phase = Phase.WAIT;
                    timer = gap;
                }
                break;
        }
    }

    long _next_column()
    {
        if (column >= 0)
        {
            long c = column;
            column = SimConfig.WORLD_W - column;
            return c;
        }
        if (style == Style.STAKE)
            return FLOOR_SPIKE_W / 2 + FLOOR_SPIKE_W * (1 + _rng.next_below(FLOOR_SPIKES - 2));
        if (style == Style.WOBBLE)
            return MIN_X + SWAY + _rng.next_below(MAX_X - MIN_X - 2 * SWAY + 1);
        return MIN_X + _rng.next_below(MAX_X - MIN_X + 1);
    }

    void _step_shards()
    {
        shard_t -= 1;
        shard_dx += SHARD_VX;
        shard_vy += SHARD_GRAVITY;
        shard_y += shard_vy;
        if (shard_y > SHARD_FLOOR)
        {
            shard_y = SHARD_FLOOR;
            shard_vy = -G.absi(shard_vy) * 45 / 100;
        }
    }

    public bool warning() => phase == Phase.WARN;

    public bool falling() => phase == Phase.FALL;

    public bool staked() => phase == Phase.STAKE;

    public long warn_progress()
    {
        if (phase != Phase.WARN) return 0;
        return SimTrig.ONE * (warn - timer) / warn;
    }

    public long stake_height()
    {
        if (phase != Phase.STAKE) return 0;
        long age = STAKE_STEPS - timer;
        if (age < STAKE_GROW) return STAKE_HEIGHT * (age + 1) / STAKE_GROW;
        if (timer < STAKE_SINK) return STAKE_HEIGHT * timer / STAKE_SINK;
        return STAKE_HEIGHT;
    }

    public long stake_half_base() => FLOOR_SPIKE_W / 2 + stake_height() / 10;

    public override bool kills(GameSim sim)
    {
        if (phase == Phase.FALL && sim.bird_touches_circle(x, y, radius))
            return true;
        if (shard_t > 0)
        {
            if (sim.bird_touches_circle(shard_x - shard_dx, shard_y, SHARD_RADIUS))
                return true;
            if (sim.bird_touches_circle(shard_x + shard_dx, shard_y, SHARD_RADIUS))
                return true;
        }
        return phase == Phase.STAKE && _touches_stake(sim);
    }

    bool _touches_stake(GameSim sim)
    {
        long tip_y = SimConfig.KILL_BOTTOM - stake_height();
        long dx = G.absi(sim.state.x - base_x);
        long dy = sim.state.y - tip_y;
        long ex = stake_half_base();
        long ey = FLOOR_BASE - tip_y;
        if (dy >= 0 && dy <= ey && dx * ey <= ex * dy)
            return true;
        long r = SimConfig.BIRD_RADIUS;
        long dot = dx * ex + dy * ey;
        long len2 = ex * ex + ey * ey;
        if (dot <= 0)
            return dx * dx + dy * dy <= r * r;
        if (dot >= len2)
            return false;
        long cross = dx * ey - dy * ex;
        return cross * cross <= r * r * len2;
    }

    public override long checksum(long h) => mix_all(
        h, x, y, phase, timer, speed, gap, delay, warn, radius, style, column, base_x, fall_t,
        shard_t, shard_x, shard_dx, shard_y, shard_vy, _rng.state_checksum());
}
