using System.Diagnostics;
using System.Text.Json.Nodes;

namespace FastSim.Rl;

/// Imitation learning with DAgger over whole runs (an alternative to the
/// near-death teacher in Dagger.cs). The expert is dense: at a labelled tick
/// it asks Teacher.safe_moves; when only one move is safe that move is the
/// label, when both are, a fixed aiming rule picks (a smaller weight), so the
/// labels follow one consistent style. Runs are played by a mix of expert
/// and student (beta falls to 0), every `label_every`-th tick is labelled, the
/// labels gather over iterations and the net (any sizes) is fit to them.
/// The expert only labels at training time; the policy plays on its own.
public sealed class Imitation
{
    public int threads = 4;
    public int runs = 32;
    public long cap = 12000;
    public double practice = 0.5;
    public long horizon = 90;
    public int label_every = 3;
    public float free_weight = 0.3f;
    /// Weight of a label where only one move is safe.
    public float forced_weight = 1f;
    /// On a death, every one of the last `back` ticks is labelled too.
    public int back = 0;
    public double beta0 = 1.0, beta_decay = 0.7;
    public int max_data = 1_500_000;
    public int epochs_per_iter = 1;
    public int max_batches = 600;
    public int batch = 256;
    public float lr = 1e-3f;
    public int eval_every = 3;
    public int eval_seeds = 64;
    public long eval_cap = 54000;
    public int[] sizes = { inputs, 256, 128, 1 };
    public const long TRAIN_SEED = 40_000_000;

    readonly string dir;
    Mlp net;
    float[] w;
    Adam opt;
    int iter;
    long next_seed = TRAIN_SEED;
    double best = -1;
    readonly List<(sbyte[] x, byte y, float wt)> data = new();
    int data_head;

    public Imitation(string dir) => this.dir = dir;

    string policy_path => Path.Combine(dir, "policy.json");
    string data_path => Path.Combine(dir, "imitate_data.bin");
    string state_path => Path.Combine(dir, "imitate_state.json");

    /// Marks a forced label (weight scaled by forced_weight when stored).
    const float FORCED = 1f;

    /// Adds the arcs (Arc.cs, in the observation since layout 4) against the
    /// hazards of 6 and 12 ticks ago after the observation (an experiment).
    public static bool arc_past = false;
    public static readonly int[] PAST = { 6, 12 };
    public static int inputs => Observer.INPUTS + (arc_past ? Arc.SIZE * PAST.Length : 0);

    /// The student's eyes: the observation, the arcs and a short history of
    /// room copies for the past arcs (one per run).
    public sealed class Eyes
    {
        public readonly Player player;
        readonly RoomRuntime[] hist = new RoomRuntime[13];
        long n;
        public Eyes(long seed) => player = new Player(null, Handicap.NONE, seed);

        public float[] see(GameSim sim, float[] buf)
        {
            var x = player.observe(sim);
            if (!arc_past) return x;
            Array.Copy(x, buf, Observer.INPUTS);
            {
                hist[n % hist.Length] = sim.room.clone_deep();
                for (int k = 0; k < PAST.Length; k++)
                {
                    long back = Math.Min(PAST[k], n);
                    var old = hist[(n - back) % hist.Length];
                    // Another room then: use this room's hazards (no motion seen yet).
                    if (old.index != sim.room.index) old = hist[n % hist.Length];
                    Arc.fill_past(sim, old, buf, Observer.INPUTS + Arc.SIZE * k);
                }
            }
            n++;
            return buf;
        }
    }

    /// The student plays one run on its own.
    public static (long points, bool dead, List<bool> taps) play_student(Policy pol, GameSim sim, long cap)
    {
        var eyes = new Eyes(sim.seed_value);
        var acts = pol.net.scratch();
        var buf = new float[inputs];
        var taps = new List<bool>();
        long start = sim.state.score;
        while (!sim.is_over() && taps.Count < cap)
        {
            var x = eyes.see(sim, buf);
            bool t = !sim.state.started || pol.act(x, acts) > 0f;
            taps.Add(t);
            sim.step(t);
        }
        return (sim.state.score - start, sim.is_over(), taps);
    }

