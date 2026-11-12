using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using FastSim.Yard;

namespace FastSim.Measure;

/// One trial: a bot plays one room (kind "room") or the rest of a run (kind
/// "run") from a bank entry snapshot, with the room drawn again. `k` names the
/// redraw: the trial's spine is `new SimRng(Strat.spine_seed(seed, tick, k))`
/// and its bot seed `Strat.bot_seed(...)`; k = -1 is the bank run's own visit
/// (real spine, real bot). Rows of `*.trials.tsv` (format `flapjaw_trials` 1).
public sealed record Trial(string bot, string kind, long seed, long tick, long k, string key, bool died, bool censored, long points, long ticks, double ms);

/// The room-stratified estimator (docs/BOT_TESTING.md).
///
/// The rooms a run meets come from the spine, an RNG of its own, so how
/// often each room comes up per visit (pi_s) is a property of the game, not
/// of the bot: it is counted once from the bank's visits. The death rate per
/// 100 points on a score range is then
///     Q = 100 * sum_s pi_s p_s / sum_s pi_s l_s
/// with p_s the chance to die in a visit of stratum s and l_s the points a
/// visit gives. p_s and l_s come from trials: the bank's entry snapshot of a
/// visit, the spine replaced (so the room and everything it will draw is new,
/// drawn the way the game draws it, arrival checks included), then the bot
/// from that tick to the next room. Trials go where they buy the most
/// precision per CPU second (Neyman allocation: n_s ~ pi_s sd_s / sqrt(cost_s)),
/// so the rooms that kill get most of them and the safe rooms only a few.
public static class Strat
{
    public const long PLATEAU = 40;
    public const string FORMAT = "flapjaw_trials";
    public const int VERSION = 1;
    /// Strata with a smaller visit share are not tried; their p comes from the
    /// bank (`imputed` in the estimate says how much of pi that is).
    public const double MIN_SHARE = 0.002;
    public const int MIN_TRIALS = 3;
    public const double SHRINK = 2;

    public static long spine_seed(long seed, long tick, long k) =>
        SimHash.mix(SimHash.mix(SimHash.mix(SimHash.SEED, seed), tick), k);
    public static long bot_seed(long seed, long tick, long k) => SimHash.mix(spine_seed(seed, tick, k), 0x5EED);

    public static bool plateau(string key) => !key.Contains("@b");
    public static bool in_range(string key, string range) => range switch
    {
        "plateau" => plateau(key),
        "ramp" => !plateau(key),
        _ => true,
    };

    // ------------------------------------------------------------- playing

    /// The entry state with the room drawn again: null when the step did not enter a room.
    public static GameSim redraw(GameSim pre, bool tap, long x)
    {
        var c = pre.clone_deep();
        c._spine = new SimRng(x);
        long ri = c.state.room_index;
        c.step(tap);
        return c.state.room_index != ri && !c.is_over() ? c : null;
    }

    /// Plays one trial from an entry state (after the entry step).
    public static Trial play(BotSpec bot, string kind, GameSim sim, long seed, long tick, long k, long cap)
    {
        string key = Bank.key(sim);
        var decide = bot.make(bot_seed(seed, tick, k));
        long ri = sim.state.room_index, s0 = sim.state.score, t0 = sim.state.tick;
        var clock = Stopwatch.StartNew();
        bool left = false;
        while (sim.state.tick < cap && !sim.is_over())
        {
            sim.step(decide(sim));
            if (kind == "room" && sim.state.room_index != ri) { left = true; break; }
        }
        bool died = sim.is_over();
        return new Trial(bot.name, kind, seed, tick, k, key, died, !died && !left, sim.state.score - s0, sim.state.tick - t0, clock.Elapsed.TotalMilliseconds);
    }

    /// Redraws of bank entries that land in each stratum, found by trying
    /// spine seeds k = 0, 1, ... on every entry (one step each, no bot). A
    /// pool's members are used once each, so no two trials repeat.
    public sealed class Pools
    {
        readonly Bank _bank;
        readonly string _range;
        public readonly Dictionary<string, List<(int run, long tick, bool tap, long k)>> by_key = new();
        public int tried_k;
        public long redraws;
        readonly HashSet<(long, long, long)> _used = new();

