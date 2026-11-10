namespace FastSim;

/// Port of sim/hazards/crate_drop.gd.
public sealed class CrateDrop : Hazard
{
    public const long COLS = 7;
    public const long COL_X0 = 40 * SimConfig.SUB;
    public const long COL_W = 40 * SimConfig.SUB;
    public const long CRATE = 36 * SimConfig.SUB;
    public const long MAX_HEIGHT = 4;
    public const long FLOOR = SimConfig.KILL_BOTTOM;
    public const long START_DELAY = 20;
    public const long WARN_TICKS = 45;
    public const long FALL_ACCEL = 20;
    public const long MAX_FALL = 9 * SimConfig.SUB;
    public const long COIN_LIFT = 4 * SimConfig.SUB;

    public long col = -1;
    public long y = 0;
    public long vy = 0;
    public long warn_left = 0;
    public long drops = 0;
    public long salt = 0;
    public List<long> heights = new();
    public List<long> coins = new();
    public bool gifts = false;

    public CrateDrop(bool p_gifts = false)
    {
        kind = "crate_drop";
        gifts = p_gifts;
        for (long i = 0; i < COLS; i++) heights.Add(0);
        for (long i = 0; i < COLS; i++) coins.Add(0);
    }

    public override Hazard clone_deep()
    {
        var c = (CrateDrop)MemberwiseClone();
        c.heights = new List<long>(heights);
        c.coins = new List<long>(coins);
        return c;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        salt = rng.next_u32();
        _next_drop(START_DELAY + WARN_TICKS);
    }

    public void _next_drop(long warn)
    {
        col = -1;
        long start = G.posmod(SimHash.mix(salt, drops), COLS);
        for (long i = 0; i < COLS; i++)
        {
            long c = (start + i) % COLS;
            if (heights[(int)c] < MAX_HEIGHT)
            {
                col = c;
                break;
            }
        }
        drops += 1;
        y = -CRATE;
        vy = 0;
        warn_left = warn;
    }

    public override void step(GameSim sim)
    {
        if (col < 0) return;
        if (warn_left > 0)
        {
            warn_left -= 1;
            return;
        }
        vy = G.mini(vy + FALL_ACCEL, MAX_FALL);
        y += vy;
        long land = stack_top(col) - CRATE;
        if (y >= land)
        {
            y = land;
            heights[(int)col] += 1;
            if (gifts && heights[(int)col] == 1) coins[(int)col] = 1;
            _next_drop(WARN_TICKS);
        }
    }

    public bool falling() => col >= 0 && warn_left == 0;

    public long col_left(long c) => COL_X0 + c * COL_W + (COL_W - CRATE) / 2;

    public long col_center(long c) => COL_X0 + c * COL_W + COL_W / 2;

    public long stack_top(long c) => FLOOR - heights[(int)c] * CRATE;

    public long coin_y(long c) => stack_top(c) - COIN_LIFT - SimConfig.COIN_RADIUS;

    public override bool kills(GameSim sim)
    {
        if (falling())
        {
            long x = col_left(col);
            if (sim.bird_touches_rect(x, y, x + CRATE, y + CRATE)) return true;
        }
        for (long c = 0; c < COLS; c++)
        {
            if (heights[(int)c] > 0)
            {
                long x = col_left(c);
                if (sim.bird_touches_rect(x, stack_top(c), x + CRATE, SimConfig.WORLD_H)) return true;
            }
        }
        return false;
    }

    public override void touch(GameSim sim)
    {
        for (long c = 0; c < COLS; c++)
        {
            if (coins[(int)c] == 1
                && sim.bird_touches_circle(col_center(c), coin_y(c), SimConfig.COIN_RADIUS))
            {
                coins[(int)c] = 0;
                sim.collect_coin(col_center(c), coin_y(c));
            }
        }
    }

    public override long checksum(long h)
    {
        long out_ = mix_all(h, col, y, vy, warn_left, drops, salt, G.B(gifts));
        out_ = mix_all(out_, heights);
        return mix_all(out_, coins);
    }
}
