using System.Text.Json.Nodes;

namespace FastSim.Yard;

/// The leak check: does a bot use what is not on screen yet? The same seed is
/// played twice by two fresh copies of the bot. At a fork tick T (just after
/// a wall bounce, so the screens stay the same for a whole flight) the second
/// sim gets every hidden draw replaced (BlindPlanner.blind_copy: the sim's
/// RNG, so the next walls, the portal, the next room, plus the hazards'
/// hidden salts, private RNGs and drawn-but-unshown values). Both bots have
/// seen the same screen so far, so until the first tick where something
/// visible differs between the two sims, an honest bot taps the same. A tap
/// that differs before then came from the hidden future: a leak.
/// "Visible" is everything in the sim but those hidden values (`visible`).
/// Hidden values that blind_copy does not replace are not tested.
public static class Leak
{
    public static readonly long[] FORKS = { 200, 700, 1500, 3000, 5000, 8000 };
    public const long WINDOW = 400;

    /// The sim's checksum with the hidden values blind_copy replaces set to
    /// fixed values (keep the two lists in step).
    public static long visible(GameSim sim)
    {
        var c = sim.clone_deep();
        foreach (var hz in c.room.hazards)
        {
            switch (hz)
            {
                case CrateDrop cd: cd.salt = 0; break;
                case Dart d: d.salt = 0; break;
                case Drop dr: dr._rng.reseed(0); break;
                case Firework fw: fw._rng.reseed(0); break;
                case OrchardSpawner os: os._rng.reseed(0); break;
                case Bubble b: b.next_x = 0; break;
                case Stalactite st when st.gap_y != st.target_y:
                    st.target_y = st.gap_y + Math.Sign(st.target_y - st.gap_y);
                    break;
                case KeepyBall kb when kb.waiting > 0 && c.room.t < KeepyBall.SECOND_DROP:
                    kb.x = 0;
                    break;
                case Beam bm:
                {
                    var idle = new List<int>();
                    for (int i = 0; i < bm.delays.Count; i++)
                        if (bm.t < bm.delays[i]) idle.Add(i);
                    var vals = idle.Select(i => bm.delays[i]).OrderBy(x => x).ToList();
                    for (int i = 0; i < idle.Count; i++) bm.delays[idle[i]] = vals[i];
                    break;
                }
                case Updraft up when up.drift_span == 0 && up.gust != Updraft.Gust.NONE && up.t + up.phase < Updraft.GUST_OFF:
                    up.phase = 0;
                    break;
            }
        }
        return c.room.checksum(c.state.checksum());
    }

    public sealed record Fork(long seed, long at, string verdict, long first_diff_tap, long visible_from);

    /// One fork: "same" (no tap differs before the screen does), "leak",
    /// "nondeterministic" (the two runs differ before the fork), or "dead"
    /// (the run ended before T).
    public static Fork fork(BotSpec bot, long seed, long at)
    {
        var a = bot.make(seed);
        var b = bot.make(seed);
        var sa = new GameSim(seed);
        var sb = new GameSim(seed);
        // Fork right after a bounce at or past `at`: the next wall is drawn at
        // the next bounce, so the screens then stay the same for a whole flight.
        bool bounced = false;
        while (sa.state.tick < at || !bounced)
        {
            if (sa.state.tick >= at + 300) break;
            if (sa.is_over() || sb.is_over()) return new Fork(seed, at, "dead", -1, -1);
            bool ta = a(sa), tb = b(sb);
            if (ta != tb) return new Fork(seed, at, "nondeterministic", sa.state.tick, -1);
            sa.step(ta);
            sb.step(tb);
            bounced = sa.state.tick > at && sa.events.Contains(Event.BOUNCE);
        }
        if (sa.is_over() || !bounced) return new Fork(seed, at, "dead", -1, -1);
        at = sa.state.tick;
        // Both sims are swapped for copies, so a bot that remembers hazards by
        // object sees new objects in both runs alike; only B's hidden draws change.
        sa = sa.clone_deep();
        sb = BlindPlanner.blind_copy(sb, new SimRng(seed * 7919 + at));
        long visible_from = -1, first_diff = -1;
        while (sa.state.tick < at + WINDOW && !sa.is_over() && !sb.is_over())
        {
            long t = sa.state.tick;
            if (visible_from < 0 && visible(sa) != visible(sb)) visible_from = t;
            bool ta = a(sa), tb = b(sb);
            if (ta != tb && first_diff < 0) first_diff = t;
            if (visible_from >= 0) break;
            sa.step(ta);
            sb.step(tb);
        }
        bool leak = first_diff >= 0 && (visible_from < 0 || first_diff < visible_from);
        return new Fork(seed, at, leak ? "leak" : "same", first_diff, visible_from);
    }

    public static JsonObject check(BotSpec bot, int seeds, int threads)
    {
        var jobs = Enumerable.Range(1, seeds).SelectMany(s => FORKS.Select(t => ((long)s, t))).ToList();
        var res = new Fork[jobs.Count];
        Parallel.For(0, jobs.Count, new ParallelOptions { MaxDegreeOfParallelism = threads },
            i => res[i] = fork(bot, jobs[i].Item1, jobs[i].Item2));
        int leaks = res.Count(f => f.verdict == "leak"), tested = res.Count(f => f.verdict is "leak" or "same");
        int nondet = res.Count(f => f.verdict == "nondeterministic");
        var ex = res.FirstOrDefault(f => f.verdict == "leak");
        string verdict = nondet > 0 ? "nondeterministic" : tested == 0 ? "untested" : leaks > 0 ? "yes" : "no";
        var o = new JsonObject
        {
            ["leaks"] = verdict,
            ["forks_tested"] = tested,
            ["forks_leaking"] = leaks,
            ["nondeterministic"] = nondet,
            // How long the screens stayed the same after the forks: the test only sees leaks inside that time.
            ["same_screen_ticks_median"] = Stats.pct(res.Where(f => f.verdict is "leak" or "same")
                .Select(f => (double)((f.visible_from < 0 ? f.at + WINDOW : f.visible_from) - f.at)), 0.5),
            ["how"] = "same seed twice, every hidden draw replaced at the fork; a tap differing before anything visible differs is a leak",
        };
        if (ex != null)
            o["example"] = $"seed {ex.seed}, fork at tick {ex.at}: taps differ at tick {ex.first_diff_tap}, " +
                (ex.visible_from < 0 ? "nothing visible differed yet" : $"the screen differed only from tick {ex.visible_from}");
        return o;
    }
}
