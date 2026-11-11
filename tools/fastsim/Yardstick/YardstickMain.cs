using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace FastSim.Yard;

/// `fastsim yardstick <run|compare|list> [options]` (tools/yardstick.ps1,
/// docs/YARDSTICK.md): one shared measure of every bot. Same seeds, same cap
/// and the same numbers for all, written as one JSON per bot and run set plus
/// a comparison table across every JSON in the output folder.
public static class YardstickMain
{
    public const int FORMAT = 1;
    /// Seeds FIRST+1.. : apart from the RL calibration (500 001..) and the
    /// usual 1..n sweeps, so no bot is measured on seeds it was tuned on.
    public const long FIRST = 7_000_000;
    public const int QUICK = 200, FULL = 1000;
    /// 20 minutes of play: past a beast median of 500 points (~80 ticks a point).
    public const long CAP = 60 * 60 * 20;
    public static readonly JsonSerializerOptions PRETTY = new() { WriteIndented = true };

    public static int run(List<string> pos, Dictionary<string, string> opts)
    {
        string what = pos.Count > 1 ? pos[1] : "run";
        string O(string k, string d) => opts.GetValueOrDefault(k, d);
        string out_dir = Path.GetFullPath(O("out", @"D:\SoftwareProjects\SpikeCage-coord\research\yardstick"));
        try
        {
            switch (what)
            {
                case "list":
                    foreach (var b in Bots.all()) Console.WriteLine($"  {b.name,-16} {(b.peeks ? "peeks" : "fair "),-6} {b.about}");
                    return 0;
                case "compare":
                    return write_table(out_dir);
                case "run":
                {
                    string set = O("set", "quick");
                    int seeds = int.Parse(O("seeds", (set == "full" ? FULL : QUICK).ToString()));
                    if (opts.ContainsKey("seeds")) set = $"seeds{seeds}";
                    long first = long.Parse(O("first", FIRST.ToString()));
                    long cap = long.Parse(O("cap", CAP.ToString()));
                    int threads = Math.Clamp(int.Parse(O("threads", "16")), 1, 64);
                    int t_runs = int.Parse(O("timing-runs", "40")), t_taps = int.Parse(O("timing-taps", "20"));
                    var human = opts.ContainsKey("human") ? load_humans(O("human", ""), cap) : null;
                    Directory.CreateDirectory(out_dir);
                    int rc = 0;
                    foreach (var bot in Bots.pick(O("bot", "")))
                        rc |= measure(bot, set, first, seeds, cap, threads, t_runs, t_taps, human, out_dir);
                    write_table(out_dir);
                    return rc;
                }
                case "humans":
                {
                    // Measures human run files on their own, as the "human" row.
                    long cap = long.Parse(O("cap", CAP.ToString()));
                    var human = load_humans(O("human", ""), cap);
                    if (human.Count == 0) return 1;
                    Directory.CreateDirectory(out_dir);
                    int t_runs = int.Parse(O("timing-runs", "40")), t_taps = int.Parse(O("timing-taps", "20"));
                    var timing = judge(human, t_runs, t_taps, int.Parse(O("threads", "16")));
                    var o = report("human", "human run files: " + O("human", ""), false, "human", 0, human.Count, cap, human, timing, null, 0);
                    save(o, out_dir);
                    write_table(out_dir);
                    return 0;
                }
            }
            Console.Error.WriteLine($"unknown yardstick mode '{what}': run, compare, list, humans");
            return 2;
        }
        catch (Exception e) when (e is ArgumentException or FileNotFoundException or InvalidDataException)
        {
            Console.Error.WriteLine(e.Message);
            return 2;
        }
    }