    /// Expert style: false = aim when both moves are safe; true = the move
    /// that keeps more of the beam alive (more slack), aim only on near ties.
    public static bool by_width = false;

    /// How many beam states (Teacher's buckets) are still alive after
    /// `horizon` ticks from `sim` (not changed); 0 when none lives.
    public static int width(GameSim sim, long horizon)
    {
        if (sim.is_over()) return 0;
        var frontier = new List<GameSim> { sim.clone_deep() };
        var slots = new Dictionary<long, int>();
        var next = new List<GameSim>();
        for (long t = 0; t < horizon; t++)
        {
            slots.Clear();
            next.Clear();
            foreach (var s in frontier)
            {
                if (s.state.vy * s.room.gravity > Teacher.TAP_BELOW_VY || !s.state.started)
                {
                    var c = s.clone_deep();
                    c.step(true);
                    keep(slots, next, c);
                }
                if (!s.state.started) continue;
                s.step(false);
                keep(slots, next, s);
            }
            if (next.Count == 0) return 0;
            (frontier, next) = (next, frontier);
        }
        return frontier.Count;
    }

    static void keep(Dictionary<long, int> slots, List<GameSim> next, GameSim s)
    {
        if (s.is_over()) return;
        var st = s.state;
        long along = st.vy * s.room.gravity - SimConfig.FLAP_VY;
        long speed = G.clampi(along / Teacher.BUCKET_VY, 0, Teacher.SPEED_BUCKETS - 1);
        long key = (st.room_index * 1000 + st.y / Teacher.BUCKET_H) * Teacher.SPEED_BUCKETS + speed;
        if (slots.TryGetValue(key, out int slot))
        {
            if (SurvivalSearch._better(s, next[slot])) next[slot] = s;
        }
        else
        {
            slots[key] = next.Count;
            next.Add(s);
        }
    }

    /// The expert's move at `sim` and the label's weight.
    public static (bool tap, float wt, bool forced) expert(GameSim sim, long horizon, float free_weight)
    {
        if (!sim.state.started) return (true, 0f, false);
        if (by_width)
        {
            var a = sim.clone_deep();
            a.step(true);
            var b = sim.clone_deep();
            b.step(false);
            int wt_tap = width(a, horizon), wt_wait = width(b, horizon);
            if (wt_tap == 0 && wt_wait == 0) return (aim(sim), 0f, false);
            if (wt_tap == 0 || wt_wait == 0) return (wt_tap > 0, FORCED, true);
            float r = Math.Abs(wt_tap - wt_wait) / (float)Math.Max(wt_tap, wt_wait);
            if (r < 0.1f) return (aim(sim), free_weight * 0.5f, false);
            return (wt_tap > wt_wait, free_weight + r * (1f - free_weight), false);
        }
        var (tap_ok, wait_ok) = Teacher.safe_moves(sim, horizon);
        if (tap_ok != wait_ok) return (tap_ok, FORCED, true);
        return (aim(sim), tap_ok ? free_weight : 0f, false);
    }

    /// The expert's move only (one search): aim, unless aiming dies.
    public static bool expert_move(GameSim sim, long horizon)
    {
        if (!sim.state.started) return true;
        if (by_width) return expert(sim, horizon, 1f).tap;
        bool a = aim(sim);
        var c = sim.clone_deep();
        c.step(a);
        return Teacher.survives(c, horizon) ? a : !a;
    }

