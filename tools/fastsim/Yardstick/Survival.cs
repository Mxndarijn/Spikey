using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;

namespace FastSim.Yard;

/// Confidence intervals and survival curves for bot scores
/// (`fastsim yardstick stats`, docs/YARDSTICK.md "Statistics").
///
/// A run is a score T (points) that either ended in a death or was cut by
/// the tick cap (censored). Everything here treats the cap properly:
/// Kaplan-Meier for the median and the survival curve, exact Poisson
/// intervals for deaths per 100 points, a piecewise-exponential model
/// (one death rate per score band) for a median that also works past the
/// cap, and paired comparisons between two run sets on the same seeds.
/// No sim is played: it reads yardstick JSONs or death-atlas TSVs.
public static class Survival
{
    public sealed record Obs(long seed, long points, bool dead);

    public sealed class Set
    {
        public string name = "", source = "";
        public List<Obs> runs = new();
        /// True when survivors' points were not stored and were spread evenly.
        public bool approx;
        public long cap;
        public int deaths => runs.Count(r => r.dead);
        public int alive => runs.Count(r => !r.dead);
    }

    // ---------------------------------------------------------------- loading

    /// A yardstick JSON (`runs`: seed, points, dead) or a death atlas TSV
    /// (one row per death; survivors are the seeds without a row, and their
    /// points are the header's total minus the deaths' points, spread evenly).
    public static Set load(string path)
    {
        if (!File.Exists(path)) throw new FileNotFoundException($"no such run set: {path}");
        string text = File.ReadAllText(path);
        var set = new Set { source = path, name = Path.GetFileNameWithoutExtension(path) };
        if (text.TrimStart().StartsWith("{"))
        {
            var o = JsonNode.Parse(text)!.AsObject();
            set.name = ((string)o["bot"] ?? set.name) + (o["set"] is JsonNode s ? "_" + (string)s : "");
            set.cap = (long?)o["cap"] ?? 0;
            foreach (var r in o["runs"]!.AsArray())
                set.runs.Add(new Obs((long)r!["seed"]!, (long)r["points"]!, (bool)r["dead"]!));
            return set;
        }
        // Death atlas: "... seeds 1..400, cap 108000 ..." then "D deaths in P points ...; A of N alive".
        var lines = text.Split('\n').Select(l => l.TrimEnd('\r')).ToList();
        var m = System.Text.RegularExpressions.Regex.Match(lines[0], @"seeds (\d+)\.\.(\d+), cap (\d+)");
        var m2 = System.Text.RegularExpressions.Regex.Match(text, @"(\d+) deaths in (\d+) points");
        if (!m.Success || !m2.Success) throw new InvalidDataException($"{path}: not a yardstick JSON or a death atlas");
        long first = long.Parse(m.Groups[1].Value), last = long.Parse(m.Groups[2].Value);
        set.cap = long.Parse(m.Groups[3].Value);
        long total = long.Parse(m2.Groups[2].Value);
        int head = lines.FindIndex(l => l.StartsWith("seed\tscore"));
        if (head < 0) throw new InvalidDataException($"{path}: no death rows");
        var dead = new Dictionary<long, long>();
        foreach (var l in lines.Skip(head + 1))
        {
            var c = l.Split('\t');
            if (c.Length < 3 || !long.TryParse(c[0], out long seed)) continue;
            dead[seed] = long.Parse(c[1]);
        }
        var alive = new List<long>();
        for (long s = first; s <= last; s++)
            if (dead.TryGetValue(s, out long p)) set.runs.Add(new Obs(s, p, true));
            else alive.Add(s);
        long left = total - dead.Values.Sum();
        for (int i = 0; i < alive.Count; i++)
        {
            long share = left / alive.Count + (i < left % alive.Count ? 1 : 0);
            set.runs.Add(new Obs(alive[i], share, false));
        }
        set.approx = alive.Count > 0;
        return set;
    }

    // ---------------------------------------------------------- distributions

    static double ln_gamma(double x)
    {
        // Lanczos, g = 7.
        double[] c = { 0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313,
            -176.61502916214059, 12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7 };
        if (x < 0.5) return Math.Log(Math.PI / Math.Sin(Math.PI * x)) - ln_gamma(1 - x);
        x -= 1;
        double a = c[0], t = x + 7.5;
        for (int i = 1; i < 9; i++) a += c[i] / (x + i);
        return 0.5 * Math.Log(2 * Math.PI) + (x + 0.5) * Math.Log(t) - t + Math.Log(a);
    }

