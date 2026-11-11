using System.Text.Json.Nodes;

namespace FastSim.Yard;

/// Bot runs against human runs: distances between their distributions and a
/// small human-vs-bot classifier on per-run features (the Navigation Turing
/// Test idea, Devlin et al. ICML 2021). A classifier at 50% accuracy cannot
/// tell them apart; at 100% the bot is easy to spot.
public static class Compare
{
    public const int MIN_TAPS = 10;

    public static readonly string[] FEATURES =
    {
        "taps_per_s", "interval_median", "interval_p10", "interval_cv", "under_8",
        "band0", "band1", "band2", "band3", "band4", "band5", "band6", "band7", "react_bounce", "react_new",
    };

    public static double[] features(Run r)
    {
        var ints = r.intervals.Select(x => (double)x).ToList();
        double mean = ints.Count == 0 ? 0 : ints.Average();
        double sd = ints.Count < 2 ? 0 : Math.Sqrt(ints.Sum(x => (x - mean) * (x - mean)) / (ints.Count - 1));
        double total = Math.Max(1, r.bands.Sum());
        var f = new List<double>
        {
            r.taps_per_s, Stats.pct(ints, 0.5), Stats.pct(ints, 0.1), mean > 0 ? sd / mean : 0,
            ints.Count == 0 ? 0 : (double)r.intervals.Count(i => i < Stats.HUMAN_MIN_INTERVAL) / ints.Count,
        };
        f.AddRange(r.bands.Select(b => b / total));
        double rb = Stats.pct(r.react_bounce.Select(x => (double)x), 0.5);
        double rn = Stats.pct(r.react_new.Select(x => (double)x), 0.5);
        f.Add(double.IsNaN(rb) ? Run.REACT_WINDOW : rb);
        f.Add(double.IsNaN(rn) ? Run.REACT_WINDOW : rn);
        return f.Select(x => double.IsNaN(x) ? 0 : x).ToArray();
    }

    static double tv(double[] a, double[] b) => 0.5 * a.Zip(b, (x, y) => Math.Abs(x - y)).Sum();

    static double ks(List<double> a, List<double> b)
    {
        if (a.Count == 0 || b.Count == 0) return double.NaN;
        var all = a.Concat(b).Distinct().OrderBy(x => x);
        var sa = a.OrderBy(x => x).ToArray();
        var sb = b.OrderBy(x => x).ToArray();
        double d = 0;
        foreach (var x in all)
        {
            double fa = upper(sa, x) / (double)sa.Length, fb = upper(sb, x) / (double)sb.Length;
            d = Math.Max(d, Math.Abs(fa - fb));
        }
        return d;
    }

    static int upper(double[] s, double x)
    {
        int lo = 0, hi = s.Length;
        while (lo < hi)
        {
            int m = (lo + hi) / 2;
            if (s[m] <= x) lo = m + 1;
            else hi = m;
        }
        return lo;
    }

    /// Distances (0 = the same as the humans, 1 = nothing alike) and the classifier.
    public static JsonObject against(IList<Run> bot, IList<Run> human)
    {
        double t_int = tv(Stats.hist(bot.SelectMany(r => r.intervals), Stats.INTERVAL_BINS),
            Stats.hist(human.SelectMany(r => r.intervals), Stats.INTERVAL_BINS));
        double t_band = tv(Stats.band_shares(bot), Stats.band_shares(human));
        double t_react = tv(Stats.hist(bot.SelectMany(r => r.react_new), Stats.REACT_BINS),
            Stats.hist(human.SelectMany(r => r.react_new), Stats.REACT_BINS));
        double k_tps = ks(bot.Select(r => r.taps_per_s).ToList(), human.Select(r => r.taps_per_s).ToList());
        var parts = new[] { t_int, t_band, t_react, k_tps }.Where(x => !double.IsNaN(x)).ToList();
        var o = new JsonObject
        {
            ["human_runs"] = human.Count,
            ["intervals_tv"] = Math.Round(t_int, 4),
            ["bands_tv"] = Math.Round(t_band, 4),
            ["react_tv"] = Math.Round(t_react, 4),
            ["taps_per_s_ks"] = double.IsNaN(k_tps) ? null : Math.Round(k_tps, 4),
            ["likeness"] = Math.Round(1 - parts.Average(), 4),
        };
        var b = bot.Where(r => r.taps_played >= MIN_TAPS).ToList();
        var h = human.Where(r => r.taps_played >= MIN_TAPS).ToList();
        if (b.Count >= 5 && h.Count >= 5) o["classifier"] = classify(b, h);
        return o;
    }

