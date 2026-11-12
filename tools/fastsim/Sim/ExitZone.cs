namespace FastSim;

/// Port of sim/exit_zone.gd: the mouths of a room's drawn exits (a ghost or
/// open), which hazards treat as part of the wall.
public static class ExitZone
{
    public const long DEPTH = 3 * SimConfig.BIRD_RADIUS;
    public const long HALF = SimConfig.EXIT_HALF + SimConfig.BIRD_RADIUS;

    public const long BOXES = 2;

    public static long count(GameSim _sim) => BOXES;

    public static long box_side(GameSim sim, long _i) => sim.state.exit_side;

    public static long box_y(GameSim sim, long i)
    {
        var s = sim.state;
        if (!s.exit_open && !s.exit_preview) return 0;
        if (i == 0) return s.exit_a_y;
        return s.exit_b_kind != ExitKind.NORMAL ? s.exit_b_y : 0;
    }

    public static long left_on(GameSim sim, long side)
    {
        if (side == 0) return sim.room.wall_left();
        return sim.room.wall_right() - DEPTH;
    }

    public static long right_on(GameSim sim, long side)
    {
        if (side == 0) return sim.room.wall_left() + DEPTH;
        return sim.room.wall_right();
    }

    static long _lo(GameSim sim, long side) => left_on(sim, side) + (side == 1 ? 1 : 0);

    static long _hi(GameSim sim, long side) => right_on(sim, side) - (side == 0 ? 1 : 0);

    public static bool rect_in_box(GameSim sim, long side, long ey, long x0, long y0, long x1, long y1)
    {
        if (G.maxi(x0, x1) < _lo(sim, side) || G.mini(x0, x1) > _hi(sim, side)) return false;
        return G.maxi(y0, y1) >= ey - HALF && G.mini(y0, y1) <= ey + HALF;
    }

    public static bool circle_in_box(GameSim sim, long side, long ey, long cx, long cy, long r)
    {
        long nx = G.clampi(cx, _lo(sim, side), _hi(sim, side));
        long ny = G.clampi(cy, ey - HALF, ey + HALF);
        long dx = cx - nx;
        long dy = cy - ny;
        return dx * dx + dy * dy <= r * r;
    }

    public static bool hits_rect(GameSim sim, long x0, long y0, long x1, long y1)
    {
        for (long i = 0; i < BOXES; i++)
        {
            long ey = box_y(sim, i);
            if (ey != 0 && rect_in_box(sim, box_side(sim, i), ey, x0, y0, x1, y1)) return true;
        }
        return false;
    }

    public static bool hits_rect_on(GameSim sim, long side, long x0, long y0, long x1, long y1)
    {
        for (long i = 0; i < BOXES; i++)
        {
            long ey = box_y(sim, i);
            if (ey != 0 && box_side(sim, i) == side && rect_in_box(sim, side, ey, x0, y0, x1, y1)) return true;
        }
        return false;
    }

    public static long circle_box(GameSim sim, long cx, long cy, long r)
    {
        for (long i = 0; i < BOXES; i++)
        {
            long ey = box_y(sim, i);
            if (ey != 0 && circle_in_box(sim, box_side(sim, i), ey, cx, cy, r)) return i;
        }
        return -1;
    }

    public static bool hits_circle(GameSim sim, long cx, long cy, long r) => circle_box(sim, cx, cy, r) >= 0;

    public static long clear_y(GameSim sim, long side, long y, long half, long lo, long hi)
    {
        long reach = HALF + half + 1;
        long first = -1;
        for (long i = 0; i < BOXES; i++)
        {
            long ey = box_y(sim, i);
            if (ey != 0 && _on(sim, i, side) && G.absi(y - ey) < reach)
            {
                first = i;
                break;
            }
        }
        if (first < 0) return y;
        long dir = y < box_y(sim, first) ? -1 : 1;
        long out_ = _push_y(sim, side, y, reach, dir);
        if (out_ < lo || out_ > hi) out_ = _push_y(sim, side, y, reach, -dir);
        return out_;
    }

    static long _push_y(GameSim sim, long side, long y, long reach, long dir)
    {
        long out_ = y;
        for (long k = 0; k < BOXES; k++)
        {
            bool moved = false;
            for (long i = 0; i < BOXES; i++)
            {
                long ey = box_y(sim, i);
                if (ey != 0 && _on(sim, i, side) && G.absi(out_ - ey) < reach)
                {
                    out_ = ey + dir * reach;
                    moved = true;
                }
            }
            if (!moved) break;
        }
        return out_;
    }

    public static long stop_y(GameSim sim, long side, long from, long to, long half, long lo, long hi)
    {
        long reach = HALF + half + 1;
        if (clear_y(sim, side, from, half, lo, hi) != from) return clear_y(sim, side, to, half, lo, hi);
        if (to == from) return to;
        return _push_y(sim, side, to, reach, to > from ? -1 : 1);
    }

    static bool _on(GameSim sim, long i, long side) => side < 0 || box_side(sim, i) == side;

    public static long push_x(GameSim sim, long x, long y, long r)
    {
        long i = circle_box(sim, x, y, r);
        if (i < 0) return x;
        if (box_side(sim, i) == 0) return right_on(sim, 0) + r + 1;
        return left_on(sim, 1) - r - 1;
    }

    /// [x, y, vx, vy] after the bounce, or null (GDScript: an empty array).
    public static long[] bounce(GameSim sim, long x, long y, long vx, long vy, long r)
    {
        long i = circle_box(sim, x, y, r);
        if (i < 0) return null;
        long ey = box_y(sim, i);
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
        else if (box_side(sim, i) == 0)
        {
            long edge = right_on(sim, 0) + r + 1;
            nx = 2 * edge - x;
            nvx = G.absi(vx);
        }
        else
        {
            long edge = left_on(sim, 1) - r - 1;
            nx = 2 * edge - x;
            nvx = -G.absi(vx);
        }
        return new[] { nx, ny, nvx, nvy };
    }
}