    /// Regularized lower incomplete gamma P(a, x).
    public static double gamma_p(double a, double x)
    {
        if (x <= 0) return 0;
        if (x < a + 1)
        {
            double sum = 1 / a, term = sum;
            for (int n = 1; n < 1000; n++)
            {
                term *= x / (a + n);
                sum += term;
                if (Math.Abs(term) < Math.Abs(sum) * 1e-15) break;
            }
            return sum * Math.Exp(-x + a * Math.Log(x) - ln_gamma(a));
        }
        // Continued fraction for Q, Lentz.
        double b = x + 1 - a, cc = 1e300, d = 1 / b, h = d;
        for (int i = 1; i < 1000; i++)
        {
            double an = -i * (i - a);
            b += 2;
            d = an * d + b; if (Math.Abs(d) < 1e-300) d = 1e-300;
            cc = b + an / cc; if (Math.Abs(cc) < 1e-300) cc = 1e-300;
            d = 1 / d;
            double del = d * cc;
            h *= del;
            if (Math.Abs(del - 1) < 1e-15) break;
        }
        return 1 - Math.Exp(-x + a * Math.Log(x) - ln_gamma(a)) * h;
    }

    /// The x with P(a, x) = p (bisection; a > 0).
    static double gamma_inv(double a, double p)
    {
        double lo = 0, hi = Math.Max(10, a * 4 + 50);
        while (gamma_p(a, hi) < p) hi *= 2;
        for (int i = 0; i < 200; i++)
        {
            double mid = (lo + hi) / 2;
            if (gamma_p(a, mid) < p) lo = mid; else hi = mid;
        }
        return (lo + hi) / 2;
    }

    /// Exact (Garwood) 95% interval for a Poisson count d.
    public static (double lo, double hi) poisson_ci(int d, double conf = 0.95)
    {
        double a = (1 - conf) / 2;
        double lo = d == 0 ? 0 : gamma_inv(d, a);
        double hi = gamma_inv(d + 1, 1 - a);
        return (lo, hi);
    }

    /// Wilson interval for k of n.
    public static (double lo, double hi) wilson(int k, int n, double z = 1.96)
    {
        if (n == 0) return (double.NaN, double.NaN);
        double p = (double)k / n, den = 1 + z * z / n;
        double mid = (p + z * z / (2 * n)) / den, half = z * Math.Sqrt(p * (1 - p) / n + z * z / (4.0 * n * n)) / den;
        return (Math.Max(0, mid - half), Math.Min(1, mid + half));
    }

    static double norm_cdf(double z) => 0.5 * (1 + erf(z / Math.Sqrt(2)));

    static double erf(double x)
    {
        // Abramowitz-Stegun 7.1.26 is too coarse for p-values; use P(1/2, x^2).
        double v = gamma_p(0.5, x * x);
        return x < 0 ? -v : v;
    }

    // ----------------------------------------------------------- exposure

    /// Points a run tried inside [lo, hi): it scored min(T, hi) - lo of them
    /// and, if it died at T inside the band, failed one more. A death at
    /// exactly the band's low edge counts as one trial, not zero.
    static (long trials, int deaths) band(IEnumerable<Obs> runs, long lo, long hi)
    {
        long t = 0;
        int d = 0;
        foreach (var r in runs)
        {
            if (r.points > lo) t += Math.Min(r.points, hi) - lo;
            if (r.dead && r.points >= lo && r.points < hi) { t++; d++; }
        }
        return (t, d);
    }

    /// Deaths per 100 points with an exact interval, inside [lo, hi).
    public static (double rate, double lo, double hi, int deaths, long trials) rate(IEnumerable<Obs> runs, long lo = 0, long hi = long.MaxValue)
    {
        var (t, d) = band(runs, lo, hi);
        if (t == 0) return (double.NaN, double.NaN, double.NaN, d, t);
        var (a, b) = poisson_ci(d);
        return (100.0 * d / t, 100.0 * a / t, 100.0 * b / t, d, t);
    }

    /// The "rate median" of the yardstick (ln 0.5 / ln(1 - h)) for a per-100 rate.
    public static double rate_median(double per100) =>
        per100 <= 0 ? double.PositiveInfinity : Math.Log(0.5) / Math.Log(1 - per100 / 100);

