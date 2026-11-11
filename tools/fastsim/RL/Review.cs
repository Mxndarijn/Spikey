using System.Diagnostics;

namespace FastSim.Rl;

/// `rl review <horizon|sens|shape>`: quick measurements for the bot review
/// (SpikeCage-coord/research/bot-review.md). Tool only.
///   horizon  how far ahead a player must see: a peeking search that only
///            ever looks `h` ticks ahead (re-planned every `k` ticks), with
///            --cut 1 never past the next bounce (+8 ticks).
///   sens     the policy's median under one handicap at a time.
///   shape    the policy's score distribution against a constant death rate.
public static class Review
{
    public static int run(string what, string dir, Dictionary<string, string> opts)
    {
        string O(string k, string d) => opts.GetValueOrDefault(k, d);
        int threads = Math.Clamp(int.Parse(O("threads", "16")), 1, 16);
        int seeds = int.Parse(O("seeds", "32"));
        long cap = long.Parse(O("cap", "12000"));
        switch (what)
        {
            case "horizon":
                foreach (string h in O("h", "20,40,60,90").Split(','))
                    horizon(long.Parse(h), int.Parse(O("k", "4")), O("cut", "0") == "1", seeds, cap, threads);
                return 0;
            case "honest":
                honest(opts, seeds, cap, threads);
                return 0;
            case "sens":
                return sens(dir, seeds, threads);
            case "shape":
                return shape(dir, seeds, threads);
        }
        Console.Error.WriteLine("rl review: horizon, sens or shape");
        return 2;
    }

