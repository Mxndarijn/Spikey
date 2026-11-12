using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using FastSim.Yard;

namespace FastSim.Measure;

/// `fastsim measure <bank|trials|estimate|confirm|runs|report|leak|check>`
/// (tools/yardstick.ps1 -Mode quick|confirm|report|leakrun, docs/BOT_TESTING.md).
public static class MeasureMain
{
    public static readonly JsonSerializerOptions PRETTY = new() { WriteIndented = true };
    /// Pocock bound for 5 equally spaced looks, two-sided 5%; and the sample
    /// size inflation of that design over one fixed look (80% power).
    public const int LOOKS = 5;
    public const double POCOCK = 2.413, POCOCK_INFLATION = 1.207;

    static void log(string s) => Console.Error.WriteLine(s);

    public static int run(List<string> pos, Dictionary<string, string> opts)
    {
        string what = pos.Count > 1 ? pos[1] : "";
        string O(string k, string d) => opts.GetValueOrDefault(k, d);
        int threads = Math.Clamp(int.Parse(O("threads", "16")), 1, 64);
        try
        {
            switch (what)
            {
                case "bank":
                {
                    var bot = MBots.find(O("bot", "blind"));
                    long first = long.Parse(O("first", SeedSets.DEV.ToString()));
                    var b = Bank.make(bot, first, int.Parse(O("seeds", "100")), long.Parse(O("cap", BotCaps.RUN_CAP.ToString())),
                        long.Parse(O("points", "400")), threads, log);
                    string path = O("out", $"{bot.name.Replace(':', '-')}.bank.json");
                    b.save(path);
                    Console.WriteLine($"bank {path}: {b.runs.Count} runs, {b.runs.Sum(r => r.visits.Count)} visits, {b.seconds:F0} s");
                    print_bank(b);
                    return 0;
                }
                case "trials":
                    return trials(opts, threads);
                case "estimate":
                    return estimate(opts);
                case "confirm":
                    return confirm(opts, threads);
                case "runs":
                    return late_runs(opts, threads);
                case "report":
                    return report(opts, threads);
                case "median":
                    return median(opts, threads);
                case "leak":
                {
                    var bot = MBots.find(O("bot", "blind"));
                    var o = LeakRun.check(bot, opts, threads, log);
                    Console.WriteLine(o.ToJsonString(PRETTY));
                    if (opts.ContainsKey("json")) File.WriteAllText(O("json", ""), o.ToJsonString(PRETTY) + "\n");
                    return (string)o["leaks"] == "no" ? 0 : 1;
                }
                case "visibility":
                {
                    // Rebuilds Measure/visible.tsv from game/run (the painters) and the sim's sources.
                    string root = Path.GetFullPath(O("root", Path.Combine(Path.GetDirectoryName(Visibility.file)!, "..", "..", "..")));
                    var rows = Visibility.generate(root);
                    string text = Visibility.header + string.Join("\n", rows) + "\n";
                    if (opts.ContainsKey("write")) File.WriteAllText(Visibility.file, text);
                    else Console.Write(text);
                    Console.Error.WriteLine($"{rows.Count} visible fields{(opts.ContainsKey("write") ? " written to " + Visibility.file : "")}");
                    return 0;
                }
                case "check":
                {
                    var errs = self_test();
                    foreach (var e in errs) Console.WriteLine("FAIL " + e);
                    Console.WriteLine(errs.Count == 0 ? "measure self-test ok" : $"measure self-test: {errs.Count} failures");
                    return errs.Count == 0 ? 0 : 1;
                }
            }
            Console.Error.WriteLine("measure: bank, trials, estimate, confirm, runs, report, median, leak, check");
            return 2;
        }
        catch (Exception e) when (e is ArgumentException or FileNotFoundException or InvalidDataException)
        {
            Console.Error.WriteLine(e.Message);
            return 2;
        }
    }

    static void print_bank(Bank b)
    {
        var set = b.as_set();
        var d = Survival.describe(set, 500);
        Console.WriteLine(Survival.text(d));
        var full = full_plateau(b);
        Console.WriteLine($"full runs, plateau 40..{(b.point_cap > 0 ? b.point_cap : "cap")}: {full.q:F4} [{full.lo:F4}, {full.hi:F4}] per 100, {full.deaths} deaths, " +
            $"{full.cpu_s:F0} CPU s ({full.cpu_per_death:F0} CPU s per plateau death)");
    }