    // ---------------------------------------------------------- Kaplan-Meier

    public sealed record KmStep(long t, int at_risk, int deaths, double s, double lo, double hi);

    /// Kaplan-Meier on points: S(t) = chance to score more than t. Steps at
    /// each death score, with Greenwood variance and log-log 95% limits.
    public static List<KmStep> km(IList<Obs> runs)
    {
        var steps = new List<KmStep>();
        var by = runs.GroupBy(r => r.points).OrderBy(g => g.Key).ToList();
        int n = runs.Count;
        double s = 1, gw = 0;
        foreach (var g in by)
        {
            int d = g.Count(r => r.dead);
            if (d > 0)
            {
                s *= 1 - (double)d / n;
                if (n > d) gw += (double)d / ((double)n * (n - d));
                double lo = s, hi = s;
                if (s > 0 && s < 1)
                {
                    double se = Math.Sqrt(gw) / Math.Abs(Math.Log(s));
                    lo = Math.Pow(s, Math.Exp(1.96 * se));
                    hi = Math.Pow(s, Math.Exp(-1.96 * se));
                }
                steps.Add(new KmStep(g.Key, n, d, s, lo, hi));
            }
            n -= g.Count();
        }
        return steps;
    }

    /// S(t) from the steps (the last step at or below t).
    public static KmStep at(List<KmStep> steps, long t, int n)
    {
        KmStep last = new(0, n, 0, 1, 1, 1);
        foreach (var s in steps) { if (s.t > t) break; last = s; }
        return last;
    }

    /// KM median and its 95% interval (Brookmeyer-Crowley: the scores whose
    /// log-log band contains 0.5). NaN when the curve never gets that low,
    /// which happens when half or more of the runs reach the cap.
    public static (double med, double lo, double hi) km_median(List<KmStep> steps)
    {
        double med = double.NaN, lo = double.NaN, hi = double.NaN;
        foreach (var s in steps)
        {
            if (double.IsNaN(lo) && s.lo <= 0.5) lo = s.t;
            if (double.IsNaN(med) && s.s <= 0.5) med = s.t;
            if (double.IsNaN(hi) && s.hi <= 0.5) hi = s.t;
        }
        return (med, lo, hi);
    }

    /// Restricted mean score up to tau (area under the KM curve).
    public static double rmst(List<KmStep> steps, long tau)
    {
        double area = 0, s = 1;
        long prev = 0;
        foreach (var st in steps)
        {
            if (st.t >= tau) break;
            area += s * (st.t - prev);
            prev = st.t;
            s = st.s;
        }
        return area + s * (tau - prev);
    }

    // --------------------------------------------------- piecewise exponential

    /// Bands for the piecewise model: fine where the rate climbs (the first
    /// rooms), coarse on the plateau; the last band runs on past the cap.
    public static readonly long[] PEM_BANDS = { 0, 5, 10, 15, 20, 30, 40, 60, 80, 120, 160, 240, 320, 480, 640 };

    /// The median of a model with one death chance per point in each band:
    /// the first score where the chance to have survived falls to 0.5. Uses
    /// every run (capped ones too) and extends the last band's rate past the
    /// cap, so it gives a number even when most runs reach the cap.
    public static double pem_median(IList<Obs> runs)
    {
        double log_s = 0, half = Math.Log(0.5);
        for (int i = 0; i < PEM_BANDS.Length; i++)
        {
            long lo = PEM_BANDS[i], hi = i + 1 < PEM_BANDS.Length ? PEM_BANDS[i + 1] : long.MaxValue;
            var (t, d) = band(runs, lo, hi);
            double q = t == 0 ? 0 : (double)d / t;
            if (q <= 0) { if (hi == long.MaxValue) return double.PositiveInfinity; log_s += 0; continue; }
            double per = Math.Log(1 - q);
            double need = (half - log_s) / per;
            if (hi == long.MaxValue || need <= hi - lo) return lo + need;
            log_s += per * (hi - lo);
        }
        return double.PositiveInfinity;
    }

    // ------------------------------------------------------------- bootstrap

