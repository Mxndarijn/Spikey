using System.Text.Json;
using System.Text.Json.Nodes;

namespace FastSim.Diff;

/// fastsim difficulty score --in a.tsv[,b.tsv] [--out report]: one row per room and
/// variant (docs/ROOM_DIFFICULTY.md).
///
/// Skill (bots): an item-response fit over every bot's clears, P(clear) =
///   1 / (1 + e^-(skill_bot - b_room)). The skill a room needs for 90% clears is
///   b_room + ln 9, read on the tier scale: 1 beginner, 2 normal, 3 good, 4 expert,
///   5 beast (between tiers: linear). The score is 20 x that (20 beginner ... 100 beast).
/// Analytic: a ridge fit of that skill on the exact-knowledge and reaction measures
///   (tube, react), leave-one-out; it scores rooms the bots didn't play too.
/// Score: the mean of the two (either one alone when the other is missing).
public static class Score
{
    public static readonly string[] TIERS = { "beginner", "normal", "good", "expert", "beast" };

    public sealed class Room
    {
        public string label, id, variant = "", group;
        public long from;
        public bool boss;
        // tube (per entry lists)
        public List<double[]> tube = new();
        // react: per entry [shown, (noway, died, fail|way0) x 4]
        public List<long[]> react = new();
        public List<string> react_detail = new();
        // bots: bot -> (clears, plays)
        public Dictionary<string, (int k, int n)> bots = new();
        public Dictionary<string, Dictionary<string, int>> causes = new();
        public int errors;
        public JsonObject o = new();
        public double b = double.NaN, skill = double.NaN, analytic = double.NaN, score = double.NaN;
        public Dictionary<string, double> f = new();
    }

    public static int run(Dictionary<string, string> opts)
    {
        var rooms = load(opts.GetValueOrDefault("in", "difficulty.tsv").Split(','));
        string outp = opts.GetValueOrDefault("out", "difficulty_report");
        var list = rooms.Values.ToList();
        foreach (var r in list) features(r);
        var theta = fit_irt(list);
        foreach (var r in list) if (!double.IsNaN(r.b)) r.skill = tier_needed(r.b + Math.Log(9), theta);
        var (names, w, loo, corr) = fit_analytic(list);
        foreach (var r in list)
        {
            var parts = new[] { r.skill * 20, r.analytic * 20 }.Where(x => !double.IsNaN(x)).ToList();
            r.score = parts.Count == 0 ? double.NaN : Math.Clamp(parts.Average(), 0, 130);
        }
        var bands = Bands.suggest(list);
        var report = build(list, theta, names, w, loo, corr, bands);
        File.WriteAllText(outp + ".json", report.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        File.WriteAllText(outp + ".md", markdown(list, theta, corr, loo, bands));
        Console.Write(File.ReadAllText(outp + ".md").Split("\n## Rooms")[0]);
        Console.WriteLine($"wrote {outp}.md and {outp}.json");
        return 0;
    }

    /// The lines of a TSV that a measure run may still be writing.
    public static IEnumerable<string> lines(string path)
    {
        using var r = new StreamReader(new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite));
        string l;
        while ((l = r.ReadLine()) != null) yield return l;
    }

    static double D(string s) => double.Parse(s, DiffMain.INV);

    static Dictionary<string, Room> load(string[] files)
    {
        var targets = Cases.all().ToDictionary(t => t.label);
        var rooms = new Dictionary<string, Room>();
        foreach (var t in targets.Values)
            rooms[t.label] = new Room
            {
                label = t.label, id = t.def.id, variant = t.variant, group = t.def.season != Seasons.NONE ? "seasonal" : t.def.group,
                from = t.def.from_score, boss = t.boss,
            };
        foreach (var file in files)
            foreach (var line in lines(file))
            {
                var f = line.Split('\t');
                if (f.Length < 5 || !rooms.TryGetValue(f[1], out var r)) continue;
                if (f[4] == "error") { r.errors++; continue; }
                switch (f[0])
                {
                    case "tube": r.tube.Add(f.Skip(4).Take(17).Select(D).ToArray()); break;
                    case "react":
                        r.react.Add(f.Skip(4).Take(13).Select(long.Parse).ToArray());
                        r.react_detail.Add(f[17]);
                        break;
                    case "bots":
                    {
                        var (k, n) = r.bots.GetValueOrDefault(f[3]);
                        r.bots[f[3]] = (k + int.Parse(f[4]), n + 1);
                        if (f[4] == "0")
                        {
                            if (!r.causes.ContainsKey(f[3])) r.causes[f[3]] = new();
                            r.causes[f[3]][f[6]] = r.causes[f[3]].GetValueOrDefault(f[6]) + 1;
                        }
                        break;
                    }
                }
            }
        return rooms;
    }

