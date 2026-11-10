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

    public long cols = COLS;
    public long col_w = COL_W;
    public long col_x0 = COL_X0;
    public long crate_w = CRATE;
    public long crate_h = CRATE;
    public long max_height = MAX_HEIGHT;
    public bool pair = false;

    public long col = -1;
    public long y = 0;
    public long vy = 0;
    public bool done = false;
    public long col_b = -1;
    public long y_b = 0;
    public long vy_b = 0;
    public bool done_b = false;
    public long warn_left = 0;
    public long drops = 0;
    public long salt = 0;
    public List<long> heights = new();
    public List<long> coins = new();
    public bool gifts = false;

    public CrateDrop(
        bool p_gifts = false,
        long p_cols = COLS,
        long p_col_w = COL_W,
        long p_crate_w = CRATE,
        long p_crate_h = CRATE,
        long p_max_height = MAX_HEIGHT,
        bool p_pair = false)
    {
        kind = "crate_drop";
        gifts = p_gifts;
        cols = p_cols;
        col_w = p_col_w;
        col_x0 = (SimConfig.WORLD_W - cols * col_w) / 2;
        crate_w = p_crate_w;
        crate_h = p_crate_h;
        max_height = p_max_height;
        pair = p_pair;
        for (long i = 0; i < cols; i++) heights.Add(0);
        for (long i = 0; i < cols; i++) coins.Add(0);
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
        col = _free_col(G.posmod(SimHash.mix(salt, drops), cols), -1);
        col_b = -1;
        if (pair && col >= 0) col_b = _free_col((col + cols / 2) % cols, col);
        drops += 1;
        y = -crate_h;
        vy = 0;
        done = false;
        y_b = y;
        vy_b = 0;
        done_b = false;
        warn_left = warn;
    }

    public long _free_col(long start, long skip)
    {
        for (long i = 0; i < cols; i++)
        {
            long c = (start + i) % cols;
            if (c != skip && heights[(int)c] < max_height) return c;
        }
        return -1;
    }

    public override void step(GameSim sim)
    {
        if (col < 0) return;
        if (warn_left > 0)
        {
            warn_left -= 1;
            return;
        }
        if (!done)
        {
            vy = G.mini(vy + FALL_ACCEL, MAX_FALL);
            y += vy;
            long land = stack_top(col) - crate_h;
            if (y >= land)
            {
                y = land;
                _land(col);
                done = true;
            }
        }
        if (col_b >= 0 && !done_b)
        {
            vy_b = G.mini(vy_b + FALL_ACCEL, MAX_FALL);
            y_b += vy_b;
            long land_b = stack_top(col_b) - crate_h;
            if (y_b >= land_b)
            {
                y_b = land_b;
                _land(col_b);
                done_b = true;
            }
        }
        if (done && (col_b < 0 || done_b)) _next_drop(WARN_TICKS);
    }

    public void _land(long c)
    {
        heights[(int)c] += 1;
        if (gifts && heights[(int)c] == 1) coins[(int)c] = 1;
    }

    public bool falling() => col >= 0 && warn_left == 0;

    public long col_left(long c) => col_x0 + c * col_w + (col_w - crate_w) / 2;

    public long col_center(long c) => col_x0 + c * col_w + col_w / 2;

    public long stack_top(long c) => FLOOR - heights[(int)c] * crate_h;

    public long coin_y(long c) => stack_top(c) - COIN_LIFT - SimConfig.COIN_RADIUS;

    public override bool kills(GameSim sim)
    {
        if (falling())
        {
            if (!done)
            {
                long x = col_left(col);
                if (sim.bird_touches_rect(x, y, x + crate_w, y + crate_h)) return true;
            }
            if (col_b >= 0 && !done_b)
            {
                long xb = col_left(col_b);
                if (sim.bird_touches_rect(xb, y_b, xb + crate_w, y_b + crate_h)) return true;
            }
        }
        for (long c = 0; c < cols; c++)
        {
            if (heights[(int)c] > 0)
            {
                long x = col_left(c);
                if (sim.bird_touches_rect(x, stack_top(c), x + crate_w, SimConfig.WORLD_H)) return true;
            }
        }
        return false;
    }

    public override void touch(GameSim sim)
    {
        for (long c = 0; c < cols; c++)
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
        if (pair) out_ = mix_all(out_, col_b, y_b, vy_b, G.B(done), G.B(done_b));
        out_ = mix_all(out_, heights);
        return mix_all(out_, coins);
    }
}
