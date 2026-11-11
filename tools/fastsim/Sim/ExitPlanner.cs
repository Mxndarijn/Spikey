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

    public static void plan(GameSim sim, SimRng rng, long side, long at)
    {
        sim.state.exit_side = side;
        bool fork = at % SimConfig.FORK_EVERY == 0 && !sim.is_practice();
        if (fork)
        {
            long top = random_y(sim, rng, SimConfig.EXIT_MIN_Y, SimConfig.FORK_SPLIT_Y - SimConfig.EXIT_HALF);
            long bottom = random_y(sim, rng, SimConfig.FORK_SPLIT_Y + SimConfig.EXIT_HALF, SimConfig.EXIT_MAX_Y);
            bool calm_on_top = rng.next_below(2) == 0;
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
                any = G.clampi((sim.state.y - c0 + SimConfig.SLOT_SIZE / 2) / SimConfig.SLOT_SIZE, first, last);
            return SimConfig.slot_center_y(any);
        }
        return SimConfig.slot_center_y(open[(int)rng.next_below(open.Count)]);
    }

    public static bool at_bird(GameSim sim, long side)
    {
        var s = sim.state;
        s.exit_side = side;
        long c0 = SimConfig.slot_center_y(0);
        long slot = G.clampi((s.y - c0 + SimConfig.SLOT_SIZE / 2) / SimConfig.SLOT_SIZE, 0, SimConfig.SLOT_COUNT - 1);
        long y = SimConfig.slot_center_y(slot);
        if (blocked(sim, y)) return false;
        if (s.exit_b_kind != ExitKind.NORMAL && s.y >= SimConfig.FORK_SPLIT_Y)
            s.exit_b_y = y;
        else
            s.exit_a_y = y;
        return true;
    }

    public static bool blocked(GameSim sim, long y)
    {
        if (sim.room.def.reach > 0 && G.absi(y - sim.state.y) > sim.room.def.reach) return true;
        for (int i = 0; i < sim.room.hazards.Count; i++)
        {
            var h = sim.room.hazards[i];
            if (h.alive && h.blocks_exit(sim, sim.state.exit_side, y)) return true;
        }
        return false;
    }
}