    static void horizon(long h, int k, bool cut, int seeds, long cap, int threads)
    {
        var clock = Stopwatch.StartNew();
        var res = new (long points, long ticks, bool dead, string room)[seeds];
        Parallel.For(0, seeds, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            var sim = new GameSim(i + 1);
            var plan = new Queue<bool>();
            int since = k;
            long n = 0;
            while (!sim.is_over() && n < cap)
            {
                if (!sim.state.started)
                {
                    sim.step(true);
                    n++;
                    continue;
                }
                if (since >= k || plan.Count == 0)
                {
                    long want = h;
                    if (cut) want = Math.Min(h, sim.steps_to_wall(sim.state.vx > 0 ? 1 : 0) + 8);
                    byte[] found = null;
                    // The longest look that still finds a way to live.
                    for (long t = want; t >= 2 && found == null; t = t * 3 / 4)
                    {
                        var s = new SurvivalSearch { max_level = 0 };
                        if (s.run(sim, t)) found = s.best_inputs;
                    }
                    plan.Clear();
                    if (found != null)
                        foreach (byte b in found) plan.Enqueue(b != 0);
                    since = 0;
                }
                sim.step(plan.Count > 0 && plan.Dequeue());
                since++;
                n++;
            }
            res[i] = (sim.state.score, n, sim.is_over(), sim.room.def.id);
        });
        long pts = res.Sum(r => r.points), deaths = res.Count(r => r.dead), ticks = res.Sum(r => r.ticks);
        // Constant death rate per point d: median = ln 2 / d.
        string med = deaths == 0 ? $"> {pts * 0.69 / 3:F0} (no deaths; 95% bound)" : $"{0.693 * pts / deaths:F0}";
        var rooms = res.Where(r => r.dead).GroupBy(r => r.room).OrderByDescending(g => g.Count()).Take(4).Select(g => $"{g.Key} {g.Count()}");
        Console.WriteLine($"horizon {h,3} ticks{(cut ? ", cut at the bounce" : "")}: {deaths} deaths in {pts} points ({ticks} ticks, {seeds} runs) -> median about {med}  [{string.Join(", ", rooms)}]  {clock.Elapsed.TotalSeconds:F0} s");
    }

    /// The BlindPlanner (Bots/BlindPlanner.cs) on full runs: deaths per 100
    /// points by score band, and how the last look before each death ended.
    static void honest(Dictionary<string, string> opts, int seeds, long cap, int threads)
    {
        long L(string k, long d) => long.Parse(opts.GetValueOrDefault(k, d.ToString()));
        long first = L("first", 0);
        var clock = Stopwatch.StartNew();
        var res = new (long points, long ticks, bool dead, string room, int look, string cause)[seeds];
        long looks = 0, fine = 0, shorter = 0, none = 0;
        string setup = "";
        Parallel.For(0, seeds, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            var sim = new GameSim(first + i + 1);
            var bot = new BlindPlanner(first + i + 1);
            bot.horizon = L("h", bot.horizon);
            bot.past = L("past", bot.past);
            bot.replan = (int)L("k", bot.replan);
            bot.mid_cost = L("mid", bot.mid_cost);
            bot.tap_cost = L("tap", bot.tap_cost);
            bot.margin = L("margin", bot.margin);
            bot.margin_cost = L("margincost", bot.margin_cost);
            bot.bucket_px = L("bpx", bot.bucket_px);
            bot.speed_buckets = L("speeds", bot.speed_buckets);
            bot.fine_px = L("fine", bot.fine_px);
            if (i == 0) setup = $"h {bot.horizon} past {bot.past} k {bot.replan} mid {bot.mid_cost} tap {bot.tap_cost} margin {bot.margin}/{bot.margin_cost} buckets {bot.bucket_px}px x{bot.speed_buckets} fine {bot.fine_px}";
            long ticks = 0;
            while (!sim.is_over() && ticks < cap)
            {
                sim.step(bot.decide(sim));
                ticks++;
            }
            Interlocked.Add(ref looks, bot.looks);
            Interlocked.Add(ref fine, bot.fine_looks);
            Interlocked.Add(ref shorter, bot.short_looks);
            Interlocked.Add(ref none, bot.no_looks);
            res[i] = (sim.state.score, ticks, sim.is_over(), sim.room.def.id + "/" + sim.room.variant_id(), bot.last_look,
                sim.is_over() ? DeathCause.NAMES[sim.state.death_cause] : "");
        });
        long pts = res.Sum(r => r.points), deaths = res.Count(r => r.dead), all = res.Sum(r => r.ticks);
        Console.WriteLine($"blind planner [{setup}], seeds {first + 1}..{first + seeds}, cap {cap}: {deaths} deaths in {pts} points = {100.0 * deaths / Math.Max(1, pts):F3} per 100; median of the runs {Tiers.pct(res.Select(r => r.points), 0.5)}, {res.Count(r => !r.dead)} alive at the cap; {all / clock.Elapsed.TotalSeconds / threads:F0} ticks/s per thread, {clock.Elapsed.TotalSeconds:F0} s");
        foreach (var (lo, hi) in new[] { (0L, 40L), (40, 100000) })
        {
            long played = res.Sum(r => Math.Clamp(r.points - lo, 0, hi - lo));
            long died = res.Count(r => r.dead && r.points >= lo && r.points < hi);
            Console.WriteLine($"  score {lo}+: {died} deaths in {played} points = {100.0 * died / Math.Max(1, played):F3} per 100");
        }
        Console.WriteLine($"  looks {looks}: fine {100.0 * fine / looks:F2}%, shorter {100.0 * shorter / looks:F2}%, none {100.0 * none / looks:F3}%");
        string[] kinds = { "surprise (had a full line)", "after a fine look", "after a shorter look", "no line" };
        Console.WriteLine("  deaths by last look: " + string.Join(", ", res.Where(r => r.dead).GroupBy(r => r.look).OrderBy(g => g.Key).Select(g => $"{kinds[g.Key]} {g.Count()}")));
        Console.WriteLine("  deaths by cause: " + string.Join(", ", res.Where(r => r.dead).GroupBy(r => r.cause).OrderByDescending(g => g.Count()).Select(g => $"{g.Key} {g.Count()}")));
        Console.WriteLine("  deaths by room: " + string.Join(", ", res.Where(r => r.dead).GroupBy(r => r.room + (r.look == 0 ? "!" : "")).OrderByDescending(g => g.Count()).Take(16).Select(g => $"{g.Key} {g.Count()}")) + "   (! = surprise)");
    }

    static int sens(string dir, int seeds, int threads)
    {
        var pol = Policy.load(Path.Combine(dir, "policy.json"));
        var list = new List<Handicap> { Handicap.NONE };
        foreach (int d in new[] { 1, 2, 3, 6, 12, 17 }) list.Add(new Handicap(d, 0, 0));
        foreach (int j in new[] { 1, 2, 4 }) list.Add(new Handicap(0, j, 0));
        foreach (double m in new[] { 0.01, 0.03, 0.1 }) list.Add(new Handicap(0, 0, m));
        foreach (var hc in list)
        {
            var runs = Tiers.play(pol, hc, 0, seeds, SimConfig.MAX_TICKS, threads);
            var p = runs.Select(r => r.points).ToList();
            Console.WriteLine($"  {hc,-34} median {Tiers.pct(p, 0.5),6:F1}  mean {p.Average(),6:F1}");
        }
        return 0;
    }

    static int shape(string dir, int seeds, int threads)
    {
        var pol = Policy.load(Path.Combine(dir, "policy.json"));
        var runs = Tiers.play(pol, Handicap.NONE, 0, seeds, SimConfig.MAX_TICKS, threads);
        var p = runs.Select(r => r.points).ToList();
        double med = Tiers.pct(p, 0.5);
        Console.WriteLine($"shape: {seeds} runs, median {med}, p25 {Tiers.pct(p, 0.25)}, p75 {Tiers.pct(p, 0.75)}, p90 {Tiers.pct(p, 0.9)}, mean {p.Average():F1}");
        Console.WriteLine($"  constant death rate would give p25 {0.415 * med:F1}, p75 {2 * med:F1}, p90 {3.32 * med:F1}, mean {1.443 * med:F1}");
        // Death rate per point in each score band (deaths in the band / points played in it).
        foreach (var (lo, hi) in new[] { (0L, 10L), (10, 20), (20, 40), (40, 80), (80, 160), (160, 100000) })
        {
            long played = p.Sum(x => Math.Clamp(x - lo, 0, hi - lo));
            long died = runs.Count(r => r.dead && r.points >= lo && r.points < hi);
            if (played > 0) Console.WriteLine($"  score {lo,3}..{(hi > 1000 ? "" : hi.ToString()),-4} deaths per 100 points {100.0 * died / played,5:F2}  ({died} deaths)");
        }
        // Bootstrap: how far a median over n seeds moves.
        var rng = new Random(1);
        foreach (int n in new[] { 64, 200, 400 })
        {
            var meds = new List<double>();
            for (int b = 0; b < 2000; b++) meds.Add(Tiers.pct(Enumerable.Range(0, n).Select(_ => p[rng.Next(p.Count)]), 0.5));
            meds.Sort();
            Console.WriteLine($"  median over {n} seeds: 95% between {meds[50]} and {meds[1949]}");
        }
        return 0;
    }
}
