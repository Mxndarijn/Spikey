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
                foreach (string h in O("h", "90").Split(','))
                    honest(long.Parse(h), int.Parse(O("k", "4")), int.Parse(O("n", "3")), long.Parse(O("past", "8")), seeds, cap, threads);
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

    /// A planner that knows the rules but not the hidden future: it looks
    /// ahead on `n` copies of the sim whose RNG (and crate / dart salts) are
    /// replaced by its own random numbers, never more than `past` ticks past
    /// the next bounce, and wants a line of taps that lives in every copy.
    static void honest(long h, int k, int n, long past, int seeds, long cap, int threads)
    {
        var clock = Stopwatch.StartNew();
        var res = new (long points, long ticks, bool dead, string room)[seeds];
        Parallel.For(0, seeds, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            var sim = new GameSim(i + 1);
            var own = new SimRng(977 * (i + 1) + 5);
            var plan = new Queue<bool>();
            int since = k;
            long ticks = 0;
            while (!sim.is_over() && ticks < cap)
            {
                if (!sim.state.started)
                {
                    sim.step(true);
                    ticks++;
                    continue;
                }
                if (since >= k || plan.Count == 0)
                {
                    long want = Math.Min(h, sim.steps_to_wall(sim.state.vx > 0 ? 1 : 0) + past);
                    byte[] found = null;
                    for (int copies = n; copies >= 1 && found == null; copies = copies == 1 ? 0 : 1)
                        for (long t = want; t >= 2 && found == null; t = t * 3 / 4)
                        {
                            var roots = new GameSim[copies];
                            for (int j = 0; j < copies; j++) roots[j] = blind_copy(sim, own);
                            found = beam(roots, t);
                        }
                    plan.Clear();
                    if (found != null)
                        foreach (byte b in found) plan.Enqueue(b != 0);
                    since = 0;
                }
                sim.step(plan.Count > 0 && plan.Dequeue());
                since++;
                ticks++;
            }
            res[i] = (sim.state.score, ticks, sim.is_over(), sim.room.def.id + "/" + sim.room.variant_id());
        });
        long pts = res.Sum(r => r.points), deaths = res.Count(r => r.dead), all = res.Sum(r => r.ticks);
        string med = deaths == 0 ? $"> {pts * 0.69 / 3:F0} (no deaths; 95% bound)" : $"{0.693 * pts / deaths:F0}";
        var rooms = res.Where(r => r.dead).GroupBy(r => r.room).OrderByDescending(g => g.Count()).Take(8).Select(g => $"{g.Key} {g.Count()}");
        Console.WriteLine($"honest planner, horizon {h}, {past} past the bounce, {n} copies: {deaths} deaths in {pts} points ({all} ticks, {seeds} runs) -> median about {med}; real median of the runs {Tiers.pct(res.Select(r => r.points), 0.5)}  [{string.Join(", ", rooms)}]  {clock.Elapsed.TotalSeconds:F0} s");
    }

    static GameSim blind_copy(GameSim sim, SimRng own)
    {
        var c = sim.clone_deep();
        c._rng = new SimRng(own.next_u32());
        foreach (var hz in c.room.hazards)
        {
            if (hz is CrateDrop cd) cd.salt = own.next_u32();
            if (hz is Dart d) d.salt = own.next_u32();
        }
        return c;
    }

    struct Node
    {
        public GameSim[] sims;
        public int parent;
        public byte tap;
    }

    /// Beam search over tap / wait for `ticks` ticks: a line lives only if
    /// the bird lives in every copy. One survivor per height and speed bucket.
    /// Of the lines that live, the one ending nearest the middle height.
    static byte[] beam(GameSim[] roots, long ticks)
    {
        var parents = new List<int>();
        var taps = new List<byte>();
        var frontier = new List<Node> { new Node { sims = roots, parent = -1 } };
        var slots = new Dictionary<long, int>();
        var next = new List<Node>();
        for (long t = 0; t < ticks; t++)
        {
            slots.Clear();
            next.Clear();
            foreach (var e in frontier)
            {
                var s0 = e.sims[0];
                bool can_tap = s0.state.vy * s0.room.gravity > SurvivalSearch.TAP_BELOW_VY;
                for (int a = can_tap ? 1 : 0; a >= 0; a--)
                {
                    var sims = e.sims;
                    if (a == 1)
                    {
                        sims = new GameSim[e.sims.Length];
                        for (int j = 0; j < sims.Length; j++) sims[j] = e.sims[j].clone_deep();
                    }
                    bool dead = false;
                    foreach (var s in sims)
                    {
                        s.step(a == 1);
                        if (s.is_over()) dead = true;
                    }
                    if (dead) continue;
                    var st = sims[0].state;
                    long along = st.vy * sims[0].room.gravity - SimConfig.FLAP_VY;
                    long speed = G.clampi(along / Teacher.BUCKET_VY, 0, Teacher.SPEED_BUCKETS - 1);
                    long key = (st.room_index * 1000 + st.y / Teacher.BUCKET_H) * Teacher.SPEED_BUCKETS + speed;
                    if (slots.ContainsKey(key)) continue;
                    slots[key] = next.Count;
                    next.Add(new Node { sims = sims, parent = e.parent, tap = (byte)a });
                }
            }
            if (next.Count == 0) return null;
            frontier = new List<Node>(next.Count);
            foreach (var e in next)
            {
                parents.Add(e.parent);
                taps.Add(e.tap);
                frontier.Add(new Node { sims = e.sims, parent = parents.Count - 1 });
            }
        }
        long mid = (SimConfig.KILL_TOP + SimConfig.KILL_BOTTOM) / 2;
        var top = frontier[0];
        foreach (var e in frontier)
        {
            var (a, b) = (e.sims[0].state, top.sims[0].state);
            if (a.room_index > b.room_index || (a.room_index == b.room_index && Math.Abs(a.y - mid) < Math.Abs(b.y - mid))) top = e;
        }
        var out_ = new List<byte>();
        for (int nd = top.parent; nd >= 0; nd = parents[nd]) out_.Add(taps[nd]);
        out_.Reverse();
        return out_.ToArray();
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
