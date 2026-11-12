using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;
using FastSim.Model;

namespace FastSim;

/// `fastsim world ...`: checks and measurements of the structured world model
/// (World/, docs/WORLD_MODEL.md). This file may run the sim forward (it is
/// the test, not the model): it plays a run, lets the model predict from the
/// present state, then compares the prediction with what the sim really did.
///   world errors [seeds] [ticks]   prediction error per hazard type, every room variant
///   world nopeek                   World/ never runs or copies the sim, never reads its RNG
public static partial class WorldCheck
{
    public static readonly long[] OFFSETS = { 10, 30, 60 };
    public const long SAMPLE_EVERY = 30;
    public const long PROBE = 24 * SimConfig.SUB;

    public static int Run(List<string> pos, Dictionary<string, string> opts)
    {
        string what = pos.Count > 1 ? pos[1] : "errors";
        string O(string k, string d) => opts.GetValueOrDefault(k, d);
        int threads = Math.Clamp(int.Parse(O("threads", "12")), 1, 16);
        switch (what)
        {
            case "errors":
                return Errors(int.Parse(pos.Count > 2 ? pos[2] : "3"), long.Parse(pos.Count > 3 ? pos[3] : "900"), threads,
                    O("room", ""), O("out", ""), O("bot", "planner"));
            case "nopeek":
                return NoPeek(O("dir", Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../fastsim/World"))));
            default:
                return RunMore(what, pos, opts, threads);
        }
    }

    /// Every (room index, def, variant id) the catalog has: one per variant, or one per room without variants.
    public static List<(int index, RoomDef def, string variant)> Variants()
    {
        var out_ = new List<(int, RoomDef, string)>();
        var all = RoomCatalog.all();
        for (int i = 0; i < all.Count; i++)
        {
            var def = all[i];
            if (def.variants.Count == 0) out_.Add((i, def, ""));
            else foreach (var v in def.variants) out_.Add((i, def, v.id));
        }
        return out_;
    }

    // --- Prediction errors ---

    sealed class Stat
    {
        public long n, on_mismatch, exact;
        public double err_sum, err_max;
        public long cells, kill_true, miss, false_kill;
        public long guess_bodies;
        public readonly HashSet<string> rooms = new();
    }

    sealed class Pending
    {
        public WorldModel w;
        public long born;
    }

    /// For every room variant: `seeds` practice runs of up to `ticks` ticks played by a bot.
    /// Every SAMPLE_EVERY ticks the model reads the present and predicts OFFSETS ticks ahead
    /// (fed the taps the bot really made); the prediction is then compared with the sim:
    /// each body's outline (px, the largest edge difference), bodies there or not, and the
    /// kill zone on a 24 px probe grid (hazard.kills() vs the model's deadly bodies).
    static int Errors(int seeds, long ticks, int threads, string only, string out_path, string bot)
    {
        var clock = Stopwatch.StartNew();
        var variants = Variants().Where(v => only == "" || v.def.id == only).ToList();
        var stats = new ConcurrentDictionary<(string type, long k), Stat>();
        var bird_err = new ConcurrentDictionary<(string room, long k), Stat>();
        var wall_err = new ConcurrentDictionary<long, Stat>();
        var types_seen = new ConcurrentDictionary<string, byte>();
        long samples = 0;
        Parallel.ForEach(variants, new ParallelOptions { MaxDegreeOfParallelism = threads }, v =>
        {
            for (int s = 0; s < seeds; s++)
            {
                long n = ErrorsRun(v.index, v.def, v.variant, 1000 + 37 * s, ticks, bot, stats, bird_err, wall_err, types_seen);
                Interlocked.Add(ref samples, n);
            }
        });

        var sb = new StringBuilder();
        sb.AppendLine($"world errors: {variants.Count} room variants x {seeds} practice runs (up to {ticks} ticks, bot {bot}), " +
            $"{samples} predictions, offsets {string.Join("/", OFFSETS)} ticks, probe grid {PROBE / SimConfig.SUB} px");
        sb.AppendLine("  per hazard type (model/motion): bodies compared, mean / max outline error (px), bodies there-or-not wrong," +
            " kill zone missed / falsely predicted (share of real kill cells), guessed bodies");
        foreach (var type in stats.Keys.Select(k => k.type).Distinct().OrderBy(x => x))
        {
            sb.Append($"  {type,-36}");
            foreach (long k in OFFSETS)
            {
                if (!stats.TryGetValue((type, k), out var st)) { sb.Append($" | +{k,2}: -"); continue; }
                double mean = st.n > 0 ? st.err_sum / Math.Max(1, st.n - st.on_mismatch) : 0;
                double miss = st.kill_true > 0 ? 100.0 * st.miss / st.kill_true : 0;
                double fals = st.kill_true > 0 ? 100.0 * st.false_kill / st.kill_true : (st.false_kill > 0 ? 100 : 0);
                sb.Append($" | +{k,2}: err {mean,5:F1}/{st.err_max,5:F0} px, on {100.0 * st.on_mismatch / Math.Max(1, st.n),4:F1}%," +
                    $" miss {miss,4:F1}% false {fals,4:F1}%, guess {100.0 * st.guess_bodies / Math.Max(1, st.n),3:F0}%");
            }
            sb.AppendLine($"  ({stats[(type, OFFSETS[0])].rooms.Count} variants)");
        }
        sb.AppendLine("  walls (spike mask of the wall ahead + belt shift, before the predicted bounce):");
        foreach (long k in OFFSETS)
            if (wall_err.TryGetValue(k, out var st))
                sb.AppendLine($"    +{k,2}: {st.n} compared, mask wrong {100.0 * st.on_mismatch / Math.Max(1, st.n):F2}%, shift err mean {st.err_sum / Math.Max(1, st.n):F2} max {st.err_max:F0} px");
        sb.AppendLine("  bird path (exact physics + modelled pushes; y error in px, given the same taps), worst variants:");
        foreach (long k in OFFSETS)
        {
            var rows = bird_err.Where(e => e.Key.k == k).Select(e => (e.Key.room, mean: e.Value.err_sum / Math.Max(1, e.Value.n), e.Value.err_max, e.Value.n, e.Value.exact)).ToList();
            long all_n = rows.Sum(r => r.n), all_exact = rows.Sum(r => r.exact);
            sb.AppendLine($"    +{k,2}: {all_n} compared, exact {100.0 * all_exact / Math.Max(1, all_n):F1}%, mean {rows.Sum(r => r.mean * r.n) / Math.Max(1, all_n):F2} px;" +
                " worst: " + string.Join(", ", rows.Where(r => r.err_max > 0).OrderByDescending(r => r.mean).Take(8).Select(r => $"{r.room} {r.mean:F1}/{r.err_max:F0}")));
        }
        var missing = Models.CLASSES.Select(c => c.Name).Where(c => !types_seen.ContainsKey(c)).ToList();
        sb.AppendLine($"  hazard classes met: {types_seen.Count} of {Models.CLASSES.Length}" + (missing.Count > 0 ? $" (not met: {string.Join(", ", missing)})" : ""));
        sb.AppendLine($"world errors: {clock.Elapsed.TotalSeconds:F0} s ({threads} threads)");
        Console.Write(sb.ToString());
        if (out_path != "") File.WriteAllText(out_path, sb.ToString());
        return 0;
    }

    static string TypeName(HazardModel m) => m.GetType().Name.TrimEnd('M') + "/" + m.kind + "/" + m.Motion;

    static long ErrorsRun(int index, RoomDef def, string variant, long seed, long ticks, string bot,
        ConcurrentDictionary<(string, long), Stat> stats, ConcurrentDictionary<(string, long), Stat> bird_err,
        ConcurrentDictionary<long, Stat> wall_err, ConcurrentDictionary<string, byte> seen)
    {
        var sim = new GameSim(seed, def.season, index, variant);
        string label = variant == "" ? def.id : def.id + "/" + variant;
        foreach (var h in sim.room.hazards) seen.TryAdd(h.GetType().Name, 0);
        var mem = new Memory();
        var rng = new SimRng(seed * 7 + 1);
        var planner = bot == "planner" ? new WorldPlanner(WorldPlanner.Skill.BEAST, seed) : null;
        var pending = new List<Pending>();
        long made = 0;
        long room_index = sim.state.room_index;
        for (long tick = 0; tick < ticks && !sim.is_over(); tick++)
        {
            mem.Observe(sim);
            if (sim.state.room_index != room_index)
            {
                pending.Clear();
                room_index = sim.state.room_index;
                foreach (var h in sim.room.hazards) seen.TryAdd(h.GetType().Name, 0);
            }
            if (tick % SAMPLE_EVERY == 0 && sim.state.started)
            {
                pending.Add(new Pending { w = WorldModel.Read(sim, mem), born = tick });
                made++;
            }
            bool tap = planner != null ? planner.Decide(sim, mem) : (!sim.state.started || PlannerBot.aim(sim, rng));
            sim.step(tap);
            foreach (var p in pending) p.w.Tick(tap);
            if (sim.is_over() || sim.state.room_index != room_index) { pending.Clear(); continue; }
            for (int i = pending.Count - 1; i >= 0; i--)
            {
                var p = pending[i];
                long k = tick + 1 - p.born;
                if (Array.IndexOf(OFFSETS, k) >= 0) Compare(sim, p.w, k, label, stats, bird_err, wall_err);
                if (k >= OFFSETS[^1] || p.w.exited || !p.w.bird.alive) pending.RemoveAt(i);
            }
        }
        foreach (var h in sim.room.hazards) seen.TryAdd(h.GetType().Name, 0);
        return made;
    }

    static void Compare(GameSim sim, WorldModel pred, long k, string room,
        ConcurrentDictionary<(string, long), Stat> stats, ConcurrentDictionary<(string, long), Stat> bird_err,
        ConcurrentDictionary<long, Stat> wall_err)
    {
        var truth = WorldModel.Read(sim);
        // The bird.
        if (pred.bird.alive)
        {
            var bs = bird_err.GetOrAdd((room, k), _ => new Stat());
            double e = Math.Abs(pred.bird.y - truth.bird.y) / (double)SimConfig.SUB;
            lock (bs)
            {
                bs.n++;
                bs.err_sum += e;
                bs.err_max = Math.Max(bs.err_max, e);
                if (pred.bird.y == truth.bird.y && pred.bird.x == truth.bird.x) bs.exact++;
            }
        }
        // The wall ahead (while the prediction has not bounced).
        long side = truth.bird.vx > 0 ? 1 : 0;
        if (!pred.room.unknown[side] && pred.bird.vx == truth.bird.vx)
        {
            var ws = wall_err.GetOrAdd(k, _ => new Stat());
            long shift_p = Physics.Shift(pred.hz, null, side), shift_t = Physics.Shift(truth.hz, null, side);
            double e = Math.Abs(shift_p - shift_t) / (double)SimConfig.SUB;
            lock (ws)
            {
                ws.n++;
                if (pred.room.Mask(side) != truth.room.Mask(side)) ws.on_mismatch++;
                ws.err_sum += e;
                ws.err_max = Math.Max(ws.err_max, e);
            }
        }
        // Each hazard: outlines and the kill zone.
        var keep = (sim.state.x, sim.state.y);
        for (int i = 0; i < truth.hz.Length && i < sim.room.hazards.Count; i++)
        {
            var hp = pred.Find(truth.hz[i].index);
            var ht = truth.hz[i];
            if (hp == null) continue;
            var st = stats.GetOrAdd((TypeName(ht), k), _ => new Stat());
            long n = 0, mism = 0, guess = 0;
            double sum = 0, mx = 0;
            int bodies = Math.Min(hp.bodies.Length, ht.bodies.Length);
            for (int j = 0; j < bodies; j++)
            {
                bool on_p = hp.alive && hp.bodies[j].on, on_t = ht.alive && ht.bodies[j].on;
                if (!on_p && !on_t) continue;
                n++;
                if (hp.bodies[j].guess) guess++;
                if (on_p != on_t) { mism++; continue; }
                var a = hp.bodies[j].s;
                var b = ht.bodies[j].s;
                double e = Math.Max(Math.Max(Math.Abs(a.Left - b.Left), Math.Abs(a.Right - b.Right)),
                    Math.Max(Math.Abs(a.Top - b.Top), Math.Abs(a.Bottom - b.Bottom))) / (double)SimConfig.SUB;
                if (Math.Abs(a.Left) > (1L << 26) || Math.Abs(a.Right) > (1L << 26)) e = Math.Abs(a.Top - b.Top + a.Bottom - b.Bottom) / (double)SimConfig.SUB;
                sum += e;
                mx = Math.Max(mx, e);
            }
            // Kill zone on the probe grid.
            long cells = 0, kt = 0, miss = 0, fals = 0;
            var h = sim.room.hazards[i];
            bool deadly_class = ht.bodies.Any(b => b.deadly) || hp.bodies.Any(b => b.deadly);
            if (deadly_class)
                for (long px = PROBE / 2; px < SimConfig.WORLD_W; px += PROBE)
                    for (long py = SimConfig.KILL_TOP + PROBE / 2; py < SimConfig.KILL_BOTTOM; py += PROBE)
                    {
                        sim.state.x = px;
                        sim.state.y = py;
                        bool real = h.alive && h.kills(sim);
                        bool said = false;
                        if (hp.alive)
                            foreach (var body in hp.bodies)
                                if (body.on && body.deadly && body.s.Hits(px, py, Physics.R)) { said = true; break; }
                        cells++;
                        if (real) kt++;
                        if (real && !said) miss++;
                        if (said && !real) fals++;
                    }
            lock (st)
            {
                st.n += n;
                st.on_mismatch += mism;
                st.err_sum += sum;
                st.err_max = Math.Max(st.err_max, mx);
                st.guess_bodies += guess;
                st.cells += cells;
                st.kill_true += kt;
                st.miss += miss;
                st.false_kill += fals;
                st.rooms.Add(room);
            }
        }
        sim.state.x = keep.x;
        sim.state.y = keep.y;
    }

    // --- No peeking ---

    /// What World/ must never contain: running or copying the sim forward, its
    /// RNG, the hazard code that runs at a bounce, or fields that hold a hidden
    /// random choice (a slide target, a next column, a hash salt).
    public static readonly (string rule, string pattern)[] FORBIDDEN =
    {
        ("copies the sim", @"\bclone_deep\b"),
        ("runs the sim or a hazard", @"\.step\s*\("),
        ("runs room steps", @"\.steps_this_tick\s*\("),
        ("reads the RNG", @"\b(SimRng|_rng|next_u32|next_below|reseed)\b"),
        ("reads a hidden salt", @"\.salt\b"),
        ("reads a hidden target", @"\.(target_y|next_x)\b"),
        ("reads a boss draw", @"\.seed\b|\.(draw|lit_rows|slam_of|_next_lane|hop_to|_pick_column|safe_y)\s*\("),
        ("runs hazard hooks", @"\.(setup|_place|on_bounce|on_flap|on_wall_bounce|adjust_wall|near_row|touch|kills|_next_drop|_pick_y|_aim|_load|pop)\s*\("),
        ("runs arrival checks", @"\b(ArrivalCheck|_arrival_retries|_arrive_in|_go_through|_enter_room)\b"),
        ("changes the sim", @"\bsim\.(state|room)\.[a-z_]+\s*(=[^=]|\+=|-=|\+\+|--)"),
    };

    public static int NoPeek(string dir)
    {
        var files = Directory.GetFiles(dir, "*.cs", SearchOption.AllDirectories);
        int bad = 0;
        foreach (var f in files)
        {
            var lines = File.ReadAllLines(f);
            for (int i = 0; i < lines.Length; i++)
            {
                string code = lines[i];
                int c = code.IndexOf("//", StringComparison.Ordinal);
                if (c >= 0) code = code[..c];
                foreach (var (rule, pattern) in FORBIDDEN)
                    if (System.Text.RegularExpressions.Regex.IsMatch(code, pattern))
                    {
                        Console.WriteLine($"  {Path.GetFileName(f)}:{i + 1} {rule}: {lines[i].Trim()}");
                        bad++;
                    }
            }
        }
        Console.WriteLine($"world nopeek: {files.Length} files in {dir}, {bad} problems");
        return bad == 0 && files.Length > 3 ? 0 : 1;
    }
}
