using System.Diagnostics;
using System.Text.Json.Nodes;

namespace FastSim.Rl;

/// Learning from the teacher (DAgger, docs/RL_BOT.md). The policy plays
/// runs on its own; for every death the teacher rewinds to the last tick
/// where the run could still be saved and labels the move that saves it
/// (and a few ticks before it where only one move is safe). The policy
/// learns those labels, plus some of its own moves as anchors, by gradient
/// descent on the cross-entropy. The labels gather over the iterations.
/// At play time the policy is on its own: no teacher, no look-ahead.
public sealed class Dagger
{
    public int threads = 4;
    public int runs = 32;
    public long cap = 20000;
    public double practice = 0.5;
    /// Ticks a saving move must keep the bird alive.
    public long horizon = 90;
    /// How far back from a death the teacher looks for the deciding tick.
    public long back = 240;
    /// Extra ticks labelled before the deciding one (every EXTRA_STEP ticks).
    public int extra = 20;
    public const int EXTRA_STEP = 2;
    public int anchor_every = 90;
    public float anchor_weight = 0.05f;
    public int max_data = 200_000;
    public int batches = 60;
    public int batch = 512;
    public float lr = 3e-4f;
    public int eval_every = 5;
    public int eval_seeds = 64;
    public long eval_cap = 54000;
    public const long TRAIN_SEED = 30_000_000;

    readonly string dir;
    Mlp net;
    float[] w;
    Adam opt;
    int iter;
    long next_seed = TRAIN_SEED;
    double best = -1;
    readonly List<(sbyte[] x, byte y, float wt)> data = new();
    int data_head;

    public Dagger(string dir) => this.dir = dir;

    string policy_path => Path.Combine(dir, "policy.json");
    string state_path => Path.Combine(dir, "teach_state.json");

    record struct Run(long seed, long room, byte[] taps, bool dead);

    public int run(bool resume, double minutes)
    {
        net = new Mlp(Policy.SIZES);
        if (resume && File.Exists(state_path))
        {
            var o = JsonNode.Parse(File.ReadAllText(state_path)).AsObject();
            iter = (int)o["iteration"];
            next_seed = (long)o["next_seed"];
            best = (double)o["best"];
            w = o["weights"].AsArray().Select(x => (float)x).ToArray();
            opt = new Adam(w.Length, lr) { m = floats(o["m"]), v = floats(o["v"]), t = (long)o["t"] };
        }
        else
        {
            // Start from the trained policy (PPO) so the teacher fixes its mistakes.
            var start = Policy.load(policy_path);
            if (!start.net.sizes.SequenceEqual(Policy.SIZES)) throw new InvalidDataException("policy.json has other network sizes");
            w = (float[])start.w.Clone();
            opt = new Adam(w.Length, lr);
            var meta = JsonNode.Parse(File.ReadAllText(policy_path)).AsObject();
            best = meta["eval_median"] != null ? (double)meta["eval_median"] + (double)meta["eval_mean"] / 1000.0 : -1;
        }
        opt.lr = lr;
        Console.WriteLine($"rlbot teach: {w.Length} weights, {runs} runs per iteration (cap {cap}), horizon {horizon}, from iteration {iter}, best so far {best:F1}");
        var clock = Stopwatch.StartNew();
        var par = new ParallelOptions { MaxDegreeOfParallelism = threads };
        while (clock.Elapsed.TotalMinutes < minutes)
        {
            var ic = Stopwatch.StartNew();
            var pol = new Policy((float[])w.Clone(), Policy.SIZES);
            long first = next_seed;
            next_seed += runs;
            var found = new List<(sbyte[] x, byte y, float wt)>[runs];
            var pts = new long[runs];
            var deaths = new int[runs];
            var labels = new int[runs];
            Parallel.For(0, runs, par, r =>
            {
                long seed = first + r;
                var rng = new Random((int)(seed % int.MaxValue));
                long room = rng.NextDouble() < practice ? Ppo.rooms()[rng.Next(Ppo.rooms().Count)] : -1;
                var mine = new List<(sbyte[] x, byte y, float wt)>();
                var run = play(pol, seed, room, mine, out pts[r]);
                if (run.dead)
                {
                    deaths[r] = 1;
                    labels[r] = teach(pol, run, mine);
                }
                found[r] = mine;
            });
            int added = 0;
            foreach (var list in found)
                foreach (var d in list)
                {
                    add(d);
                    added++;
                }
            double play_s = ic.Elapsed.TotalSeconds;
            double loss = learn(par);
            double acc = teacher_accuracy();
            iter++;
            string line = $"iter {iter,4}: {runs} runs, {deaths.Sum()} died, points/run {pts.Average(),6:F1}, {labels.Sum()} teacher labels, {added - labels.Sum()} anchors, data {data.Count}, loss {loss:F3}, teacher labels right {acc:P0}  {play_s:F0}+{ic.Elapsed.TotalSeconds - play_s:F0} s";
            if (iter % eval_every == 0)
            {
                var (median, mean) = evaluate(par);
                line += $"  | eval median {median} mean {mean:F1}";
                double score = median + mean / 1000.0;
                if (score > best)
                {
                    best = score;
                    var extra_ = new JsonObject { ["algorithm"] = "ppo+teacher", ["iteration"] = iter, ["eval_median"] = median, ["eval_mean"] = Math.Round(mean, 2) };
                    File.WriteAllText(policy_path, Policy.to_json(w, Policy.SIZES, extra_).ToJsonString(Policy.PRETTY));
                    line += "  (saved)";
                }
            }
            Console.WriteLine(line);
            save();
        }
        Console.WriteLine($"rlbot teach: stopped at iteration {iter} after {clock.Elapsed.TotalMinutes:F1} min (resume with -Resume)");
        return 0;
    }