    static int measure(BotSpec bot, string set, long first, int seeds, long cap, int threads, int t_runs, int t_taps,
        List<Run> human, string out_dir)
    {
        var clock = Stopwatch.StartNew();
        var runs = new Run[seeds];
        int done = 0;
        Parallel.For(0, seeds, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            var input = Run.play(bot, first + 1 + i, cap);
            runs[i] = Run.analyze(input, cap);
            int n = Interlocked.Increment(ref done);
            if (n % Math.Max(1, seeds / 4) == 0 && clock.Elapsed.TotalSeconds > 30)
                Console.Error.WriteLine($"  {bot.name}: {n}/{seeds} runs, {clock.Elapsed.TotalSeconds:F0} s");
        });
        double play_s = clock.Elapsed.TotalSeconds;
        var timing = judge(runs, t_runs, t_taps, threads);
        var o = report(bot.name, bot.about, bot.peeks, set, first, seeds, cap, runs, timing, human, clock.Elapsed.TotalSeconds);
        o["play_seconds"] = Math.Round(play_s, 1);
        var s = o["strength"];
        string claimed = Stats.claimed_tier(bot.name);
        Console.WriteLine($"yardstick {bot.name} ({set}, {seeds} runs, cap {cap}): median {s["median"]}, p25 {s["p25"]}, " +
            $"p75 {s["p75"]}, p90 {s["p90"]}, rate median {s["rate_median"]} -> {s["tier_by_rate"]}" +
            (claimed != "" ? $" (claims {claimed})" : "") + $"  [{clock.Elapsed.TotalSeconds:F0} s]");
        save(o, out_dir);
        return 0;
    }

    static Timing.Result judge(IList<Run> runs, int t_runs, int t_taps, int threads)
    {
        var parts = new Timing.Result[Math.Min(t_runs, runs.Count)];
        Parallel.For(0, parts.Length, new ParallelOptions { MaxDegreeOfParallelism = threads },
            i => parts[i] = Timing.judge(runs[i].input, runs[i], t_taps));
        var all = new Timing.Result();
        foreach (var p in parts)
        {
            all.taps_judged += p.taps_judged;
            all.critical += p.critical;
            all.errors.AddRange(p.errors);
            all.widths.AddRange(p.widths);
        }
        return all;
    }

    static JsonObject report(string name, string about, bool peeks, string set, long first, int seeds, long cap,
        IList<Run> runs, Timing.Result timing, List<Run> human, double seconds)
    {
        var o = new JsonObject
        {
            ["yardstick"] = FORMAT,
            ["bot"] = name,
            ["about"] = about,
            ["peeks"] = peeks,
            ["claimed_tier"] = Stats.claimed_tier(name),
            ["set"] = set,
            ["first_seed"] = first + 1,
            ["seeds"] = seeds,
            ["cap"] = cap,
            ["gameplay_version"] = SimConfig.GAMEPLAY_VERSION,
            ["made"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture),
            ["seconds"] = Math.Round(seconds, 1),
            ["strength"] = Stats.strength(runs),
            ["human"] = Stats.human(runs, timing),
        };
        if (human != null && human.Count > 0) o["vs_human"] = Compare.against(runs, human);
        o["runs"] = new JsonArray(runs.Select(r => (JsonNode)new JsonObject
        {
            ["seed"] = r.input.seed, ["points"] = r.points, ["ticks"] = r.ticks, ["dead"] = r.dead,
            ["room"] = r.room, ["cause"] = r.cause, ["taps"] = r.taps_played,
        }).ToArray());
        return o;
    }

    static string file_name(string bot, string set) =>
        string.Concat($"{bot}_{set}".Select(c => char.IsLetterOrDigit(c) || c == '_' || c == '-' ? c : '-')) + ".json";

    static void save(JsonObject o, string out_dir)
    {
        string path = Path.Combine(out_dir, file_name((string)o["bot"], (string)o["set"]));
        File.WriteAllText(path, o.ToJsonString(PRETTY) + "\n");
        Console.WriteLine($"  wrote {path}");
    }

    /// Run files (meta/run_file.gd), a folder of them, or a Your runs file
    /// (user://runs.json): every object with "format": "flapjaw_run" counts.
    public static List<Run> load_humans(string path, long cap)
    {
        var files = Directory.Exists(path) ? Directory.GetFiles(path, "*.json", SearchOption.AllDirectories) : new[] { path };
        var inputs = new List<RunInput>();
        int old = 0;
        foreach (var f in files)
        {
            if (!File.Exists(f)) throw new FileNotFoundException($"{f} not found");
            void walk(JsonNode n)
            {
                if (n is JsonArray a) foreach (var x in a) walk(x);
                if (n is not JsonObject o) return;
                if ((string)o["format"] == "flapjaw_run")
                {
                    if ((long)o["gameplay_version"] != SimConfig.GAMEPLAY_VERSION) { old++; return; }
                    var taps = o["taps"].AsArray().Select(t => (long)t).ToArray();
                    inputs.Add(new RunInput((long)o["seed"], (long?)o["season"] ?? Seasons.NONE, taps, f));
                    return;
                }
                foreach (var kv in o) walk(kv.Value);
            }
            walk(JsonNode.Parse(File.ReadAllText(f)));
        }
        Console.WriteLine($"yardstick: {inputs.Count} human runs from {path}" +
            (old > 0 ? $" ({old} skipped: another gameplay version, they no longer replay)" : ""));
        return inputs.Select(r => Run.analyze(r, cap)).ToList();
    }

    // ---- the comparison table -------------------------------------------------

    static string f(JsonNode n, string fmt = "0.#")
    {
        if (n == null) return "-";
        if (n is JsonValue v && v.TryGetValue(out double d)) return d.ToString(fmt, CultureInfo.InvariantCulture);
        if (n is JsonValue b && b.TryGetValue(out bool x)) return x ? "yes" : "**no**";
        return n.ToString();
    }

    public static int write_table(string out_dir)
    {
        if (!Directory.Exists(out_dir)) return 0;
        var rows = new List<JsonObject>();
        foreach (var p in Directory.GetFiles(out_dir, "*.json"))
        {
            try
            {
                var o = JsonNode.Parse(File.ReadAllText(p)) as JsonObject;
                if (o != null && o["yardstick"] != null) rows.Add(o);
            }
            catch (JsonException) { }
        }
        rows = rows.OrderBy(o => (string)o["set"]).ThenBy(o => (double?)o["strength"]["rate_median"] ?? 1e9).ToList();
        var sb = new StringBuilder();
        sb.AppendLine("# Bot yardstick: comparison");
        sb.AppendLine();
        sb.AppendLine("Made by `tools/yardstick.ps1` (docs/YARDSTICK.md). Every bot plays the same seeds with the same tick cap;");
        sb.AppendLine("runs end at the first death (no revive). *Rate median* is ln 0.5 / ln(1 - h), h = deaths per point:");
        sb.AppendLine("scores are roughly exponential, so it is the steadier number for tiers. Tier edges are the geometric middles");
        sb.AppendLine("of the targets 30 / 60 / 120 / 250 / 500 (42, 85, 173, 354). *Peeks* bots read the future: a ceiling, not a player.");
        sb.AppendLine();
        sb.AppendLine("## Strength");
        sb.AppendLine();
        sb.AppendLine("| bot | set | peeks | runs | median | p25 | p75 | p90 | deaths/pt | rate median | tier (rate) | claims | fits | exp KS | capped | top killer | deadliest per visit |");
        sb.AppendLine("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|");
        foreach (var o in rows)
        {
            var s = o["strength"];
            string claim = (string)o["claimed_tier"] ?? "";
            string tier = (string)s["tier_by_rate"];
            string fits = claim == "" ? "" : tier == claim ? "yes" : "**no**";
            var k = s["killers"].AsArray().FirstOrDefault();
            var dv = s["deadliest_per_visit"].AsArray().FirstOrDefault();
            sb.AppendLine($"| {o["bot"]} | {o["set"]} | {((bool)o["peeks"] ? "yes" : "")} | {s["runs"]} | {f(s["median"])} | {f(s["p25"])} | " +
                $"{f(s["p75"])} | {f(s["p90"])} | {f(s["death_rate_per_point"], "0.0000")} | {f(s["rate_median"])} | {tier} | {claim} | {fits} | " +
                $"{f(s["exp_fit_ks"], "0.00")} | {s["capped"]} | " +
                (k == null ? "-" : $"{k["room"]} {f((double)k["share"] * 100, "0")}%") + " | " +
                (dv == null ? "-" : $"{dv["room"]} {f((double)dv["per_visit"] * 100, "0.0")}%") + " |");
        }
        sb.AppendLine();
        sb.AppendLine("## Human-likeness");
        sb.AppendLine();
        sb.AppendLine("Human reference until there are human runs: Isaksen et al. (FDG 2015): at most 7.7 taps/s (taps 8+ ticks apart),");
        sb.AppendLine("timing sigma 2.2-3.7 ticks around the ideal tap, reaction to a new obstacle ~17 ticks (rarely under 10).");
        sb.AppendLine("*Timing sd* is the spread of timing-critical taps around the middle of their survivable window (Timing.cs).");
        sb.AppendLine("*React* is the first tap after a new room or hazard (a proxy: a tap can be planned before the new thing shows).");
        sb.AppendLine();
        sb.AppendLine("| bot | set | taps/s | interval median | taps <8 ticks apart | timing sd | timing mean | critical taps | react (new) median | react <10 | react (bounce) median | height bands (top→bottom, %) | humanlike | classifier acc |");
        sb.AppendLine("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|");
        foreach (var o in rows)
        {
            var h = o["human"];
            var t = h["timing"];
            var bands = string.Join(" ", h["height_bands"].AsArray().Select(b => f((double)b * 100, "0")));
            var vs = o["vs_human"];
            string critical = t == null ? "-" : $"{t["critical"]}/{t["taps_judged"]}";
            sb.AppendLine($"| {o["bot"]} | {o["set"]} | {f(h["taps_per_s"]["median"], "0.00")} | {f(h["interval"]["median"])} | " +
                $"{f((double?)h["interval"]["under_8_ticks"] * 100, "0.0")}% | {f(t?["error_sd"], "0.00")} | {f(t?["error_mean"], "0.00")} | {critical} | " +
                $"{f(h["react_new"]["median"])} | {f((double?)h["react_new"]["under_10_ticks"] * 100, "0")}% | {f(h["react_bounce"]["median"])} | {bands} | " +
                $"{f(vs?["likeness"], "0.00")} | {f(vs?["classifier"]?["balanced_accuracy"], "0.00")} |");
        }
        sb.AppendLine();
        sb.AppendLine("No human runs of this game yet: *humanlike* and *classifier acc* stay empty until there are (docs/YARDSTICK.md).");
        string path = Path.Combine(out_dir, "comparison.md");
        File.WriteAllText(path, sb.ToString());
        Console.WriteLine($"yardstick: {rows.Count} run sets -> {path}");
        return 0;
    }
}