    static double median(IEnumerable<double> xs)
    {
        var s = xs.OrderBy(x => x).ToList();
        if (s.Count == 0) return double.NaN;
        return s.Count % 2 == 1 ? s[s.Count / 2] : (s[s.Count / 2 - 1] + s[s.Count / 2]) / 2;
    }

    // tube columns (after the 4 key columns)
    const int WAY = 0, TICKS = 1, FIRST_EXIT = 2, PEAK = 3, BAND_MIN = 4, BAND_P10 = 5, BAND_MED = 6, TIGHT_S = 7,
        BITS = 8, BITS_S = 9, WIN = 10, WIN_MED = 11, TAPS = 12, TIGHT = 13, LINE_S = 14, CHOICE_S = 15, VIABLE = 16;

    /// The per-room measures (medians over the entries), in Room.f.
    static void features(Room r)
    {
        double points = r.boss ? SimConfig.BOSS_POINTS : SimConfig.POINTS_PER_ROOM;
        if (r.tube.Count > 0)
        {
            var ok = r.tube.Where(x => x[WAY] > 0).ToList();
            r.f["entries"] = r.tube.Count;
            r.f["no_way_entries"] = r.tube.Count - ok.Count;
            if (ok.Count > 0)
            {
                r.f["band_min"] = median(ok.Select(x => x[BAND_MIN]));
                r.f["band_worst"] = ok.Min(x => x[BAND_MIN]);
                r.f["band_p10"] = median(ok.Select(x => x[BAND_P10]));
                r.f["band_med"] = median(ok.Select(x => x[BAND_MED]));
                r.f["tight_s"] = median(ok.Select(x => x[TIGHT_S]));
                r.f["bits_per_point"] = median(ok.Select(x => x[BITS] / points));
                r.f["window"] = median(ok.Select(x => x[WIN]));
                r.f["window_worst"] = ok.Min(x => x[WIN]);
                r.f["window_med"] = median(ok.Select(x => x[WIN_MED]));
                r.f["tight_taps_per_s"] = median(ok.Select(x => x[LINE_S] > 0 ? x[TIGHT] / x[LINE_S] : 0));
                r.f["taps_per_s"] = median(ok.Select(x => x[LINE_S] > 0 ? x[TAPS] / x[LINE_S] : 0));
                r.f["choice_frac"] = median(ok.Select(x => x[LINE_S] > 0 ? x[CHOICE_S] / x[LINE_S] : 0));
                r.f["viable_frac"] = median(ok.Select(x => x[VIABLE]));
                r.f["line_s"] = median(ok.Select(x => x[LINE_S]));
            }
        }
        if (r.react.Count > 0)
        {
            double shown = r.react.Sum(x => x[0]);
            double way0 = r.react.Sum(x => x[0] - x[1] - x[2]);
            r.f["shown"] = shown;
            r.f["shown_per_s"] = shown / Math.Max(1, r.react.Count) / Math.Max(1, r.f.GetValueOrDefault("line_s", 16));
            r.f["doomed0"] = shown == 0 ? 0 : r.react.Sum(x => x[1] + x[2]) / shown;
            for (int j = 1; j < ReactSweep.REACTS.Length; j++)
            {
                double fail = r.react.Sum(x => x[3 + 3 * j]);
                r.f[$"fail{ReactSweep.REACTS[j]}"] = way0 == 0 ? 0 : fail / way0;
                r.f[$"fails{ReactSweep.REACTS[j]}"] = fail;
            }
            r.f["way0"] = way0;
        }
        foreach (var (bot, (k, n)) in r.bots) r.f["clear_" + bot] = n == 0 ? double.NaN : k / (double)n;
    }