    /// The policy plays one run on its own; every anchor_every ticks its own
    /// move is kept as an anchor.
    Run play(Policy pol, long seed, long room, List<(sbyte[] x, byte y, float wt)> anchors, out long points)
    {
        var sim = new GameSim(seed, Seasons.NONE, room);
        long start = sim.state.score;
        var eyes = new Player(null, Handicap.NONE, seed);
        var acts = pol.net.scratch();
        var taps = new List<byte>();
        while (!sim.is_over() && taps.Count < cap)
        {
            var x = eyes.observe(sim);
            bool tap = !sim.state.started || pol.act(x, acts) > 0f;
            if (sim.state.started && taps.Count % anchor_every == 0) anchors.Add((pack(x), tap ? (byte)1 : (byte)0, anchor_weight));
            taps.Add(tap ? (byte)1 : (byte)0);
            sim.step(tap);
        }
        points = sim.state.score - start;
        return new Run(seed, room, taps.ToArray(), sim.is_over());
    }

    /// The sim before tick `t` of a run and what the bird saw then.
    static (GameSim sim, float[] x) replay(Run run, long t)
    {
        var sim = new GameSim(run.seed, Seasons.NONE, run.room);
        long from = Math.Max(0, t - Observer.MOTION);
        for (long i = 0; i < from; i++) sim.step(run.taps[i] != 0);
        var eyes = new Player(null, Handicap.NONE, run.seed);
        for (long i = from; i < t; i++)
        {
            eyes.observe(sim);
            sim.step(run.taps[i] != 0);
        }
        var x = (float[])eyes.observe(sim).Clone();
        return (sim, x);
    }

    /// Finds the deciding tick before the death and labels it, and the
    /// ticks before it where only one move is safe. Returns the labels added.
    int teach(Policy pol, Run run, List<(sbyte[] x, byte y, float wt)> out_)
    {
        long T = run.taps.Length;
        // Savable (some move lives `horizon` more ticks) holds up to some tick
        // and not after it, along the run: find the last savable tick.
        bool savable(long t, out (bool tap, bool wait) moves, out float[] x)
        {
            var (sim, obs) = replay(run, t);
            x = obs;
            moves = sim.state.started ? Teacher.safe_moves(sim, horizon) : (true, false);
            return moves.tap || moves.wait;
        }
        long lo = Math.Max(1, T - back), hi = T;
        if (!savable(lo, out var m_lo, out var x_lo)) return 0;
        var best_moves = m_lo;
        var best_x = x_lo;
        while (hi - lo > 1)
        {
            long mid = (lo + hi) / 2;
            if (savable(mid, out var mv, out var mx))
            {
                lo = mid;
                best_moves = mv;
                best_x = mx;
            }
            else hi = mid;
        }
        int n = 0;
        // At the last savable tick the run's own move was the wrong one.
        if (best_moves.tap != best_moves.wait)
        {
            out_.Add((pack(best_x), best_moves.tap ? (byte)1 : (byte)0, 1f));
            n++;
        }
        for (int j = 1; j <= extra; j++)
        {
            long t = lo - j * EXTRA_STEP;
            if (t < 1) break;
            savable(t, out var mv, out var mx);
            if (mv.tap == mv.wait) continue;
            out_.Add((pack(mx), mv.tap ? (byte)1 : (byte)0, 1f));
            n++;
        }
        return n;
    }