        public Pools(Bank bank, string range)
        {
            _bank = bank;
            _range = range;
        }

        /// Tries `more` further spine seeds on every entry whose class can give `range`.
        public void grow(int more, int threads)
        {
            var entries = new List<(int run, Visit v)>();
            for (int i = 0; i < _bank.runs.Count; i++)
                foreach (var v in _bank.runs[i].visits)
                    if (in_range(v.key, _range)) entries.Add((i, v));
            var found = new List<(string key, int run, long tick, bool tap, long k)>[_bank.runs.Count];
            int k0 = tried_k;
            Parallel.For(0, _bank.runs.Count, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
            {
                var mine = entries.Where(e => e.run == i).ToList();
                found[i] = new();
                if (mine.Count == 0) return;
                var pre = Bank.replay_all(_bank.runs[i], mine.Select(e => e.v.tick));
                foreach (var (_, v) in mine)
                    for (long k = k0; k < k0 + more; k++)
                    {
                        var c = redraw(pre[v.tick], v.tap, spine_seed(_bank.runs[i].seed, v.tick, k));
                        if (c != null) found[i].Add((Bank.key(c), i, v.tick, v.tap, k));
                    }
            });
            foreach (var f in found)
                foreach (var e in f)
                {
                    if (!in_range(e.key, _range)) continue;
                    if (!by_key.TryGetValue(e.key, out var l)) by_key[e.key] = l = new();
                    l.Add((e.run, e.tick, e.tap, e.k));
                    redraws++;
                }
            tried_k += more;
        }

        /// The next unused member of `key`'s pool (members in a fixed shuffled order).
        public (int run, long tick, bool tap, long k)? take(string key, Random order)
        {
            if (!by_key.TryGetValue(key, out var l)) return null;
            for (int a = 0; a < l.Count; a++)
            {
                int j = a + order.Next(l.Count - a);
                (l[a], l[j]) = (l[j], l[a]);
                var e = l[a];
                if (_used.Add((_bank.runs[e.run].seed, e.tick, e.k))) return e;
            }
            return null;
        }

        public void mark_used(long seed, long tick, long k) => _used.Add((seed, tick, k));
    }

