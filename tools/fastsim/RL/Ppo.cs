using System.Diagnostics;
using System.Text.Json.Nodes;

namespace FastSim.Rl;

/// PPO (clipped policy gradient with a learned value, GAE) on FastSim
/// (docs/RL_BOT.md). Many runs play side by side; every tick is a sample, so
/// each tap is credited or blamed on its own, not only the run's total.
/// Resumable: the state is saved after every iteration and training stops
/// after `minutes`.
public sealed class Ppo
{
    public int envs = 32;
    public int steps = 512;
    public int epochs = 4;
    public int minibatch = 2048;
    public float lr = 3e-4f;
    public float vlr = 1e-3f;
    public float clip = 0.2f;
    public float entropy = 0.003f;
    public float gamma = 0.995f;
    public float lambda = 0.95f;
    /// Reward: +1 per point, -DEATH on death.
    public float death = 2f;
    /// Share of runs that start in a random room (practice) instead of the start room.
    public double practice = 0.5;
    /// Longest training run (ticks); then it starts over (the value is bootstrapped).
    public long cap = 30000;
    public int threads = 4;
    public int eval_every = 10;
    public int eval_seeds = 64;
    public long eval_cap = 54000;
    /// Seeds: training 10,000,000+, evaluation 2,000,000+ (measure uses 1+, calibrate 500,000+).
    public const long TRAIN_SEED = 10_000_000, EVAL_SEED = 2_000_000;
    public static readonly int[] VALUE_SIZES = { Observer.INPUTS, 64, 64, 1 };

    readonly string dir;
    Mlp pnet, vnet;
    float[] pw, vw;
    Adam popt, vopt;
    int iter;
    long next_seed;
    double best = -1;
    Env[] env;
    static List<long> _rooms;

    public Ppo(string dir) => this.dir = dir;

    string state_path => Path.Combine(dir, "train_state.json");
    string policy_path => Path.Combine(dir, "policy.json");

    /// Rooms a practice run can start in: every room but the open start room.
    public static List<long> rooms()
    {
        if (_rooms != null) return _rooms;
        // Filled first, then published: worker threads may call this at once.
        var all = RoomCatalog.all();
        var list = new List<long>();
        for (int i = 0; i < all.Count; i++)
            if (i != RoomCatalog.first_index()) list.Add(i);
        _rooms = list;
        return _rooms;
    }

    /// One training run in progress.
    sealed class Env
    {
        public GameSim sim;
        public Player eyes;
        public Random rng;
        public long ticks;
        public long points;
    }

    void reset(Env e)
    {
        long seed;
        lock (this) seed = next_seed++;
        long room = e.rng.NextDouble() < practice ? rooms()[e.rng.Next(rooms().Count)] : -1;
        e.sim = new GameSim(seed, Seasons.NONE, room);
        e.eyes = new Player(null, Handicap.NONE, seed);
        e.ticks = 0;
        // The run starts on the first tap; no sample for it.
        e.eyes.observe(e.sim);
        e.sim.step(true);
    }