    /// Item-response (Rasch) fit: b per room, skill per bot. Every room's b has a
    /// N(0, 2.5^2) prior, so a room every bot clears still gets a finite b.
    static Dictionary<string, double> fit_irt(List<Room> rooms)
    {
        var bots = rooms.SelectMany(r => r.bots.Keys).Distinct().ToList();
        var th = bots.ToDictionary(b => b, b => 0.0);
        var played = rooms.Where(r => r.bots.Count > 0).ToList();
        if (played.Count == 0) return th;
        foreach (var r in played) r.b = 0;
        const double PRIOR = 1 / (2.5 * 2.5);
        for (int it = 0; it < 300; it++)
        {
            foreach (var r in played)
            {
                double g = -PRIOR * r.b, h = -PRIOR;
                foreach (var (bot, (k, n)) in r.bots)
                {
                    double p = 1 / (1 + Math.Exp(-(th[bot] - r.b)));
                    g -= k - n * p;
                    h -= n * p * (1 - p);
                }
                r.b -= g / h;
            }
            foreach (var bot in bots)
            {
                double g = 0, h = -1e-3;
                foreach (var r in played)
                    if (r.bots.TryGetValue(bot, out var kn))
                    {
                        double p = 1 / (1 + Math.Exp(-(th[bot] - r.b)));
                        g += kn.k - kn.n * p;
                        h -= kn.n * p * (1 - p);
                    }
                th[bot] -= g / h;
            }
        }
        return th;
    }

    /// Skill `x` on the tier scale (1 beginner .. 5 beast), linear between the
    /// fitted tier skills and past the ends.
    public static double tier_needed(double x, Dictionary<string, double> th)
    {
        var pts = new List<double>();
        foreach (var t in TIERS)
            if (th.TryGetValue(t, out var v)) pts.Add(pts.Count == 0 ? v : Math.Max(v, pts[^1] + 1e-3));
        if (pts.Count < 2) return double.NaN;
        int i = 0;
        while (i < pts.Count - 2 && x > pts[i + 1]) i++;
        return 1 + i + (x - pts[i]) / (pts[i + 1] - pts[i]);
    }

    /// The analytic measures used to predict the skill a room needs.
    public static readonly string[] FEATURES =
    {
        "band_p10", "band_worst", "tight_s", "bits_per_point", "window", "window_worst", "tight_taps_per_s",
        "choice_frac", "viable_frac", "doomed0", "fail20", "fail40", "fail60",
    };

    static double tr(string name, double v) => name switch
    {
        "band_p10" or "band_worst" or "bits_per_point" or "window" or "window_worst" => Math.Log(Math.Max(1, v)),
        _ => v,
    };

    /// Ridge regression of the bot skill on the analytic measures (standardised);
    /// leave-one-out correlation; Spearman of every single measure with the skill.
    static (string[] names, double[] w, double loo, Dictionary<string, double> corr) fit_analytic(List<Room> rooms)
    {
        var names = FEATURES;
        var have = rooms.Where(r => names.All(n => r.f.ContainsKey(n))).ToList();
        var train = have.Where(r => !double.IsNaN(r.skill)).ToList();
        var corr = new Dictionary<string, double>();
        foreach (var n in names.Concat(new[] { "band_min", "band_med", "taps_per_s", "no_way_entries" }))
        {
            var pr = train.Where(r => r.f.ContainsKey(n)).ToList();
            if (pr.Count > 3) corr[n] = spearman(pr.Select(r => r.f[n]).ToList(), pr.Select(r => r.skill).ToList());
        }
        if (train.Count < names.Length + 3) return (names, null, double.NaN, corr);
        var mu = names.Select(n => train.Average(r => tr(n, r.f[n]))).ToArray();
        var sd = names.Select((n, j) => Math.Sqrt(train.Average(r => Math.Pow(tr(n, r.f[n]) - mu[j], 2))) + 1e-9).ToArray();
        double[] X(Room r) => names.Select((n, j) => (tr(n, r.f[n]) - mu[j]) / sd[j]).ToArray();
        double[] solve(List<Room> rs)
        {
            int p = names.Length + 1;
            var A = new double[p, p];
            var y = new double[p];
            foreach (var r in rs)
            {
                var x = X(r).Append(1).ToArray();
                for (int a = 0; a < p; a++)
                {
                    y[a] += x[a] * r.skill;
                    for (int c = 0; c < p; c++) A[a, c] += x[a] * x[c];
                }
            }
            for (int a = 0; a < p - 1; a++) A[a, a] += 3.0; // ridge
            return gauss(A, y);
        }
        double predict(double[] w, Room r) => X(r).Append(1).Zip(w, (a, c) => a * c).Sum();
        var loo_pred = train.Select(r => predict(solve(train.Where(o => o != r).ToList()), r)).ToList();
        double loo = pearson(loo_pred, train.Select(r => r.skill).ToList());
        var wall = solve(train);
        foreach (var r in have) r.analytic = predict(wall, r);
        return (names, wall, loo, corr);
    }

