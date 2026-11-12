using System.Diagnostics;

namespace FastSim.Human;

/// `fastsim human <mode>` (docs/HUMAN_BOT.md):
///   measure  --skill s | --tier name   play seeds, print scores + looks-human
///   fit                                 bisect the skill knob for each tier's target median
///   baseline --bot gap|rl|search        the looks-human score of other bots
///   runfile  --skill s --seed n --out f a run file for tools/render_run.ps1
/// Common: --seeds n, --first n, --threads n (max 4), --cap ticks, --bot human|percept
public static class HumanMain
{
    public static readonly string[] TIERS = { "beginner", "normal", "good", "expert", "beast" };
    public static readonly double[] TARGETS = { 30, 60, 120, 250, 500 };
    public const long FIT_SEED = 700_000;

    static Dictionary<string, string> O;
    static string opt(string k, string d) => O.GetValueOrDefault(k, d);

    public static int run(List<string> pos, Dictionary<string, string> opts)
    {
        O = opts;
        HumanBot.MIDPULL = double.Parse(opt("midpull", "0.25"));
        HumanBot.FORESIGHT = opt("foresight", "0") == "1";
        HumanBot.BEAM = long.Parse(opt("beam", "0"));
        HumanBot.SPEEDS = long.Parse(opt("speeds", "6"));
        HumanBot.WIDTH = long.Parse(opt("width", "0"));
        HumanBot.ESCALATE = int.Parse(opt("escalate", "2"));
        HumanBot.GAPMID = opt("gapmid", "0") == "1";
        MotorPlayer.MASK_SPIKES = opt("mask", "both") is "both" or "spikes";
        MotorPlayer.MASK_HAZARDS = opt("mask", "both") is "both" or "hazards";
        HumanBot.BMARGIN = double.Parse(opt("bmargin", "-1"));
        string mode = pos.Count > 1 ? pos[1] : "measure";
        int threads = Math.Clamp(int.Parse(opt("threads", "4")), 1, 16);
        int seeds = int.Parse(opt("seeds", "100"));
        long first = long.Parse(opt("first", "0"));
        long cap = long.Parse(opt("cap", SimConfig.MAX_TICKS.ToString()));
        string bot = opt("bot", "human");
        var sw = Stopwatch.StartNew();
        switch (mode)
        {
            case "measure":
            {
                double s = skill_of(opt("tier", ""), double.Parse(opt("skill", "1")));
                var runs = play(bot, s, first, seeds, cap, threads);
                report($"{bot} skill {s:F3}", runs, sw);
                if (O.ContainsKey("out")) dump(opt("out", ""), runs);
                return 0;
            }
            case "fit":
            {
                int fseeds = int.Parse(opt("seeds", "60"));
                double floor = 0;
                for (int ti = 0; ti < 4; ti++)
                {
                    double lo = floor, hi = 1;
                    for (int it = 0; it < int.Parse(opt("steps", "6")); it++)
                    {
                        double mid = (lo + hi) / 2;
                        var r = play(bot, mid, FIT_SEED, fseeds, cap, threads);
                        double m = Humanness.med(r.Select(x => x.points));
                        Console.WriteLine($"  {TIERS[ti]}: skill {mid:F3} -> median {m}  ({sw.Elapsed.TotalSeconds:F0}s)");
                        if (m < TARGETS[ti]) lo = mid; else hi = mid;
                    }
                    Console.WriteLine($"{TIERS[ti]} = {(lo + hi) / 2:F3}");
                    floor = lo;
                }
                return 0;
            }
            case "baseline":
            {
                var runs = new Trace[seeds];
                Parallel.For(0, seeds, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
                    runs[i] = Trace.play(new GameSim(first + 1 + i), baseline(bot, first + 1 + i), cap));
                report($"baseline {bot}", runs, sw);
                return 0;
            }
            case "deaths":
            {
                // For each death: from the tick after the last bounce (the new
                // spikes are up and on screen), could a full SurvivalSearch live
                // 150 ticks? If not, the height at the bounce already doomed it.
                double s = skill_of(opt("tier", ""), double.Parse(opt("skill", "1")));
                var runs = play(bot, s, first, seeds, cap, threads);
                var rows = new string[runs.Length];
                Parallel.For(0, runs.Length, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
                {
                    var r = runs[i];
                    if (!r.dead || r.bounces.Count == 0) return;
                    long from = r.bounces[^1] + 1;
                    var sim = new GameSim(r.seed);
                    var taps = new HashSet<long>(r.taps);
                    sim.step(true);
                    while (sim.state.tick < from && !sim.is_over()) sim.step(taps.Contains(sim.state.tick));
                    if (sim.is_over()) return;
                    var ss = new SurvivalSearch();
                    bool ok = ss.run(sim, 150);
                    rows[i] = $"{(ok ? "savable" : "DOOMED")} {r.cause} {r.room} ({r.since_bounce}t after bounce)";
                });
                var got = rows.Where(x => x != null).ToList();
                foreach (var x in got) Console.WriteLine("  " + x);
                Console.WriteLine($"deaths {got.Count}: savable after the bounce {got.Count(x => x.StartsWith("savable"))}, " +
                                  $"doomed at the bounce {got.Count(x => x.StartsWith("DOOMED"))}");
                return 0;
            }
            case "reflextrace":
            {
                ReflexBot.LOG = Console.WriteLine;
                var sim = new GameSim(long.Parse(opt("seed", "1")));
                var tr = Trace.play(sim, decider("reflex", 1, 1), long.Parse(opt("cap", "120")), false);
                Console.WriteLine($"{tr.points} points, {tr.cause}");
                return 0;
            }
            case "motortrace":
            {
                long seed = long.Parse(opt("seed", "3"));
                var m = Motor.at(double.Parse(opt("sigma", "0.5"))) with { react_mu = double.Parse(opt("react", "13")) };
                var mp = new MotorPlayer(m, seed);
                var lines = new List<string>();
                mp.log = lines.Add;
                var sim = new GameSim(seed);
                var tr = Trace.play(sim, mp.decide, cap, false);
                foreach (var l in lines.Skip(Math.Max(0, lines.Count - int.Parse(opt("last", "100"))))) Console.WriteLine(l);
                Console.WriteLine($"{tr.points} points, {tr.cause} in {tr.room}");
                return 0;
            }
            case "train-reflex":
            {
                var best = ReflexTrainer.train(int.Parse(opt("gens", "20")), int.Parse(opt("pop", "16")),
                    int.Parse(opt("seeds", "24")), long.Parse(opt("cap", "6000")), threads,
                    m => Console.WriteLine($"{m}  ({sw.Elapsed.TotalSeconds:F0}s)"));
                Directory.CreateDirectory(Path.GetDirectoryName(REFLEX_FILE));
                File.WriteAllText(REFLEX_FILE, string.Join(",", best.Select(x => x.ToString("R"))) + "\n");
                Console.WriteLine($"saved {REFLEX_FILE}");
                return 0;
            }
            case "runfile":
            {
                double s = skill_of(opt("tier", ""), double.Parse(opt("skill", "1")));
                long seed = long.Parse(opt("seed", "1"));
                var sim = new GameSim(seed);
                var d = decider(bot, s, seed);
                var tr = Trace.play(sim, d, cap, false);
                string name = opt("name", $"{bot} {s:F2}");
                RunFile.write(opt("out", "run.json"), sim, tr.taps, name: name);
                Console.WriteLine($"seed {seed}: {tr.points} points, {tr.ticks} ticks, {tr.cause} in {tr.room} -> {opt("out", "run.json")}");
                return 0;
            }
        }
        Console.Error.WriteLine($"unknown human mode '{mode}'");
        return 2;
    }