    public int run(bool resume, double minutes, int init_seed)
    {
        Directory.CreateDirectory(dir);
        pnet = new Mlp(Policy.SIZES);
        vnet = new Mlp(VALUE_SIZES);
        if (resume && File.Exists(state_path)) load();
        else
        {
            pw = pnet.init(init_seed);
            // Start tapping about one tick in ten (p = 0.08), roughly a hover.
            pw[^1] = -2.5f;
            vw = vnet.init(init_seed + 1, 1f);
            popt = new Adam(pw.Length, lr);
            vopt = new Adam(vw.Length, vlr);
            iter = 0;
            next_seed = TRAIN_SEED;
        }
        popt.lr = lr;
        vopt.lr = vlr;
        env = new Env[envs];
        for (int i = 0; i < envs; i++)
        {
            env[i] = new Env { rng = new Random(init_seed * 7919 + iter * 131 + i) };
            reset(env[i]);
        }
        Console.WriteLine($"rlbot train (PPO): policy {pw.Length} + value {vw.Length} weights, {envs} runs x {steps} ticks per iteration, {threads} threads, from iteration {iter}");
        var clock = Stopwatch.StartNew();
        var par = new ParallelOptions { MaxDegreeOfParallelism = threads };
        int N = envs * steps, D = Observer.INPUTS;
        var obs = new float[N * D];
        var act = new byte[N];
        var logp = new float[N];
        var val = new float[N];
        var rew = new float[N];
        var done = new byte[N];   // 1 dead, 2 cut at the cap (bootstrap), 0 going on
        var boot = new float[N];  // value after a cut
        var last_v = new float[envs];
        var adv = new float[N];
        var ret = new float[N];
        while (clock.Elapsed.TotalMinutes < minutes)
        {
            var it_clock = Stopwatch.StartNew();
            long ep_count = 0, ep_points = 0, dead_count = 0;
            // 1. Play.
            Parallel.For(0, envs, par, i =>
            {
                var e = env[i];
                var pa = pnet.scratch();
                var va = vnet.scratch();
                long eps = 0, pts = 0, deaths = 0;
                for (int t = 0; t < steps; t++)
                {
                    int k = t * envs + i;
                    var x = e.eyes.observe(e.sim);
                    Array.Copy(x, 0, obs, k * D, D);
                    float z = pnet.forward(pw, x, pa);
                    float p = sigmoid(z);
                    bool tap = e.rng.NextDouble() < p;
                    act[k] = tap ? (byte)1 : (byte)0;
                    logp[k] = tap ? log_sig(z) : log_sig(-z);
                    val[k] = vnet.forward(vw, x, va);
                    long before = e.sim.state.score;
                    e.sim.step(tap);
                    e.ticks++;
                    float r = e.sim.state.score - before;
                    done[k] = 0;
                    if (e.sim.is_over())
                    {
                        r -= death;
                        done[k] = 1;
                    }
                    else if (e.ticks >= cap) done[k] = 2;
                    rew[k] = r;
                    if (done[k] != 0)
                    {
                        if (done[k] == 2)
                        {
                            var nx = e.eyes.observe(e.sim);
                            boot[k] = vnet.forward(vw, nx, va);
                        }
                        eps++;
                        deaths += done[k] == 1 ? 1 : 0;
                        pts += e.sim.state.score - (e.sim.is_practice() ? RoomCatalog.all()[(int)e.sim.practice_room].from_score : 0);
                        reset(e);
                    }
                }
                // The value where this batch stops, for the last GAE step.
                last_v[i] = vnet.forward(vw, peek(e), va);
                Interlocked.Add(ref ep_count, eps);
                Interlocked.Add(ref ep_points, pts);
                Interlocked.Add(ref dead_count, deaths);
            });
            double play_s = it_clock.Elapsed.TotalSeconds;
            // 2. Advantages (GAE), per run, backwards.
            for (int i = 0; i < envs; i++)
            {
                float next_v = last_v[i], gae = 0;
                for (int t = steps - 1; t >= 0; t--)
                {
                    int k = t * envs + i;
                    float nv = done[k] == 1 ? 0 : done[k] == 2 ? boot[k] : next_v;
                    float cont = done[k] != 0 ? 0 : 1;
                    float delta = rew[k] + gamma * nv - val[k];
                    gae = delta + gamma * lambda * cont * gae;
                    adv[k] = gae;
                    ret[k] = gae + val[k];
                    next_v = val[k];
                }
            }
            double mean = adv.Average(), sd = Math.Sqrt(adv.Select(a => (a - mean) * (a - mean)).Average()) + 1e-8;
            var nadv = adv.Select(a => (float)((a - mean) / sd)).ToArray();
            // 3. Learn: a few epochs of minibatches, gradients summed over threads.
            var order = Enumerable.Range(0, N).ToArray();
            var shuf = new Random(iter + 17);
            double clipped = 0, vloss = 0, ent = 0;
            int parts = threads;
            var pg = new float[parts][];
            var vg = new float[parts][];
            for (int q = 0; q < parts; q++)
            {
                pg[q] = new float[pw.Length];
                vg[q] = new float[vw.Length];
            }
            for (int ep = 0; ep < epochs; ep++)
            {
                for (int i = N - 1; i > 0; i--)
                {
                    int j = shuf.Next(i + 1);
                    (order[i], order[j]) = (order[j], order[i]);
                }
                for (int mb = 0; mb + minibatch <= N; mb += minibatch)
                {
                    var stats = new double[parts * 3];
                    Parallel.For(0, parts, par, q =>
                    {
                        Array.Clear(pg[q]);
                        Array.Clear(vg[q]);
                        var pa = pnet.scratch();
                        var pd = pnet.delta_scratch();
                        var va = vnet.scratch();
                        var vd = vnet.delta_scratch();
                        int per = minibatch / parts;
                        for (int s = mb + q * per; s < mb + (q + 1) * per; s++)
                        {
                            int k = order[s];
                            var x = new ReadOnlySpan<float>(obs, k * D, D);
                            float z = pnet.forward(pw, x, pa);
                            float p = sigmoid(z);
                            float a = act[k];
                            float lp = a > 0 ? log_sig(z) : log_sig(-z);
                            float ratio = MathF.Exp(lp - logp[k]);
                            float A = nadv[k];
                            // d(-min(r A, clip(r) A))/dz; zero where the clip holds.
                            bool held = (A > 0 && ratio > 1 + clip) || (A < 0 && ratio < 1 - clip);
                            float dz = held ? 0f : -A * ratio * (a - p);
                            if (held) stats[q * 3] += 1;
                            // Entropy bonus: -entropy * H, dH/dz = -z p (1-p).
                            dz += entropy * z * p * (1 - p);
                            stats[q * 3 + 2] += -(p * MathF.Log(p + 1e-8f) + (1 - p) * MathF.Log(1 - p + 1e-8f));
                            pnet.backward(pw, pa, dz / minibatch, pg[q], pd);
                            float v = vnet.forward(vw, x, va);
                            float dv = v - ret[k];
                            stats[q * 3 + 1] += dv * dv;
                            vnet.backward(vw, va, dv / minibatch, vg[q], vd);
                        }
                    });
                    for (int q = 1; q < parts; q++)
                    {
                        for (int i = 0; i < pw.Length; i++) pg[0][i] += pg[q][i];
                        for (int i = 0; i < vw.Length; i++) vg[0][i] += vg[q][i];
                    }
                    popt.step(pw, pg[0]);
                    vopt.step(vw, vg[0], 5f);
                    for (int q = 0; q < parts; q++)
                    {
                        clipped += stats[q * 3];
                        vloss += stats[q * 3 + 1];
                        ent += stats[q * 3 + 2];
                    }
                }
            }
            iter++;
            double seen = (double)epochs * (N / minibatch * minibatch);
            string line = $"iter {iter,5}: runs {ep_count,4} ({dead_count} died)  points/run {(ep_count > 0 ? (double)ep_points / ep_count : 0),6:F1}  "
                + $"clip {clipped / seen:F2}  vloss {vloss / seen:F3}  entropy {ent / seen:F3}  {play_s:F1}+{it_clock.Elapsed.TotalSeconds - play_s:F1} s";
            if (iter % eval_every == 0)
            {
                var (median, avg) = evaluate(par);
                line += $"  | eval median {median} mean {avg:F1}";
                double score = median + avg / 1000.0;
                if (score > best)
                {
                    best = score;
                    var extra = new JsonObject { ["algorithm"] = "ppo", ["iteration"] = iter, ["eval_median"] = median, ["eval_mean"] = Math.Round(avg, 2) };
                    File.WriteAllText(policy_path, Policy.to_json(pw, Policy.SIZES, extra).ToJsonString(Policy.PRETTY));
                    line += "  (saved)";
                }
            }
            Console.WriteLine(line);
            save();
        }
        Console.WriteLine($"rlbot train: stopped at iteration {iter} after {clock.Elapsed.TotalMinutes:F1} min (resume with -Resume)");
        return 0;
    }