    static double[] gauss(double[,] A, double[] y)
    {
        int n = y.Length;
        var M = (double[,])A.Clone();
        var b = (double[])y.Clone();
        for (int c = 0; c < n; c++)
        {
            int piv = c;
            for (int r = c + 1; r < n; r++) if (Math.Abs(M[r, c]) > Math.Abs(M[piv, c])) piv = r;
            for (int k = 0; k < n; k++) (M[c, k], M[piv, k]) = (M[piv, k], M[c, k]);
            (b[c], b[piv]) = (b[piv], b[c]);
            for (int r = 0; r < n; r++)
            {
                if (r == c) continue;
                double f = M[r, c] / M[c, c];
                for (int k = 0; k < n; k++) M[r, k] -= f * M[c, k];
                b[r] -= f * b[c];
            }
        }
        return Enumerable.Range(0, n).Select(i => b[i] / M[i, i]).ToArray();
    }

    public static double pearson(List<double> a, List<double> b)
    {
        double ma = a.Average(), mb = b.Average();
        double sab = a.Zip(b, (x, y) => (x - ma) * (y - mb)).Sum();
        double sa = Math.Sqrt(a.Sum(x => (x - ma) * (x - ma))), sb = Math.Sqrt(b.Sum(y => (y - mb) * (y - mb)));
        return sa * sb == 0 ? 0 : sab / (sa * sb);
    }

    static List<double> ranks(List<double> v)
    {
        var idx = Enumerable.Range(0, v.Count).OrderBy(i => v[i]).ToList();
        var r = new double[v.Count];
        for (int i = 0; i < idx.Count;)
        {
            int j = i;
            while (j + 1 < idx.Count && v[idx[j + 1]] == v[idx[i]]) j++;
            for (int k = i; k <= j; k++) r[idx[k]] = (i + j) / 2.0;
            i = j + 1;
        }
        return r.ToList();
    }

    public static double spearman(List<double> a, List<double> b) => pearson(ranks(a), ranks(b));

    public static string flags(Room r, Bands.Result bands)
    {
        var f = new List<string>();
        if (r.f.GetValueOrDefault("no_way_entries") > 0) f.Add("no-way");
        // Reaction.MAX_EXTRA_PCT: at most 2% of cases may die that a quick reaction survives.
        if (r.f.GetValueOrDefault("fails20") >= 2 && r.f.GetValueOrDefault("fail20") * 100 > Reaction.MAX_EXTRA_PCT) f.Add("unfair-react");
        else if (r.f.GetValueOrDefault("fail40") > bands.fail40_limit) f.Add("slow-react");
        string sug = bands.category(r);
        if (sug != null && sug != r.group && Bands.ORDER.Contains(r.group))
        {
            int a = Array.IndexOf(Bands.ORDER, r.group), b = Array.IndexOf(Bands.ORDER, sug);
            if (b > a) f.Add("too-hard");
            if (b < a) f.Add("too-easy");
        }
        if ((r.group == "bonus" || r.group == "seasonal") && r.score > bands.hi) f.Add("too-hard");
        if (r.group == "boss" && r.score < bands.lo) f.Add("too-easy");
        return string.Join(" ", f.Distinct());
    }

    static JsonNode num(double x) => double.IsNaN(x) || double.IsInfinity(x) ? null : JsonValue.Create(Math.Round(x, 4));

