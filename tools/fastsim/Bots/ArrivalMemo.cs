namespace FastSim;

/// Planner copies only (`GameSim.memo_arrivals`, set by BlindPlanner.blind_copy):
/// remembers `GameSim._arrival_retries` (the portal arrival check, which plays
/// up to 32 x 5 short arrivals on copies). In a beam every line that takes the
/// exit at the same moment asks the same question, and the answer depends only
/// on what goes into this key: the state, but for the fields the arrival never
/// reads (`SKIP`: x, y, vx and vy are overwritten before they are read; the
/// counters and the tick are read only by revive and the painters), both RNGs, the new room's seed, the free
/// run of the last wall and the points overrides. The old room is replaced by
/// `_enter_room` before anything reads it. The real game never uses this, so
/// parity is untouched; `rl review speed --memo 0` checks the planner plays the
/// same taps without it. Tool only.
public static class ArrivalMemo
{
    public static bool on = true;
    /// Check mode: on a hit, run the check anyway and count answers that differ.
    public static bool verify = false;
    public static long wrong;
    static readonly HashSet<string> SKIP = new()
        { "x", "y", "vx", "vy", "tick", "flaps", "coins", "pickup_x", "pickup_y", "death_cause", "revives" };
    public static long hits, misses;

    static readonly System.Reflection.FieldInfo[] FIELDS = typeof(SimState).GetFields(
        System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance);

    sealed class KeyEq : IEqualityComparer<long[]>
    {
        public bool Equals(long[] a, long[] b) => a.AsSpan().SequenceEqual(b);

        public int GetHashCode(long[] a)
        {
            long h = SimHash.SEED;
            foreach (long v in a) h = SimHash.mix(h, v);
            return (int)(h ^ (h >> 32));
        }
    }

    [ThreadStatic] static Dictionary<long[], (long skip, long wait)> _memo;

    static long[] key(GameSim sim, long side, long next)
    {
        var k = new List<long>(FIELDS.Length + 20) { side, next };
        foreach (var f in FIELDS)
        {
            if (SKIP.Contains(f.Name)) continue;
            object v = f.GetValue(sim.state);
            k.Add(v is bool b ? (b ? 1 : 0) : (long)v);
        }
        foreach (var r in new[] { sim._rng, sim._spine }) k.AddRange(new[] { r._s0, r._s1, r._s2, r._s3 });
        k.AddRange(new[] { sim.room.rng_seed, sim._free_lo, sim._free_hi, sim._points_override, sim._points_also,
            sim.season, sim.practice_room, sim.forced_variant.GetHashCode(), sim._checking ? 1 : 0 });
        return k.ToArray();
    }

    public static long retries(GameSim sim, long side, long next)
    {
        if (!on) return sim._arrival_retries(side, next);
        var k = key(sim, side, next);
        _memo ??= new Dictionary<long[], (long, long)>(new KeyEq());
        if (_memo.TryGetValue(k, out var got))
        {
            if (verify)
            {
                long s2 = sim._arrival_retries(side, next);
                if (s2 != got.skip || sim._arrival_wait != got.wait) Interlocked.Increment(ref wrong);
            }
            Interlocked.Increment(ref hits);
            sim._arrival_wait = got.wait;
            return got.skip;
        }
        Interlocked.Increment(ref misses);
        long skip = sim._arrival_retries(side, next);
        if (_memo.Count > 4096) _memo.Clear();
        _memo[k] = (skip, sim._arrival_wait);
        return skip;
    }
}