    /// Percentile 95% interval of `f` over `reps` resamples of the runs
    /// (resampling seeds: the honest unit when seeds differ in difficulty).
    public static (double lo, double hi) boot(IList<Obs> runs, Func<IList<Obs>, double> f, int reps = 2000, int seed = 1)
    {
        var rng = new Random(seed);
        var vals = new List<double>(reps);
        var buf = new Obs[runs.Count];
        for (int b = 0; b < reps; b++)
        {
            for (int i = 0; i < buf.Length; i++) buf[i] = runs[rng.Next(runs.Count)];
            vals.Add(f(buf));
        }
        vals.Sort();
        return (vals[(int)(0.025 * (reps - 1))], vals[(int)Math.Ceiling(0.975 * (reps - 1))]);
    }

    // ------------------------------------------------------------- comparison

    /// Log-rank test of two run sets (chi-square, 1 df) and its p-value.
    public static (double chi2, double p, double observed_a, double expected_a) logrank(IList<Obs> a, IList<Obs> b)
    {
        var all = a.Select(r => (r, g: 0)).Concat(b.Select(r => (r, g: 1))).ToList();
        var times = all.Where(x => x.r.dead).Select(x => x.r.points).Distinct().OrderBy(t => t).ToList();
        double o = 0, e = 0, v = 0;
        foreach (long t in times)
        {
            int na = a.Count(r => r.points >= t), nb = b.Count(r => r.points >= t);
            int da = a.Count(r => r.dead && r.points == t), db = b.Count(r => r.dead && r.points == t);
            int n = na + nb, d = da + db;
            if (n < 2) continue;
            o += da;
            e += (double)d * na / n;
            v += (double)d * na * nb * (n - d) / ((double)n * n * (n - 1));
        }
        double chi = v > 0 ? (o - e) * (o - e) / v : 0;
        return (chi, 2 * (1 - norm_cdf(Math.Sqrt(chi))), o, e);
    }

    /// Deaths needed in each of two sets to see a rate ratio `r` with a
    /// two-sided 5% test and 80% power: 2 (1.96 + 0.84)^2 / ln(r)^2.
    public static double deaths_needed(double r, double z_a = 1.96, double z_b = 0.8416) =>
        2 * Math.Pow(z_a + z_b, 2) / Math.Pow(Math.Log(r), 2);

    static double spearman(IList<double> x, IList<double> y)
    {
        double[] rank(IList<double> v)
        {
            var idx = Enumerable.Range(0, v.Count).OrderBy(i => v[i]).ToArray();
            var r = new double[v.Count];
            for (int i = 0; i < idx.Length;)
            {
                int j = i;
                while (j + 1 < idx.Length && v[idx[j + 1]] == v[idx[i]]) j++;
                for (int k = i; k <= j; k++) r[idx[k]] = (i + j) / 2.0;
                i = j + 1;
            }
            return r;
        }
        var rx = rank(x); var ry = rank(y);
        double mx = rx.Average(), my = ry.Average(), sxy = 0, sxx = 0, syy = 0;
        for (int i = 0; i < rx.Length; i++)
        {
            sxy += (rx[i] - mx) * (ry[i] - my);
            sxx += (rx[i] - mx) * (rx[i] - mx);
            syy += (ry[i] - my) * (ry[i] - my);
        }
        return sxx == 0 || syy == 0 ? double.NaN : sxy / Math.Sqrt(sxx * syy);
    }

    // ---------------------------------------------------------------- report

    /// The plateau starts here: past the first rooms the rate stops climbing
    /// (bot-review.md), so "deaths per 100 from 40 on" is a skill number that
    /// does not depend on the ramp.
    public const long PLATEAU = 40;
    public static readonly long[] CURVE_AT = { 10, 20, 40, 80, 160, 320, 640, 1000 };

