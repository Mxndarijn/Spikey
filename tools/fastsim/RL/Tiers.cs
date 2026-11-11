using System.Diagnostics;
using System.Text.Json.Nodes;

namespace FastSim.Rl;

/// The five skill tiers: one policy, five handicaps (docs/RL_BOT.md).
/// calibrate finds each tier's handicap for its target median; measure plays
/// every tier over many seeds and prints median and p90.
public static class Tiers
{
    public static readonly string[] NAMES = { "beginner", "normal", "good", "expert", "beast" };
    /// Target medians of the handicapped tiers (set by the user; expert can be overridden).
    public static readonly Dictionary<string, double> TARGETS = new() { ["beginner"] = 30, ["normal"] = 60, ["good"] = 120, ["expert"] = 250 };
    /// Beast is the policy with no handicap; its median should reach this.
    public const double BEAST_TARGET = 500;
    public const long CALIBRATE_SEED = 500_000;
    public const int BISECT_STEPS = 11;

    public sealed record Tier(string name, double target, double skill, Handicap hc);

    /// Plays `n` full runs (seeds first+1..first+n), capped at `cap` ticks.
    public static RunResult[] play(Policy pol, Handicap hc, long first, int n, long cap, int threads)
    {
        var out_ = new RunResult[n];
        Parallel.For(0, n, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
            out_[i] = Player.play(pol, hc, new GameSim(first + 1 + i), cap));
        return out_;
    }

    public static double pct(IEnumerable<long> xs, double p)
    {
        var s = xs.OrderBy(x => x).ToArray();
        if (s.Length == 0) return 0;
        double at = p * (s.Length - 1);
        int lo = (int)Math.Floor(at), hi = (int)Math.Ceiling(at);
        return s[lo] + (s[hi] - s[lo]) * (at - lo);
    }

    public static int calibrate(string dir, int seeds, long cap, int threads, double expert_target)
    {
        var pol = Policy.load(Path.Combine(dir, "policy.json"));
        var clock = Stopwatch.StartNew();
        var beast = play(pol, Handicap.NONE, CALIBRATE_SEED, seeds, cap, threads);
        double beast_median = pct(beast.Select(r => r.points), 0.5);
        Console.WriteLine($"rlbot calibrate: beast median {beast_median} over {seeds} seeds (cap {cap} ticks)");
        var targets = new Dictionary<string, double>(TARGETS);
        if (expert_target > 0) targets["expert"] = expert_target;
        if (beast_median < BEAST_TARGET) Console.WriteLine($"  beast median {beast_median} is under its target {BEAST_TARGET}: train more");
        var tiers = new JsonArray();
        foreach (var name in NAMES)
        {
            if (name == "beast")
            {
                tiers.Add(tier_json(new Tier(name, beast_median, 1, Handicap.NONE), beast));
                continue;
            }
            double target = targets[name];
            double lo = 0, hi = 1;
            (double s, double median, RunResult[] runs) found = (0, double.MaxValue, null);
            for (int step = 0; step < BISECT_STEPS; step++)
            {
                double s = (lo + hi) / 2;
                var runs = play(pol, Handicap.at(s), CALIBRATE_SEED, seeds, cap, threads);
                double med = pct(runs.Select(r => r.points), 0.5);
                if (found.runs == null || Math.Abs(med - target) < Math.Abs(found.median - target)) found = (s, med, runs);
                if (med < target) lo = s;
                else hi = s;
            }
            var t = new Tier(name, target, Math.Round(found.s, 4), Handicap.at(found.s));
            Console.WriteLine($"  {name,-9} target {target,5}  skill {t.skill:F4} ({t.hc})  median {found.median}");
            tiers.Add(tier_json(t, found.runs));
        }
        var o = new JsonObject
        {
            ["gameplay_version"] = SimConfig.GAMEPLAY_VERSION,
            ["layout"] = Observer.LAYOUT,
            ["calibrate_seeds"] = seeds,
            ["cap"] = cap,
            ["tiers"] = tiers,
        };
        File.WriteAllText(Path.Combine(dir, "tiers.json"), o.ToJsonString(Policy.PRETTY));
        Console.WriteLine($"rlbot calibrate: wrote tiers.json in {clock.Elapsed.TotalSeconds:F0} s");
        return 0;
    }

    static JsonObject tier_json(Tier t, RunResult[] runs) => new()
    {
        ["name"] = t.name,
        ["target"] = t.target,
        ["skill"] = t.skill,
        ["delay"] = t.hc.delay,
        ["jitter"] = t.hc.jitter,
        ["miss"] = Math.Round(t.hc.miss, 4),
        ["calibrated_median"] = pct(runs.Select(r => r.points), 0.5),
        ["calibrated_p90"] = pct(runs.Select(r => r.points), 0.9),
    };

    /// Score bands for the deaths-per-100-points report.
    public static readonly long[] BANDS = { 0, 10, 20, 40, 80 };