    /// Logistic regression on standardised features, 5-fold cross-validated,
    /// classes weighted equally. Returns accuracy, AUC and the features it leans on.
    public static JsonObject classify(List<Run> bot, List<Run> human)
    {
        var xs = bot.Select(features).Concat(human.Select(features)).ToList();
        var ys = bot.Select(_ => 0).Concat(human.Select(_ => 1)).ToList();
        int n = xs.Count, d = xs[0].Length;
        var mean = new double[d];
        var sdv = new double[d];
        for (int j = 0; j < d; j++)
        {
            mean[j] = xs.Average(x => x[j]);
            sdv[j] = Math.Sqrt(xs.Average(x => (x[j] - mean[j]) * (x[j] - mean[j])));
            if (sdv[j] < 1e-9) sdv[j] = 1;
        }
        var z = xs.Select(x => x.Select((v, j) => (v - mean[j]) / sdv[j]).ToArray()).ToList();
        var order = Enumerable.Range(0, n).OrderBy(i => (i * 2654435761L) % 1000003).ToArray();
        var score = new double[n];
        const int FOLDS = 5;
        for (int f = 0; f < FOLDS; f++)
        {
            var train = order.Where((_, k) => k % FOLDS != f).ToList();
            var w = fit(z, ys, train, d);
            foreach (var i in order.Where((_, k) => k % FOLDS == f)) score[i] = dot(w, z[i]);
        }
        int right = 0;
        double wb = 0.5 / bot.Count, wh = 0.5 / human.Count, acc = 0;
        for (int i = 0; i < n; i++)
            if ((score[i] > 0) == (ys[i] == 1)) { right++; acc += ys[i] == 1 ? wh : wb; }
        var all_w = fit(z, ys, Enumerable.Range(0, n).ToList(), d);
        var top = new JsonObject();
        foreach (var j in Enumerable.Range(0, d).OrderByDescending(j => Math.Abs(all_w[j])).Take(5))
            top[FEATURES[j]] = Math.Round(all_w[j], 3);
        return new JsonObject
        {
            ["balanced_accuracy"] = Math.Round(acc, 4),
            ["auc"] = Math.Round(auc(score, ys), 4),
            ["bot_runs"] = bot.Count,
            ["human_runs"] = human.Count,
            ["weights"] = top,
            ["note"] = "0.5 = cannot tell the bot from the humans; 1.0 = always can",
        };
    }

    static double dot(double[] w, double[] x)
    {
        double s = w[^1];
        for (int j = 0; j < x.Length; j++) s += w[j] * x[j];
        return s;
    }

    static double[] fit(List<double[]> z, List<int> ys, List<int> rows, int d)
    {
        var w = new double[d + 1];
        int pos = rows.Count(i => ys[i] == 1), neg = rows.Count - pos;
        double wp = rows.Count / (2.0 * Math.Max(1, pos)), wn = rows.Count / (2.0 * Math.Max(1, neg));
        const double LR = 0.1, L2 = 0.01;
        for (int it = 0; it < 500; it++)
        {
            var g = new double[d + 1];
            foreach (int i in rows)
            {
                double p = 1 / (1 + Math.Exp(-dot(w, z[i])));
                double e = (p - ys[i]) * (ys[i] == 1 ? wp : wn);
                for (int j = 0; j < d; j++) g[j] += e * z[i][j];
                g[d] += e;
            }
            for (int j = 0; j <= d; j++) w[j] -= LR * (g[j] / rows.Count + (j < d ? L2 * w[j] : 0));
        }
        return w;
    }

    static double auc(double[] s, List<int> ys)
    {
        var idx = Enumerable.Range(0, s.Length).OrderBy(i => s[i]).ToArray();
        double rank_sum = 0;
        long pos = ys.Count(y => y == 1), neg = ys.Count - pos;
        for (int r = 0; r < idx.Length; r++) if (ys[idx[r]] == 1) rank_sum += r + 1;
        if (pos == 0 || neg == 0) return double.NaN;
        return (rank_sum - pos * (pos + 1) / 2.0) / (pos * neg);
    }
}