    static double skill_of(string tier, double s)
    {
        if (tier == "") return s;
        var fit = opt("fitted", "");
        if (fit != "")
        {
            var parts = fit.Split(',').Select(double.Parse).ToArray();
            int i = Array.IndexOf(TIERS, tier);
            if (i >= 0 && i < parts.Length) return parts[i];
        }
        return HumanTiers.SKILL.GetValueOrDefault(tier, 1.0);
    }

    public static Func<GameSim, bool> decider(string bot, double s, long seed)
    {
        if (bot == "blind")
        {
            var bp = new BlindPlanner(seed);
            return bp.decide;
        }
        if (bot == "motor")
        {
            var m = O.ContainsKey("sigma") ? Motor.at(double.Parse(opt("sigma", "0"))) : MotorTiers.of(opt("tier", "beast"));
            double sg = m.sigma;
            if (O.ContainsKey("react")) m = m with { react_mu = double.Parse(opt("react", "13")) };
            if (O.ContainsKey("gap")) m = m with { min_gap = long.Parse(opt("gap", "8")) };
            var bp = MotorPlayer.make_planner(seed, sg);
            if (O.ContainsKey("lines")) bp.lines = int.Parse(opt("lines", "1"));
            if (O.ContainsKey("wobble")) bp.wobble = int.Parse(opt("wobble", "0"));
            if (O.ContainsKey("copies")) bp.copies = int.Parse(opt("copies", "1"));
            if (O.ContainsKey("margin")) bp.margin = long.Parse(opt("margin", "10"));
            if (O.ContainsKey("smargin")) bp.spike_margin = opt("smargin", "1") == "1";
            if (O.ContainsKey("mcost")) bp.margin_cost = long.Parse(opt("mcost", "40"));
            if (O.ContainsKey("midcost")) bp.mid_cost = long.Parse(opt("midcost", "1"));
            var mp = new MotorPlayer(m, seed, bp);
            return mp.decide;
        }
        if (bot == "reflex")
        {
            var p = new ReflexBot(reflex_weights(), s >= 1 && !O.ContainsKey("set") ? null : with_overrides(Skill.at(s)), seed);
            return p.decide;
        }
        var h = new HumanBot(with_overrides(Skill.at(s)), seed);
        return h.decide;
    }