    /// Why a policy dies: for each death (seeds first+1..), walks back over
    /// the last `back` ticks and asks the expert. A death is the student's
    /// error when some tick there had one safe move and the student took the
    /// other; otherwise the expert saw no single right move (horizon / buckets).
    public static int diagnose(string dir, int seeds, long first, long cap, long horizon, int back, int threads)
    {
        var pol = load(Path.Combine(dir, "policy.json"));
        var lines = new string[seeds];
        var kind = new int[seeds];
        var last_err = new long[seeds];
        var pts = new long[seeds];
        Parallel.For(0, seeds, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            long seed = first + 1 + i;
            var sim = new GameSim(seed);
            var (got, _, taps) = play_student(pol, sim, cap);
            pts[i] = got;
            if (!sim.is_over()) return;
            string room = sim.room.def.id + (sim.room.variant_id() != "" ? "/" + sim.room.variant_id() : "");
            string cause = DeathCause.NAMES[sim.state.death_cause];
            long T = taps.Count;
            var re = new GameSim(seed);
            long errs = 0, forced = 0, unsavable_from = -1;
            last_err[i] = -1;
            for (long t = 0; t < T; t++)
            {
                if (t >= T - back && re.state.started)
                {
                    var (tap_ok, wait_ok) = Teacher.safe_moves(re, horizon);
                    if (!tap_ok && !wait_ok && unsavable_from < 0) unsavable_from = T - t;
                    if (tap_ok != wait_ok)
                    {
                        forced++;
                        if (taps[(int)t] != tap_ok)
                        {
                            errs++;
                            last_err[i] = T - t;
                        }
                    }
                }
                re.step(taps[(int)t]);
            }
            kind[i] = errs > 0 ? 1 : 2;
            lines[i] = $"seed {seed,4}: {pts[i],4} pts, {room,-24} {cause,-10} forced {forced,3}, student errors {errs,2}, last error {last_err[i],4} ticks before death, no move safe from {unsavable_from,4}";
        });
        foreach (var l in lines) if (l != null) Console.WriteLine(l);
        int deaths = kind.Count(k => k > 0);
        Console.WriteLine($"diagnose: {seeds} runs, median {Tiers.pct(pts, 0.5)}, {deaths} deaths: {kind.Count(k => k == 1)} with a student error on a forced move, {kind.Count(k => k == 2)} without (expert gave no single answer)");
        var by_room = lines.Where(l => l != null).GroupBy(l => l.Substring(21, 24).Trim()).OrderByDescending(g => g.Count()).Take(12);
        foreach (var g in by_room) Console.WriteLine($"  {g.Key,-24} {g.Count()}");
        return 0;
    }

    /// PlannerBot.aim without its jitter: steer to the gap (or exit) ahead.
    public static bool aim(GameSim sim)
    {
        var s = sim.state;
        long side = s.vx > 0 ? 1 : 0;
        long target = PlannerBot.gap_center_y(sim.wall_mask(side));
        if (s.exit_open && s.exit_side == side)
        {
            target = s.exit_a_y;
            if (s.exit_b_kind == ExitKind.WILD) target = s.exit_b_y;
        }
        long margin = 6 * SimConfig.SUB;
        if (sim.room.gravity < 0) return s.y < target - margin && s.vy <= 0;
        return s.y > target + margin && s.vy >= 0;
    }

    /// The expert playing on its own (how good a teacher it is).
    public static int expert_score(int seeds, long first, long cap, long horizon, int threads)
    {
        var clock = Stopwatch.StartNew();
        var pts = new long[seeds];
        var ticks = new long[seeds];
        Parallel.For(0, seeds, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            var sim = new GameSim(first + 1 + i);
            long start = sim.state.score, n = 0;
            while (!sim.is_over() && n < cap)
            {
                sim.step(expert_move(sim, horizon));
                n++;
            }
            pts[i] = sim.state.score - start;
            ticks[i] = n;
        });
        Console.WriteLine($"rlbot expert (horizon {horizon}): {seeds} runs, median {Tiers.pct(pts, 0.5)}, p90 {Tiers.pct(pts, 0.9)}, mean {pts.Average():F1}, {ticks.Sum()} ticks in {clock.Elapsed.TotalSeconds:F0} s");
        return 0;
    }

    public int run(bool resume, double minutes)
    {
        net = new Mlp(sizes);
        if (resume && File.Exists(state_path)) load();
        else
        {
            w = net.init(7, 1f);
            opt = new Adam(w.Length, lr);
        }
        opt.lr = lr;
        Console.WriteLine($"rlbot imitate: net {string.Join("-", sizes)} ({w.Length} weights), {runs} runs/iter (cap {cap}), horizon {horizon}, label every {label_every}, from iteration {iter}, data {data.Count}, best {best:F1}");
        var clock = Stopwatch.StartNew();
        var par = new ParallelOptions { MaxDegreeOfParallelism = threads };
        while (clock.Elapsed.TotalMinutes < minutes)
        {
            var ic = Stopwatch.StartNew();
            double beta = beta0 * Math.Pow(beta_decay, iter);
            if (beta < 0.02) beta = 0;
            var pol = new Policy((float[])w.Clone(), sizes);
            long first = next_seed;
            next_seed += runs;
            var found = new List<(sbyte[] x, byte y, float wt)>[runs];
            var pts = new long[runs];
            var forced = new int[runs];
            var agree = new int[runs];
            var asked = new int[runs];
            Parallel.For(0, runs, par, r =>
            {
                long seed = first + r;
                var rng = new Random((int)(seed % int.MaxValue));
                long room = rng.NextDouble() < practice ? Ppo.rooms()[rng.Next(Ppo.rooms().Count)] : -1;
                var sim = new GameSim(seed, Seasons.NONE, room);
                long start = sim.state.score;
                var eyes = new Eyes(seed);
                var buf = new float[inputs];
                var acts = pol.net.scratch();
                var mine = new List<(sbyte[] x, byte y, float wt)>();
                long n = 0;
                var taps = new List<bool>();
                // Whose move it is switches in stretches (not every tick) so
                // the student sees its own drift.
                bool expert_turn = rng.NextDouble() < beta;
                while (!sim.is_over() && n < cap)
                {
                    if (n % 60 == 0) expert_turn = rng.NextDouble() < beta;
                    var x = eyes.see(sim, buf);
                    bool student = !sim.state.started || pol.act(x, acts) > 0f;
                    bool move = student;
                    if (sim.state.started && n % label_every == 0)
                    {
                        var (tap, wt, frc) = expert(sim, horizon, free_weight);
                        if (wt > 0)
                        {
                            mine.Add((Dagger_pack(x), tap ? (byte)1 : (byte)0, frc ? forced_weight : wt));
                            asked[r]++;
                            if (frc) forced[r]++;
                            if (tap == student) agree[r]++;
                        }
                        if (expert_turn) move = tap;
                    }
                    else if (sim.state.started && expert_turn) move = expert_move(sim, horizon);
                    taps.Add(move);
                    sim.step(move);
                    n++;
                }
                if (sim.is_over() && back > 0)
                {
                    // Replay the run and label every tick of its last `back`.
                    long T = taps.Count, from = Math.Max(0, T - back);
                    var re = new GameSim(seed, Seasons.NONE, room);
                    var re_eyes = new Eyes(seed);
                    var re_buf = new float[inputs];
                    for (long t = 0; t < T; t++)
                    {
                        if (t >= from - Observer.MOTION)
                        {
                            var x = re_eyes.see(re, re_buf);
                            if (t >= from && t % label_every != 0 && re.state.started)
                            {
                                var (tap, wt, frc) = expert(re, horizon, free_weight);
                                if (wt > 0)
                                {
                                    mine.Add((Dagger_pack(x), tap ? (byte)1 : (byte)0, frc ? forced_weight : wt));
                                    asked[r]++;
                                    if (frc) forced[r]++;
                                }
                            }
                        }
                        re.step(taps[(int)t]);
                    }
                }
                pts[r] = sim.state.score - start;
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
            var (loss, acc_all, acc_forced) = learn(par);
            iter++;
            string line = $"iter {iter,4}: beta {beta:F2}, points/run {pts.Average(),6:F1}, labels +{added} ({forced.Sum()} forced), student agrees {(double)agree.Sum() / Math.Max(1, asked.Sum()):P0}, data {data.Count}, loss {loss:F3}, fit {acc_all:P1} forced {acc_forced:P1}  {play_s:F0}+{ic.Elapsed.TotalSeconds - play_s:F0} s";
            if (iter % eval_every == 0)
            {
                var (median, mean) = evaluate(par);
                line += $"  | eval median {median} mean {mean:F1}";
                double score = median + mean / 1000.0;
                if (score > best)
                {
                    best = score;
                    var extra = new JsonObject { ["algorithm"] = "imitation", ["iteration"] = iter, ["eval_median"] = median, ["eval_mean"] = Math.Round(mean, 2) };
                    File.WriteAllText(policy_path, Policy.to_json(w, sizes, extra).ToJsonString(Policy.PRETTY));
                    line += "  (saved)";
                }
            }
            Console.WriteLine($"{line}  [{clock.Elapsed.TotalMinutes:F1} min]");
            save();
        }
        Console.WriteLine($"rlbot imitate: stopped at iteration {iter} after {clock.Elapsed.TotalMinutes:F1} min (resume with --resume 1)");
        return 0;
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

    /// Minibatch cross-entropy over the gathered labels (about one pass, at
    /// most max_batches batches); returns loss and fit on the forced labels.
    (double loss, double acc, double acc_forced) learn(ParallelOptions par)
    {
        if (data.Count < batch) return (0, 0, 0);
        var rng = new Random(iter * 31 + 5);
        int parts = threads;
        var grads = new float[parts][];
        for (int q = 0; q < parts; q++) grads[q] = new float[w.Length];
        int batches = Math.Min(max_batches, epochs_per_iter * data.Count / batch);
        double total = 0;
        var pick = new int[batch];
        for (int b = 0; b < batches; b++)
        {
            for (int i = 0; i < batch; i++) pick[i] = rng.Next(data.Count);
            var losses = new double[parts];
            float wsum = 0;
            foreach (int i in pick) wsum += data[i].wt;
            Parallel.For(0, parts, par, q =>
            {
                Array.Clear(grads[q]);
                var acts = net.scratch();
                var deltas = net.delta_scratch();
                var x = new float[sizes[0]];
                int per = batch / parts;
                for (int s = q * per; s < (q + 1) * per; s++)
                {
                    var d = data[pick[s]];
                    Dagger_unpack(d.x, x);
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
        // Fit on (up to) 8,000 recent labels.
        {
            var acts = net.scratch();
            var x = new float[sizes[0]];
            int n = 0, right = 0, nf = 0, rf = 0;
            for (int i = data.Count - 1; i >= 0 && n < 8000; i--)
            {
                var d = data[i];
                Dagger_unpack(d.x, x);
                bool ok = net.forward(w, x, acts) > 0f == (d.y == 1);
                n++;
                if (ok) right++;
                if (d.wt > free_weight)
                {
                    nf++;
                    if (ok) rf++;
                }
            }
            return (total / Math.Max(1, batches), (double)right / Math.Max(1, n), (double)rf / Math.Max(1, nf));
        }
    }

    (long median, double mean) evaluate(ParallelOptions par)
    {
        var pol = new Policy((float[])w.Clone(), sizes);
        var pts = new long[eval_seeds];
        Parallel.For(0, eval_seeds, par, i =>
            pts[i] = play_student(pol, new GameSim(Ppo.EVAL_SEED + i), eval_cap).points);
        var sorted = pts.OrderBy(x => x).ToArray();
        return (sorted[sorted.Length / 2], pts.Average());
    }

    static sbyte[] Dagger_pack(float[] x)
    {
        var o = new sbyte[x.Length];
        for (int i = 0; i < x.Length; i++) o[i] = (sbyte)Math.Clamp(MathF.Round(x[i] * 63f), -127, 127);
        return o;
    }

    static void Dagger_unpack(sbyte[] s, float[] x)
    {
        for (int i = 0; i < s.Length; i++) x[i] = s[i] / 63f;
    }

    void save()
    {
        var o = new JsonObject
        {
            ["algorithm"] = "imitation",
            ["iteration"] = iter,
            ["next_seed"] = next_seed,
            ["best"] = best,
            ["sizes"] = new JsonArray(sizes.Select(s => (JsonNode)s).ToArray()),
            ["data_head"] = data_head,
            ["weights"] = arr(w), ["m"] = arr(opt.m), ["v"] = arr(opt.v), ["t"] = opt.t,
        };
        string tmp = state_path + ".tmp";
        File.WriteAllText(tmp, o.ToJsonString());
        File.Move(tmp, state_path, true);
        // The labels, appended as fixed-size records (x, y, weight).
        using var f = new BinaryWriter(File.Create(data_path + ".tmp"));
        f.Write(data.Count);
        foreach (var d in data)
        {
            f.Write((byte[])(Array)d.x);
            f.Write(d.y);
            f.Write(d.wt);
        }
        f.Close();
        File.Move(data_path + ".tmp", data_path, true);
    }

    void load()
    {
        var o = JsonNode.Parse(File.ReadAllText(state_path)).AsObject();
        sizes = o["sizes"].AsArray().Select(n => (int)n).ToArray();
        net = new Mlp(sizes);
        iter = (int)o["iteration"];
        next_seed = (long)o["next_seed"];
        best = (double)o["best"];
        data_head = (int)o["data_head"];
        w = floats(o["weights"]);
        opt = new Adam(w.Length, lr) { m = floats(o["m"]), v = floats(o["v"]), t = (long)o["t"] };
        if (File.Exists(data_path))
        {
            using var f = new BinaryReader(File.OpenRead(data_path));
            int n = f.ReadInt32();
            for (int i = 0; i < n; i++)
            {
                var x = (sbyte[])(Array)f.ReadBytes(sizes[0]);
                data.Add((x, f.ReadByte(), f.ReadSingle()));
            }
        }
    }

    /// A policy file of any input size (Policy.load wants Observer.INPUTS);
    /// a wider one means the Arc input.
    public static Policy load(string path)
    {
        var o = JsonNode.Parse(File.ReadAllText(path)).AsObject();
        var sz = o["sizes"].AsArray().Select(n => (int)n).ToArray();
        arc_past = sz[0] > Observer.INPUTS;
        if (sz[0] != inputs) throw new InvalidDataException($"{path}: {sz[0]} inputs");
        return new Policy(floats(o["weights"]), sz);
    }

    /// 400 measure seeds (1..400, as rlbot measure): median, p90, mean.
    public static int measure(string dir, int seeds, long first, long cap, int threads)
    {
        var pol = load(Path.Combine(dir, "policy.json"));
        var clock = Stopwatch.StartNew();
        var pts = new long[seeds];
        Parallel.For(0, seeds, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
            pts[i] = play_student(pol, new GameSim(first + 1 + i), cap).points);
        Console.WriteLine($"imitation measure: {seeds} seeds, median {Tiers.pct(pts, 0.5)}, p90 {Tiers.pct(pts, 0.9)}, mean {pts.Average():F1}  ({clock.Elapsed.TotalSeconds:F0} s)");
        return 0;
    }

    static float[] floats(JsonNode n) => n.AsArray().Select(x => (float)x).ToArray();
    static JsonArray arr(float[] xs) => new(xs.Select(x => (JsonNode)x).ToArray());
}