    /// Plain full-run numbers on the bank's plateau visits: deaths / points, and the CPU it took (all of it, ramp included).
    public sealed record Full(double q, double lo, double hi, int deaths, long points, double cpu_s, double cpu_per_death);

    public static Full full_plateau(Bank b)
    {
        var vis = b.runs.SelectMany(r => r.visits).Where(v => Strat.plateau(v.key) && !v.censored).ToList();
        int d = vis.Count(v => v.died);
        long pts = vis.Sum(v => v.points + (v.died ? 1 : 0));
        var (lo, hi) = Survival.poisson_ci(d);
        double cpu = b.runs.Sum(r => r.ms) / 1000;
        return new Full(100.0 * d / Math.Max(1, pts), 100 * lo / Math.Max(1, pts), 100 * hi / Math.Max(1, pts), d, pts, cpu, cpu / Math.Max(1, d));
    }

    static string bots_of(Dictionary<string, string> opts) => opts.GetValueOrDefault("bots", opts.GetValueOrDefault("bot", "blind"));

    /// `trials --bank B --bots a,b --budget S --out T.tsv`: S CPU seconds more of
    /// trials (per bot), allocated by Neyman over the strata, the same jobs for every bot (paired).
    static int trials(Dictionary<string, string> opts, int threads)
    {
        var bank = Bank.load(opts["bank"]);
        string range = opts.GetValueOrDefault("range", "plateau");
        string path = opts.GetValueOrDefault("out", Path.ChangeExtension(opts["bank"], null).Replace(".bank", "") + ".trials.tsv");
        var bots = bots_of(opts).Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).Select(MBots.find).ToList();
        double budget = double.Parse(opts.GetValueOrDefault("budget", "600")) * 1000;
        var pools = new Strat.Pools(bank, range);
        var have = load_arms(path, bank, bots);
        foreach (var t in have.SelectMany(x => x)) pools.mark_used(t.seed, t.tick, t.k);
        pools.grow(8, threads);
        var arms = batch(bank, range, bots, have, pools, budget * bots.Count, threads, path);
        foreach (var (bot, ts) in bots.Zip(arms)) print_est(bank, ts, range);
        if (bots.Count > 1) print_ratios(bank, bots, arms, range);
        return 0;
    }

    /// Trials so far of each bot in `path`, plus the bank's own visits for the bank's bot.
    static List<List<Trial>> load_arms(string path, Bank bank, List<BotSpec> bots)
    {
        var all = Strat.load(path);
        return bots.Select(b =>
        {
            var l = all.Where(t => t.bot == b.name).ToList();
            if (b.name == bank.bot) l.AddRange(Strat.bank_trials(bank));
            return l;
        }).ToList();
    }

    static List<List<Trial>> batch(Bank bank, string range, List<BotSpec> bots, List<List<Trial>> arms, Strat.Pools pools,
        double budget_ms, int threads, string path)
    {
        var prior = Strat.bank_prior(bank);
        // budget_ms is for all arms together (each job is played by every arm).
        var plan = Strat.allocate(bank, range, arms, budget_ms, prior);
        int strata = plan.Count(kv => kv.Value > 0);
        var jobs = Strat.jobs(pools, plan, threads, new Random(arms.Sum(a => a.Count) + 17));
        log($"batch: {jobs.Count} trials per bot over {strata} strata (pool: {pools.redraws} redraws, k < {pools.tried_k})");
        var res = new List<List<Trial>>();
        for (int i = 0; i < bots.Count; i++)
        {
            var got = Strat.run_trials(bots[i], "room", bank, jobs, bank.cap, threads, log);
            Strat.append(path, got);
            res.Add(arms[i].Concat(got).ToList());
        }
        return res;
    }

    /// Prints an estimate and its cost. Information = 1 / se_log^2 (= deaths for a plain
    /// Poisson count); full runs give one unit per plateau death at the bank's CPU per death
    /// (ramp included), so the speedup is the ratio of CPU per unit of information.
    static Strat.Est print_est(Bank bank, List<Trial> ts, string range)
    {
        var prior = Strat.bank_prior(bank);
        var e = Strat.estimate(bank, ts, range, prior.ToDictionary(kv => kv.Key, kv => (kv.Value.p, kv.Value.l)));
        double cpu = e.ms / 1000;
        double per_info = cpu * e.se_log * e.se_log;
        var full = full_plateau(bank);
        Console.WriteLine(e.text());
        Console.WriteLine($"    CPU per unit of information: {per_info:F0} s here, {full.cpu_per_death:F0} s with full runs ({full.cpu_per_death / Math.Max(1e-9, per_info):F2}x)" +
            (ts.Any(t => t.k < 0) ? "; the bank's visits are counted in" : "; the shared bank not counted"));
        Console.WriteLine("    killers: " + string.Join(", ", e.cells.Where(c => c.d > 0).OrderByDescending(c => c.pi * c.p).Take(6)
            .Select(c => $"{c.key} {c.d}/{c.n}")));
        return e;
    }

    static void print_ratios(Bank bank, List<BotSpec> bots, List<List<Trial>> arms, string range)
    {
        var prior = Strat.bank_prior(bank).ToDictionary(kv => kv.Key, kv => (kv.Value.p, kv.Value.l));
        var ea = Strat.estimate(bank, arms[0], range, prior);
        for (int i = 1; i < bots.Count; i++)
        {
            var eb = Strat.estimate(bank, arms[i], range, prior);
            var r = Strat.ratio(ea, eb, bank);
            Console.WriteLine($"{bots[i].name} / {bots[0].name}: {r.r:F3} [{r.lo:F3}, {r.hi:F3}], z {r.z:F2}, paired trials {r.paired} (rho {r.rho:F2})");
        }
    }

    /// `estimate --bank B --trials T [--bots a,b]`: estimates from saved files only.
    static int estimate(Dictionary<string, string> opts)
    {
        var bank = Bank.load(opts["bank"]);
        string range = opts.GetValueOrDefault("range", "plateau");
        print_bank(bank);
        var all = opts.ContainsKey("trials") ? opts["trials"].Split(',').SelectMany(Strat.load).ToList() : new List<Trial>();
        var names = opts.ContainsKey("bots") ? opts["bots"].Split(',').ToList() : all.Select(t => t.bot).Distinct().Prepend(bank.bot).Distinct().ToList();
        var arms = names.Select(n => all.Where(t => t.bot == n).Concat(n == bank.bot && !opts.ContainsKey("no-bank") ? Strat.bank_trials(bank) : Enumerable.Empty<Trial>()).ToList()).ToList();
        var json = new JsonArray();
        var prior = Strat.bank_prior(bank).ToDictionary(kv => kv.Key, kv => (kv.Value.p, kv.Value.l));
        for (int i = 0; i < names.Count; i++)
        {
            if (arms[i].Count == 0) continue;
            json.Add(print_est(bank, arms[i], range).json());
        }
        var ests = arms.Select(a => Strat.estimate(bank, a, range, prior)).ToList();
        var cmp = new JsonArray();
        for (int i = 1; i < names.Count; i++)
        {
            if (arms[i].Count == 0 || arms[0].Count == 0) continue;
            var r = Strat.ratio(ests[0], ests[i], bank);
            Console.WriteLine($"{names[i]} / {names[0]}: {r.r:F3} [{r.lo:F3}, {r.hi:F3}], z {r.z:F2}, paired {r.paired} (rho {r.rho:F2})");
            cmp.Add(new JsonObject { ["a"] = names[0], ["b"] = names[i], ["ratio"] = Math.Round(r.r, 4), ["lo"] = Math.Round(r.lo, 4),
                ["hi"] = Math.Round(r.hi, 4), ["z"] = Math.Round(r.z, 3), ["paired"] = r.paired, ["rho"] = Math.Round(r.rho, 3) });
        }
        if (opts.ContainsKey("json"))
            File.WriteAllText(opts["json"], new JsonObject { ["estimates"] = json, ["compare"] = cmp }.ToJsonString(PRETTY) + "\n");
        return 0;
    }

    /// `confirm --bank B --bots base,new --ratio 0.8 --out T.tsv`: a sequential
    /// comparison. The plan is fixed before the first trial: the information
    /// (1 / se^2 of the log rate ratio) that gives 80% power for `ratio` at
    /// 5% with Pocock's 5 looks. Look j comes when 1/se^2 reaches j/5 of it; the
    /// test stops at the first look with |z| > 2.413. Sized by information
    /// (deaths), not by seeds.
    static int confirm(Dictionary<string, string> opts, int threads)
    {
        var bank = Bank.load(opts["bank"]);
        string range = opts.GetValueOrDefault("range", "plateau");
        var bots = bots_of(opts).Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).Select(MBots.find).ToList();
        if (bots.Count != 2) throw new ArgumentException("confirm compares two bots: --bots base,new");
        double rmin = double.Parse(opts.GetValueOrDefault("ratio", "0.8"));
        string path = opts.GetValueOrDefault("out", Path.ChangeExtension(opts["bank"], null).Replace(".bank", "") + ".confirm.tsv");
        double max_cpu = double.Parse(opts.GetValueOrDefault("max-cpu", "1e9"));
        double z_ab = 1.96 + 0.8416;
        double i_max = POCOCK_INFLATION * Math.Pow(z_ab / Math.Log(rmin), 2);
        Console.WriteLine($"plan: ratio {rmin} (80% power, 5% two-sided), {LOOKS} looks, stop at |z| > {POCOCK}; information at the last look {i_max:F0} (deaths-equivalent per arm about {2 * i_max:F0})");
        var pools = new Strat.Pools(bank, range);
        var arms = load_arms(path, bank, bots);
        foreach (var t in arms.SelectMany(x => x)) pools.mark_used(t.seed, t.tick, t.k);
        pools.grow(8, threads);
        var prior = Strat.bank_prior(bank).ToDictionary(kv => kv.Key, kv => (kv.Value.p, kv.Value.l));
        var clock = Stopwatch.StartNew();
        string decision = "no difference shown at the planned size";
        for (int look = 1; look <= LOOKS; look++)
        {
            double want = i_max * look / LOOKS;
            Strat.Ratio r = null;
            for (int round = 0; round < 12; round++)
            {
                var ea = Strat.estimate(bank, arms[0], range, prior);
                var eb = Strat.estimate(bank, arms[1], range, prior);
                r = Strat.ratio(ea, eb, bank);
                double info = 1 / (r.se_log * r.se_log);
                if (info >= want * 0.97) break;
                // CPU so far per unit of information, times what is missing (at least a minute, at most double).
                double spent = (ea.ms + eb.ms) / 1000;
                double need = spent > 0 && info > 0 ? spent * (want / info - 1) : 600;
                need = Math.Clamp(need * 1.1, 60, Math.Max(120, spent));
                if (spent + need > max_cpu) { decision = "stopped: --max-cpu reached"; look = LOOKS + 1; break; }
                arms = batch(bank, range, bots, arms, pools, need * 1000, threads, path);
            }
            if (look > LOOKS) break;
            var cpu = arms.Sum(a => a.Where(t => t.k >= 0).Sum(t => t.ms)) / 1000;
            Console.WriteLine($"look {look}: {bots[1].name} / {bots[0].name} = {r.r:F3} [{r.lo:F3}, {r.hi:F3}], z {r.z:F2}, information {1 / (r.se_log * r.se_log):F0} of {want:F0}, rho {r.rho:F2}, {cpu:F0} CPU s of trials");
            if (Math.Abs(r.z) > POCOCK)
            {
                decision = r.z < 0 ? $"{bots[1].name} dies less (stopped at look {look})" : $"{bots[1].name} dies more (stopped at look {look})";
                break;
            }
            // Futility: the gain hoped for is outside the interval (Pocock-adjusted).
            double hi_p = Math.Exp(Math.Log(r.r) + POCOCK * r.se_log), lo_p = Math.Exp(Math.Log(r.r) - POCOCK * r.se_log);
            if (look < LOOKS && hi_p < 1 / rmin && lo_p > rmin)
            {
                decision = $"no change as big as {rmin} either way (futility at look {look})";
                break;
            }
        }
        Console.WriteLine("decision: " + decision);
        foreach (var a in arms) print_est(bank, a, range);
        {
            // What full runs would have cost for the same certainty: two independent arms of D
            // plateau deaths each give a log-ratio information of D / 2, at the bank's CPU per death.
            var ea = Strat.estimate(bank, arms[0], range, prior);
            var eb = Strat.estimate(bank, arms[1], range, prior);
            var r = Strat.ratio(ea, eb, bank);
            double info = 1 / (r.se_log * r.se_log);
            double trial_cpu = arms.Sum(a => a.Where(t => t.k >= 0).Sum(t => t.ms)) / 1000;
            var full = full_plateau(bank);
            // Each arm at its own speed: the bank's CPU per death times the arm's CPU on the
            // paired trials relative to the bank bot's (the same jobs for both).
            double ms_a = arms[0].Where(t => t.k >= 0).Sum(t => t.ms), ms_b = arms[1].Where(t => t.k >= 0).Sum(t => t.ms);
            double speed_b = ms_a > 0 ? ms_b / ms_a : 1;
            double full_cpu = (2 * info) * full.cpu_per_death * (1 + speed_b);
            Console.WriteLine($"cost: information {info:F0} on the log ratio for {trial_cpu:F0} CPU s of trials (+{full.cpu_s:F0} s for the shared bank); " +
                $"full runs for the same: {2 * info:F0} plateau deaths per arm, {full_cpu:F0} CPU s: {full_cpu / trial_cpu:F2}x, {full_cpu / (trial_cpu + full.cpu_s):F2}x with the bank");
        }
        return 0;
    }

    /// `runs --bank B --bot X --from 100 --n 50 --out T.tsv`: plateau runs that
    /// start late. Each starts from a bank entry at or past `from` points (the
    /// first per bank run), with the spine replaced, so the rest of the run is
    /// new; it plays to death or the cap. Gives the plateau rate and the
    /// survival past `from` for strong bots without replaying the first rooms.
    static int late_runs(Dictionary<string, string> opts, int threads)
    {
        var bank = Bank.load(opts["bank"]);
        var bot = MBots.find(opts.GetValueOrDefault("bot", bank.bot));
        long from = long.Parse(opts.GetValueOrDefault("from", "100"));
        int n = int.Parse(opts.GetValueOrDefault("n", "50"));
        long cap = long.Parse(opts.GetValueOrDefault("cap", BotCaps.RUN_CAP.ToString()));
        string path = opts.GetValueOrDefault("out", Path.ChangeExtension(opts["bank"], null).Replace(".bank", "") + $".from{from}.tsv");
        var starts = new List<(int run, long tick, bool tap, long k)>();
        for (int i = 0; i < bank.runs.Count; i++)
        {
            var v = bank.runs[i].visits.FirstOrDefault(v => v.score >= from);
            if (v != null) starts.Add((i, v.tick, v.tap, 0));
        }
        if (starts.Count == 0) throw new ArgumentException($"no bank run reaches {from} points");
        var jobs = Enumerable.Range(0, n).Select(j => { var s = starts[j % starts.Count]; return (s.run, s.tick, s.tap, (long)(1000 + j / starts.Count)); }).ToList();
        var got = Strat.run_trials(bot, "run", bank, jobs, cap, threads, log);
        Strat.append(path, got);
        var all = Strat.load(path).Where(t => t.kind == "run" && t.bot == bot.name).ToList();
        var set = new Survival.Set { name = $"{bot.name} from {from}", cap = cap, runs = all.Select(t => new Survival.Obs(t.seed, t.points, t.died)).ToList() };
        int d = set.deaths;
        long pts = set.runs.Sum(r => r.points);
        var (lo, hi) = Survival.poisson_ci(d);
        Console.WriteLine($"{bot.name}, {all.Count} runs from {from} points: {100.0 * d / Math.Max(1, pts):F4} [{100 * lo / Math.Max(1, pts):F4}, {100 * hi / Math.Max(1, pts):F4}] per 100 past {from}, {d} deaths in {pts} points, {set.alive} alive at the cap, {all.Sum(t => t.ms) / 1000:F0} CPU s");
        Console.WriteLine(Survival.text(Survival.describe(set, 500)));
        return 0;
    }

    /// The score bands of the median model: the ramp's four classes, then the plateau.
    public static readonly (string range, long from, long to)[] BANDS =
    {
        ("@b0", 0, 10), ("@b10", 10, 20), ("@b20", 20, 30), ("@b30", 30, 40), ("plateau", 40, long.MaxValue),
    };

    /// The score where a run with these death rates per 100 points (one per band) is
    /// alive with chance 1/2: survival exp(-sum of rate x points in each band).
    public static double median_of(double[] per100)
    {
        double h = Math.Log(2);
        for (int i = 0; i < BANDS.Length; i++)
        {
            double rate = Math.Max(1e-9, per100[i] / 100), span = BANDS[i].to - BANDS[i].from;
            if (rate * span >= h) return BANDS[i].from + h / rate;
            h -= rate * span;
        }
        return double.PositiveInfinity;
    }

    /// `median --bank B --bot X --budget S [--out T.tsv] [--json J]`: the KM median a bot
    /// would get on full runs, from room trials (docs/BOT_TESTING.md, "Tier calibration").
    /// S more CPU seconds of trials over every stratum, ramp and plateau (Neyman), the death
    /// rate per band from the stratified estimator, then the median of the piecewise
    /// constant survival those rates give; its interval from 4000 draws of the rates
    /// (each lognormal by its own CI). Trials pile up in T, so a second call refines.
    static int median(Dictionary<string, string> opts, int threads)
    {
        var bank = Bank.load(opts["bank"]);
        var bot = MBots.find(opts.GetValueOrDefault("bot", "blind"));
        string path = opts.GetValueOrDefault("out", Path.ChangeExtension(opts["bank"], null).Replace(".bank", "") + ".median.tsv");
        double budget = double.Parse(opts.GetValueOrDefault("budget", "300"), System.Globalization.CultureInfo.InvariantCulture) * 1000;
        var bots = new List<BotSpec> { bot };
        var pools = new Strat.Pools(bank, "all");
        var have = load_arms(path, bank, bots);
        foreach (var t in have.SelectMany(x => x)) pools.mark_used(t.seed, t.tick, t.k);
        pools.grow(8, threads);
        var arms = budget > 0 ? batch(bank, "all", bots, have, pools, budget, threads, path) : have;
        var prior = Strat.bank_prior(bank).ToDictionary(kv => kv.Key, kv => (kv.Value.p, kv.Value.l));
        var est = BANDS.Select(b => Strat.estimate(bank, arms[0], b.range, prior)).ToArray();
        double med = median_of(est.Select(e => e.q).ToArray());
        var rng = new Random(4711);
        var draws = new List<double>();
        for (int i = 0; i < 4000; i++)
        {
            var q = est.Select(e =>
            {
                double u = 1.0 - rng.NextDouble(), v = rng.NextDouble();
                double g = Math.Sqrt(-2 * Math.Log(u)) * Math.Cos(2 * Math.PI * v);
                return e.q * Math.Exp(g * e.se_log);
            }).ToArray();
            draws.Add(median_of(q));
        }
        draws.Sort();
        double lo = draws[(int)(0.025 * draws.Count)], hi = draws[(int)(0.975 * draws.Count) - 1];
        double cpu = arms[0].Where(t => t.k >= 0).Sum(t => t.ms) / 1000;
        JsonNode R(double v) => double.IsInfinity(v) ? null : Math.Round(v, 1);
        var o = new JsonObject
        {
            ["bot"] = bot.name, ["about"] = bot.about, ["median"] = R(med), ["lo"] = R(lo), ["hi"] = R(hi),
            ["trials"] = arms[0].Count(t => t.k >= 0), ["deaths"] = arms[0].Count(t => t.k >= 0 && t.died), ["cpu_s"] = Math.Round(cpu),
            ["bank"] = opts["bank"], ["gameplay_version"] = SimConfig.GAMEPLAY_VERSION,
            ["bands"] = new JsonArray(BANDS.Zip(est).Select(x => (JsonNode)new JsonObject
            {
                ["range"] = x.First.range, ["per100"] = Math.Round(x.Second.q, 4), ["lo"] = Math.Round(x.Second.lo, 4),
                ["hi"] = Math.Round(x.Second.hi, 4), ["trials"] = x.Second.trials, ["deaths"] = x.Second.deaths,
                ["imputed_share"] = Math.Round(x.Second.imputed_share, 3),
            }).ToArray()),
        };
        Console.WriteLine($"{bot.name}: median {(double.IsInfinity(med) ? "past every band" : med.ToString("F0"))} " +
            $"[{(double.IsInfinity(lo) ? "inf" : lo.ToString("F0"))}, {(double.IsInfinity(hi) ? "inf" : hi.ToString("F0"))}], " +
            $"{o["trials"]} trials, {o["deaths"]} deaths, {cpu:F0} CPU s");
        foreach (var e in est) Console.WriteLine("  " + e.text());
        if (opts.ContainsKey("json")) File.WriteAllText(opts["json"], o.ToJsonString(PRETTY) + Environment.NewLine);
        return 0;
    }

    /// `report --bot X [--fair F] [--claimed tier]`: the holdout (seeds 1..400,
    /// the bots' cap), run once per release candidate. KM median with CI and
    /// the tier verdict; beast and infinite by the plateau rate and the share
    /// of finishable runs finished.
    static int report(Dictionary<string, string> opts, int threads)
    {
        var bot = MBots.find(opts.GetValueOrDefault("bot", "blind"));
        int seeds = int.Parse(opts.GetValueOrDefault("seeds", SeedSets.HOLDOUT_N.ToString()));
        long cap = long.Parse(opts.GetValueOrDefault("cap", BotCaps.RUN_CAP.ToString()));
        string path = opts.GetValueOrDefault("out", $"{bot.name.Replace(':', '-')}.holdout.bank.json");
        Bank bank = File.Exists(path) && !opts.ContainsKey("again") ? Bank.load(path) : null;
        if (bank == null || bank.bot != bot.name)
        {
            bank = Bank.make(bot, SeedSets.HOLDOUT, seeds, cap, 0, threads, log);
            bank.save(path);
        }
        var fair = opts.ContainsKey("fair") ? Tier.load_fair(opts["fair"]) : null;
        string claimed = opts.GetValueOrDefault("claimed", Stats.claimed_tier(bot.name));
        var v = Tier.verdict(bank.as_set(bot.name + "_holdout"), claimed, fair);
        v["bot"] = bot.name;
        v["seeds"] = $"{SeedSets.HOLDOUT + 1}..{SeedSets.HOLDOUT + seeds}";
        v["gameplay_version"] = SimConfig.GAMEPLAY_VERSION;
        Console.WriteLine(Survival.text(Survival.describe(bank.as_set(), 1000)));
        Console.WriteLine(v.ToJsonString(PRETTY));
        if (opts.ContainsKey("json")) File.WriteAllText(opts["json"], v.ToJsonString(PRETTY) + "\n");
        return 0;
    }

    // ------------------------------------------------------------ self-test

    /// Checks the estimator on made-up trials with known answers, the file
    /// round trips, and that a redraw from a bank entry enters a room.
    public static List<string> self_test()
    {
        var errs = new List<string>();
        // A bank with two strata: A (share 0.75, p 0.02) and B (share 0.25, p 0.2), 10 points a visit.
        var bank = new Bank { bot = "t", cap = 1000 };
        var run = new BankRun { seed = 1 };
        for (int i = 0; i < 300; i++) run.visits.Add(new Visit(i, false, 50, "A@p", false, false, 10, 100, 1));
        for (int i = 0; i < 100; i++) run.visits.Add(new Visit(1000 + i, false, 50, "B@p", false, false, 10, 100, 1));
        bank.runs.Add(run);
        var rng = new Random(5);
        var trials = new List<Trial>();
        for (int i = 0; i < 4000; i++) trials.Add(new Trial("x", "room", 1, i, 0, "A@p", rng.NextDouble() < 0.02, false, 10, 100, 1));
        for (int i = 0; i < 4000; i++) trials.Add(new Trial("x", "room", 1, i, 1, "B@p", rng.NextDouble() < 0.2, false, 10, 100, 1));
        // Died visits score fewer points; here they score 10 too, so Q = 100 * (0.75*0.02 + 0.25*0.2) / 10 = 0.65.
        var e = Strat.estimate(bank, trials, "plateau");
        if (Math.Abs(e.q - 0.65) > 0.05) errs.Add($"stratified estimate {e.q:F3}, want 0.65");
        if (!(e.lo < 0.65 && e.hi > 0.65)) errs.Add($"interval [{e.lo:F3}, {e.hi:F3}] misses 0.65");
        // Coverage of the interval over repeated samples (should be near 95%).
        int cover = 0;
        for (int rep = 0; rep < 200; rep++)
        {
            var r2 = new Random(100 + rep);
            var ts = new List<Trial>();
            for (int i = 0; i < 300; i++) ts.Add(new Trial("x", "room", 1, i, 0, "A@p", r2.NextDouble() < 0.02, false, 10, 100, 1));
            for (int i = 0; i < 200; i++) ts.Add(new Trial("x", "room", 1, i, 1, "B@p", r2.NextDouble() < 0.2, false, 10, 100, 1));
            var e2 = Strat.estimate(bank, ts, "plateau");
            if (e2.lo < 0.65 && e2.hi > 0.65) cover++;
        }
        if (cover < 180 || cover > 198) errs.Add($"interval coverage {cover}/200, want about 190");
        // Neyman: B (p 0.2) must get more trials per visit share than A.
        var prior = new Dictionary<string, (double, double, double)> { ["A@p"] = (0.02, 10, 1), ["B@p"] = (0.2, 10, 1) };
        var plan = Strat.allocate(bank, "plateau", new List<List<Trial>> { new() }, 1000, prior);
        double ra = plan.GetValueOrDefault("A@p") / 0.75, rb = plan.GetValueOrDefault("B@p") / 0.25;
        if (!(rb > ra * 2)) errs.Add($"allocation A {plan.GetValueOrDefault("A@p")} B {plan.GetValueOrDefault("B@p")}: the deadly stratum should get more per share");
        // Ratio of an arm with itself is 1 and fully paired.
        var rr = Strat.ratio(e, e, bank);
        if (Math.Abs(rr.r - 1) > 1e-9 || rr.rho < 0.999) errs.Add($"self ratio {rr.r} rho {rr.rho}");
        // Trial file round trip.
        string tmp = Path.Combine(Path.GetTempPath(), $"measure_selftest_{Environment.ProcessId}.tsv");
        try
        {
            File.Delete(tmp);
            Strat.append(tmp, trials.Take(5));
            var back = Strat.load(tmp);
            if (back.Count != 5 || back[3] != trials[3]) errs.Add("trials file round trip");
        }
        finally { File.Delete(tmp); }
        // A real bank: a short run of the gap seeker, saved and loaded, then a redraw from an entry.
        var gap = Bots.find("gap");
        var b = Bank.make(gap, 0, 3, 6000, 0, 3);
        string bp = Path.Combine(Path.GetTempPath(), $"measure_selftest_{Environment.ProcessId}.bank.json");
        try
        {
            b.save(bp);
            var b2 = Bank.load(bp);
            if (b2.runs.Count != 3 || b2.runs[1].taps.Length != b.runs[1].taps.Length || b2.runs[1].visits.Count != b.runs[1].visits.Count)
                errs.Add("bank file round trip");
        }
        finally { File.Delete(bp); }
        var r0 = b.runs.FirstOrDefault(r => r.visits.Count > 0);
        if (r0 == null) errs.Add("gap seeker entered no room in 6000 ticks");
        else
        {
            var v = r0.visits[0];
            var pre = Bank.replay(r0, v.tick);
            var real = pre.clone_deep();
            real.step(v.tap);
            if (Bank.key(real) != v.key) errs.Add($"replayed entry is {Bank.key(real)}, bank says {v.key}");
            int entered = 0;
            var keys = new HashSet<string>();
            for (long k = 0; k < 20; k++)
                if (Strat.redraw(pre, v.tap, Strat.spine_seed(r0.seed, v.tick, k)) is { } c)
                {
                    entered++;
                    keys.Add(Bank.key(c));
                }
            if (entered < 20) errs.Add($"only {entered}/20 redraws entered a room");
            if (keys.Count < 3) errs.Add($"20 redraws gave only {keys.Count} different rooms");
        }
        // The visible list matches the drawing code (rebuild: measure visibility --write).
        string root = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(Visibility.file)!, "..", "..", ".."));
        if (Directory.Exists(Path.Combine(root, "game", "run")))
        {
            var want = Visibility.generate(root);
            var have = File.Exists(Visibility.file) ? File.ReadAllLines(Visibility.file).Where(l => !l.StartsWith('#') && l != "").ToList() : new List<string>();
            if (!want.SequenceEqual(have)) errs.Add("tools/fastsim/Measure/visible.tsv is stale: run `fastsim measure visibility --write`");
        }
        // The whole-run leak check, calibrated: the gap seeker sees only the screen
        // (no leak), PlannerBot steps copies of the real sim (it must leak).
        var leak_opts = new Dictionary<string, string> { ["seeds"] = "2", ["forks"] = "6", ["cap"] = "5000", ["points"] = "60" };
        var lg = LeakRun.check(Bots.find("gap"), leak_opts, 2, null);
        if ((string)lg["leaks"] != "no") errs.Add($"leak check on the gap seeker: {lg["leaks"]} ({lg["example"]})");
        var lp = LeakRun.check(Bots.find("planner"), leak_opts, 2, null);
        if ((string)lp["leaks"] != "yes") errs.Add($"leak check on PlannerBot (real copies) found no leak: {lp.ToJsonString()}");
        // Tier bands.
        var (blo, bhi) = Tier.band("normal");
        if (Math.Abs(blo - 42.4) > 0.1 || Math.Abs(bhi - 84.9) > 0.1) errs.Add($"normal band [{blo}, {bhi})");
        return errs;
    }
}
