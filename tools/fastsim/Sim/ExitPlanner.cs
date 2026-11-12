namespace FastSim;

/// Port of sim/exit_planner.gd.
public static class ExitPlanner
{
    public static long slots(SimState state)
    {
        long out_ = 0;
        long reach = SimConfig.EXIT_HALF + SimConfig.SPIKE_HALF_BASE;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            long cy = SimConfig.slot_center_y(slot);
            if (G.absi(cy - state.exit_a_y) < reach) out_ |= 1L << (int)slot;
            if (state.exit_b_kind != ExitKind.NORMAL && G.absi(cy - state.exit_b_y) < reach)
                out_ |= 1L << (int)slot;
        }
        return out_;
    }

    public static bool is_fork(GameSim sim, long at)
    {
        if (sim.is_practice()) return false;
        if (sim.room.def != null && sim.room.def.boss) return true;
        return at % SimConfig.FORK_EVERY == 0 && at % SimConfig.BOSS_EVERY != 0;
    }

    public static void plan(GameSim sim, SimRng rng, long side, long at)
    {
        sim.state.exit_side = side;
        bool fork = is_fork(sim, at);
        if (fork)
        {
            long top = random_y(sim, rng, SimConfig.EXIT_MIN_Y, SimConfig.FORK_SPLIT_Y - SimConfig.EXIT_HALF);
            long bottom = random_y(sim, rng, SimConfig.FORK_SPLIT_Y + SimConfig.EXIT_HALF, SimConfig.EXIT_MAX_Y);
            bool calm_on_top = rng.next_below(2) == 0;
            if (blocked(sim, bottom)) bottom = _free_apart(sim, bottom, top);
            if (blocked(sim, top)) top = _free_apart(sim, top, bottom);
            sim.state.exit_a_y = top;
            sim.state.exit_b_y = bottom;
            sim.state.exit_a_kind = calm_on_top ? ExitKind.CALM : ExitKind.WILD;
            sim.state.exit_b_kind = calm_on_top ? ExitKind.WILD : ExitKind.CALM;
        }
        else
        {
            sim.state.exit_a_y = random_y(sim, rng, SimConfig.EXIT_MIN_Y, SimConfig.EXIT_MAX_Y);
            sim.state.exit_a_kind = ExitKind.NORMAL;
            sim.state.exit_b_y = 0;
            sim.state.exit_b_kind = ExitKind.NORMAL;
        }
    }

    public const long PLAN_SALT = 0x45584954;

    public static void plan_room(GameSim sim, long at)
    {
        var s = sim.state;
        var rng = new SimRng(SimHash.mix(sim.room.rng_seed, PLAN_SALT));
        long k0 = s.exit_side, k1 = s.exit_a_y, k2 = s.exit_a_kind, k3 = s.exit_b_y, k4 = s.exit_b_kind;
        s.plan_at = at;
        s.plan_a_y_left = 0;
        s.plan_b_y_left = 0;
        s.plan_a_y_right = 0;
        s.plan_b_y_right = 0;
        long heading = s.vx > 0 ? 1 : 0;
        for (long side = 0; side < 2; side++)
        {
            sim._points_also = side != heading ? 1 : -1;
            plan(sim, rng, side, at);
            sim._points_also = -1;
            if (side == 0)
            {
                s.plan_a_y_left = s.exit_a_y;
                s.plan_a_kind_left = s.exit_a_kind;
                s.plan_b_y_left = s.exit_b_y;
            }
            else
            {
                s.plan_a_y_right = s.exit_a_y;
                s.plan_a_kind_right = s.exit_a_kind;
                s.plan_b_y_right = s.exit_b_y;
            }
        }
        s.exit_side = k0;
        s.exit_a_y = k1;
        s.exit_a_kind = k2;
        s.exit_b_y = k3;
        s.exit_b_kind = k4;
    }

    public static void use_plan(GameSim sim, long side, long at)
    {
        var s = sim.state;
        if (s.plan_at != at) plan_room(sim, at);
        s.exit_side = side;
        s.exit_a_y = side == 0 ? s.plan_a_y_left : s.plan_a_y_right;
        s.exit_a_kind = side == 0 ? s.plan_a_kind_left : s.plan_a_kind_right;
        s.exit_b_y = side == 0 ? s.plan_b_y_left : s.plan_b_y_right;
        s.exit_b_kind = _other_kind(s.exit_a_kind);
    }

    public static long planned_y(GameSim sim, long side, long y)
    {
        var s = sim.state;
        long a = side == 0 ? s.plan_a_y_left : s.plan_a_y_right;
        long kind = side == 0 ? s.plan_a_kind_left : s.plan_a_kind_right;
        long b = side == 0 ? s.plan_b_y_left : s.plan_b_y_right;
        if (kind != ExitKind.NORMAL && G.absi(b - y) < G.absi(a - y)) return b;
        return a;
    }

    public static bool reserved(GameSim sim, long side, long y)
    {
        var s = sim.state;
        long reach = SimConfig.EXIT_HALF + SimConfig.SPIKE_HALF_BASE;
        long a = side == 0 ? s.plan_a_y_left : s.plan_a_y_right;
        long kind = side == 0 ? s.plan_a_kind_left : s.plan_a_kind_right;
        long b = side == 0 ? s.plan_b_y_left : s.plan_b_y_right;
        if (G.absi(y - a) < reach) return true;
        return kind != ExitKind.NORMAL && G.absi(y - b) < reach;
    }

    static long _nearest_free(GameSim sim, long first, long last, long fallback)
    {
        long c0 = SimConfig.slot_center_y(0);
        long lo = (SimConfig.EXIT_MIN_Y - c0 + SimConfig.SLOT_SIZE - 1) / SimConfig.SLOT_SIZE;
        long hi = (SimConfig.EXIT_MAX_Y - c0) / SimConfig.SLOT_SIZE;
        long best = fallback;
        long best_d = -1;
        for (long slot = lo; slot < hi + 1; slot++)
        {
            if (blocked(sim, SimConfig.slot_center_y(slot))) continue;
            long near = G.clampi(slot, first, last);
            long d = G.absi(slot - near);
            if (best_d < 0 || d < best_d)
            {
                best = near;
                best_d = d;
            }
        }
        return best;
    }

    public const long FORK_APART = 3 * SimConfig.SLOT_SIZE;

    static long _free_apart(GameSim sim, long y, long other)
    {
        long c0 = SimConfig.slot_center_y(0);
        long lo = (SimConfig.EXIT_MIN_Y - c0 + SimConfig.SLOT_SIZE - 1) / SimConfig.SLOT_SIZE;
        long hi = (SimConfig.EXIT_MAX_Y - c0) / SimConfig.SLOT_SIZE;
        long best = y;
        long best_d = -1;
        for (long slot = lo; slot < hi + 1; slot++)
        {
            long cy = SimConfig.slot_center_y(slot);
            if (G.absi(cy - other) < FORK_APART || blocked(sim, cy)) continue;
            long d = G.absi(cy - y);
            if (best_d < 0 || d < best_d)
            {
                best = cy;
                best_d = d;
            }
        }
        return best;
    }

    static long _other_kind(long kind)
    {
        if (kind == ExitKind.CALM) return ExitKind.WILD;
        if (kind == ExitKind.WILD) return ExitKind.CALM;
        return ExitKind.NORMAL;
    }

    public static long random_y(GameSim sim, SimRng rng, long lo, long hi)
    {
        long c0 = SimConfig.slot_center_y(0);
        long first = (lo - c0 + SimConfig.SLOT_SIZE - 1) / SimConfig.SLOT_SIZE;
        long last = (hi - c0) / SimConfig.SLOT_SIZE;
        var open = new List<long>();
        for (long slot = first; slot < last + 1; slot++)
            if (!blocked(sim, SimConfig.slot_center_y(slot))) open.Add(slot);
        if (open.Count == 0)
        {
            long any = first + rng.next_below(last - first + 1);
            if (sim.room.def.reach > 0)
                any = G.clampi((sim.state.anchor_y - c0 + SimConfig.SLOT_SIZE / 2) / SimConfig.SLOT_SIZE, first, last);
            else
                any = _nearest_free(sim, first, last, any);
            return SimConfig.slot_center_y(any);
        }
        return SimConfig.slot_center_y(open[(int)rng.next_below(open.Count)]);
    }

    public static bool blocked(GameSim sim, long y)
    {
        if (_blocked_now(sim, y)) return true;
        if (sim._points_also < 0) return false;
        long keep = sim._points_override;
        sim._points_override = sim._points_also;
        bool out_ = _blocked_now(sim, y);
        sim._points_override = keep;
        return out_;
    }

    static bool _blocked_now(GameSim sim, long y)
    {
        if (sim.room.def.reach > 0 && G.absi(y - sim.state.anchor_y) > sim.room.def.reach) return true;
        for (int i = 0; i < sim.room.hazards.Count; i++)
        {
            var h = sim.room.hazards[i];
            if (h.alive && h.blocks_exit(sim, sim.state.exit_side, y)) return true;
        }
        return in_mouth(sim, sim.state.exit_side, y);
    }

    public const long MOUTH_STEP = 4 * SimConfig.SUB;

    public static bool in_mouth(GameSim sim, long side, long y)
    {
        var s = sim.state;
        long r = SimConfig.BIRD_RADIUS;
        long keep_x = s.x;
        long keep_y = s.y;
        long wall = side == 0 ? sim.room.wall_left() + r : sim.room.wall_right() - r;
        long dir = side == 0 ? 1 : -1;
        bool out_ = false;
        foreach (long dx in new[] { 0, r / 2, r - 1 })
        {
            long dy = -SimConfig.EXIT_HALF;
            while (dy <= SimConfig.EXIT_HALF && !out_)
            {
                s.x = wall + dir * dx;
                s.y = y + dy;
                for (int i = 0; i < sim.room.hazards.Count; i++)
                {
                    var h = sim.room.hazards[i];
                    if (h.alive && h.kills(sim))
                    {
                        out_ = true;
                        break;
                    }
                }
                dy += MOUTH_STEP;
            }
            if (out_) break;
        }
        s.x = keep_x;
        s.y = keep_y;
        return out_;
    }
}
