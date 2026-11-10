namespace FastSim;

public static class RoomRules
{
    public const long GAP_REACH = 200 * SimConfig.SUB;

    public static long spike_count(long score, RoomDef def, long bonus = 0)
    {
        if (!def.spikes) return 0;
        long n = SimConfig.BASE_SPIKES + score / SimConfig.POINTS_PER_EXTRA_SPIKE + def.extra_spikes;
        long room_for_spikes = SimConfig.SLOT_COUNT - def.gap;
        return G.maxi(G.mini(G.mini(n, def.max_spikes) + bonus, room_for_spikes), 1);
    }

    public static long gap_reach(RoomDef def)
    {
        if (def.reach > 0) return def.reach;
        if (def.hazards.Count > 0 || def.combos.Count > 0) return GAP_REACH;
        // Rooms that keep their hazards only in variants count too.
        foreach (var variant in def.variants)
        {
            if (variant.hazards.Count > 0) return GAP_REACH;
        }
        return 0;
    }

    [ThreadStatic] static long[] _candidates;

    public static long generate_wall(SimRng rng, long score, RoomDef def, long bird_y = -1, long bonus = 0)
    {
        long n = spike_count(score, def, bonus);
        if (n == 0) return 0;
        long gap = def.gap;
        long lo = 0;
        long hi = SimConfig.SLOT_COUNT - gap;
        long reach = gap_reach(def);
        if (bird_y >= 0 && reach > 0)
        {
            long first = hi;
            long last = lo;
            for (long start = lo; start < hi + 1; start++)
            {
                long center = SimConfig.slot_center_y(start) + (gap - 1) * SimConfig.SLOT_SIZE / 2;
                if (G.absi(center - bird_y) <= reach)
                {
                    first = G.mini(first, start);
                    last = G.maxi(last, start);
                }
            }
            if (first <= last)
            {
                lo = first;
                hi = last;
            }
        }
        long gap_start = lo + rng.next_below(hi - lo + 1);
        var candidates = _candidates ??= new long[SimConfig.SLOT_COUNT];
        int count = 0;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
            if (slot < gap_start || slot >= gap_start + gap) candidates[count++] = slot;
        long mask = 0;
        for (long i = 0; i < n; i++)
        {
            long j = i + rng.next_below(count - i);
            long picked = candidates[j];
            candidates[j] = candidates[i];
            candidates[i] = picked;
            mask |= 1L << (int)picked;
        }
        return mask;
    }

    public static bool has_slot(long mask, long slot) => ((mask >> (int)slot) & 1) == 1;

    public static long longest_gap(long mask)
    {
        long best = 0, run = 0;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            if (has_slot(mask, slot)) run = 0;
            else { run++; best = G.maxi(best, run); }
        }
        return best;
    }
}
