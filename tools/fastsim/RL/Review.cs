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
        long cap = long.Parse(O("cap", BotCaps.RUN_CAP.ToString()));
        switch (what)
        {
            case "horizon":
                foreach (string h in O("h", "20,40,60,90").Split(','))
                    horizon(long.Parse(h), int.Parse(O("k", "4")), O("cut", "0") == "1", seeds, cap, threads);
                return 0;
            case "honest":
                honest(opts, seeds, cap, threads);
                return 0;
            case "atlas":
                return atlas(opts, seeds, cap, threads);
            case "blindcheck":
                return blindcheck(seeds);
            case "trace":
                return trace(opts, cap);
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

    /// Sets the planner's knobs from the command line; returns them as text.
    static string configure(BlindPlanner bot, Dictionary<string, string> opts)
    {
        long L(string k, long d) => long.Parse(opts.GetValueOrDefault(k, d.ToString()));
        BlindPlanner.know_exits = L("knowexits", 0) != 0;
        bot.horizon = L("h", bot.horizon);
        bot.past = L("past", bot.past);
        bot.replan = (int)L("k", bot.replan);
        bot.replan_danger = (int)L("kd", bot.replan_danger);
        bot.copies = (int)L("n", bot.copies);
        bot.lines = (int)L("lines", bot.lines);
        bot.wobble = (int)L("wobble", bot.wobble);
        bot.part = (int)L("part", bot.part);
        bot.after = L("after", bot.after);
        bot.band = L("band", bot.band);
        bot.coarse_px = L("coarse", bot.coarse_px);
        bot.mid_cost = L("mid", bot.mid_cost);
        bot.tap_cost = L("tap", bot.tap_cost);
        bot.margin = L("margin", bot.margin);
        bot.margin_cost = L("margincost", bot.margin_cost);
        bot.worst_fangs = (int)L("fangs", bot.worst_fangs);
        bot.no_pingpong = L("pingpong", 1) != 0;
        bot.keep_plan = L("keep", 1) != 0;
        bot.bounce_look = L("bouncelook", 1) != 0;
        bot.wide_key = L("widekey", 0) != 0;
        bot.aim_exit = L("aimexit", 1) != 0;
        bot.wall_look = L("walllook", 1) != 0;
        bot.full_speeds = L("fullspeeds", 0) != 0;
        bot.aim_anchor = L("aimanchor", 0) != 0;
        bot.fine_speeds = L("finespeeds", bot.fine_speeds);
        bot.spike_margin = L("spikemargin", bot.spike_margin ? 1 : 0) != 0;
        bot.bucket_px = L("bpx", bot.bucket_px);
        bot.speed_buckets = L("speeds", bot.speed_buckets);
        bot.fine_px = L("fine", bot.fine_px);
        return $"h {bot.horizon} past {bot.past} k {bot.replan}/{bot.replan_danger} n {bot.copies} lines {bot.lines} wobble {bot.wobble} part {bot.part} after {bot.after} band {bot.band} coarse {bot.coarse_px} mid {bot.mid_cost} tap {bot.tap_cost} margin {bot.margin}/{bot.margin_cost}{(bot.spike_margin ? " +spikes" : "")} fangs {bot.worst_fangs} rules {(bot.no_pingpong ? "P" : "-")}{(bot.keep_plan ? "K" : "-")}{(bot.bounce_look ? "B" : "-")}{(bot.wide_key ? "W" : "-")}{(bot.aim_exit ? "A" : "-")}{(bot.wall_look ? "L" : "-")}{(bot.full_speeds ? "S" : "-")}{(bot.aim_anchor ? "N" : "-")} buckets {bot.bucket_px}px x{bot.speed_buckets} fine {bot.fine_px}";
    }

    /// `rl review atlas`: every death of the BlindPlanner with a verdict.
    ///   last-chance: ticks before the death at which a search that sees the
    ///     true future could last still save the run (binary search, at most
    ///     BACK ticks; "never" = not even BACK ticks before: no player could).
    ///   rescue: of RESCUES fresh planners (other guesses) started LEAD ticks
    ///     before that last chance, how many live past the death.
    ///   verdict: unfair (never), mistake (half or more rescues live: the
    ///     planner could have known), hidden (savable only with luck or
    ///     knowledge the screen does not give).
    public const long BACK = 900, AFTER = 240, LEAD = 45;
    public const int RESCUES = 8;

    static int atlas(Dictionary<string, string> opts, int seeds, long cap, int threads)
    {
        long L(string k, long d) => long.Parse(opts.GetValueOrDefault(k, d.ToString()));
        long first = L("first", 0);
        string out_path = opts.GetValueOrDefault("out", "");
        var clock = Stopwatch.StartNew();
        var rows = new string[seeds];
        var res = new (long points, long ticks, bool dead, string room, string verdict, long chance, int rescued, string cause)[seeds];
        string setup = "";
        Parallel.For(0, seeds, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            long seed = first + i + 1;
            var sim = new GameSim(seed);
            var bot = new BlindPlanner(seed);
            string cfg = configure(bot, opts);
            if (i == 0) setup = cfg;
            var taps = new List<bool>();
            var look = new List<byte>();
            long bounce_tick = 0, entry_tick = 0, drops = -1, drop_tick = 0;
            while (!sim.is_over() && taps.Count < cap)
            {
                bool tap = bot.decide(sim);
                taps.Add(tap);
                look.Add((byte)(bot.last_look * 10 + Math.Min(9, bot.last_agree)));
                long vx = sim.state.vx, ri = sim.state.room_index;
                sim.step(tap);
                if (sim.state.vx != vx) bounce_tick = taps.Count;
                if (sim.state.room_index != ri) entry_tick = taps.Count;
                // The tick a crate's column was last marked (its warning began).
                var cd = sim.room.hazards.OfType<CrateDrop>().FirstOrDefault();
                long dn = cd == null ? -1 : cd.drops;
                if (dn != drops)
                {
                    drops = dn;
                    drop_tick = taps.Count;
                }
            }
            string room = sim.room.def.id + "/" + sim.room.variant_id();
            if (!sim.is_over())
            {
                res[i] = (sim.state.score, taps.Count, false, room, "", 0, 0, "");
                return;
            }
            long died = taps.Count;
            string cause = DeathCause.NAMES[sim.state.death_cause];
            // The state `back` ticks before the death.
            GameSim at(long back)
            {
                var c = new GameSim(seed);
                for (int t = 0; t < died - back; t++) c.step(taps[t]);
                return c;
            }
            bool savable(long back) => new SurvivalSearch().run_quick(at(back), back + AFTER);
            long max_back = Math.Min(BACK, died - 1);
            long chance = -1;
            if (savable(max_back))
            {
                // Savable at lo, not at hi (the death tick itself is not).
                long hi = 0, lo = max_back;
                while (lo - hi > 1)
                {
                    long mid = (lo + hi) / 2;
                    if (savable(mid)) lo = mid;
                    else hi = mid;
                }
                chance = lo;
            }
            int rescued = 0;
            byte seen = 0;
            if (chance >= 0)
            {
                long from = Math.Min(max_back, chance + LEAD);
                seen = look[(int)(died - chance)];
                for (int r = 0; r < RESCUES; r++)
                {
                    var c = at(from);
                    var b2 = new BlindPlanner(seed * 1000 + r + 7);
                    configure(b2, opts);
                    for (long t = 0; t < from + AFTER && !c.is_over(); t++) c.step(b2.decide(c));
                    if (!c.is_over()) rescued++;
                }
            }
            // Crates: `shown` = ticks before the death the last crate's column was marked.
            // A last chance before that means the run was lost before the player could see why.
            long shown = sim.room.hazards.OfType<CrateDrop>().Any() ? died - drop_tick : -1;
            string verdict = chance < 0 ? "unfair" : rescued * 2 >= RESCUES ? "mistake" : shown >= 0 && chance > shown ? "unseen" : "hidden";
            res[i] = (sim.state.score, died, true, room, verdict, chance, rescued, cause);
            rows[i] = $"{seed}\t{sim.state.score}\t{died}\t{room}\t{cause}\t{verdict}\t{chance}\t{rescued}/{RESCUES}\t{seen / 10}\t{seen % 10}\t{sim.state.x / SimConfig.SUB}\t{sim.state.y / SimConfig.SUB}\t{died - bounce_tick}\t{died - entry_tick}\t{shown}";
        });
        long pts = res.Sum(r => r.points), deaths = res.Count(r => r.dead);
        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"death atlas, blind planner [{setup}], seeds {first + 1}..{first + seeds}, cap {cap}, gameplay {SimConfig.GAMEPLAY_VERSION}");
        sb.AppendLine($"{deaths} deaths in {pts} points = {100.0 * deaths / Math.Max(1, pts):F3} per 100; {res.Count(r => !r.dead)} of {seeds} alive at the cap; median {Tiers.pct(res.Select(r => r.points), 0.5)}; {clock.Elapsed.TotalSeconds:F0} s");
        sb.AppendLine("verdicts: " + string.Join(", ", res.Where(r => r.dead).GroupBy(r => r.verdict).OrderByDescending(g => g.Count()).Select(g => $"{g.Key} {g.Count()}")));
        sb.AppendLine("by room (deaths: mistake / hidden / unfair / unseen; median last chance in ticks before the death):");
        foreach (var g in res.Where(r => r.dead).GroupBy(r => r.room).OrderByDescending(g => g.Count()))
        {
            var ch = g.Where(r => r.chance >= 0).Select(r => r.chance).ToList();
            sb.AppendLine($"  {g.Key,-26} {g.Count(),3}: {g.Count(r => r.verdict == "mistake")} / {g.Count(r => r.verdict == "hidden")} / {g.Count(r => r.verdict == "unfair")} / {g.Count(r => r.verdict == "unseen")}   last chance {(ch.Count > 0 ? Tiers.pct(ch, 0.5).ToString("F0") : "-")}   causes {string.Join(" ", g.GroupBy(r => r.cause).Select(c => $"{c.Key} {c.Count()}"))}");
        }
        sb.AppendLine("seed\tscore\ttick\troom\tcause\tverdict\tlast_chance\trescued\tlook\tagree\tx\ty\tsince_bounce\tsince_entry\tcrate_shown");
        foreach (string r in rows.Where(r => r != null)) sb.AppendLine(r);
        string text = sb.ToString();
        if (out_path != "") File.WriteAllText(out_path, text);
        Console.Write(out_path != "" ? string.Join("\n", text.Split('\n').TakeWhile(l => !l.StartsWith("seed\t"))) + "\n" : text);
        return 0;
    }

    /// `rl review blindcheck`: blind_copy must wipe what it scrambles. For
    /// many states in every room: a copy scrambled with seed A must equal a
    /// copy that was first scrambled with seed B and then with A (same
    /// checksum). If not, some scrambled value still depends on the hidden
    /// truth. It can't find a hidden field nobody scrambles: that list is
    /// kept by hand (bot-review.md).
    static int blindcheck(int seeds)
    {
        long states = 0, bad = 0;
        var where = new Dictionary<string, int>();
        foreach (long room in Ppo.rooms().Append(-1))
            for (int i = 0; i < seeds; i++)
            {
                var sim = new GameSim(31 * i + 3, Seasons.NONE, room);
                var rng = new SimRng(i + 1);
                for (int t = 0; t < 900 && !sim.is_over(); t++)
                {
                    sim.step(SimBots.gap_seeker(sim, rng));
                    if (t % 15 != 0 || sim.is_over()) continue;
                    states++;
                    long a = BlindPlanner.blind_copy(sim, new SimRng(111)).checksum();
                    long b = BlindPlanner.blind_copy(BlindPlanner.blind_copy(sim, new SimRng(222)), new SimRng(111)).checksum();
                    if (a == b) continue;
                    bad++;
                    string id = sim.room.def.id + "/" + sim.room.variant_id();
                    where[id] = where.GetValueOrDefault(id) + 1;
                }
            }
        Console.WriteLine($"blindcheck: {states} states, {bad} where a second scramble changed the copy" + (bad > 0 ? ": " + string.Join(", ", where.Select(kv => $"{kv.Key} {kv.Value}")) : ""));
        return bad == 0 ? 0 : 1;
    }

    /// `rl review trace --seed n [--last 150] [--every 10]`: the planner's last
    /// ticks before its death on one seed: the bird each tick, the wall ahead
    /// and every hazard's fields every `every` ticks. For reading one death.
    static int trace(Dictionary<string, string> opts, long cap)
    {
        long L(string k, long d) => long.Parse(opts.GetValueOrDefault(k, d.ToString()));
        long seed = L("seed", 1), last = L("last", 150), every = L("every", 10);
        var sim = new GameSim(seed);
        var bot = new BlindPlanner(seed);
        Console.WriteLine("trace seed " + seed + " [" + configure(bot, opts) + "]");
        var taps = new List<bool>();
        while (!sim.is_over() && taps.Count < cap) { bool tap = bot.decide(sim); taps.Add(tap); sim.step(tap); }
        if (!sim.is_over()) { Console.WriteLine("alive at the cap"); return 0; }
        long died = taps.Count;
        Console.WriteLine($"died at tick {died}, score {sim.state.score}, room {sim.room.def.id}/{sim.room.variant_id()}, cause {DeathCause.NAMES[sim.state.death_cause]}");
        sim = new GameSim(seed);
        bot = new BlindPlanner(seed);
        configure(bot, opts);
        for (int t = 0; t < died; t++)
        {
            bool tap = bot.decide(sim);
            if (t >= died - last)
            {
                var st = sim.state;
                long side = st.vx > 0 ? 1 : 0;
                if ((t - (died - last)) % every == 0)
                {
                    long mask = sim.wall_mask(side);
                    string wall = string.Concat(Enumerable.Range(0, (int)SimConfig.SLOT_COUNT).Select(k => RoomRules.has_slot(mask, k) ? '#' : '.'));
                    Console.WriteLine($"  -- wall ahead ({(side == 1 ? "right" : "left")}) {wall}  exit open {st.exit_open} preview {st.exit_preview} side {st.exit_side} a_y {st.exit_a_y / SimConfig.SUB}  anchor {st.anchor_y / SimConfig.SUB}  room t {sim.room.t}");
                    foreach (var hz in sim.room.hazards.Where(h => h.alive))
                    {
                        var parts = new List<string>();
                        foreach (var f in hz.GetType().GetFields(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance))
                        {
                            object v = f.GetValue(hz);
                            if (v is long l) parts.Add($"{f.Name} {(Math.Abs(l) >= 4 * SimConfig.SUB && l % SimConfig.SUB == 0 ? (l / SimConfig.SUB) + "px" : l.ToString())}");
                            else if (v is bool b) parts.Add($"{f.Name} {(b ? 1 : 0)}");
                            else if (v is List<long> ls) parts.Add($"{f.Name} [{string.Join(",", ls)}]");
                        }
                        Console.WriteLine($"  -- {hz.GetType().Name}: {string.Join(" ", parts)}");
                    }
                }
                Console.WriteLine($"  {t - died,5} x {st.x / SimConfig.SUB,3} y {st.y / SimConfig.SUB,3} vy {st.vy * 10 / SimConfig.SUB,4} {(tap ? "TAP" : "   ")} look {bot.last_look} agree {bot.last_agree} to wall {sim.steps_to_wall(side)}");
            }
            sim.step(tap);
        }
        return 0;
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
            string cfg = configure(bot, opts);
            if (i == 0) setup = cfg;
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
            var runs = Tiers.play(pol, hc, 0, seeds, BotCaps.RUN_CAP, threads);
            var p = runs.Select(r => r.points).ToList();
            Console.WriteLine($"  {hc,-34} median {Tiers.pct(p, 0.5),6:F1}  mean {p.Average(),6:F1}");
        }
        return 0;
    }

    static int shape(string dir, int seeds, int threads)
    {
        var pol = Policy.load(Path.Combine(dir, "policy.json"));
        var runs = Tiers.play(pol, Handicap.NONE, 0, seeds, BotCaps.RUN_CAP, threads);
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