    public static JsonObject describe(Set set, int reps)
    {
        var runs = set.runs;
        int n = runs.Count;
        var all = rate(runs);
        var plat = rate(runs, PLATEAU);
        var steps = km(runs);
        var (med, mlo, mhi) = km_median(steps);
        double pem = pem_median(runs);
        var (plo, phi) = boot(runs, pem_median, reps);
        var (alo, ahi) = wilson(set.alive, n);
        var curve = new JsonArray();
        foreach (long t in CURVE_AT)
        {
            var s = at(steps, t, n);
            int risk = runs.Count(r => r.points >= t);
            curve.Add(new JsonObject { ["score"] = t, ["survive"] = R(s.s, 4), ["lo"] = R(s.lo, 4), ["hi"] = R(s.hi, 4), ["at_risk"] = risk });
        }
        var bands = new JsonArray();
        for (int i = 0; i < Stats.SCORE_BANDS.Length; i++)
        {
            long lo = Stats.SCORE_BANDS[i], hi = i + 1 < Stats.SCORE_BANDS.Length ? Stats.SCORE_BANDS[i + 1] : long.MaxValue;
            var r = rate(runs, lo, hi);
            bands.Add(new JsonObject
            {
                ["band"] = hi == long.MaxValue ? $"{lo}+" : $"{lo}..{hi}",
                ["deaths"] = r.deaths, ["points"] = r.trials,
                ["per_100"] = R(r.rate, 3), ["lo"] = R(r.lo, 3), ["hi"] = R(r.hi, 3),
            });
        }
        long tau = runs.Where(r => !r.dead).Select(r => r.points).DefaultIfEmpty(runs.Max(r => r.points)).Min();
        var raw = runs.Select(r => (double)r.points).ToList();
        var (rlo, rhi) = boot(runs, xs => Stats.pct(xs.Select(r => (double)r.points), 0.5), reps, 2);
        return new JsonObject
        {
            ["name"] = set.name,
            ["source"] = set.source,
            ["runs"] = n,
            ["deaths"] = set.deaths,
            ["alive_at_cap"] = set.alive,
            ["alive_share"] = new JsonObject { ["p"] = R((double)set.alive / n, 4), ["lo"] = R(alo, 4), ["hi"] = R(ahi, 4) },
            ["survivor_points_approx"] = set.approx,
            ["per_100"] = new JsonObject { ["all"] = R(all.rate, 4), ["lo"] = R(all.lo, 4), ["hi"] = R(all.hi, 4) },
            ["per_100_plateau"] = new JsonObject { ["from"] = PLATEAU, ["rate"] = R(plat.rate, 4), ["lo"] = R(plat.lo, 4), ["hi"] = R(plat.hi, 4), ["deaths"] = plat.deaths },
            ["rate_median"] = new JsonObject { ["value"] = R(rate_median(all.rate), 1), ["lo"] = R(rate_median(all.hi), 1), ["hi"] = R(rate_median(all.lo), 1) },
            ["raw_median"] = new JsonObject { ["value"] = R(Stats.pct(raw, 0.5), 1), ["lo"] = R(rlo, 1), ["hi"] = R(rhi, 1) },
            ["km_median"] = new JsonObject { ["value"] = R(med, 1), ["lo"] = R(mlo, 1), ["hi"] = R(mhi, 1) },
            ["pem_median"] = new JsonObject { ["value"] = R(pem, 1), ["lo"] = R(plo, 1), ["hi"] = R(phi, 1) },
            ["tier_km"] = double.IsNaN(med) ? "beast (half reach the cap)" : Stats.tier_of(med),
            ["tier_pem"] = double.IsInfinity(pem) ? "beast" : Stats.tier_of(pem),
            ["rmst"] = new JsonObject { ["tau"] = tau, ["mean_points"] = R(rmst(steps, tau), 1) },
            ["survival"] = curve,
            ["bands"] = bands,
            ["deaths_for_10pct"] = Math.Ceiling(Math.Pow(1.96 / Math.Log(1.1), 2)),
        };
    }

