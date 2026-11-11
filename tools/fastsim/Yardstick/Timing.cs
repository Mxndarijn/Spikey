namespace FastSim.Yard;

/// Tap timing against the ideal moment (Isaksen et al., FDG 2015). A press is
/// a tap, or a burst of taps no more than PRESS_GAP ticks apart (a bot can tap
/// on many ticks in a row; a human finger makes one press). For a press at
/// tick t, move it to t+d for every d in -SHIFT..SHIFT, keep the run's other
/// taps where they were, and replay: the shifts after which the bird is still
/// alive HORIZON ticks past t+SHIFT form the press's window. The ideal moment
/// is the window's middle and the press's error is its distance from it
/// (positive = late). Only presses whose window is closed on both sides are
/// timing-critical; for the others any time nearby works. This replays the
/// real sim, but only to judge a tap already made, never to make one.
public static class Timing
{
    public const int SHIFT = 12;
    public const long HORIZON = 40;
    public const int PRESS_GAP = 3;

    public sealed class Result
    {
        public int taps_judged, critical;
        /// Press tick minus the ideal tick, for the timing-critical presses.
        public List<double> errors = new();
        public List<int> widths = new();
    }

    /// The presses of a run: (first tick, taps in it).
    public static List<(long at, long[] taps)> presses(long[] taps)
    {
        var out_ = new List<(long, long[])>();
        int i = 0;
        while (i < taps.Length)
        {
            int j = i;
            while (j + 1 < taps.Length && taps[j + 1] - taps[j] <= PRESS_GAP) j++;
            out_.Add((taps[i], taps[i..(j + 1)]));
            i = j + 1;
        }
        return out_;
    }

    /// Judges up to `per_run` presses of the run, spread evenly over it.
    public static Result judge(RunInput r, Run played, int per_run)
    {
        var res = new Result();
        long last_ok = played.ticks - SHIFT - HORIZON - 1;
        var all = presses(r.taps);
        var cand = all.Where(p => p.at >= played.start_tick + SHIFT && p.taps[^1] + SHIFT <= last_ok).ToList();
        if (cand.Count == 0) return res;
        int want = Math.Min(per_run, cand.Count);
        var pick = Enumerable.Range(0, want).Select(i => cand[(int)((long)i * cand.Count / want)]).Distinct().ToList();
        var tapset = new HashSet<long>(r.taps);
        var sim = new GameSim(r.seed, r.season);
        foreach (var (t, press) in pick)
        {
            long from = t - SHIFT;
            if (sim.state.tick > from) continue;
            while (sim.state.tick < from && !sim.is_over()) sim.step(tapset.Contains(sim.state.tick));
            if (sim.is_over()) break;
            var mine = new HashSet<long>(press);
            long end = press[^1] + SHIFT + HORIZON;
            var ok = new bool[2 * SHIFT + 1];
            for (int d = -SHIFT; d <= SHIFT; d++)
            {
                if (d == 0)
                {
                    ok[SHIFT] = true;
                    continue;
                }
                var c = sim.clone_deep();
                while (c.state.tick < end && !c.is_over())
                {
                    long k = c.state.tick;
                    bool tap = mine.Contains(k - d) || (!mine.Contains(k) && tapset.Contains(k));
                    c.step(tap);
                }
                ok[d + SHIFT] = !c.is_over();
            }
            res.taps_judged++;
            int lo = SHIFT, hi = SHIFT;
            while (lo > 0 && ok[lo - 1]) lo--;
            while (hi < 2 * SHIFT && ok[hi + 1]) hi++;
            if (lo == 0 || hi == 2 * SHIFT) continue;
            res.critical++;
            res.widths.Add(hi - lo + 1);
            res.errors.Add(SHIFT - (lo + hi) / 2.0);
        }
        return res;
    }
}
