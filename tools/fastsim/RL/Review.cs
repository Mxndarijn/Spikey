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
            case "fair":
                return Fairness.run(opts, seeds, cap, threads);
            case "atlas":
                return atlas(opts, seeds, cap, threads);
            case "exposure":
                return Autopsy.exposure(opts, seeds, threads);
            case "bouncefair":
                return Autopsy.bouncefair(opts, seeds, threads);
            case "fixtest":
                return Autopsy.fixtest(opts, threads);
            case "autopsy":
                return Autopsy.run(opts, seeds, cap, threads);
            case "rescue":
                return rescue(opts, threads);
            case "blindcheck":
                return blindcheck(seeds);
            case "trace":
                return trace(opts, cap);
            case "speed":
                return speed(opts, seeds, cap, threads);
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
    internal static string configure(BlindPlanner bot, Dictionary<string, string> opts)
    {
        long L(string k, long d) => long.Parse(opts.GetValueOrDefault(k, d.ToString()));
        BlindPlanner.know_exits = L("knowexits", 0) != 0;
        BlindPlanner.boss_blind = L("hideboss", 1) != 0;
        BlindPlanner.hide_keys = L("hidekeys", 1) != 0;
        bot.own_anchor = L("ownanchor", 1) != 0;
        BlindPlanner.know_walls = L("knowwalls", 0) != 0;
        BlindPlanner.know_all = L("knowall", 0) != 0;
        bot.horizon = L("h", bot.horizon);
        bot.past = L("past", bot.past);
        bot.replan = (int)L("k", bot.replan);
        bot.replan_danger = (int)L("kd", bot.replan_danger);
        bot.copies = (int)L("n", bot.copies);
        bot.lines = (int)L("lines", bot.lines);
        bot.wobble = (int)L("wobble", bot.wobble);
        bot.part = (int)L("part", bot.part);
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
        bot.follow = (int)L("follow", bot.follow);
        bot.peek = L("peek", 0) != 0;
        bot.longest = L("longest", 0) != 0;
        if (L("anytap", 0) != 0) bot.tap_below = long.MinValue;
        return $"h {bot.horizon} past {bot.past} k {bot.replan}/{bot.replan_danger} n {bot.copies} lines {bot.lines} wobble {bot.wobble} part {bot.part} mid {bot.mid_cost} tap {bot.tap_cost} margin {bot.margin}/{bot.margin_cost}{(bot.spike_margin ? " +spikes" : "")} fangs {bot.worst_fangs} rules {(bot.no_pingpong ? "P" : "-")}{(bot.keep_plan ? "K" : "-")}{(bot.bounce_look ? "B" : "-")}{(bot.wide_key ? "W" : "-")}{(bot.aim_exit ? "A" : "-")}{(bot.wall_look ? "L" : "-")}{(bot.full_speeds ? "S" : "-")}{(bot.aim_anchor ? "N" : "-")} buckets {bot.bucket_px}px x{bot.speed_buckets} fine {bot.fine_px}";
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
        // --alt "name:key=value,key=value;name2:...": the rescue runs again with each other setup (same starts).
        var alts = new List<(string name, Dictionary<string, string> opts)>();
        foreach (string part in opts.GetValueOrDefault("alt", "").Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            var o = new Dictionary<string, string>(opts);
            string[] nv = part.Split(':');
            foreach (string kv in nv[1].Split(',', StringSplitOptions.RemoveEmptyEntries)) o[kv.Split('=')[0]] = kv.Split('=')[1];
            alts.Add((nv[0], o));
        }
        var alt_saved = new long[alts.Count];
        long psteps = 0, pticks = 0;
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
            Interlocked.Add(ref psteps, bot.steps);
            Interlocked.Add(ref pticks, taps.Count);
            if (opts.ContainsKey("taps"))
            {
                Directory.CreateDirectory(opts["taps"]);
                File.WriteAllBytes(Path.Combine(opts["taps"], seed + ".taps"), taps.Select(b => (byte)(b ? 1 : 0)).ToArray());
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
            string alt_cols = "";
            for (int a = 0; a < alts.Count; a++)
            {
                int ok = 0;
                if (chance >= 0)
                {
                    long from = Math.Min(max_back, chance + LEAD);
                    for (int r = 0; r < RESCUES; r++)
                    {
                        var c = at(from);
                        var b2 = new BlindPlanner(seed * 1000 + r + 7);
                        configure(b2, alts[a].opts);
                        for (long t = 0; t < from + AFTER && !c.is_over(); t++) c.step(b2.decide(c));
                        if (!c.is_over()) ok++;
                    }
                }
                Interlocked.Add(ref alt_saved[a], ok);
                alt_cols += "\t" + ok;
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
        sb.AppendLine($"{deaths} deaths in {pts} points = {100.0 * deaths / Math.Max(1, pts):F3} per 100; {res.Count(r => !r.dead)} of {seeds} alive at the cap; median {Tiers.pct(res.Select(r => r.points), 0.5)}; {psteps / Math.Max(1, pticks)} search steps per tick; {clock.Elapsed.TotalSeconds:F0} s");
        sb.AppendLine("scores: " + string.Join(" ", res.Select(r => r.points + (r.dead ? "" : "+"))));
        if (alts.Count > 0) sb.AppendLine($"rescues (of {RESCUES} per death): same setup {res.Sum(r => r.rescued)}, " + string.Join(", ", alts.Select((a, k) => $"{a.name} {alt_saved[k]}")));
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

    static List<(string name, Dictionary<string, string> opts)> parse_alts(Dictionary<string, string> opts)
    {
        var alts = new List<(string name, Dictionary<string, string> opts)>();
        foreach (string part in opts.GetValueOrDefault("alt", "").Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            var o = new Dictionary<string, string>(opts);
            string[] nv = part.Split(':');
            if (nv.Length > 1)
                foreach (string kv in nv[1].Split(',', StringSplitOptions.RemoveEmptyEntries)) o[kv.Split('=')[0]] = kv.Split('=')[1];
            alts.Add((nv[0], o));
        }
        return alts;
    }

    /// `rl review rescue --atlas file.tsv --taps dir --alt "name:key=value,..;name2:.."`:
    /// every death of an atlas played again from LEAD ticks before its last
    /// chance (--lead n for another start) by RESCUES fresh planners per setup.
    /// A setup that saves deaths the atlas's own setup does not is a better
    /// search (or, with peek=1, shows the death was a matter of knowledge).
    static int rescue(Dictionary<string, string> opts, int threads)
    {
        long lead = long.Parse(opts.GetValueOrDefault("lead", LEAD.ToString()));
        int tries = int.Parse(opts.GetValueOrDefault("tries", RESCUES.ToString()));
        var alts = parse_alts(opts);
        var rows = File.ReadAllLines(opts["atlas"]).SkipWhile(l => !l.StartsWith("seed\t")).Skip(1)
            .Where(l => l.Trim() != "").Select(l => l.Split('\t')).Where(c => long.Parse(c[6]) >= 0).ToList();
        var saved = new int[rows.Count, alts.Count];
        var steps = new long[alts.Count];
        var ticks = new long[alts.Count];
        var clock = Stopwatch.StartNew();
        Parallel.For(0, rows.Count * alts.Count, new ParallelOptions { MaxDegreeOfParallelism = threads }, job =>
        {
            int i = job / alts.Count, a = job % alts.Count;
            long seed = long.Parse(rows[i][0]), died = long.Parse(rows[i][2]), chance = long.Parse(rows[i][6]);
            byte[] taps = File.ReadAllBytes(Path.Combine(opts["taps"], seed + ".taps"));
            long from = Math.Min(Math.Min(BACK, died - 1), chance + lead);
            var start = new GameSim(seed);
            for (int t = 0; t < died - from; t++) start.step(taps[t] != 0);
            int ok = 0;
            for (int r = 0; r < tries; r++)
            {
                var c = start.clone_deep();
                var b2 = new BlindPlanner(seed * 1000 + r + 7);
                configure(b2, alts[a].opts);
                long n = 0;
                for (; n < from + AFTER && !c.is_over(); n++) c.step(b2.decide(c));
                if (!c.is_over()) ok++;
                Interlocked.Add(ref steps[a], b2.steps);
                Interlocked.Add(ref ticks[a], n);
            }
            saved[i, a] = ok;
        });
        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"rescue: {rows.Count} deaths with a last chance, {tries} tries each, start {lead} ticks before the last chance; {clock.Elapsed.TotalSeconds:F0} s");
        for (int a = 0; a < alts.Count; a++)
        {
            int total = 0, half = 0, all = 0;
            for (int i = 0; i < rows.Count; i++)
            {
                total += saved[i, a];
                if (saved[i, a] * 2 >= tries) half++;
                if (saved[i, a] == tries) all++;
            }
            sb.AppendLine($"  {alts[a].name,-12} saved {total,4} of {rows.Count * tries} tries = {100.0 * total / Math.Max(1, rows.Count * tries),5:F1}%; deaths saved in half or more tries {half}, in all {all}; {steps[a] / Math.Max(1, ticks[a])} search steps per tick");
        }
        sb.AppendLine("seed\tscore\troom\tverdict\tlast_chance\tlook" + string.Concat(alts.Select(a => "\t" + a.name)));
        for (int i = 0; i < rows.Count; i++)
            sb.AppendLine($"{rows[i][0]}\t{rows[i][1]}\t{rows[i][3]}\t{rows[i][5]}\t{rows[i][6]}\t{rows[i][8]}" + string.Concat(Enumerable.Range(0, alts.Count).Select(a => "\t" + saved[i, a])));
        string text = sb.ToString();
        if (opts.GetValueOrDefault("out", "") != "") File.WriteAllText(opts["out"], text);
        Console.Write(string.Join("\n", text.Split('\n').TakeWhile(l => !l.StartsWith("seed\t"))) + "\n");
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

    /// `rl review speed [--bot blind|world] [--skill beast] [planner options]`: ticks per second
    /// of the planner on full runs (cap `cap`), the garbage collector's share, and with a
    /// PROF build (`-p:DefineConstants=PROF`) where the time goes. Tool only.
    static int speed(Dictionary<string, string> opts, int seeds, long cap, int threads)
    {
        long first = long.Parse(opts.GetValueOrDefault("first", "0"));
        bool world = opts.GetValueOrDefault("bot", "blind") == "world";
        var res = new (long points, long ticks, bool dead, ulong taps)[seeds];
        string setup = "";
        long looks = 0, nodes = 0;
        ArrivalMemo.on = opts.GetValueOrDefault("memo", "1") != "0";
        ArrivalMemo.verify = opts.GetValueOrDefault("memo", "1") == "2";
        BlindPlanner.pool = opts.GetValueOrDefault("pool", "1") != "0";
        // Warm up the JIT (tiered PGO) so the first seeds do not count the compile.
        {
            var sim = new GameSim(999);
            var bot = new BlindPlanner(999);
            for (int t = 0; t < 600 && !sim.is_over(); t++) sim.step(bot.decide(sim));
        }
        Prof.flush();
        Array.Clear(Prof.total);
        Array.Clear(Prof.count);
        ArrivalMemo.hits = ArrivalMemo.misses = 0;
        long a0 = GC.GetTotalAllocatedBytes(true);
        int g0 = GC.CollectionCount(0), g1 = GC.CollectionCount(1), g2 = GC.CollectionCount(2);
        var pause0 = GC.GetTotalPauseDuration();
        var clock = Stopwatch.StartNew();
        Parallel.For(0, seeds, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            long seed = first + i + 1;
            var sim = new GameSim(seed);
            long ticks = 0;
            ulong fp = 14695981039346656037UL;
            bool Mark(bool tap)
            {
                fp = (fp ^ (tap ? 1UL : 0UL) ^ (ulong)ticks << 1) * 1099511628211UL;
                return tap;
            }
            if (world)
            {
                var sk = FastSim.Model.WorldPlanner.Skill.Named(opts.GetValueOrDefault("skill", "beast"));
                var bot = new FastSim.Model.WorldPlanner(sk, seed);
                var mem = new FastSim.Model.Memory();
                if (i == 0) setup = sk.ToString();
                while (!sim.is_over() && ticks < cap)
                {
                    sim.step(Mark(bot.Decide(sim, mem)));
                    ticks++;
                }
                Interlocked.Add(ref looks, bot.decisions);
                Interlocked.Add(ref nodes, bot.nodes_expanded);
            }
            else
            {
                var bot = new BlindPlanner(seed);
                string cfg = configure(bot, opts);
                if (i == 0) setup = cfg;
                while (!sim.is_over() && ticks < cap)
                {
                    sim.step(Mark(bot.decide(sim)));
                    ticks++;
                }
                Interlocked.Add(ref looks, bot.looks);
            }
            Prof.flush();
            res[i] = (sim.state.score, ticks, sim.is_over(), fp);
        });
        double sec = clock.Elapsed.TotalSeconds;
        long alloc = GC.GetTotalAllocatedBytes(true) - a0;
        double pause = (GC.GetTotalPauseDuration() - pause0).TotalSeconds;
        long all = res.Sum(r => r.ticks), pts = res.Sum(r => r.points), deaths = res.Count(r => r.dead);
        Console.WriteLine($"speed {(world ? "world" : "blind")} [{setup}] seeds {first + 1}..{first + seeds} cap {cap} threads {threads}");
        Console.WriteLine($"  {all} ticks in {sec:F1} s = {all / sec:F0} ticks/s, {all / sec / threads:F0} per thread; {deaths} deaths in {pts} points; looks {looks} ({1000.0 * sec * threads / Math.Max(1, looks):F3} ms each)" + (world ? $", nodes {nodes} ({nodes / sec / threads / 1e6:F2} M/s/thread)" : ""));
        ulong all_fp = 0;
        foreach (var r in res) all_fp = (all_fp ^ r.taps) * 1099511628211UL;
        Console.WriteLine($"  taps fingerprint {all_fp:x16} (same = same play); arrival memo {(ArrivalMemo.on ? "on" : "off")}: {ArrivalMemo.hits} hits, {ArrivalMemo.misses} misses{(ArrivalMemo.verify ? $", {ArrivalMemo.wrong} wrong" : "")}; sim pool {(BlindPlanner.pool ? "on" : "off")}");
        Console.WriteLine($"  GC: {alloc / 1e9:F1} GB allocated ({alloc / Math.Max(1, all) / 1024.0:F0} KB/tick), gen0 {GC.CollectionCount(0) - g0} gen1 {GC.CollectionCount(1) - g1} gen2 {GC.CollectionCount(2) - g2}, pauses {pause:F1} s = {100 * pause / sec:F1}% of wall time");
        double busy = sec * threads * 1000;
        for (int k = 0; k < Prof.N; k++)
            if (Prof.count[k] > 0)
                Console.WriteLine($"  {Prof.NAMES[k],-24} {Prof.ms(k) / 1000,8:F2} s {100 * Prof.ms(k) / busy,5:F1}%  {Prof.count[k],12} calls {Prof.ms(k) * 1e6 / Prof.count[k],8:F0} ns each");
        return 0;
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
        // --taps dir: the run from a tap file (Autopsy), no planner (look / agree read 0).
        string tdir = opts.GetValueOrDefault("taps", "");
        if (tdir != "")
            foreach (byte b in File.ReadAllBytes(Path.Combine(tdir, $"{seed}.taps"))) { taps.Add(b != 0); sim.step(b != 0); }
        else
        while (!sim.is_over() && taps.Count < cap) { bool tap = bot.decide(sim); taps.Add(tap); sim.step(tap); }
        if (!sim.is_over()) { Console.WriteLine("alive at the cap"); return 0; }
        long died = taps.Count;
        Console.WriteLine($"died at tick {died}, score {sim.state.score}, room {sim.room.def.id}/{sim.room.variant_id()}, cause {DeathCause.NAMES[sim.state.death_cause]}");
        sim = new GameSim(seed);
        bot = new BlindPlanner(seed);
        configure(bot, opts);
        for (int t = 0; t < died; t++)
        {
            bool tap = tdir != "" ? taps[t] : bot.decide(sim);
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
        long looks = 0, fine = 0, shorter = 0, none = 0, psteps = 0;
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
            Interlocked.Add(ref psteps, bot.steps);
            res[i] = (sim.state.score, ticks, sim.is_over(), sim.room.def.id + "/" + sim.room.variant_id(), bot.last_look,
                sim.is_over() ? DeathCause.NAMES[sim.state.death_cause] : "");
        });
        long pts = res.Sum(r => r.points), deaths = res.Count(r => r.dead), all = res.Sum(r => r.ticks);
        Console.WriteLine($"blind planner [{setup}], seeds {first + 1}..{first + seeds}, cap {cap}: {deaths} deaths in {pts} points = {100.0 * deaths / Math.Max(1, pts):F3} per 100; median of the runs {Tiers.pct(res.Select(r => r.points), 0.5)}, {res.Count(r => !r.dead)} alive at the cap; {all / clock.Elapsed.TotalSeconds / threads:F0} ticks/s per thread, {psteps / Math.Max(1, all)} search steps per tick, {clock.Elapsed.TotalSeconds:F0} s");
        if (opts.ContainsKey("scores")) Console.WriteLine("  scores: " + string.Join(" ", res.Select(r => r.points + (r.dead ? "" : "+"))));
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