    public static JsonObject compare(Set a, Set b, int reps)
    {
        var o = new JsonObject { ["a"] = a.name, ["b"] = b.name };
        foreach (var (key, lo) in new[] { ("all", 0L), ("plateau", PLATEAU) })
        {
            var ra = rate(a.runs, lo); var rb = rate(b.runs, lo);
            double ratio = ra.rate / rb.rate;
            double se = Math.Sqrt(1.0 / Math.Max(1, ra.deaths) + 1.0 / Math.Max(1, rb.deaths));
            double z = Math.Log(ratio) / se;
            o["rate_ratio_" + key] = new JsonObject
            {
                ["ratio"] = R(ratio, 3),
                ["lo"] = R(ratio * Math.Exp(-1.96 * se), 3),
                ["hi"] = R(ratio * Math.Exp(1.96 * se), 3),
                ["z"] = R(z, 2),
                ["p"] = R(2 * (1 - norm_cdf(Math.Abs(z))), 4),
            };
        }
        var lr = logrank(a.runs, b.runs);
        o["logrank"] = new JsonObject { ["chi2"] = R(lr.chi2, 2), ["p"] = R(lr.p, 4), ["deaths_a"] = lr.observed_a, ["expected_a"] = R(lr.expected_a, 1) };
        // Paired by seed: does playing the same seeds help?
        var bs = b.runs.GroupBy(r => r.seed).ToDictionary(g => g.Key, g => g.First());
        var common = a.runs.Where(r => bs.ContainsKey(r.seed)).Select(r => (x: r, y: bs[r.seed])).ToList();
        if (common.Count >= 10)
        {
            double rho = spearman(common.Select(c => Math.Log(1 + c.x.points)).ToList(), common.Select(c => Math.Log(1 + c.y.points)).ToList());
            int both = common.Count(c => c.x.dead && c.y.dead), only_a = common.Count(c => c.x.dead && !c.y.dead), only_b = common.Count(c => !c.x.dead && c.y.dead);
            int a_longer = common.Count(c => c.x.points > c.y.points), b_longer = common.Count(c => c.y.points > c.x.points);
            o["paired"] = new JsonObject
            {
                ["seeds"] = common.Count,
                ["spearman_log_points"] = R(rho, 3),
                ["variance_saved_by_pairing"] = R(double.IsNaN(rho) ? 0 : Math.Max(0, rho), 3),
                ["a_scores_more"] = a_longer,
                ["b_scores_more"] = b_longer,
                ["sign_test_p"] = R(sign_p(a_longer, b_longer), 4),
                ["capped_only_a_alive"] = only_b, ["capped_only_b_alive"] = only_a, ["both_dead"] = both,
            };
        }
        var (kma, _, _) = km_median(km(a.runs));
        var (kmb, _, _) = km_median(km(b.runs));
        o["km_median"] = new JsonObject { ["a"] = R(kma, 1), ["b"] = R(kmb, 1) };
        // Pocock bound for 5 equally spaced looks: stop early only if |z| > 2.41.
        double zall = (double)o["rate_ratio_all"]!["z"]!;
        o["sequential"] = new JsonObject
        {
            ["rule"] = "look after every fifth of the planned deaths; stop when |z| > 2.41 (Pocock, 5 looks, 5% overall)",
            ["stop_now"] = Math.Abs(zall) > 2.41,
        };
        return o;
    }

    static double sign_p(int a, int b)
    {
        int n = a + b;
        if (n == 0) return 1;
        int k = Math.Min(a, b);
        double p = 0;
        for (int i = 0; i <= k; i++) p += Math.Exp(ln_choose(n, i) - n * Math.Log(2));
        return Math.Min(1, 2 * p);
    }

    static double ln_choose(int n, int k) => ln_gamma(n + 1) - ln_gamma(k + 1) - ln_gamma(n - k + 1);

    static JsonNode R(double x, int d) => double.IsNaN(x) || double.IsInfinity(x) ? null : Math.Round(x, d);

    // ------------------------------------------------------------------- text

    static string F(JsonNode n, string fmt = "0.###") => n == null ? "-" : ((double)n).ToString(fmt, CultureInfo.InvariantCulture);

    static string ci(JsonNode o, string v = "value", string fmt = "0.#") => $"{F(o[v], fmt)} [{F(o["lo"], fmt)}, {F(o["hi"], fmt)}]";

