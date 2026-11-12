using System.Diagnostics;

namespace FastSim.Rl;

/// `rl review autopsy --seeds n --threads t --cap c --out f.tsv [--first k] [--taps dir]`:
/// the death atlas (Review.atlas) plus, for every death, what the planner's
/// own copy expected against what happened.
///   chance    latest tick before the death a true-future SurvivalSearch still
///             saves the run (-1: not even BACK ticks before).
///   save60    that search saves the run from 60 ticks (1 s) before.
///   rescued   of 8 fresh BlindPlanners started 45 ticks before `chance`, how many live.
///   For two looks, `L` (the last look at or before the last chance) and
///   `E` (the last look before the death), the plan the planner left is
///   played on the true state and on the planner's own guessed copy:
///   *_real    tick (after the look) the plan dies on the true state, or "live".
///   *_copy    the same on the copy: what the planner expected.
///   *_div     first tick the copy and the truth differ on screen, and what
///             (bird = position/speed, wall = spikes, or the hazard type whose
///             killing area differs), "-" = never within the plan.
/// Tool only.
public static class Autopsy
{
    const long BACK = 900, AFTER = 240, LEAD = 45, KEEP = 1100;
    const int RESCUES = 8;

    record Look(long tick, long seed0, bool[] plan, int kind, int agree, long anchor);