    static double[] _rw;
    static double[] reflex_weights()
    {
        if (_rw != null) return _rw;
        string w = opt("weights", "");
        if (w == "" && File.Exists(REFLEX_FILE)) w = File.ReadAllText(REFLEX_FILE).Trim();
        _rw = w == "" ? ReflexBot.START : w.Split(',').Select(double.Parse).ToArray();
        return _rw;
    }
    public static readonly string REFLEX_FILE = Path.Combine("tools", "humanbot", "reflex.txt");

    /// --set lag=1,think=2,...: override single limits (for experiments).
    public static Skill with_overrides(Skill k)
    {
        string set = O?.GetValueOrDefault("set", "") ?? "";
        foreach (var kv in set.Split(',', StringSplitOptions.RemoveEmptyEntries))
        {
            var p = kv.Split('=');
            double v = double.Parse(p[1]);
            k = p[0] switch
            {
                "lag" => k with { lag = v }, "think" => k with { think = v }, "horizon" => k with { horizon = v },
                "jitter" => k with { jitter = v }, "perr" => k with { perr = v }, "lapse" => k with { lapse = v },
                "comfort" => k with { comfort = v }, "tapcost" => k with { tapcost = v }, "margin" => k with { margin = v }, "focus" => k with { focus = v }, "plan" => k with { plan = v }, "width" => k with { width = v },
                _ => throw new ArgumentException($"unknown limit '{p[0]}'"),
            };
        }
        return k;
    }