    static JsonObject build(List<Room> rooms, Dictionary<string, double> theta, string[] names, double[] w, double loo,
        Dictionary<string, double> corr, Bands.Result bands)
    {
        var arr = new JsonArray();
        foreach (var r in rooms.OrderByDescending(r => double.IsNaN(r.score) ? -1 : r.score))
        {
            var o = new JsonObject
            {
                ["label"] = r.label, ["room"] = r.id, ["variant"] = r.variant, ["group"] = r.group, ["from"] = r.from,
                ["score"] = num(r.score), ["skill"] = num(r.skill * 20), ["analytic"] = num(r.analytic * 20), ["b"] = num(r.b),
                ["suggested"] = bands.category(r), ["flags"] = flags(r, bands), ["errors"] = r.errors,
            };
            var sub = Sub.of(r, rooms);
            o["sub"] = new JsonObject(sub.Select(kv => KeyValuePair.Create(kv.Key, num(kv.Value))));
            o["f"] = new JsonObject(r.f.Select(kv => KeyValuePair.Create(kv.Key, num(kv.Value))));
            o["bots"] = new JsonObject(r.bots.Select(kv => KeyValuePair.Create(kv.Key, (JsonNode)new JsonArray(kv.Value.k, kv.Value.n))));
            o["react_fails"] = new JsonArray(r.react_detail.Where(d => d != "-").Take(12).Select(d => (JsonNode)d).ToArray());
            arr.Add(o);
        }
        return new JsonObject
        {
            ["theta"] = new JsonObject(theta.Select(kv => KeyValuePair.Create(kv.Key, num(kv.Value)))),
            ["weights"] = w == null ? null : new JsonObject(names.Select((n, j) => KeyValuePair.Create(n, num(w[j])))),
            ["loo_r"] = num(loo),
            ["spearman"] = new JsonObject(corr.Select(kv => KeyValuePair.Create(kv.Key, num(kv.Value)))),
            ["bands"] = new JsonObject { ["starter_max"] = num(bands.lo), ["mid_max"] = num(bands.hi), ["fail40_limit"] = num(bands.fail40_limit), ["agree"] = num(bands.agree),
                ["fit_starter_max"] = num(bands.fit_lo), ["fit_mid_max"] = num(bands.fit_hi), ["fit_agree"] = num(bands.fit_agree) },
            ["group_median"] = new JsonObject(rooms.Where(r => !double.IsNaN(r.score)).GroupBy(r => r.group)
                .Select(g => KeyValuePair.Create(g.Key, num(median(g.Select(r => r.score)))))),
            ["rooms"] = arr,
        };
    }

    static string P(double x, string fmt = "F0") => double.IsNaN(x) ? "-" : x.ToString(fmt, DiffMain.INV);

    static string markdown(List<Room> rooms, Dictionary<string, double> theta, Dictionary<string, double> corr, double loo, Bands.Result bands)
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine("# Room difficulty");
        sb.AppendLine();
        sb.AppendLine("Bot skills (item-response fit): " + string.Join(", ", theta.OrderBy(kv => kv.Value).Select(kv => $"{kv.Key} {kv.Value:F2}")));
        sb.AppendLine($"Analytic fit, leave-one-out r with the bot skill: {P(loo, "F2")}");
        sb.AppendLine("Spearman of each measure with the bot skill:");
        foreach (var kv in corr.OrderByDescending(kv => Math.Abs(kv.Value))) sb.AppendLine($"  {kv.Key,-18} {kv.Value,6:F2}");
        sb.AppendLine($"Bands: starter <= {bands.lo:F0} < mid <= {bands.hi:F0} < late; agreement with today's groups {bands.agree:P0} " +
            $"(best-fitting cuts {bands.fit_lo:F0} / {bands.fit_hi:F0} would agree {bands.fit_agree:P0})");
        sb.AppendLine("Median score per group: " + string.Join(", ", rooms.Where(r => !double.IsNaN(r.score)).GroupBy(r => r.group)
            .Select(g => $"{g.Key} {median(g.Select(r => r.score)):F0}")));
        sb.AppendLine();
        sb.AppendLine("## Rooms");
        sb.AppendLine();
        sb.AppendLine("| # | room | group | from | score | skill | analytic | space | precision | reaction | busy | beginner | normal | good | expert | beast | honest | suggested | flags |");
        sb.AppendLine("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|");
        int i = 0;
        foreach (var r in rooms.OrderByDescending(r => double.IsNaN(r.score) ? -1 : r.score))
        {
            var sub = Sub.of(r, rooms);
            string c(string bot) => r.bots.TryGetValue(bot, out var kn) ? $"{100.0 * kn.k / kn.n:F0}%" : "-";
            sb.AppendLine($"| {++i} | {r.label} | {r.group} | {r.from} | {P(r.score)} | {P(r.skill * 20)} | {P(r.analytic * 20)} | " +
                $"{P(sub.GetValueOrDefault("space", double.NaN))} | {P(sub.GetValueOrDefault("precision", double.NaN))} | " +
                $"{P(sub.GetValueOrDefault("reaction", double.NaN))} | {P(sub.GetValueOrDefault("busy", double.NaN))} | " +
                $"{c("beginner")} | {c("normal")} | {c("good")} | {c("expert")} | {c("beast")} | {c("honest")} | {bands.category(r) ?? "-"} | {flags(r, bands)} |");
        }
        return sb.ToString();
    }
}