    public static int run(Dictionary<string, string> opts, int seeds, long cap, int threads)
    {
        long L(string k, long d) => long.Parse(opts.GetValueOrDefault(k, d.ToString()));
        long first = L("first", 0);
        string out_path = opts.GetValueOrDefault("out", "autopsy.tsv");
        string taps_dir = opts.GetValueOrDefault("taps", "");
        if (taps_dir != "") Directory.CreateDirectory(taps_dir);
        var clock = Stopwatch.StartNew();
        string setup = "";
        var rows = new string[seeds];
        var res = new (long points, bool dead)[seeds];
        object gate = new();
        string partial = out_path + ".partial";
        File.WriteAllText(partial, "");
        int done = 0;
        Parallel.For(0, seeds, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            long seed = first + i + 1;
            var sim = new GameSim(seed);
            var bot = new BlindPlanner(seed);
            string cfg = Review.configure(bot, opts);
            if (i == 0) setup = cfg;
            var taps = new List<bool>();
            var looks = new LinkedList<Look>();
            long bounce_tick = 0, entry_tick = 0, last_looks = 0;
            while (!sim.is_over() && taps.Count < cap)
            {
                long tick = taps.Count;
                bool tap = bot.decide(sim);
                if (bot.looks != last_looks)
                {
                    last_looks = bot.looks;
                    looks.AddLast(new Look(tick, bot.last_seed0, bot.last_plan, bot.last_look, bot.last_agree, bot.last_anchor));
                    while (looks.First.Value.tick < tick - KEEP) looks.RemoveFirst();
                }
                taps.Add(tap);
                long vx = sim.state.vx, ri = sim.state.room_index;
                sim.step(tap);
                if (sim.state.vx != vx) bounce_tick = taps.Count;
                if (sim.state.room_index != ri) entry_tick = taps.Count;
            }
            if (taps_dir != "")
                File.WriteAllBytes(Path.Combine(taps_dir, $"{seed}.taps"), taps.Select(b => (byte)(b ? 1 : 0)).ToArray());
            res[i] = (sim.state.score, sim.is_over());
            if (sim.is_over()) rows[i] = autopsy(seed, sim, taps, looks.ToList(), bounce_tick, entry_tick, opts);
            lock (gate)
            {
                done++;
                File.AppendAllText(partial, (rows[i] ?? $"{seed}\t{sim.state.score}\t{taps.Count}\talive") + "\n");
                Console.Error.WriteLine($"[{done}/{seeds}] seed {seed}: {sim.state.score} {(sim.is_over() ? "dead" : "alive")} ({clock.Elapsed.TotalMinutes:F0} min)");
            }
        });
        long pts = res.Sum(r => r.points), deaths = res.Count(r => r.dead);
        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"# autopsy, blind planner [{setup}], seeds {first + 1}..{first + seeds}, cap {cap}, gameplay {SimConfig.GAMEPLAY_VERSION}");
        sb.AppendLine($"# {deaths} deaths in {pts} points = {100.0 * deaths / Math.Max(1, pts):F3} per 100; {res.Count(r => !r.dead)} of {seeds} alive at the cap; median {Tiers.pct(res.Select(r => r.points), 0.5)}; {clock.Elapsed.TotalSeconds:F0} s");
        sb.AppendLine(HEADER);
        foreach (string r in rows.Where(r => r != null)) sb.AppendLine(r);
        File.WriteAllText(out_path, sb.ToString());
        Console.WriteLine(string.Join("\n", sb.ToString().Split('\n').Take(2)));
        return 0;
    }

    const string HEADER = "seed\tscore\ttick\troom\tboss\tfork\texit\tcause\tkiller\tchance\tsave60\trescued\tatlas_verdict"
        + "\tx\ty\tvy\tsince_bounce\tsince_entry\tL_back\tL_kind\tL_agree\tL_len\tL_real\tL_copy\tL_div\tL_div_what"
        + "\tE_back\tE_kind\tE_agree\tE_len\tE_real\tE_copy\tE_div\tE_div_what";

    static string autopsy(long seed, GameSim dead, List<bool> taps, List<Look> looks, long bounce_tick, long entry_tick,
        Dictionary<string, string> opts)
    {
        long died = taps.Count;
        // One snapshot KEEP ticks before the death; every other state is a copy stepped on from it.
        long base_t = Math.Max(0, died - KEEP);
        var snap = new GameSim(seed);
        for (int t = 0; t < base_t; t++) snap.step(taps[t]);
        GameSim at_tick(long tick)
        {
            var c = snap.clone_deep();
            for (long t = base_t; t < tick; t++) c.step(taps[(int)t]);
            return c;
        }
        GameSim at(long back) => at_tick(died - back);
        bool savable(long back) => new SurvivalSearch().run_quick(at(back), back + AFTER);
        long max_back = Math.Min(BACK, died - 1);
        long chance = -1;
        if (savable(max_back))
        {
            long hi = 0, lo = max_back;
            while (lo - hi > 1)
            {
                long mid = (lo + hi) / 2;
                if (savable(mid)) lo = mid;
                else hi = mid;
            }
            chance = lo;
        }
        bool save60 = died > 60 && savable(60);
        int rescued = 0;
        if (chance >= 0)
        {
            long from = Math.Min(max_back, chance + LEAD);
            for (int r = 0; r < RESCUES; r++)
            {
                var c = at(from);
                var b2 = new BlindPlanner(seed * 1000 + r + 7);
                Review.configure(b2, opts);
                for (long t = 0; t < from + AFTER && !c.is_over(); t++) c.step(b2.decide(c));
                if (!c.is_over()) rescued++;
            }
        }
        string verdict = chance < 0 ? "unfair" : rescued * 2 >= RESCUES ? "mistake" : "hidden";
        // The hazards that kill the bird where it died.
        var killers = dead.room.hazards.Where(h => h.alive && h.kills(dead)).Select(h => h.GetType().Name).Distinct().ToList();
        var st = dead.state;
        string exit = st.exit_open ? "open" : st.exit_preview ? "preview" : "none";
        bool fork = st.exit_b_kind != ExitKind.NORMAL;
        var row = new List<string>
        {
            seed.ToString(), st.score.ToString(), died.ToString(), dead.room.def.id + "/" + dead.room.variant_id(),
            dead.room.def.boss ? "1" : "0", fork ? "1" : "0", exit, DeathCause.NAMES[st.death_cause],
            killers.Count > 0 ? string.Join("+", killers) : "-", chance.ToString(), save60 ? "1" : "0",
            $"{rescued}/{RESCUES}", verdict, (st.x / SimConfig.SUB).ToString(), (st.y / SimConfig.SUB).ToString(),
            (st.vy * 10 / SimConfig.SUB).ToString(), (died - bounce_tick).ToString(), (died - entry_tick).ToString(),
        };
        int lost_at = row.Count;
        // L: the last look at or before the last chance (or 60 ticks before an unfair death).
        long cut = died - (chance >= 0 ? chance : Math.Min(60, died - 1));
        Look lk = looks.LastOrDefault(l => l.tick <= cut);
        Look ek = looks.LastOrDefault(l => l.tick < died && l.kind <= 1 && l.plan.Length > 0);
        // Looks in the last 60 ticks that found no line for their whole span.
        long lost = looks.Count(l => l.tick >= died - 60 && l.kind >= 2);
        foreach (var look in new[] { lk, ek })
        {
            if (look == null)
            {
                row.AddRange(Enumerable.Repeat("-", 8));
                continue;
            }
            var real = at_tick(look.tick);
            var copy = BlindPlanner.blind_copy(real, new SimRng(look.seed0), -1, 0, look.anchor);
            var (real_end, copy_end, div, what) = compare(real, copy, look.plan);
            row.AddRange(new[]
            {
                (died - look.tick).ToString(), look.kind.ToString(), look.agree.ToString(), look.plan.Length.ToString(),
                real_end, copy_end, div, what,
            });
        }
        return string.Join("\t", row);
    }

    /// Plays `plan` on the truth and on the copy side by side.
    static (string real, string copy, string div, string what) compare(GameSim real, GameSim copy, bool[] plan)
    {
        string real_end = "live", copy_end = "live", div = "-", what = "-";
        for (int t = 0; t < plan.Length; t++)
        {
            if (div == "-")
            {
                string d = differs(real, copy);
                if (d != null)
                {
                    div = t.ToString();
                    what = d;
                }
            }
            if (real_end == "live") real.step(plan[t]);
            if (copy_end == "live") copy.step(plan[t]);
            if (real_end == "live" && real.is_over()) real_end = (t + 1) + ":" + DeathCause.NAMES[real.state.death_cause] + kill_name(real);
            if (copy_end == "live" && copy.is_over()) copy_end = (t + 1) + ":" + DeathCause.NAMES[copy.state.death_cause] + kill_name(copy);
            if (real_end != "live" && copy_end != "live") break;
        }
        return (real_end, copy_end, div, what);
    }

    static string kill_name(GameSim s)
    {
        if (s.state.death_cause != DeathCause.HAZARD) return "";
        var k = s.room.hazards.Where(h => h.alive && h.kills(s)).Select(h => h.GetType().Name).FirstOrDefault();
        return k == null ? "" : ":" + k;
    }

    /// What differs on screen between two sims at the same tick, or null.
    static string differs(GameSim a, GameSim b)
    {
        if (a.is_over() || b.is_over()) return null;
        var sa = a.state;
        var sb = b.state;
        if (sa.x != sb.x || sa.y != sb.y || sa.vy != sb.vy || sa.vx != sb.vx) return "bird";
        if (a.wall_mask(0) != b.wall_mask(0) || a.wall_mask(1) != b.wall_mask(1)) return "wall";
        if (sa.exit_open != sb.exit_open || sa.exit_preview != sb.exit_preview || (sa.exit_open || sa.exit_preview) && sa.exit_a_y != sb.exit_a_y)
            return "exit";
        var ha = a.room.hazards;
        var hb = b.room.hazards;
        if (ha.Count != hb.Count) return "hazards";
        long x0 = sa.x, y0 = sa.y;
        string found = null;
        long step = 12 * SimConfig.SUB;
        for (int h = 0; h < ha.Count && found == null; h++)
        {
            if (ha[h].alive != hb[h].alive)
            {
                found = ha[h].GetType().Name;
                break;
            }
            if (!ha[h].alive) continue;
            for (long x = a.room.wall_left(); x <= a.room.wall_right() && found == null; x += step)
                for (long y = SimConfig.KILL_TOP; y <= SimConfig.KILL_BOTTOM; y += step)
                {
                    sa.x = sb.x = x;
                    sa.y = sb.y = y;
                    if (ha[h].kills(a) != hb[h].kills(b))
                    {
                        found = ha[h].GetType().Name;
                        break;
                    }
                }
        }
        sa.x = sb.x = x0;
        sa.y = sb.y = y0;
        return found;
    }

    /// `rl review fixtest --rows autopsy.tsv --taps dir --cfgs "base;aimanchor=1;n=4,lines=4" [--back 600] [--tries 4]`:
    /// for every death in `rows`, `tries` planners of each setup (fresh own seeds) start
    /// `back` ticks before the death (on the true run) and play to AFTER ticks past it.
    /// Prints, per setup, the deaths it saves (sum of the share of tries alive) and per room.
    /// Saved minus "base" estimates the deaths a fix removes (it does not see deaths it adds later).
    public static int fixtest(Dictionary<string, string> opts, int threads)
    {
        string rows_path = opts["rows"], taps_dir = opts["taps"];
        long back = long.Parse(opts.GetValueOrDefault("back", "600"));
        int tries = int.Parse(opts.GetValueOrDefault("tries", "4"));
        var cfgs = opts.GetValueOrDefault("cfgs", "base").Split(';');
        var deaths = File.ReadAllLines(rows_path).Where(l => l.Length > 0 && char.IsDigit(l[0]) && !l.EndsWith("alive"))
            .Select(l => l.Split('\t')).Select(f => (seed: long.Parse(f[0]), died: long.Parse(f[2]), room: f[3])).ToList();
        var saved = new double[cfgs.Length, deaths.Count];
        // Snapshots once; setups one after another (configure sets static switches).
        var snaps = new GameSim[deaths.Count];
        Parallel.For(0, deaths.Count, new ParallelOptions { MaxDegreeOfParallelism = threads }, d =>
        {
            var (seed, died, _) = deaths[d];
            var taps = File.ReadAllBytes(Path.Combine(taps_dir, $"{seed}.taps"));
            long from = Math.Max(0, died - back);
            var snap = new GameSim(seed);
            for (long t = 0; t < from; t++) snap.step(taps[t] != 0);
            snaps[d] = snap;
        });
        for (int c = 0; c < cfgs.Length; c++)
        {
            var o = new Dictionary<string, string>();
            foreach (string kv in cfgs[c].Split(',', StringSplitOptions.RemoveEmptyEntries))
                if (kv.Contains('=')) o[kv.Split('=')[0]] = kv.Split('=')[1];
            Review.configure(new BlindPlanner(1), o);
            Parallel.For(0, deaths.Count * tries, new ParallelOptions { MaxDegreeOfParallelism = threads }, j =>
            {
                int d = j / tries, r = j % tries;
                var (seed, died, _) = deaths[d];
                long from = Math.Max(0, died - back);
                var sim = snaps[d].clone_deep();
                var bot = new BlindPlanner(seed * 7919 + r * 31 + 3);
                Review.configure(bot, o);
                for (long t = from; t < died + AFTER && !sim.is_over(); t++) sim.step(bot.decide(sim));
                if (!sim.is_over()) lock (saved) saved[c, d] += 1.0 / tries;
            });
            Console.Error.WriteLine($"  done {cfgs[c]}");
        }
        Console.WriteLine($"fixtest: {deaths.Count} deaths, start {back} ticks before, {tries} tries each");
        for (int c = 0; c < cfgs.Length; c++)
        {
            double sum = 0;
            for (int d = 0; d < deaths.Count; d++) sum += saved[c, d];
            var by = deaths.Select((x, d) => (x.room, s: saved[c, d])).GroupBy(x => x.room)
                .Select(g => (g.Key, g.Sum(x => x.s), g.Count())).OrderByDescending(x => x.Item2).Take(12);
            Console.WriteLine($"  {cfgs[c],-40} saves {sum,6:F1}   " + string.Join(", ", by.Select(b => $"{b.Key} {b.Item2:F1}/{b.Item3}")));
        }
        if (opts.TryGetValue("out", out var outp))
        {
            var sb = new System.Text.StringBuilder("seed\troom\t" + string.Join("\t", cfgs) + "\n");
            for (int d = 0; d < deaths.Count; d++)
                sb.AppendLine($"{deaths[d].seed}\t{deaths[d].room}\t" + string.Join("\t", Enumerable.Range(0, cfgs.Length).Select(c => saved[c, d].ToString("F2"))));
            File.WriteAllText(outp, sb.ToString());
        }
        return 0;
    }

    /// `rl review exposure --taps dir --seeds n [--out f.tsv]`: replays the tap files and counts,
    /// per room/variant, the visits, the ticks spent and the points scored there, and the deaths.
    public static int exposure(Dictionary<string, string> opts, int seeds, int threads)
    {
        string taps_dir = opts["taps"];
        var all = new System.Collections.Concurrent.ConcurrentBag<(string room, long visits, long ticks, long points, long deaths, long fork)>();
        Parallel.For(1, seeds + 1, new ParallelOptions { MaxDegreeOfParallelism = threads }, s =>
        {
            string f = Path.Combine(taps_dir, $"{s}.taps");
            if (!File.Exists(f)) return;
            var taps = File.ReadAllBytes(f);
            var sim = new GameSim(s);
            var acc = new Dictionary<string, long[]>();
            string id() => sim.room.def.id + "/" + sim.room.variant_id();
            long[] get(string k) => acc.TryGetValue(k, out var a) ? a : acc[k] = new long[5];
            string cur = id();
            get(cur)[0]++;
            long score0 = sim.state.score;
            foreach (byte b in taps)
            {
                long ri = sim.state.room_index;
                sim.step(b != 0);
                get(cur)[1]++;
                if (sim.state.room_index != ri)
                {
                    get(cur)[2] += sim.state.score - score0;
                    score0 = sim.state.score;
                    cur = id();
                    get(cur)[0]++;
                    if (sim.state.exit_b_kind != ExitKind.NORMAL) get(cur)[4]++;
                }
                if (sim.is_over()) break;
            }
            get(cur)[2] += sim.state.score - score0;
            if (sim.is_over()) get(cur)[3]++;
            foreach (var kv in acc) all.Add((kv.Key, kv.Value[0], kv.Value[1], kv.Value[2], kv.Value[3], kv.Value[4]));
        });
        var sb = new System.Text.StringBuilder("room\tvisits\tticks\tpoints\tdeaths\tdeaths_per_100_visits\n");
        foreach (var g in all.GroupBy(x => x.room).OrderByDescending(g => g.Sum(x => x.deaths)).ThenByDescending(g => g.Sum(x => x.visits)))
        {
            long v = g.Sum(x => x.visits), dd = g.Sum(x => x.deaths);
            sb.AppendLine($"{g.Key}\t{v}\t{g.Sum(x => x.ticks)}\t{g.Sum(x => x.points)}\t{dd}\t{100.0 * dd / Math.Max(1, v):F2}");
        }
        string outp = opts.GetValueOrDefault("out", "");
        if (outp != "") File.WriteAllText(outp, sb.ToString());
        else Console.Write(sb);
        return 0;
    }

    /// `rl review bouncefair --taps dir --seeds n [--every 8] [--react 18]`: replays the tap
    /// files; at every `every`-th bounce (every bounce in boss rooms) it asks a true-future
    /// SurvivalSearch whether the bird lives to 40 ticks past the next bounce from the
    /// bounce itself (`now`) and after `react` more ticks of the run's own taps (`late`).
    /// The new wall is first on screen at the bounce, so `late` failing while `now` lives
    /// means only a reaction faster than `react` saves it; `now` failing: the bird was
    /// already lost when the wall appeared.
    public static int bouncefair(Dictionary<string, string> opts, int seeds, int threads)
    {
        string taps_dir = opts["taps"];
        int every = int.Parse(opts.GetValueOrDefault("every", "8"));
        int react = int.Parse(opts.GetValueOrDefault("react", "18"));
        var all = new System.Collections.Concurrent.ConcurrentBag<(string room, bool boss, bool now, bool late)>();
        Parallel.For(1, seeds + 1, new ParallelOptions { MaxDegreeOfParallelism = threads }, s =>
        {
            string f = Path.Combine(taps_dir, $"{s}.taps");
            if (!File.Exists(f)) return;
            var taps = File.ReadAllBytes(f);
            var sim = new GameSim(s);
            long n = 0;
            for (int t = 0; t < taps.Length && !sim.is_over(); t++)
            {
                long vx = sim.state.vx, ri = sim.state.room_index;
                sim.step(taps[t] != 0);
                if (sim.is_over() || sim.state.vx == vx || sim.state.room_index != ri || vx == 0) continue;
                bool boss = sim.room.def.boss;
                if (!boss && n++ % every != 0) continue;
                long look = sim.steps_to_wall(sim.state.vx > 0 ? 1 : 0) + 40;
                bool now = new SurvivalSearch().run_quick(sim.clone_deep(), look);
                bool late = false;
                if (now)
                {
                    var c = sim.clone_deep();
                    for (int k = 1; k <= react && t + k < taps.Length && !c.is_over(); k++) c.step(taps[t + k] != 0);
                    late = !c.is_over() && new SurvivalSearch().run_quick(c, look - react);
                }
                all.Add((sim.room.def.id + "/" + sim.room.variant_id(), boss, now, late));
            }
        });
        var sb = new System.Text.StringBuilder($"bouncefair: react {react}, every {every}th bounce (boss: all)\nroom\tbounces\tlost_at_bounce\tneeds_fast\tpct_lost\tpct_fast\n");
        foreach (var g in all.GroupBy(x => x.boss ? x.room : x.room.Split('/')[0] + (x.room.Split('/')[0] == "boss" ? "" : "*")).OrderByDescending(g => g.Count(x => !x.late)))
        {
            long b = g.Count(), lost = g.Count(x => !x.now), fast = g.Count(x => x.now && !x.late);
            sb.AppendLine($"{g.Key}\t{b}\t{lost}\t{fast}\t{100.0 * lost / b:F2}\t{100.0 * fast / b:F2}");
        }
        foreach (bool bs in new[] { true, false })
        {
            var g = all.Where(x => x.boss == bs).ToList();
            sb.AppendLine($"ALL {(bs ? "boss" : "normal")}\t{g.Count}\t{g.Count(x => !x.now)}\t{g.Count(x => x.now && !x.late)}\t{100.0 * g.Count(x => !x.now) / Math.Max(1, g.Count):F2}\t{100.0 * g.Count(x => x.now && !x.late) / Math.Max(1, g.Count):F2}");
        }
        string outp = opts.GetValueOrDefault("out", "");
        if (outp != "") File.WriteAllText(outp, sb.ToString());
        Console.Write(sb);
        return 0;
    }
}
