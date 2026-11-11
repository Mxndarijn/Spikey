namespace FastSim;

/// Port of tests/support/sim_bots.gd (the bots the checks use).
public static class SimBots
{
    /// Aims for the middle of the largest gap on the wall ahead.
    public static bool gap_seeker(GameSim sim, SimRng rng)
    {
        var s = sim.state;
        if (!s.started) return true;
        long side = s.vx > 0 ? 1 : 0;
        long mask = sim.wall_mask(side);
        long target = PlannerBot.gap_center_y(mask);
        // Head for the exit when it is on the wall ahead (Wild at a fork).
        if (s.exit_open && s.exit_side == side)
        {
            target = s.exit_a_y;
            if (s.exit_b_kind == ExitKind.WILD) target = s.exit_b_y;
        }
        long jitter = (rng.next_below(9) - 4) * SimConfig.SUB;
        long margin = 6 * SimConfig.SUB;
        return s.y > target + margin + jitter && s.vy >= 0;
    }
}