    void add((sbyte[] x, byte y, float wt) d)
    {
        if (data.Count < max_data) data.Add(d);
        else
        {
            data[data_head] = d;
            data_head = (data_head + 1) % max_data;
        }
    }

    /// Cross-entropy on random minibatches of the gathered labels.
    double learn(ParallelOptions par)
    {
        if (data.Count < batch) return 0;
        var rng = new Random(iter * 31 + 5);
        int parts = threads;
        var grads = new float[parts][];
        for (int q = 0; q < parts; q++) grads[q] = new float[w.Length];
        double total = 0;
        for (int b = 0; b < batches; b++)
        {
            var pick = new int[batch];
            for (int i = 0; i < batch; i++) pick[i] = rng.Next(data.Count);
            var losses = new double[parts];
            float wsum = 0;
            foreach (int i in pick) wsum += data[i].wt;
            Parallel.For(0, parts, par, q =>
            {
                Array.Clear(grads[q]);
                var acts = net.scratch();
                var deltas = net.delta_scratch();
                var x = new float[Observer.INPUTS];
                int per = batch / parts;
                for (int s = q * per; s < (q + 1) * per; s++)
                {
                    var d = data[pick[s]];
                    unpack(d.x, x);
                    float z = net.forward(w, x, acts);
                    float p = 1f / (1f + MathF.Exp(-z));
                    float y = d.y;
                    losses[q] += d.wt * -(y * MathF.Log(p + 1e-7f) + (1 - y) * MathF.Log(1 - p + 1e-7f));
                    net.backward(w, acts, d.wt * (p - y) / wsum, grads[q], deltas);
                }
            });
            for (int q = 1; q < parts; q++)
                for (int i = 0; i < w.Length; i++) grads[0][i] += grads[q][i];
            opt.step(w, grads[0], 1f);
            total += losses.Sum() / wsum;
        }
        return total / batches;
    }

    /// Share of (up to 4,000) gathered teacher labels the policy now gets right.
    double teacher_accuracy()
    {
        var acts = net.scratch();
        var x = new float[Observer.INPUTS];
        int n = 0, right = 0;
        for (int i = data.Count - 1; i >= 0 && n < 4000; i--)
        {
            var d = data[i];
            if (d.wt < 1f) continue;
            unpack(d.x, x);
            bool tap = net.forward(w, x, acts) > 0f;
            n++;
            if (tap == (d.y == 1)) right++;
        }
        return n == 0 ? 0 : (double)right / n;
    }

    (long median, double mean) evaluate(ParallelOptions par)
    {
        var pol = new Policy((float[])w.Clone(), Policy.SIZES);
        var pts = new long[eval_seeds];
        Parallel.For(0, eval_seeds, par, i =>
            pts[i] = Player.play(pol, Handicap.NONE, new GameSim(Ppo.EVAL_SEED + i), eval_cap).points);
        var sorted = pts.OrderBy(x => x).ToArray();
        return (sorted[sorted.Length / 2], pts.Average());
    }

    // Observations are kept as sbytes (-2..2 in steps of 1/63) to hold many labels.
    static sbyte[] pack(float[] x)
    {
        var o = new sbyte[x.Length];
        for (int i = 0; i < x.Length; i++) o[i] = (sbyte)Math.Clamp(MathF.Round(x[i] * 63f), -127, 127);
        return o;
    }

    static void unpack(sbyte[] s, float[] x)
    {
        for (int i = 0; i < s.Length; i++) x[i] = s[i] / 63f;
    }

    void save()
    {
        var o = new JsonObject
        {
            ["algorithm"] = "teacher",
            ["iteration"] = iter,
            ["next_seed"] = next_seed,
            ["best"] = best,
            ["weights"] = arr(w), ["m"] = arr(opt.m), ["v"] = arr(opt.v), ["t"] = opt.t,
        };
        string tmp = state_path + ".tmp";
        File.WriteAllText(tmp, o.ToJsonString());
        File.Move(tmp, state_path, true);
    }

    static float[] floats(JsonNode n) => n.AsArray().Select(x => (float)x).ToArray();
    static JsonArray arr(float[] xs) => new(xs.Select(x => (JsonNode)x).ToArray());
}
