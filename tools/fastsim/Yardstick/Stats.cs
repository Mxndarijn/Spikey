using System.Text.Json.Nodes;

namespace FastSim.Yard;

/// The numbers of one run set: strength, tier fit and how human it plays.
public static class Stats
{
    /// The tier targets (medians); beast is 500 or more.
    public static readonly (string name, double target)[] TIERS =
        { ("beginner", 30), ("normal", 60), ("good", 120), ("expert", 250), ("beast", 500) };
    /// Inter-tap interval histogram bins, in ticks (upper bounds; the last is open).
    public static readonly int[] INTERVAL_BINS = { 4, 7, 10, 13, 16, 20, 25, 32, 40, 50, 64, int.MaxValue };
    /// Reaction histogram bins, in ticks.
    public static readonly int[] REACT_BINS = { 3, 6, 9, 12, 15, 18, 21, 25, 30, 40, Run.REACT_WINDOW };
    /// Humans: at most 7.7 taps a second (Isaksen 2015), so taps are 8+ ticks apart.
    public const int HUMAN_MIN_INTERVAL = 8;
    /// Humans: timing error sigma 35.9-61.1 ms around the ideal tap.
    public const double HUMAN_SIGMA_LO = 2.2, HUMAN_SIGMA_HI = 3.7;
    /// Humans: reaction to a new obstacle 288 ms on average; under ~170 ms is rare.
    public const double HUMAN_REACT_MEAN = 17, HUMAN_REACT_FAST = 10;

    public static double pct(IEnumerable<double> xs, double p)
    {
        var s = xs.OrderBy(x => x).ToArray();
        if (s.Length == 0) return double.NaN;
        double at = p * (s.Length - 1);
        int lo = (int)Math.Floor(at), hi = (int)Math.Ceiling(at);
        return s[lo] + (s[hi] - s[lo]) * (at - lo);
    }

    static double sd(IList<double> xs)
    {
        if (xs.Count < 2) return double.NaN;
        double m = xs.Average();
        return Math.Sqrt(xs.Sum(x => (x - m) * (x - m)) / (xs.Count - 1));
    }

    public static double[] hist(IEnumerable<int> xs, int[] bins)
    {
        var h = new double[bins.Length];
        int n = 0;
        foreach (int x in xs)
        {
            int i = 0;
            while (i < bins.Length - 1 && x > bins[i]) i++;
            h[i]++;
            n++;
        }
        if (n > 0) for (int i = 0; i < h.Length; i++) h[i] /= n;
        return h;
    }

    public static double[] band_shares(IEnumerable<Run> runs)
    {
        var b = new double[Run.BANDS];
        foreach (var r in runs) for (int i = 0; i < Run.BANDS; i++) b[i] += r.bands[i];
        double total = b.Sum();
        if (total > 0) for (int i = 0; i < b.Length; i++) b[i] /= total;
        return b;
    }

    /// Per-point death chance h (geometric, capped runs count as survived
    /// points), and the median it implies: ln 0.5 / ln(1 - h).
    public static (double h, double median) death_rate(IList<Run> runs)
    {
        long deaths = runs.Count(r => r.dead);
        long exposure = runs.Sum(r => r.points) + deaths;
        if (deaths == 0 || exposure == 0) return (0, double.PositiveInfinity);
        double h = (double)deaths / exposure;
        return (h, h >= 1 ? 0 : Math.Log(0.5) / Math.Log(1 - h));
    }

    /// Kolmogorov-Smirnov distance between the scores and the geometric fit.
    /// Small (under ~0.1) means "dies at a steady rate", as human populations do.
    public static double exp_fit(IList<Run> runs, double h)
    {
        if (h <= 0) return double.NaN;
        var pts = runs.Select(r => r.points).OrderBy(x => x).ToArray();
        double d = 0;
        for (int i = 0; i < pts.Length; i++)
        {
            double model = 1 - Math.Pow(1 - h, pts[i] + 1);
            double below = (double)i / pts.Length, upto = (double)(i + 1) / pts.Length;
            d = Math.Max(d, Math.Max(Math.Abs(upto - model), Math.Abs(model - below)));
        }
        return d;
    }

    /// The tier a median lands in: the nearest target on a log scale
    /// (edges at the geometric middles: 42, 85, 173, 354).
    public static string tier_of(double median)
    {
        if (double.IsNaN(median)) return "-";
        if (median < TIERS[0].target / Math.Sqrt(2)) return "below beginner";
        for (int i = 0; i < TIERS.Length - 1; i++)
            if (median < Math.Sqrt(TIERS[i].target * TIERS[i + 1].target)) return TIERS[i].name;
        return "beast";
    }

