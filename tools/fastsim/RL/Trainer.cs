using System.Diagnostics;
using System.Text.Json.Nodes;

namespace FastSim.Rl;

/// Evolution strategies (antithetic pairs, centred ranks, Adam) on the policy
/// weights. Every candidate of a generation plays the same runs, so the
/// ranking compares weights, not luck. Resumable: the state is saved after
/// every generation and training stops after `minutes`.
public sealed class Trainer
{
    public int pairs = 48;
    public float sigma = 0.04f;
    public float lr = 0.015f;
    public float decay = 0.002f;
    public int full_runs = 3;
    public int practice_runs = 3;
    public long cap = 3600;
    public int threads = 4;
    public int eval_every = 10;
    public int eval_seeds = 96;
    public long eval_cap = 18000;
    /// Seeds: training 10,000,000+, evaluation 2,000,000+ (measure uses 1+, calibrate 500,000+).
    public const long TRAIN_SEED = 10_000_000, EVAL_SEED = 2_000_000;

    float[] theta, m, v;
    int gen;
    double best = -1;
    readonly string dir;
    static List<long> _rooms;

    public Trainer(string dir) => this.dir = dir;

    string state_path => Path.Combine(dir, "train_state.json");
    string policy_path => Path.Combine(dir, "policy.json");

    /// Rooms a practice run can start in: every room but the open start room.
    public static List<long> rooms()
    {
        if (_rooms != null) return _rooms;
        var all = RoomCatalog.all();
        _rooms = new List<long>();
        for (int i = 0; i < all.Count; i++)
            if (i != RoomCatalog.first_index()) _rooms.Add(i);
        return _rooms;
    }

    public int run(bool resume, double minutes, int init_seed)
    {
        Directory.CreateDirectory(dir);
        if (resume && File.Exists(state_path)) load();
        else
        {
            theta = Policy.init(init_seed);
            m = new float[theta.Length];
            v = new float[theta.Length];
            gen = 0;
            best = -1;
        }
        Console.WriteLine($"rlbot train: {theta.Length} weights, {pairs} pairs x {full_runs + practice_runs} runs, cap {cap} ticks, {threads} threads, from generation {gen}");
        var clock = Stopwatch.StartNew();
        var par = new ParallelOptions { MaxDegreeOfParallelism = threads };
        int n = theta.Length;
        var eps = new float[pairs][];
        for (int p = 0; p < pairs; p++) eps[p] = new float[n];
        var fit = new double[2 * pairs];
        var ticks = new long[2 * pairs];
        while (clock.Elapsed.TotalMinutes < minutes)
        {
            var gclock = Stopwatch.StartNew();
            var rng = new Random(1000 + gen);
            for (int p = 0; p < pairs; p++)
                for (int i = 0; i < n; i++) eps[p][i] = (float)Policy.Gauss(rng);
            var runs = new List<(long seed, long room)>();
            for (int k = 0; k < full_runs; k++) runs.Add((TRAIN_SEED + gen * 64L + k, -1));
            for (int k = 0; k < practice_runs; k++)
                runs.Add((TRAIN_SEED + gen * 64L + 32 + k, rooms()[rng.Next(rooms().Count)]));
            Parallel.For(0, 2 * pairs, par, c =>
            {
                var w = new float[n];
                float sign = c % 2 == 0 ? 1f : -1f;
                var e = eps[c / 2];
                for (int i = 0; i < n; i++) w[i] = theta[i] + sign * sigma * e[i];
                var pol = new Policy(w);
                double f = 0;
                long t = 0;
                foreach (var (seed, room) in runs)
                {
                    var r = Player.play(pol, Handicap.NONE, new GameSim(seed, Seasons.NONE, room), cap);
                    // Points, with a little for time alive so early generations have a slope.
                    f += r.points + r.ticks / 1200.0;
                    t += r.ticks;
                }
                fit[c] = f / runs.Count;
                ticks[c] = t;
            });
            // Centred ranks in -0.5..0.5.
            var order = Enumerable.Range(0, 2 * pairs).OrderBy(c => fit[c]).ToArray();
            var u = new double[2 * pairs];
            for (int r = 0; r < order.Length; r++) u[order[r]] = (double)r / (order.Length - 1) - 0.5;
            var grad = new float[n];
            for (int p = 0; p < pairs; p++)
            {
                float d = (float)(u[2 * p] - u[2 * p + 1]);
                var e = eps[p];
                for (int i = 0; i < n; i++) grad[i] += d * e[i];
            }
            gen++;
            const float b1 = 0.9f, b2 = 0.999f;
            float c1 = 1f - MathF.Pow(b1, gen), c2 = 1f - MathF.Pow(b2, gen);
            for (int i = 0; i < n; i++)
            {
                float g = grad[i] / (2 * pairs * sigma) - decay * theta[i];
                m[i] = b1 * m[i] + (1 - b1) * g;
                v[i] = b2 * v[i] + (1 - b2) * g * g;
                theta[i] += lr * (m[i] / c1) / (MathF.Sqrt(v[i] / c2) + 1e-8f);
            }
            string line = $"gen {gen,5}: mean {fit.Average(),7:F2}  best {fit.Max(),7:F2}  ticks/run {ticks.Average() / runs.Count,6:F0}  {gclock.Elapsed.TotalSeconds,5:F1} s";
            if (gen % eval_every == 0)
            {
                var (median, mean) = evaluate(new Policy((float[])theta.Clone()), par);
                line += $"  | eval median {median} mean {mean:F1}";
                double score = median + mean / 1000.0;
                if (score > best)
                {
                    best = score;
                    var extra = new JsonObject { ["generation"] = gen, ["eval_median"] = median, ["eval_mean"] = Math.Round(mean, 2) };
                    File.WriteAllText(policy_path, Policy.to_json(theta, extra).ToJsonString(Policy.PRETTY));
                    line += "  (saved)";
                }
            }
            Console.WriteLine(line);
            save();
        }
        Console.WriteLine($"rlbot train: stopped at generation {gen} after {clock.Elapsed.TotalMinutes:F1} min (resume with -Resume)");
        return 0;
    }

    (long median, double mean) evaluate(Policy pol, ParallelOptions par)
    {
        var pts = new long[eval_seeds];
        Parallel.For(0, eval_seeds, par, i =>
            pts[i] = Player.play(pol, Handicap.NONE, new GameSim(EVAL_SEED + i), eval_cap).points);
        var sorted = pts.OrderBy(x => x).ToArray();
        return (sorted[sorted.Length / 2], pts.Average());
    }

    void save()
    {
        var o = new JsonObject
        {
            ["generation"] = gen,
            ["best"] = best,
            ["theta"] = arr(theta),
            ["m"] = arr(m),
            ["v"] = arr(v),
        };
        string tmp = state_path + ".tmp";
        File.WriteAllText(tmp, o.ToJsonString());
        File.Move(tmp, state_path, true);
    }

    void load()
    {
        var o = JsonNode.Parse(File.ReadAllText(state_path)).AsObject();
        gen = (int)o["generation"];
        best = (double)o["best"];
        theta = o["theta"].AsArray().Select(x => (float)x).ToArray();
        m = o["m"].AsArray().Select(x => (float)x).ToArray();
        v = o["v"].AsArray().Select(x => (float)x).ToArray();
        if (theta.Length != Policy.count()) throw new InvalidDataException("train_state.json: network size changed, start fresh (no -Resume)");
    }

    static JsonArray arr(float[] xs) => new(xs.Select(x => (JsonNode)x).ToArray());
}