    /// Plays the trials `jobs` (bank run, tick, tap, k) for `bot`, in parallel.
    public static List<Trial> run_trials(BotSpec bot, string kind, Bank bank, List<(int run, long tick, bool tap, long k)> jobs, long cap, int threads, Action<string> log = null)
    {
        var res = new Trial[jobs.Count];
        var by_run = jobs.Select((j, i) => (j, i)).GroupBy(x => x.j.run).ToList();
        // One replay per bank run gives every snapshot it needs; the trials then run one per thread.
        var pre = new Dictionary<(int, long), GameSim>();
        var lk = new object();
        Parallel.ForEach(by_run, new ParallelOptions { MaxDegreeOfParallelism = threads }, g =>
        {
            var p = Bank.replay_all(bank.runs[g.Key], g.Select(x => x.j.tick));
            lock (lk) foreach (var kv in p) pre[(g.Key, kv.Key)] = kv.Value;
        });
        int done = 0;
        Parallel.For(0, jobs.Count, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            var (run, tick, tap, k) = jobs[i];
            long seed = bank.runs[run].seed;
            var c = redraw(pre[(run, tick)], tap, spine_seed(seed, tick, k));
            res[i] = c == null ? null : play(bot, kind, c, seed, tick, k, cap);
            int d = Interlocked.Increment(ref done);
            if (log != null && (d % 50 == 0 || d == jobs.Count)) log($"  {bot.name}: {d}/{jobs.Count} trials");
        });
        return res.Where(t => t != null).ToList();
    }

    /// The bank's own visits as trials of the bank's bot (k = -1).
    public static List<Trial> bank_trials(Bank bank) =>
        bank.runs.SelectMany(r => r.visits.Select(v => new Trial(bank.bot, "room", r.seed, v.tick, -1, v.key, v.died, v.censored, v.points, v.ticks, v.ms))).ToList();

    // --------------------------------------------------------------- files

    public const string HEADER = "bot\tkind\tseed\ttick\tk\tstratum\tdied\tcensored\tpoints\tticks\tms";

    public static void append(string path, IEnumerable<Trial> trials)
    {
        bool fresh = !File.Exists(path);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        var sb = new StringBuilder();
        if (fresh) sb.Append($"# {FORMAT} {VERSION} gameplay {SimConfig.GAMEPLAY_VERSION}\n{HEADER}\n");
        foreach (var t in trials)
            sb.Append(string.Join('\t', t.bot, t.kind, t.seed, t.tick, t.k, t.key, t.died ? 1 : 0, t.censored ? 1 : 0, t.points, t.ticks,
                t.ms.ToString("F1", CultureInfo.InvariantCulture))).Append('\n');
        File.AppendAllText(path, sb.ToString());
    }

    public static List<Trial> load(string path)
    {
        var res = new List<Trial>();
        if (!File.Exists(path)) return res;
        foreach (var raw in File.ReadLines(path))
        {
            if (raw.StartsWith('#') || raw.StartsWith("bot\t") || raw.Trim() == "") continue;
            var c = raw.Split('\t');
            res.Add(new Trial(c[0], c[1], long.Parse(c[2]), long.Parse(c[3]), long.Parse(c[4]), c[5], c[6] == "1", c[7] == "1",
                long.Parse(c[8]), long.Parse(c[9]), double.Parse(c[10], CultureInfo.InvariantCulture)));
        }
        return res;
    }

    // ------------------------------------------------------------ estimate

    /// Visit shares pi_s over `range` from the bank's visits (all bots' banks agree up to noise).
    public static (Dictionary<string, double> pi, int visits) shares(Bank bank, string range)
    {
        var n = new Dictionary<string, int>();
        int total = 0;
        foreach (var r in bank.runs)
            foreach (var v in r.visits)
                if (in_range(v.key, range))
                {
                    n[v.key] = n.GetValueOrDefault(v.key) + 1;
                    total++;
                }
        return (n.ToDictionary(kv => kv.Key, kv => kv.Value / (double)Math.Max(1, total)), total);
    }

    public sealed class Cell
    {
        public string key;
        public double pi;
        public int n, d;
        public double pts, pts2, ms;
        public bool imputed;
        public double p => n == 0 ? 0 : d / (double)n;
        public double l => n == 0 ? 0 : pts / n;
        public double cost => n == 0 ? 0 : ms / n;
    }

    public sealed class Est
    {
        public string bot = "", range = "";
        public double q, lo, hi, se, se_log;
        public double imputed_share;
        public int trials, deaths, visits;
        public double ms;
        public List<Cell> cells = new();
        /// Linearized per-trial values z = died - q * points / 100 by stratum (for paired covariances).
        public Dictionary<string, Dictionary<(long, long, long), double>> z = new();

        public JsonObject json()
        {
            var top = cells.Where(c => c.d > 0).OrderByDescending(c => c.pi * c.p).Take(12)
                .Select(c => (JsonNode)new JsonObject
                {
                    ["stratum"] = c.key, ["share"] = Math.Round(c.pi, 4), ["trials"] = c.n, ["deaths"] = c.d,
                    ["p"] = Math.Round(c.p, 4), ["of_rate"] = Math.Round(c.pi * c.p / Math.Max(1e-12, cells.Sum(x => x.pi * x.p)), 3),
                }).ToArray();
            return new JsonObject
            {
                ["bot"] = bot, ["range"] = range, ["per100"] = Math.Round(q, 4), ["lo"] = Math.Round(lo, 4), ["hi"] = Math.Round(hi, 4),
                ["rel_halfwidth"] = Math.Round(1.96 * se_log, 3), ["trials"] = trials, ["deaths"] = deaths,
                ["cpu_s"] = Math.Round(ms / 1000, 1), ["strata"] = cells.Count(c => c.n > 0), ["imputed_share"] = Math.Round(imputed_share, 4),
                ["bank_visits"] = visits, ["killers"] = new JsonArray(top),
            };
        }

        public string text() =>
            $"{bot,-28} {range,-8} {q:F4} [{lo:F4}, {hi:F4}] per 100  (+-{100 * 1.96 * se_log:F0}%, {trials} trials, {deaths} deaths, " +
            $"{ms / 1000:F0} CPU s, imputed {100 * imputed_share:F1}% of visits)";
    }

    /// Q with its interval from `trials` (one bot, kind "room") and the bank's shares.
    /// `prior`: per-stratum p for strata the bot has no trials in (null = the trials' pooled p).
    public static Est estimate(Bank bank, IEnumerable<Trial> trials, string range, Dictionary<string, (double p, double l)> prior = null)
    {
        var (pi, visits) = shares(bank, range);
        var by = trials.Where(t => t.kind == "room" && !t.censored && in_range(t.key, range)).GroupBy(t => t.key).ToDictionary(g => g.Key, g => g.ToList());
        var e = new Est { range = range, visits = visits, bot = trials.FirstOrDefault()?.bot ?? "" };
        int N = 0, D = 0;
        double pooled_p, pooled_l;
        {
            var all = by.Values.SelectMany(x => x).ToList();
            N = all.Count;
            D = all.Count(t => t.died);
            pooled_p = (D + 0.5) / (N + 1.0);
            pooled_l = all.Count > 0 ? all.Average(t => (double)t.points) : SimConfig.POINTS_PER_ROOM;
        }
        foreach (var (key, share) in pi)
        {
            var c = new Cell { key = key, pi = share };
            if (by.TryGetValue(key, out var l))
            {
                c.n = l.Count;
                c.d = l.Count(t => t.died);
                c.pts = l.Sum(t => (double)t.points);
                c.pts2 = l.Sum(t => (double)t.points * t.points);
                c.ms = l.Sum(t => t.ms);
            }
            e.cells.Add(c);
        }
        double num = 0, den = 0;
        foreach (var c in e.cells)
        {
            double p = c.p, l = c.l;
            if (c.n == 0)
            {
                c.imputed = true;
                e.imputed_share += c.pi;
                (p, l) = prior != null && prior.TryGetValue(c.key, out var pr) ? pr : (pooled_p, pooled_l);
            }
            num += c.pi * p;
            den += c.pi * l;
        }
        double qpt = num / Math.Max(1e-12, den);
        double p0 = (D + 0.5) / (N + 1.0);
        // Delta method: Q - q ~ sum_s pi_s (p_s - q l_s) / den, plus the error in pi itself.
        double var = 0, var_pi = 0;
        foreach (var c in e.cells)
        {
            if (c.n == 0)
            {
                // Imputed from the bank (another bot's visits, about pi * visits of them): its error counts too.
                var (pp, _) = prior != null && prior.TryGetValue(c.key, out var pr2) ? pr2 : (pooled_p, pooled_l);
                double nb = Math.Max(1, c.pi * visits);
                double pb = (pp * nb + SHRINK * p0) / (nb + SHRINK);
                var += c.pi * c.pi * pb * (1 - pb) / nb;
                continue;
            }
            // Shrunk toward the pooled rate (2 pseudo-visits): a stratum with no deaths yet is
            // not certain, but 118 strata must not add 59 phantom deaths either.
            double pt = (c.d + SHRINK * p0) / (c.n + SHRINK);
            double mean_pts = c.l;
            double var_pts = c.n > 1 ? Math.Max(0, (c.pts2 - c.n * mean_pts * mean_pts) / (c.n - 1)) : 0;
            // died and points are tied (a death ends the visit early): cov from the data.
            var l = by[c.key];
            double cov = c.n > 1 ? l.Sum(t => ((t.died ? 1 : 0) - c.p) * (t.points - mean_pts)) / (c.n - 1) : 0;
            double vz = pt * (1 - pt) + qpt * qpt * var_pts - 2 * qpt * cov;
            var += c.pi * c.pi * Math.Max(vz, pt * (1 - pt) * 0.25) / c.n;
            double g = c.p - qpt * c.l;
            var_pi += c.pi * g * g;
            var zs = new Dictionary<(long, long, long), double>();
            foreach (var t in l) zs[(t.seed, t.tick, t.k)] = (t.died ? 1 : 0) - qpt * t.points;
            e.z[c.key] = zs;
        }
        var += var_pi / Math.Max(1, visits);
        double se_pt = Math.Sqrt(var) / Math.Max(1e-12, den);
        e.q = 100 * qpt;
        e.se = 100 * se_pt;
        e.se_log = qpt > 0 ? se_pt / qpt : double.PositiveInfinity;
        e.lo = e.q * Math.Exp(-1.96 * e.se_log);
        e.hi = e.q * Math.Exp(1.96 * e.se_log);
        e.trials = N;
        e.deaths = D;
        e.ms = by.Values.SelectMany(x => x).Sum(t => t.ms);
        return e;
    }

    /// b vs a: rate ratio b/a with its interval. Trials both bots played from
    /// the same (seed, tick, k) are paired: their covariance is used.
    public sealed record Ratio(double r, double lo, double hi, double z, double se_log, double rho, int paired);

    public static Ratio ratio(Est a, Est b, Bank bank)
    {
        double ra = a.q / 100, rb = b.q / 100;
        double den_a = a.cells.Sum(c => c.pi * (c.n > 0 ? c.l : 0)), den_b = b.cells.Sum(c => c.pi * (c.n > 0 ? c.l : 0));
        double cov = 0, sx = 0, sy = 0, sxy = 0;
        int paired = 0;
        foreach (var ca in a.cells)
        {
            var cb = b.cells.FirstOrDefault(c => c.key == ca.key);
            if (cb == null || !a.z.TryGetValue(ca.key, out var za) || !b.z.TryGetValue(ca.key, out var zb)) continue;
            var both = za.Keys.Where(zb.ContainsKey).ToList();
            if (both.Count < 2) continue;
            double ma = both.Average(k => za[k]), mb = both.Average(k => zb[k]);
            double cv = both.Sum(k => (za[k] - ma) * (zb[k] - mb)) / (both.Count - 1);
            cov += ca.pi * ca.pi * cv * both.Count / ((double)ca.n * cb.n);
            sx += both.Sum(k => (za[k] - ma) * (za[k] - ma));
            sy += both.Sum(k => (zb[k] - mb) * (zb[k] - mb));
            sxy += both.Sum(k => (za[k] - ma) * (zb[k] - mb));
            paired += both.Count;
        }
        double cov_log = ra > 0 && rb > 0 ? cov / (den_a * den_b * ra * rb) : 0;
        double v = a.se_log * a.se_log + b.se_log * b.se_log - 2 * cov_log;
        v = Math.Max(v, 1e-12);
        double se = Math.Sqrt(v), lr = Math.Log(rb / ra);
        double rho = sx > 0 && sy > 0 ? sxy / Math.Sqrt(sx * sy) : 0;
        return new Ratio(rb / ra, Math.Exp(lr - 1.96 * se), Math.Exp(lr + 1.96 * se), lr / se, se, rho, paired);
    }

    // ---------------------------------------------------------- allocation

    /// The next `budget_ms` of trials: Neyman allocation, greedily, by the
    /// variance each trial removes per CPU ms. `arms`: the trials so far of
    /// each bot being measured together (paired: the same jobs for each).
    /// `prior` (the bank's p, l and cost per stratum) stands in for strata a bot has no trials in yet.
    public static Dictionary<string, int> allocate(Bank bank, string range, List<List<Trial>> arms, double budget_ms,
        Dictionary<string, (double p, double l, double ms)> prior)
    {
        var (pi, _) = shares(bank, range);
        var plan = new Dictionary<string, int>();
        var keys = pi.Where(kv => kv.Value >= MIN_SHARE).Select(kv => kv.Key).ToList();
        if (keys.Count == 0) return plan;
        // Per stratum and arm: trials so far, smoothed p (toward the prior), cost.
        var n = new Dictionary<string, int[]>();
        var v = new Dictionary<string, double>();
        var cost = new Dictionary<string, double>();
        double q_prior = 0, l_prior = 0;
        foreach (var k in keys)
        {
            var pr = prior.GetValueOrDefault(k, (0.01, SimConfig.POINTS_PER_ROOM, 1000.0));
            q_prior += pi[k] * pr.p;
            l_prior += pi[k] * pr.l;
        }
        double q = q_prior / Math.Max(1e-9, l_prior);
        foreach (var k in keys)
        {
            var pr = prior.GetValueOrDefault(k, (0.01, SimConfig.POINTS_PER_ROOM, 1000.0));
            var counts = new int[arms.Count];
            double vs = 0, cs = 0;
            for (int a = 0; a < arms.Count; a++)
            {
                var mine = arms[a].Where(t => t.key == k && t.kind == "room" && !t.censored).ToList();
                counts[a] = mine.Count;
                const double M = 4;
                double p = (mine.Count(t => t.died) + M * pr.p) / (mine.Count + M);
                // Relative variance (log scale), so arms with different rates weigh alike.
                vs += p * (1 - p) / Math.Max(1e-9, q * q);
                cs += mine.Count > 0 ? mine.Average(t => t.ms) : pr.ms;
            }
            n[k] = counts;
            v[k] = vs;
            cost[k] = Math.Max(1, cs);
        }
        // Greedy: one trial (in every arm) at a time to the stratum that gains most per ms.
        var pq = new PriorityQueue<string, double>();
        double gain(string k)
        {
            int m = n[k].Min() + plan.GetValueOrDefault(k);
            double g = pi[k] * pi[k] * v[k] * (m == 0 ? 1e6 : 1.0 / m - 1.0 / (m + 1));
            if (m < MIN_TRIALS) g *= 1e3;
            return g / cost[k];
        }
        foreach (var k in keys) pq.Enqueue(k, -gain(k));
        double spent = 0;
        while (spent < budget_ms && pq.Count > 0)
        {
            var k = pq.Dequeue();
            plan[k] = plan.GetValueOrDefault(k) + 1;
            spent += cost[k];
            pq.Enqueue(k, -gain(k));
        }
        return plan;
    }

    /// The bank's own p, l and cost per stratum (a prior for allocation and imputation).
    public static Dictionary<string, (double p, double l, double ms)> bank_prior(Bank bank)
    {
        var res = new Dictionary<string, (double, double, double)>();
        var all = bank.runs.SelectMany(r => r.visits).Where(v => !v.censored).ToList();
        double p0 = (all.Count(v => v.died) + 0.5) / (all.Count + 1.0);
        foreach (var g in all.GroupBy(v => v.key))
        {
            int n = g.Count(), d = g.Count(v => v.died);
            res[g.Key] = ((d + SHRINK * p0) / (n + SHRINK), g.Average(v => (double)v.points), g.Average(v => v.ms));
        }
        return res;
    }

    /// Turns a plan (trials per stratum) into jobs from the pools, growing them when short.
    public static List<(int run, long tick, bool tap, long k)> jobs(Pools pools, Dictionary<string, int> plan, int threads, Random order)
    {
        var res = new List<(int, long, bool, long)>();
        for (int round = 0; round < 6; round++)
        {
            var short_ = new List<string>();
            foreach (var (key, want) in plan.ToList())
            {
                int got = 0;
                while (got < want && pools.take(key, order) is { } e)
                {
                    res.Add(e);
                    got++;
                }
                if (got < want) short_.Add(key);
                plan[key] = want - got;
            }
            if (short_.Count == 0) break;
            pools.grow(Math.Max(4, pools.tried_k), threads);
        }
        return res;
    }
}