    /// The tier a bot's name claims ("rl:good" -> good), or "".
    public static string claimed_tier(string bot)
    {
        string last = bot[(bot.LastIndexOf(':') + 1)..];
        return TIERS.Any(t => t.name == last) ? last : "";
    }

    /// Score bands for deaths per 100 points (bot-review.md): the rate rises
    /// steeply through the first rooms, then levels off.
    public static readonly long[] SCORE_BANDS = { 0, 10, 20, 40, 80, 160, 320 };

    /// Deaths per 100 points scored inside each band: a run that ends at p
    /// spent min(p, hi) - lo points in a band it reached, and died in the
    /// band holding p. Capped runs count their points and no death.
    public static JsonArray band_rates(IList<Run> runs)
    {
        var out_ = new JsonArray();
        for (int i = 0; i < SCORE_BANDS.Length; i++)
        {
            long lo = SCORE_BANDS[i], hi = i + 1 < SCORE_BANDS.Length ? SCORE_BANDS[i + 1] : long.MaxValue;
            long pts = runs.Where(r => r.points > lo).Sum(r => Math.Min(r.points, hi) - lo);
            int deaths = runs.Count(r => r.dead && r.points >= lo && r.points < hi);
            int reached = runs.Count(r => r.points >= lo);
            out_.Add(new JsonObject
            {
                ["band"] = hi == long.MaxValue ? $"{lo}+" : $"{lo}..{hi}",
                ["reached"] = reached,
                ["points"] = pts,
                ["deaths"] = deaths,
                ["per_100"] = pts == 0 ? null : Math.Round(100.0 * deaths / pts, 3),
            });
        }
        return out_;
    }

    public static JsonObject strength(IList<Run> runs)
    {
        var pts = runs.Select(r => (double)r.points).ToList();
        var (h, exp_median) = death_rate(runs);
        int deaths = runs.Count(r => r.dead);
        var visits = new Dictionary<string, long>();
        foreach (var r in runs)
            foreach (var kv in r.visits) visits[kv.Key] = visits.GetValueOrDefault(kv.Key) + kv.Value;
        var killers = new JsonArray();
        foreach (var g in runs.Where(r => r.dead).GroupBy(r => r.room).OrderByDescending(g => g.Count()).Take(8))
        {
            long v = Math.Max(1, visits.GetValueOrDefault(g.Key));
            killers.Add(new JsonObject
            {
                ["room"] = g.Key,
                ["deaths"] = g.Count(),
                ["share"] = Math.Round((double)g.Count() / Math.Max(1, deaths), 4),
                ["visits"] = v,
                ["per_visit"] = Math.Round((double)g.Count() / v, 4),
            });
        }
        // The rooms most likely to kill per visit (seen 20+ times).
        var deadly = new JsonArray();
        var dead_in = runs.Where(r => r.dead).GroupBy(r => r.room).ToDictionary(g => g.Key, g => g.Count());
        foreach (var kv in visits.Where(kv => kv.Value >= 20).OrderByDescending(kv => (double)dead_in.GetValueOrDefault(kv.Key) / kv.Value).Take(8))
            deadly.Add(new JsonObject
            {
                ["room"] = kv.Key,
                ["per_visit"] = Math.Round((double)dead_in.GetValueOrDefault(kv.Key) / kv.Value, 4),
                ["visits"] = kv.Value,
            });
        var causes = new JsonObject();
        foreach (var g in runs.Where(r => r.dead).GroupBy(r => r.cause).OrderByDescending(g => g.Count()))
            causes[g.Key.ToLowerInvariant()] = Math.Round((double)g.Count() / Math.Max(1, deaths), 4);
        double median = pct(pts, 0.5);
        return new JsonObject
        {
            ["runs"] = runs.Count,
            ["median"] = num(median, 1),
            ["p25"] = num(pct(pts, 0.25), 1),
            ["p75"] = num(pct(pts, 0.75), 1),
            ["p90"] = num(pct(pts, 0.9), 1),
            ["mean"] = Math.Round(pts.Count == 0 ? 0 : pts.Average(), 2),
            ["deaths"] = deaths,
            ["capped"] = runs.Count - deaths,
            ["death_rate_per_point"] = Math.Round(h, 6),
            ["rate_median"] = num(exp_median, 1),
            ["tier_by_median"] = tier_of(median),
            ["tier_by_rate"] = double.IsInfinity(exp_median) ? "beast" : tier_of(exp_median),
            ["exp_fit_ks"] = num(exp_fit(runs, h), 4),
            ["deaths_per_100_by_band"] = band_rates(runs),
            ["mean_ticks"] = Math.Round(runs.Count == 0 ? 0 : runs.Average(r => (double)r.ticks), 0),
            ["killers"] = killers,
            ["deadliest_per_visit"] = deadly,
            ["causes"] = causes,
        };
    }

