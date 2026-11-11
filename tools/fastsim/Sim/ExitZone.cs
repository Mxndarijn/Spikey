namespace FastSim;

/// Port of sim/exit_zone.gd: the mouth of an open or ghost exit, which
/// hazards treat as part of the wall.
public static class ExitZone
{
    public const long DEPTH = 3 * SimConfig.BIRD_RADIUS;
    public const long HALF = SimConfig.EXIT_HALF + SimConfig.BIRD_RADIUS;

    public static long count(GameSim sim)
    {
        var s = sim.state;
        if (!s.exit_open && !s.exit_preview) return 0;
        return s.exit_b_kind != ExitKind.NORMAL ? 2 : 1;
    }

    public static long exit_y(GameSim sim, long i) => i == 0 ? sim.state.exit_a_y : sim.state.exit_b_y;

    public static long side(GameSim sim) => sim.state.exit_side;

    public static long left(GameSim sim) => left_on(sim, sim.state.exit_side);

    public static long right(GameSim sim) => right_on(sim, sim.state.exit_side);

    public static long left_on(GameSim sim, long p_side)
    {
        if (p_side == 0) return sim.room.wall_left();
        return sim.room.wall_right() - DEPTH;
    }

    public static long right_on(GameSim sim, long p_side)
    {
        if (p_side == 0) return sim.room.wall_left() + DEPTH;
        return sim.room.wall_right();
    }

    public static long inner_x(GameSim sim) => sim.state.exit_side == 0 ? right(sim) : left(sim);

    public static bool rect_in_box(GameSim sim, long p_side, long ey, long x0, long y0, long x1, long y1)
    {
        if (G.maxi(x0, x1) < left_on(sim, p_side) || G.mini(x0, x1) > right_on(sim, p_side)) return false;
        return G.maxi(y0, y1) >= ey - HALF && G.mini(y0, y1) <= ey + HALF;
    }

    public static bool hits_rect(GameSim sim, long x0, long y0, long x1, long y1)
    {
        long n = count(sim);
        for (long i = 0; i < n; i++)
            if (rect_in_box(sim, sim.state.exit_side, exit_y(sim, i), x0, y0, x1, y1)) return true;
        return false;
    }

    static long _nearest(GameSim sim, long cy)
    {
        long n = count(sim);
        if (n == 0) return -1;
        if (n == 1) return 0;
        return G.absi(cy - exit_y(sim, 0)) <= G.absi(cy - exit_y(sim, 1)) ? 0 : 1;
    }

    public static bool hits_circle(GameSim sim, long cx, long cy, long r)
    {
        long n = count(sim);
        for (long i = 0; i < n; i++)
            if (circle_in_box(sim, sim.state.exit_side, exit_y(sim, i), cx, cy, r)) return true;
        return false;
    }

    public static bool circle_in_box(GameSim sim, long p_side, long ey, long cx, long cy, long r)
    {
        long nx = G.clampi(cx, left_on(sim, p_side), right_on(sim, p_side));
        long ny = G.clampi(cy, ey - HALF, ey + HALF);
        long dx = cx - nx;
        long dy = cy - ny;
        return dx * dx + dy * dy <= r * r;
    }

    public static long clear_y(GameSim sim, long y, long half, long lo, long hi)
    {
        long out_ = y;
        long n = count(sim);
        for (long i = 0; i < n; i++)
        {
            long ey = exit_y(sim, i);
            long reach = HALF + half + 1;
            if (G.absi(out_ - ey) >= reach) continue;
            long up = ey - reach;
            long down = ey + reach;
            if (out_ < ey) out_ = up >= lo ? up : down;
            else out_ = down <= hi ? down : up;
        }
        return out_;
    }

    public static long push_x(GameSim sim, long x, long y, long r)
    {
        if (!hits_circle(sim, x, y, r)) return x;
        if (sim.state.exit_side == 0) return right(sim) + r + 1;
        return left(sim) - r - 1;
    }

    /// [x, y, vx, vy] after the bounce, or null (GDScript: an empty array).
    public static long[] bounce(GameSim sim, long x, long y, long vx, long vy, long r)
    {
        if (!hits_circle(sim, x, y, r)) return null;
        long ey = exit_y(sim, _nearest(sim, y));
        long prev_y = y - vy;
        long nx = x, ny = y, nvx = vx, nvy = vy;
        if (prev_y + r < ey - HALF)
        {
            long top = ey - HALF - r - 1;
            ny = 2 * top - y;
            nvy = -G.absi(vy);
        }
        else if (prev_y - r > ey + HALF)
        {
            long bottom = ey + HALF + r + 1;
            ny = 2 * bottom - y;
            nvy = G.absi(vy);
        }
        else if (sim.state.exit_side == 0)
        {
            long edge = right(sim) + r + 1;
            nx = 2 * edge - x;
            nvx = G.absi(vx);
        }
        else
        {
            long edge = left(sim) - r - 1;
            nx = 2 * edge - x;
            nvx = -G.absi(vx);
        }
        return new[] { nx, ny, nvx, nvy };
    }
}
