namespace FastSim;

/// Port of tests/support/planner_bot.gd (and SimBots._gap_center_y).
public sealed class PlannerBot
{
    public const long HORIZON = 120;
    public const long ROLLOUTS = 4;

    SimRng _rng;

    public PlannerBot(long seed_value = 1) { _rng = new SimRng(seed_value); }

    public bool decide(GameSim sim)
    {
        if (!sim.state.started) return true;
        long tap = _value(sim, true);
        long wait = _value(sim, false);
        return tap > wait;
    }

    long _value(GameSim sim, bool first)
    {
        long best = -1;
        for (long r = 0; r < ROLLOUTS; r++)
        {
            var c = sim.clone_deep();
            c.step(first);
            var prng = new SimRng(_rng.next_u32());
            long n = 0;
            while (n < HORIZON && !c.is_over())
            {
                c.step(_policy(c, prng, r));
                n += 1;
            }
            long room_gain = c.state.room_index - sim.state.room_index;
            long gain = (c.state.score - sim.state.score) * 3 + room_gain * 40 + c.state.coins;
            long value = n * 100 + gain;
            best = G.maxi(best, value);
            if (n >= HORIZON && r > 0) break;
        }
        return best;
    }

    static bool _policy(GameSim sim, SimRng rng, long kind)
    {
        switch (kind)
        {
            case 1: return rng.next_below(9) == 0;
            case 2: return rng.next_below(16) == 0;
            case 3: return false;
        }
        return aim(sim, rng);
    }

    public static bool aim(GameSim sim, SimRng rng)
    {
        var s = sim.state;
        long side = s.vx > 0 ? 1 : 0;
        long target = gap_center_y(sim.wall_mask(side));
        if (s.exit_open && s.exit_side == side)
        {
            target = s.exit_a_y;
            if (s.exit_b_kind == ExitKind.WILD) target = s.exit_b_y;
        }
        long jitter = (rng.next_below(9) - 4) * SimConfig.SUB;
        long margin = 6 * SimConfig.SUB;
        if (sim.room.def.gravity_sign < 0) return s.y < target - margin - jitter && s.vy <= 0;
        return s.y > target + margin + jitter && s.vy >= 0;
    }

    public static long gap_center_y(long mask)
    {
        long best_start = 0, best_len = 0, run_start = 0, run_len = 0;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            if (RoomRules.has_slot(mask, slot)) run_len = 0;
            else
            {
                if (run_len == 0) run_start = slot;
                run_len += 1;
                if (run_len > best_len)
                {
                    best_len = run_len;
                    best_start = run_start;
                }
            }
        }
        long top = SimConfig.SLOT_TOP + best_start * SimConfig.SLOT_SIZE;
        return top + best_len * SimConfig.SLOT_SIZE / 2;
    }
}