    static JsonArray arr(IEnumerable<double> xs, int digits = 4) =>
        new(xs.Select(x => (JsonNode)Math.Round(x, digits)).ToArray());

    static JsonArray arr(IEnumerable<int> xs) => new(xs.Select(x => (JsonNode)(x == int.MaxValue ? -1 : x)).ToArray());

    static JsonNode num(double x, int digits = 3) => double.IsNaN(x) || double.IsInfinity(x) ? null : Math.Round(x, digits);

    /// How the runs play, compared with what is known about humans.
    public static JsonObject human(IList<Run> runs, Timing.Result timing)
    {
        var tps = runs.Where(r => r.taps_played > 1).Select(r => r.taps_per_s).ToList();
        var ints = runs.SelectMany(r => r.intervals).ToList();
        var rb = runs.SelectMany(r => r.react_bounce).Select(x => (double)x).ToList();
        var rn = runs.SelectMany(r => r.react_new).Select(x => (double)x).ToList();
        double under = ints.Count == 0 ? double.NaN : (double)ints.Count(i => i < HUMAN_MIN_INTERVAL) / ints.Count;
        double err_sd = timing == null ? double.NaN : sd(timing.errors);
        double react = pct(rn, 0.5);
        long held = runs.Sum(r => (long)r.taps_held), played = runs.Sum(r => (long)r.taps_played);
        var o = new JsonObject
        {
            ["taps_ignored_in_portal_wait"] = num(held + played == 0 ? double.NaN : (double)held / (held + played), 4),
            ["taps_per_s"] = new JsonObject { ["median"] = num(pct(tps, 0.5)), ["p10"] = num(pct(tps, 0.1)), ["p90"] = num(pct(tps, 0.9)) },
            ["interval"] = new JsonObject
            {
                ["median"] = num(pct(ints.Select(x => (double)x), 0.5)),
                ["p10"] = num(pct(ints.Select(x => (double)x), 0.1)),
                ["under_8_ticks"] = num(under, 4),
                ["bins"] = arr(INTERVAL_BINS),
                ["hist"] = arr(hist(ints, INTERVAL_BINS)),
            },
            ["height_bands"] = arr(band_shares(runs)),
            ["bottom_quarter"] = num(band_shares(runs).Skip(Run.BANDS * 3 / 4).Sum(), 4),
            ["react_bounce"] = new JsonObject
            {
                ["median"] = num(pct(rb, 0.5)), ["p10"] = num(pct(rb, 0.1)), ["n"] = rb.Count,
                ["bins"] = arr(REACT_BINS), ["hist"] = arr(hist(rb.Select(x => (int)x), REACT_BINS)),
            },
            ["react_new"] = new JsonObject
            {
                ["median"] = num(react), ["p10"] = num(pct(rn, 0.1)), ["n"] = rn.Count,
                ["under_10_ticks"] = num(rn.Count == 0 ? double.NaN : (double)rn.Count(x => x < HUMAN_REACT_FAST) / rn.Count, 4),
                ["bins"] = arr(REACT_BINS), ["hist"] = arr(hist(rn.Select(x => (int)x), REACT_BINS)),
            },
        };
        if (timing != null)
            o["timing"] = new JsonObject
            {
                ["taps_judged"] = timing.taps_judged,
                ["critical"] = timing.critical,
                ["error_mean"] = num(timing.errors.Count == 0 ? double.NaN : timing.errors.Average()),
                ["error_sd"] = num(err_sd),
                ["error_abs_median"] = num(pct(timing.errors.Select(Math.Abs), 0.5)),
                ["window_median"] = num(pct(timing.widths.Select(x => (double)x), 0.5)),
            };
        // Against the published human numbers (no human runs of this game yet).
        o["reference"] = new JsonObject
        {
            ["source"] = "Isaksen et al. FDG 2015: <= 7.7 taps/s, timing sigma 36-61 ms (2.2-3.7 ticks), reaction ~288 ms (17 ticks)",
            ["intervals_ok"] = double.IsNaN(under) ? null : under <= 0.02,
            ["timing_ok"] = double.IsNaN(err_sd) ? null : err_sd >= HUMAN_SIGMA_LO / 1.5 && err_sd <= HUMAN_SIGMA_HI * 1.5,
            ["reaction_ok"] = double.IsNaN(react) ? null : react >= HUMAN_REACT_FAST,
        };
        return o;
    }
}