    /// The observation of a run without advancing its eyes: a copy of its frame history.
    static float[] peek(Env e)
    {
        var f = new float[Observer.INPUTS];
        var frame = new float[Observer.FRAME];
        Observer.frame(e.sim, frame);
        Array.Copy(frame, f, Observer.FRAME);
        // The motion grid: the current one again (close enough for one bootstrap value).
        Array.Copy(frame, Observer.BASE, f, Observer.FRAME, Observer.GRID);
        return f;
    }

    (long median, double mean) evaluate(ParallelOptions par)
    {
        var pol = new Policy((float[])pw.Clone(), Policy.SIZES);
        var pts = new long[eval_seeds];
        Parallel.For(0, eval_seeds, par, i =>
            pts[i] = Player.play(pol, Handicap.NONE, new GameSim(EVAL_SEED + i), eval_cap).points);
        var sorted = pts.OrderBy(x => x).ToArray();
        return (sorted[sorted.Length / 2], pts.Average());
    }

    static float sigmoid(float z) => 1f / (1f + MathF.Exp(-z));

    /// log(sigmoid(z)), stable for large |z|.
    static float log_sig(float z) => z >= 0 ? -MathF.Log(1f + MathF.Exp(-z)) : z - MathF.Log(1f + MathF.Exp(z));

    void save()
    {
        var o = new JsonObject
        {
            ["algorithm"] = "ppo",
            ["layout"] = Observer.LAYOUT,
            ["iteration"] = iter,
            ["next_seed"] = next_seed,
            ["best"] = best,
            ["policy"] = arr(pw), ["pm"] = arr(popt.m), ["pv"] = arr(popt.v), ["pt"] = popt.t,
            ["value"] = arr(vw), ["vm"] = arr(vopt.m), ["vv"] = arr(vopt.v), ["vt"] = vopt.t,
        };
        string tmp = state_path + ".tmp";
        File.WriteAllText(tmp, o.ToJsonString());
        File.Move(tmp, state_path, true);
    }

    void load()
    {
        var o = JsonNode.Parse(File.ReadAllText(state_path)).AsObject();
        if ((string)o["algorithm"] != "ppo" || (int)o["layout"] != Observer.LAYOUT)
            throw new InvalidDataException("train_state.json is from another trainer or observation layout: start fresh (no -Resume)");
        iter = (int)o["iteration"];
        next_seed = (long)o["next_seed"];
        best = (double)o["best"];
        pw = floats(o["policy"]);
        vw = floats(o["value"]);
        if (pw.Length != pnet.count || vw.Length != vnet.count)
            throw new InvalidDataException("train_state.json: network sizes changed: start fresh (no -Resume)");
        popt = new Adam(pw.Length, lr) { m = floats(o["pm"]), v = floats(o["pv"]), t = (long)o["pt"] };
        vopt = new Adam(vw.Length, vlr) { m = floats(o["vm"]), v = floats(o["vv"]), t = (long)o["vt"] };
    }

    static float[] floats(JsonNode n) => n.AsArray().Select(x => (float)x).ToArray();
    static JsonArray arr(float[] xs) => new(xs.Select(x => (JsonNode)x).ToArray());
}
