namespace FastSim.Rl;

/// Turns the sim into the RL bot's observation (docs/RL_BOT.md). Reads the
/// sim only: the danger grid moves the bird to each probe point, asks every
/// live hazard's kills() and puts the bird back, so the sim is unchanged
/// (the rlbot check holds this with checksums).
public static class Observer
{
    /// Bump when the layout below changes: old policy files stop loading.
    public const int LAYOUT = 3;
    public const int COLS = 10, ROWS = 15;
    public const long COL_STEP = 24 * SimConfig.SUB;
    public const long ROW_STEP = 24 * SimConfig.SUB;
    public const int GRID = COLS * ROWS;
    /// Ticks between the grid now and the motion grid.
    public const int MOTION = 6;
    public const int STRIP = 21;
    public const long STRIP_STEP = 16 * SimConfig.SUB;
    public const int BASE = 28 + STRIP + 6;
    /// One tick's frame: the base features and that tick's grid.
    public const int FRAME = BASE + GRID;
    /// The policy's input: a frame plus the grid MOTION ticks before it.
    public const int INPUTS = FRAME + GRID;

    /// Fills `f` (FRAME floats) with what the bird sees this tick.
    public static void frame(GameSim sim, float[] f)
    {
        var s = sim.state;
        int i = 0;
        long side = s.vx > 0 ? 1 : 0;
        f[i++] = (float)s.y / SimConfig.WORLD_H * 2f - 1f;
        f[i++] = (float)s.vy / SimConfig.MAX_FALL_VY;
        f[i++] = side == 1 ? 1f : -1f;
        f[i++] = sim.room.gravity < 0 ? -1f : 1f;
        f[i++] = Math.Min(sim.steps_to_wall(side), 120) / 60f - 1f;
        f[i++] = (float)sim.room.wall_left() / SimConfig.WORLD_W * 4f;
        f[i++] = (float)(SimConfig.WORLD_W - sim.room.wall_right()) / SimConfig.WORLD_W * 4f;
        long mask = sim.wall_mask(side);
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++) f[i++] = RoomRules.has_slot(mask, slot) ? 1f : -1f;
        long shift = sim.wall_shift(side);
        f[i++] = (float)shift / SimConfig.SLOT_SIZE;
        // The free run nearest the bird on the wall ahead: its centre (relative) and size.
        var (gap_y, gap_len) = nearest_gap(mask, s.y - shift);
        f[i++] = Math.Clamp((float)(gap_y + shift - s.y) / (SimConfig.WORLD_H / 2), -1f, 1f);
        f[i++] = gap_len / 6f;
        bool ahead = s.exit_open && s.exit_side == side;
        f[i++] = ahead ? 1f : 0f;
        f[i++] = s.exit_preview ? 1f : 0f;
        f[i++] = ahead ? Math.Clamp((float)(s.exit_a_y - s.y) / (SimConfig.WORLD_H / 2), -1f, 1f) : 0f;
        bool two = ahead && s.exit_b_kind != ExitKind.NORMAL;
        f[i++] = two ? Math.Clamp((float)(s.exit_b_y - s.y) / (SimConfig.WORLD_H / 2), -1f, 1f) : 0f;
        f[i++] = two ? 1f : 0f;
        // The wall ahead around the bird's height: 1 where a bird at that
        // height would hit a spike (or the ceiling or floor) at the wall.
        long hb = sim.room.spike_half_base();
        for (int k = 0; k < STRIP; k++) f[i++] = wall_hits(mask, shift, hb, s.y + (k - STRIP / 2) * STRIP_STEP) ? 1f : -1f;
        // Where the bird reaches the wall if it waits, and if it taps now
        // (its own fall only: what a player judges by eye).
        long steps = sim.steps_to_wall(side);
        for (int tn = 0; tn < 2; tn++)
        {
            bool tap = tn == 1;
            long y = fall(sim, steps, tap);
            f[i++] = Math.Clamp((float)(y - s.y) / (SimConfig.WORLD_H / 2), -1f, 1f);
            f[i++] = wall_hits(mask, shift, hb, y) ? 1f : -1f;
            f[i++] = Math.Clamp((float)(safe_near(mask, shift, hb, y) - y) / (SimConfig.WORLD_H / 4), -1f, 1f);
        }
        // i == BASE
        grid(sim, f, BASE);
    }

    /// Whether a bird at height `y` touching the wall hits a spike there, the ceiling or the floor.
    public static bool wall_hits(long mask, long shift, long hb, long y)
    {
        long r = SimConfig.BIRD_RADIUS;
        if (y - r <= SimConfig.KILL_TOP || y + r >= SimConfig.KILL_BOTTOM) return true;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
            if (RoomRules.has_slot(mask, slot) && Math.Abs(y - SimConfig.slot_center_y(slot) - shift) <= hb + r) return true;
        return false;
    }

    /// The height nearest `y` where the wall is safe (or `y` if none is).
    public static long safe_near(long mask, long shift, long hb, long y)
    {
        const long STEP = 4 * SimConfig.SUB;
        for (long d = 0; d <= SimConfig.WORLD_H; d += STEP)
        {
            if (!wall_hits(mask, shift, hb, y - d)) return y - d;
            if (!wall_hits(mask, shift, hb, y + d)) return y + d;
        }
        return y;
    }

    /// The bird's height after `steps` moves with no tap (or one tap now).
    public static long fall(GameSim sim, long steps, bool tap)
    {
        long g = SimConfig.GRAVITY * sim.room.gravity;
        long vy = tap ? SimConfig.FLAP_VY * sim.room.gravity : sim.state.vy;
        long y = sim.state.y;
        for (long n = 0; n < steps; n++)
        {
            vy = Math.Clamp(vy + g, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY);
            y += vy;
        }
        return y;
    }

    /// Centre y and length (slots) of the free run on `mask` closest to `y`.
    public static (long y, long len) nearest_gap(long mask, long y)
    {
        long best_y = SimConfig.WORLD_H / 2, best_len = 0, best_d = long.MaxValue;
        long slot = 0;
        while (slot < SimConfig.SLOT_COUNT)
        {
            if (RoomRules.has_slot(mask, slot))
            {
                slot++;
                continue;
            }
            long start = slot;
            while (slot < SimConfig.SLOT_COUNT && !RoomRules.has_slot(mask, slot)) slot++;
            long len = slot - start;
            long top = SimConfig.SLOT_TOP + start * SimConfig.SLOT_SIZE;
            long bottom = top + len * SimConfig.SLOT_SIZE;
            long d = y < top ? top - y : y > bottom ? y - bottom : 0;
            if (d < best_d)
            {
                best_d = d;
                best_y = (top + bottom) / 2;
                best_len = len;
            }
        }
        return (best_y, best_len);
    }

    static readonly System.Collections.Concurrent.ConcurrentDictionary<Type, bool> _guards = new();

    /// Whether the hazard's type overrides guards_edge (the base answers
    /// false), so the others need no copy to ask.
    static bool can_guard(Hazard h) =>
        _guards.GetOrAdd(h.GetType(), t => t.GetMethod(nameof(Hazard.guards_edge))!.DeclaringType != typeof(Hazard));

    /// The danger grid: 1 where a bird would be killed by a hazard, the
    /// ceiling or the floor, -1 where not.
    public static void grid(GameSim sim, float[] f, int at)
    {
        // Hazards may write the bird while answering (EdgePad.guards_edge
        // bounces it), so the bird's state is put back afterwards.
        var saved = sim.state.copy();
        var s = sim.state;
        long x0 = s.x, y0 = s.y;
        long dir = s.vx > 0 ? 1 : -1;
        var hz = sim.room.hazards;
        long r = SimConfig.BIRD_RADIUS;
        long reach = (ROWS / 2) * ROW_STEP + r;
        bool need_top = y0 - reach <= SimConfig.KILL_TOP;
        bool need_bottom = y0 + reach >= SimConfig.KILL_BOTTOM;
        int k = at;
        for (int c = 0; c < COLS; c++)
        {
            long px = x0 + dir * c * COL_STEP;
            // Ceiling and floor guards (bounce pads), only when a probe row
            // is past that edge. Asked of a copy: guarding writes the hazard.
            bool top_guard = false, bottom_guard = false;
            for (int h = 0; h < hz.Count; h++)
            {
                if (!hz[h].alive || !can_guard(hz[h])) continue;
                if (need_top && !top_guard)
                {
                    s.x = px;
                    s.y = SimConfig.KILL_TOP;
                    top_guard = hz[h].clone_deep().guards_edge(sim, true);
                }
                if (need_bottom && !bottom_guard)
                {
                    s.x = px;
                    s.y = SimConfig.KILL_BOTTOM;
                    bottom_guard = hz[h].clone_deep().guards_edge(sim, false);
                }
            }
            for (int row = 0; row < ROWS; row++)
            {
                long py = y0 + (row - ROWS / 2) * ROW_STEP;
                bool bad = (py - r <= SimConfig.KILL_TOP && !top_guard) || (py + r >= SimConfig.KILL_BOTTOM && !bottom_guard);
                if (!bad && hz.Count > 0 && px > 0 && px < SimConfig.WORLD_W)
                {
                    s.x = px;
                    s.y = py;
                    for (int h = 0; h < hz.Count; h++)
                        if (hz[h].alive && hz[h].kills(sim))
                        {
                            bad = true;
                            break;
                        }
                }
                f[k++] = bad ? 1f : -1f;
            }
        }
        sim.state = saved;
    }
}