    /// Deaths per 100 points scored inside each band: points scored in a
    /// band count for every run that got there, deaths for the runs that ended in it.
    public static string band_line(RunResult[] runs)
    {
        var parts = new List<string>();
        for (int b = 0; b < BANDS.Length; b++)
        {
            long lo = BANDS[b], hi = b + 1 < BANDS.Length ? BANDS[b + 1] : long.MaxValue;
            long points = runs.Sum(r => Math.Max(0, Math.Min(r.points, hi) - lo));
            long died = runs.Count(r => r.dead && r.points >= lo && r.points < hi);
            string name = hi == long.MaxValue ? $"{lo}+" : $"{lo}..{hi}";
            parts.Add(points == 0 ? $"{name} -" : $"{name} {100.0 * died / points:F2}");
        }
        return string.Join(", ", parts);
    }

    public static List<Tier> load(string dir)
    {
        var o = JsonNode.Parse(File.ReadAllText(Path.Combine(dir, "tiers.json"))).AsObject();
        var out_ = new List<Tier>();
        foreach (var t in o["tiers"].AsArray())
            out_.Add(new Tier((string)t["name"], (double)t["target"], (double)t["skill"],
                new Handicap((int)t["delay"], (int)t["jitter"], (double)t["miss"])));
        return out_;
    }

    /// Plays each tier (or one) on seeds 1..n and prints its numbers. Exits 1
    /// when the tiers are not clearly apart (median x1.5 and p25 above the
    /// median of the tier below).
    public static int measure(string dir, string only, int seeds, long first, long cap, int threads, string out_path)
    {
        var pol = Policy.load(Path.Combine(dir, "policy.json"));
        var tiers = load(dir).Where(t => only == "" || only == "all" || t.name == only).ToList();
        if (tiers.Count == 0)
        {
            Console.Error.WriteLine($"no tier '{only}': {string.Join(", ", NAMES)}");
            return 2;
        }
        var clock = Stopwatch.StartNew();
        Console.WriteLine($"rlbot measure: {seeds} full runs per tier (seeds {first + 1}..{first + seeds}), cap {cap} ticks, no revives");
        Console.WriteLine($"  {"tier",-9} {"median",7} {"p90",7} {"p25",6} {"mean",7} {"room 2+",8}  {"handicap",-34} most deaths");
        var report = new JsonArray();
        var rows = new List<(string name, double median, double p25)>();
        foreach (var t in tiers)
        {
            var runs = play(pol, t.hc, first, seeds, cap, threads);
            var pts = runs.Select(r => r.points).ToList();
            double med = pct(pts, 0.5), p90 = pct(pts, 0.9), p25 = pct(pts, 0.25);
            double out_first = 100.0 * runs.Count(r => r.points >= SimConfig.POINTS_PER_ROOM) / runs.Length;
            int capped = runs.Count(r => !r.dead);
            var deaths = runs.Where(r => r.dead).GroupBy(r => r.room).OrderByDescending(g => g.Count()).Take(3)
                .Select(g => $"{g.Key} {100.0 * g.Count() / runs.Length:F0}%");
            var causes = runs.Where(r => r.dead).GroupBy(r => r.cause).OrderByDescending(g => g.Count())
                .Select(g => $"{g.Key.ToLower()} {100.0 * g.Count() / runs.Length:F0}%");
            string note = $"  [{string.Join(", ", causes)}]" + (capped > 0 ? $"  ({capped} reached the cap)" : "");
            Console.WriteLine($"  {t.name,-9} {med,7:F1} {p90,7:F1} {p25,6:F1} {pts.Average(),7:F1} {out_first,7:F0}%  {t.hc,-34} {string.Join(", ", deaths)}{note}");
            Console.WriteLine($"  {"",-9} deaths per 100 points: {band_line(runs)}; alive at the cap: {capped} of {runs.Length}");
            rows.Add((t.name, med, p25));
            var runs_json = new JsonArray(runs.Select(r => (JsonNode)new JsonObject
            {
                ["seed"] = r.seed, ["points"] = r.points, ["ticks"] = r.ticks, ["dead"] = r.dead, ["room"] = r.room, ["cause"] = r.cause,
            }).ToArray());
            report.Add(new JsonObject
            {
                ["tier"] = t.name, ["median"] = med, ["p90"] = p90, ["p25"] = p25, ["mean"] = pts.Average(),
                ["delay"] = t.hc.delay, ["jitter"] = t.hc.jitter, ["miss"] = t.hc.miss, ["runs"] = runs_json,
            });
        }
        Console.WriteLine($"  gameplay version {SimConfig.GAMEPLAY_VERSION}; copies: none (the policy reads only the observation)");
        int bad = 0;
        for (int i = 1; i < rows.Count; i++)
        {
            var (a, b) = (rows[i - 1], rows[i]);
            bool apart = b.median >= 1.5 * a.median && b.p25 > a.median;
            if (!apart)
            {
                bad++;
                Console.WriteLine($"  not apart: {b.name} (median {b.median}, p25 {b.p25}) vs {a.name} (median {a.median})");
            }
        }
        if (rows.Count > 1 && bad == 0) Console.WriteLine("  tiers apart: each median >= 1.5x the tier below, each p25 above the median below");
        Console.WriteLine($"rlbot measure: {clock.Elapsed.TotalSeconds:F0} s ({threads} threads)");
        if (out_path != "")
            File.WriteAllText(out_path, new JsonObject { ["seeds"] = seeds, ["first"] = first, ["cap"] = cap, ["tiers"] = report }.ToJsonString(Policy.PRETTY));
        return bad == 0 ? 0 : 1;
    }
}