    public static Trace[] play(string bot, double s, long first, int n, long cap, int threads)
    {
        var runs = new Trace[n];
        Parallel.For(0, n, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            long seed = first + 1 + i;
            runs[i] = Trace.play(new GameSim(seed), decider(bot, s, seed), cap);
        });
        return runs;
    }

    static Func<GameSim, bool> baseline(string bot, long seed)
    {
        switch (bot)
        {
            case "gap":
            {
                var rng = new SimRng(seed);
                return sim => SimBots.gap_seeker(sim, rng);
            }
            case "rl":
            {
                string path = opt("policy", Path.Combine("tools", "rlbot", "policy.json"));
                var pol = FastSim.Rl.Policy.load(path);
                var p = new FastSim.Rl.Player(pol, FastSim.Rl.Handicap.NONE, seed);
                return p.decide;
            }
            case "search":
            {
                // SurvivalSearch replanned every 30 ticks over 150 ticks of look-ahead.
                var plan = new Queue<bool>();
                return sim =>
                {
                    if (!sim.state.started) return true;
                    if (plan.Count == 0)
                    {
                        var ss = new SurvivalSearch();
                        if (ss.run_quick(sim, 150))
                            foreach (var b in ss.best_inputs.Take(30)) plan.Enqueue(b != 0);
                        else plan.Enqueue(false);
                    }
                    return plan.Dequeue();
                };
            }
        }
        throw new ArgumentException($"unknown baseline bot '{bot}'");
    }

    public static void report(string what, IList<Trace> runs, Stopwatch sw)
    {
        var pts = runs.Select(r => r.points).ToArray();
        long ticks = runs.Sum(r => r.ticks);
        Console.WriteLine($"{what}: {runs.Count} runs, median {Humanness.med(pts)}, p25 {Humanness.pct(pts, 0.25)}, " +
                          $"p90 {Humanness.pct(pts, 0.9)}, mean {pts.Average():F1}, alive at cap {runs.Count(r => !r.dead)}, " +
                          $"deaths/100pt {100.0 * runs.Count(r => r.dead) / Math.Max(1, pts.Sum()):F3}, rate median {rate_median(runs):F0}, " +
                          $"{sw.Elapsed.TotalSeconds:F0}s ({ticks / Math.Max(0.001, sw.Elapsed.TotalSeconds):F0} ticks/s)");
        Console.WriteLine("  " + Humanness.of(runs));
        var deaths = runs.Where(r => r.dead).GroupBy(r => r.room).OrderByDescending(g => g.Count()).Take(8)
            .Select(g => $"{g.Key} {g.Count()}");
        Console.WriteLine("  deaths: " + string.Join(", ", deaths));
        var causes = runs.Where(r => r.dead).GroupBy(r => r.cause).OrderByDescending(g => g.Count())
            .Select(g => $"{g.Key} {g.Count()}");
        Console.WriteLine("  causes: " + string.Join(", ", causes));
        if (O.ContainsKey("debug"))
            foreach (var r in runs.Where(r => r.dead && r.cause.StartsWith("SPIKE")))
                Console.WriteLine($"    seed {r.seed} {r.room}: bounce y {r.bounce_y}, death y {r.death_y}, gap {r.gap_y}, {r.since_bounce}t after bounce");
    }

    /// The median a run would reach at this death rate per point (the yardstick's measure).
    public static double rate_median(IList<Trace> runs)
    {
        double d = runs.Count(r => r.dead) / (double)Math.Max(1, runs.Sum(r => r.points));
        return d <= 0 ? double.PositiveInfinity : Math.Log(0.5) / Math.Log(1 - d);
    }

    static void dump(string path, IList<Trace> runs)
    {
        using var w = new StreamWriter(path);
        w.WriteLine("seed,points,ticks,dead,room,cause,taps");
        foreach (var r in runs) w.WriteLine($"{r.seed},{r.points},{r.ticks},{r.dead},{r.room},{r.cause},{r.taps.Count}");
    }
}

/// The fitted skill knob of each tier (from `fastsim human fit`).
public static class HumanTiers
{
    public static readonly Dictionary<string, double> SKILL = new()
    {
        ["beginner"] = 0.0, ["normal"] = 0.25, ["good"] = 0.5, ["expert"] = 0.75, ["beast"] = 1.0,
    };
}