    public static string text(JsonObject d)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"{d["name"]}: {d["runs"]} runs, {d["deaths"]} deaths, {d["alive_at_cap"]} alive at the cap ({ci(d["alive_share"]!, "p", "0.###")})"
            + ((bool)d["survivor_points_approx"]! ? "  [survivors' points spread evenly: atlas file]" : ""));
        sb.AppendLine($"  deaths/100 pt      {ci(d["per_100"]!, "all", "0.###")}   from {PLATEAU}: {ci(d["per_100_plateau"]!, "rate", "0.###")} ({d["per_100_plateau"]!["deaths"]} deaths)");
        sb.AppendLine($"  median: raw {ci(d["raw_median"]!)}  KM {ci(d["km_median"]!)}  piecewise {ci(d["pem_median"]!)}  rate {ci(d["rate_median"]!)}");
        sb.AppendLine($"  tier: KM {d["tier_km"]}, piecewise {d["tier_pem"]}; mean score up to {d["rmst"]!["tau"]}: {F(d["rmst"]!["mean_points"], "0.#")}");
        sb.Append("  survive past");
        foreach (var s in d["survival"]!.AsArray()) sb.Append($"  {s!["score"]}: {F(s["survive"], "0.00")} [{F(s["lo"], "0.00")},{F(s["hi"], "0.00")}]");
        sb.AppendLine();
        sb.Append("  deaths/100 by band");
        foreach (var b in d["bands"]!.AsArray()) sb.Append($"  {b!["band"]}: {F(b["per_100"], "0.###")} [{F(b["lo"], "0.###")},{F(b["hi"], "0.###")}]");
        sb.AppendLine();
        return sb.ToString();
    }

    public static string text_compare(JsonObject c)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"{c["a"]} vs {c["b"]}:");
        foreach (var k in new[] { "all", "plateau" })
        {
            var r = c["rate_ratio_" + k]!;
            sb.AppendLine($"  rate ratio ({k,-7}) {F(r["ratio"])} [{F(r["lo"])}, {F(r["hi"])}]  z {F(r["z"], "0.00")}  p {F(r["p"], "0.####")}");
        }
        sb.AppendLine($"  log-rank chi2 {F(c["logrank"]!["chi2"], "0.00")}  p {F(c["logrank"]!["p"], "0.####")};  KM medians {F(c["km_median"]!["a"], "0.#")} vs {F(c["km_median"]!["b"], "0.#")}");
        if (c["paired"] is JsonNode p)
            sb.AppendLine($"  paired on {p["seeds"]} seeds: spearman {F(p["spearman_log_points"], "0.000")} (pairing helps only if this is well above 0); a scores more on {p["a_scores_more"]}, b on {p["b_scores_more"]}, sign test p {F(p["sign_test_p"], "0.####")}");
        sb.AppendLine($"  sequential: {c["sequential"]!["rule"]}; stop now: {c["sequential"]!["stop_now"]}");
        return sb.ToString();
    }

    public static string plan_text()
    {
        var sb = new StringBuilder("deaths needed in each set to see a rate ratio (two-sided 5%, 80% power):\n");
        foreach (double r in new[] { 0.95, 0.9, 0.85, 0.8, 0.7, 0.6, 0.5 })
            sb.AppendLine($"  ratio {r:0.00}: {Math.Ceiling(deaths_needed(r)),6} deaths each");
        sb.AppendLine("one set's rate to +-10%: ~400 deaths; +-20%: ~100; +-30%: ~45 (1.96 / sqrt(deaths) on the log scale)");
        return sb.ToString();
    }

    // ------------------------------------------------------------- self test

    /// Known values, for the yardstick check.
    public static List<string> self_test()
    {
        var fails = new List<string>();
        void near(string what, double got, double want, double tol)
        {
            if (!(Math.Abs(got - want) <= tol)) fails.Add($"{what}: {got}, want {want}");
        }
        var (lo, hi) = poisson_ci(21);
        near("poisson lo(21)", lo, 12.999, 0.01);
        near("poisson hi(21)", hi, 32.101, 0.01);
        near("poisson hi(0)", poisson_ci(0).hi, 3.689, 0.01);
        // Hand case: deaths at 3, 5, 8, 12, capped at 5 and 10 (a cap tied with a death leaves after it).
        var runs = new List<Obs>
        {
            new(1, 3, true), new(2, 5, false), new(3, 5, true), new(4, 8, true), new(5, 10, false), new(6, 12, true),
        };
        var steps = km(runs);
        // S(3) = 5/6, S(5) = 5/6 * 4/5 = 2/3, S(8) = 2/3 * 2/3 = 4/9, S(12) = 0.
        near("km S(5)", at(steps, 5, 6).s, 2.0 / 3, 1e-9);
        near("km S(8)", at(steps, 8, 6).s, 4.0 / 9, 1e-9);
        near("km median", km_median(steps).med, 8, 0);
        // A constant rate q per point gives a piecewise median of ln 0.5 / ln(1 - q).
        var rng = new Random(5);
        var geo = new List<Obs>();
        for (int i = 0; i < 4000; i++)
        {
            long p = 0;
            while (rng.NextDouble() > 0.01) p++;
            geo.Add(new Obs(i, p, true));
        }
        near("pem median of geometric(0.01)", pem_median(geo), rate_median(1), 6);
        near("km median of geometric(0.01)", km_median(km(geo)).med, rate_median(1), 6);
        near("deaths for ratio 0.8", deaths_needed(0.8), 315, 2);
        var same = logrank(geo.Take(2000).ToList(), geo.Skip(2000).ToList());
        if (same.p < 0.001) fails.Add($"log-rank calls two halves of one set different (p {same.p})");
        return fails;
    }
}