/// Sub-scores 0..100 (100 = hardest of all rooms scored), each from one family
/// of measures, as a percentile rank among the rooms.
public static class Sub
{
    static readonly Dictionary<string, (string feature, int sign)[]> PARTS = new()
    {
        ["space"] = new[] { ("band_p10", -1), ("band_worst", -1), ("tight_s", 1) },
        ["precision"] = new[] { ("window", -1), ("window_worst", -1), ("tight_taps_per_s", 1) },
        ["reaction"] = new[] { ("fail20", 1), ("fail40", 1), ("fail60", 1), ("doomed0", 1) },
        ["busy"] = new[] { ("shown_per_s", 1), ("choice_frac", 1), ("bits_per_point", -1) },
    };

    static readonly Dictionary<List<Score.Room>, Dictionary<string, Dictionary<Score.Room, double>>> _cache = new();

    public static Dictionary<string, double> of(Score.Room r, List<Score.Room> all)
    {
        if (!_cache.TryGetValue(all, out var c))
        {
            c = new();
            foreach (var (name, parts) in PARTS)
            {
                var have = all.Where(x => parts.All(p => x.f.ContainsKey(p.feature))).ToList();
                var sum = have.ToDictionary(x => x, _ => 0.0);
                foreach (var (feat, sign) in parts)
                {
                    var order = have.OrderBy(x => sign * x.f[feat]).ToList();
                    for (int i = 0; i < order.Count; i++) sum[order[i]] += order.Count > 1 ? i / (double)(order.Count - 1) : 0.5;
                }
                c[name] = sum.ToDictionary(kv => kv.Key, kv => 100 * kv.Value / parts.Length);
            }
            _cache[all] = c;
        }
        return c.Where(kv => kv.Value.ContainsKey(r)).ToDictionary(kv => kv.Key, kv => kv.Value[r]);
    }
}

/// Category bands on the tier scale: starter up to 40 (a normal player clears it 9
/// times in 10), mid up to 60 (a good player), late above. `agree` is the share of
/// today's starter, mid and late rooms already in their band; `fit_lo`/`fit_hi` the
/// two cut points that would agree best (for the report only: when today's late rooms
/// are no harder than the mid ones, that fit is degenerate). Bonus, seasonal and boss
/// rooms are placed by the same bands but keep their group.
public static class Bands
{
    public static readonly string[] ORDER = { "starter", "mid", "late" };

    public sealed class Result
    {
        public double lo, hi, agree, fail40_limit, fit_lo, fit_hi, fit_agree;
        public string category(Score.Room r)
        {
            if (double.IsNaN(r.score)) return null;
            return r.score <= lo ? "starter" : r.score <= hi ? "mid" : "late";
        }
    }

    public static Result suggest(List<Score.Room> rooms)
    {
        var rs = rooms.Where(r => !double.IsNaN(r.score) && ORDER.Contains(r.group)).ToList();
        var res = new Result { lo = 40, hi = 60 };
        // The reaction limit: twice the 90th percentile of the starter rooms' fail rate at 40 ticks.
        var st = rooms.Where(r => r.group == "starter" && r.f.ContainsKey("fail40")).Select(r => r.f["fail40"]).OrderBy(x => x).ToList();
        res.fail40_limit = st.Count == 0 ? 0.05 : Math.Max(0.02, 2 * st[(int)(0.9 * (st.Count - 1))]);
        if (rs.Count == 0) return res;
        string band(double x, double lo, double hi) => x <= lo ? "starter" : x <= hi ? "mid" : "late";
        var cuts = rs.Select(r => r.score).Distinct().OrderBy(x => x).ToList();
        int best = -1;
        foreach (var lo in cuts)
            foreach (var hi in cuts.Where(h => h > lo))
            {
                int ok = rs.Count(r => band(r.score, lo, hi) == r.group);
                if (ok > best) { best = ok; res.fit_lo = lo; res.fit_hi = hi; }
            }
        res.fit_agree = best / (double)rs.Count;
        best = rs.Count(r => band(r.score, res.lo, res.hi) == r.group);
        res.agree = best / (double)rs.Count;
        return res;
    }
}
