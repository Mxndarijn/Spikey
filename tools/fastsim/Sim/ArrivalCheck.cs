namespace FastSim;

/// Port of sim/arrival_check.gd.
public static class ArrivalCheck
{
    static readonly long[] OFFSETS = { 0, -24 * SimConfig.SUB, 24 * SimConfig.SUB };
    static readonly long[] HOLD_SHIFTS = { 0, -60 * SimConfig.SUB, 60 * SimConfig.SUB };

    public static long score(GameSim sim)
    {
        long y0 = sim.state.y;
        long n = 0;
        while (n < SimConfig.ARRIVAL_BLIND)
        {
            sim.step(_toward(sim, y0));
            if (sim.is_over()) return n;
            n += 1;
        }
        long best = 0;
        long second = 0;
        for (long kind = 0; kind < 2; kind++)
        {
            for (long i = 0; i < 3; i++)
            {
                var c = sim.clone_deep();
                long lived = _follow(c, kind, i, y0);
                if (lived > best)
                {
                    second = best;
                    best = lived;
                }
                else if (lived > second)
                {
                    second = lived;
                }
                if (second >= SimConfig.ARRIVAL_FOLLOW) return n + second;
            }
        }
        return n + second;
    }

    static long _follow(GameSim sim, long kind, long i, long y0)
    {
        long n = 0;
        while (n < SimConfig.ARRIVAL_FOLLOW)
        {
            long target = y0 + HOLD_SHIFTS[i];
            if (kind == 0) target = gap_target(sim) + OFFSETS[i];
            sim.step(_toward(sim, target));
            if (sim.is_over()) return n;
            n += 1;
        }
        return n;
    }

    public static bool _toward(GameSim sim, long target)
    {
        long g = sim.room.def.gravity_sign;
        return (sim.state.y - target) * g > 0 && sim.state.vy * g >= 0;
    }

    public static long gap_target(GameSim sim)
    {
        var s = sim.state;
        long side = s.vx > 0 ? 1 : 0;
        if (s.exit_open && s.exit_side == side) return s.exit_a_y;
        long mask = sim.wall_mask(side);
        long best_start = 0;
        long best_len = 0;
        long run_start = 0;
        long run_len = 0;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            if (RoomRules.has_slot(mask, slot))
            {
                run_len = 0;
                continue;
            }
            if (run_len == 0) run_start = slot;
            run_len += 1;
            if (run_len > best_len)
            {
                best_len = run_len;
                best_start = run_start;
            }
        }
        if (best_len == 0) return s.y;
        long top = SimConfig.slot_center_y(best_start);
        long mid = (top + SimConfig.slot_center_y(best_start + best_len - 1)) / 2;
        return mid + sim.wall_shift(side);
    }
}
