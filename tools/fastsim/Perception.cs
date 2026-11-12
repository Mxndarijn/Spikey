using System.Reflection;
using System.Text;
using System.Text.Json.Nodes;
using FastSim;
using FastSim.Model;
using FastSim.Mpc;
using FastSim.Rl;

static partial class Checks
{
    /// `sight`: every bot sees every hazard (docs/BOT_SIGHT.md). For every
    /// hazard class in FastSim (found by reflection, so a new one is in the
    /// check at once) a few rooms that hold it are played on a line that
    /// lives (SurvivalSearch). The truth is the sim's own kills(): the bird is
    /// moved to every point of a 12 px grid and each hazard is asked.
    ///   deadly  a tick where the hazard kills somewhere: does the bot's eye
    ///           see that danger now?
    ///   tell    an onset: danger that appears where the hazard killed
    ///           nothing 24 px around one tick before (a beam firing, a
    ///           press slamming in). Asked LEAD ticks earlier: does the bot
    ///           expect danger there at the onset tick?
    /// The eyes: BlindPlanner (and the human tiers on it) plans on
    /// blind_copy, so its eye is a blind copy stepped on; WorldPlanner reads
    /// WorldModel (Models.Read) and steps the models; WorldObs is the world
    /// model as the RL world bot's input; MPC is Sight (shapes and warnings);
    /// RL is Observer.frame. Recall eyes (blind, world, mpc) must flag at
    /// least half the danger points; input eyes (worldobs, rl) must change
    /// when the hazard is taken away (a pure tell: nothing of it kills yet).
    /// A cell is blind when under MIN_RATE of its samples are seen.
    ///
    /// Hidden values: every hazard field of type SimRng or named seed / salt
    /// (`*_seed`, `*_salt`) is a hidden draw. Two blind copies with different
    /// RNGs must differ in it (blind_copy replaces it), and every eye must
    /// read the same from a blind copy as from the true sim (it reads no
    /// hidden value blind_copy replaces).
    public sealed class SightCheck : Check
    {
        public override string name => "sight";
        public override string test => "tools/fastsim/Perception.cs:test_bots_see_every_hazard";

        public const long CELL = 12 * SimConfig.SUB;
        public const int COLS = (int)(SimConfig.WORLD_W / CELL);
        public static readonly int ROWS = (int)((SimConfig.KILL_BOTTOM - SimConfig.KILL_TOP) / CELL);
        /// Ticks between the look and the onset it must expect (1/3 s; the fairness rule is about 1 s).
        public const int LEAD = 20;
        /// Danger points within this of a bot's shape count as seen.
        public const long TOL = 8 * SimConfig.SUB;
        /// Plays per hazard class: rooms that place it, then more seeds of them.
        public const int SCENES_PER_CLASS = 3;
        public const int MAX_POINTS = 24;
        public const int DEADLY_EVERY = 30;
        public const int LEAK_EVERY = 30;
        public const double MIN_RATE = 0.5;
        public const int MIN_SAMPLES = 4;
        public const long DEFAULT_TICKS = 1150;

        public static readonly string[] BOTS = { "blind", "world", "worldobs", "mpc", "rl" };

        /// Hazard classes that are only a base (never placed themselves).
        public static readonly Dictionary<Type, string> BASES = new()
        {
            [typeof(Boss)] = "base of the boss hazards",
        };

        /// Blind cells allowed while their fix is in flight: (class, bot, "tell" or "deadly") -> fix session.
        public static readonly Dictionary<(string cls, string bot, string what), string> KNOWN = new()
        {
            [("BossWatcher", "worldobs", "tell")] = "frozen bot: no owner, retired at the Rust switch (BOT_PLAN.md)",
            [("Beam", "rl", "tell")] = "planner-next (RL tell input for every hazard)",
            [("BossCrusher", "rl", "tell")] = "planner-next (RL tell input for every hazard)",
            [("BossSaw", "rl", "tell")] = "planner-next (RL tell input for every hazard)",
            [("BossWatcher", "rl", "tell")] = "planner-next (RL tell input for every hazard)",
            [("CrateDrop", "rl", "tell")] = "planner-next (RL tell input for every hazard)",
            [("Dart", "rl", "tell")] = "planner-next (RL tell input for every hazard)",
            [("Drop", "rl", "tell")] = "planner-next (RL tell input for every hazard)",
            [("Firework", "rl", "tell")] = "planner-next (RL tell input for every hazard)",
            [("Lava", "rl", "tell")] = "planner-next (RL tell input for every hazard)",
            [("Piston", "rl", "tell")] = "planner-next (RL tell input for every hazard)",
            [("Stalker", "rl", "tell")] = "planner-next (RL tell input for every hazard)",
            [("Beam", "worldobs", "tell")] = "frozen bot: no owner, retired at the Rust switch (BOT_PLAN.md)",
            [("Dart", "worldobs", "tell")] = "frozen bot: no owner, retired at the Rust switch (BOT_PLAN.md)",
            [("Drop", "worldobs", "tell")] = "frozen bot: no owner, retired at the Rust switch (BOT_PLAN.md)",
            [("Firework", "worldobs", "tell")] = "frozen bot: no owner, retired at the Rust switch (BOT_PLAN.md)",
            [("Piston", "worldobs", "tell")] = "frozen bot: no owner, retired at the Rust switch (BOT_PLAN.md)",
            [("CrateDrop", "mpc", "tell")] = "frozen bot: no owner, retired at the Rust switch (BOT_PLAN.md)",
            [("Dart", "mpc", "tell")] = "frozen bot: no owner, retired at the Rust switch (BOT_PLAN.md)",
            [("Drop", "mpc", "tell")] = "frozen bot: no owner, retired at the Rust switch (BOT_PLAN.md)",
            [("Firework", "mpc", "tell")] = "frozen bot: no owner, retired at the Rust switch (BOT_PLAN.md)",
            [("Lava", "mpc", "tell")] = "frozen bot: no owner, retired at the Rust switch (BOT_PLAN.md)",
            [("Stalker", "mpc", "tell")] = "frozen bot: no owner, retired at the Rust switch (BOT_PLAN.md)",
            [("Firework", "mpc", "deadly")] = "frozen bot: no owner, retired at the Rust switch (BOT_PLAN.md)",
        };

        /// Hidden-value reads allowed while their fix is in flight: (eye, scene label) -> owner.
        public static readonly Dictionary<(string eye, string scene), string> KNOWN_LEAKS = new()
        {
            [("world (Models.Read)", "bubbles/spiky")] = "frozen bot: no owner, retired at the Rust switch (BOT_PLAN.md)",
            [("world (Models.Read)", "keepy/two-balls")] = "frozen bot: no owner, retired at the Rust switch (BOT_PLAN.md)",
            [("world (Models.Read)", "double/bramble_beams")] = "frozen bot: no owner, retired at the Rust switch (BOT_PLAN.md)",
        };

        public static List<Type> classes() => typeof(Hazard).Assembly.GetTypes()
            .Where(t => t.IsSubclassOf(typeof(Hazard)) && !t.IsAbstract).OrderBy(t => t.Name).ToList();

        static bool hidden_field(FieldInfo f) =>
            f.FieldType == typeof(SimRng) ||
            (f.FieldType == typeof(long) && (f.Name is "seed" or "salt" || f.Name.EndsWith("_seed") || f.Name.EndsWith("_salt")));

        public static List<FieldInfo> hidden_fields(Type t) => t
            .GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
            .Where(hidden_field).ToList();

        static long field_value(object o, FieldInfo f)
        {
            var v = f.GetValue(o);
            return v switch
            {
                SimRng r => r.state_checksum(),
                long l => l,
                _ => 0,
            };
        }

        public override int count() => cases.Count;

        /// [room index, variant id, seed]: SCENES_PER_CLASS plays per hazard
        /// class, in different rooms while there are, then on other seeds.
        protected override List<object> make()
        {
            var all = RoomCatalog.all();
            var scenes = new List<(int, string, int)>();
            var per = new Dictionary<Type, int>();
            var holds = new Dictionary<(int, string), List<Type>>();
            for (int i = 0; i < all.Count; i++)
            {
                var def = all[i];
                var ids = def.variants.Count == 0 ? new List<string> { "" } : def.variants.Select(v => v.id).ToList();
                foreach (var id in ids)
                {
                    var made = def.hazards.Select(f => f().GetType()).ToList();
                    var v = def.variants.Find(x => x.id == id);
                    if (v != null) made.AddRange(v.hazards.Select(f => f().GetType()));
                    bool want = false;
                    foreach (var t in made.Distinct())
                    {
                        per.TryGetValue(t, out int n);
                        if (n < SCENES_PER_CLASS) want = true;
                        per[t] = n + 1;
                    }
                    // FASTSIM_SIGHT_ONLY: only rooms whose label contains it (to time or debug one room).
                    string only = Environment.GetEnvironmentVariable("FASTSIM_SIGHT_ONLY") ?? "";
                    string label = id == "" ? def.id : $"{def.id}/{id}";
                    if (!label.Contains(only)) continue;
                    holds[(i, id)] = made.Distinct().ToList();
                    if (want) scenes.Add((i, id, 0));
                }
            }
            // A class in fewer rooms than SCENES_PER_CLASS: its rooms again, on other seeds.
            for (int again = 1; again < SCENES_PER_CLASS; again++)
                foreach (var ((i, id), types) in holds)
                {
                    bool want = types.Any(t => per[t] < SCENES_PER_CLASS);
                    if (!want) continue;
                    foreach (var t in types) per[t]++;
                    scenes.Add((i, id, again));
                }
            return scenes.Cast<object>().ToList();
        }

        sealed class Tally
        {
            public int tell_n, deadly_n;
            public readonly int[] tell = new int[BOTS.Length], deadly = new int[BOTS.Length];
            public readonly int[] tell_of = new int[BOTS.Length], deadly_of = new int[BOTS.Length];
        }

        static long cx(int c) => c * CELL + CELL / 2;
        static long cy(int r) => SimConfig.KILL_TOP + r * CELL + CELL / 2;

        /// The grid cells where hazard `i` kills a bird now. Coarse first (every
        /// other cell: a deadly zone is at least a bird wide, 28 px, so it covers
        /// a coarse point), then every cell around a coarse hit.
        static List<int> danger(GameSim sim, int i)
        {
            var out_ = new List<int>();
            var h = sim.room.hazards[i];
            if (!h.alive) return out_;
            var saved = sim.state.copy();
            var done = new bool[COLS * ROWS];
            var hits = new List<int>();
            bool probe(int cell)
            {
                sim.state.x = cx(cell % COLS);
                sim.state.y = cy(cell / COLS);
                return h.kills(sim);
            }
            for (int r = 0; r < ROWS; r += 2)
                for (int c = 0; c < COLS; c += 2)
                {
                    int cell = r * COLS + c;
                    done[cell] = true;
                    if (probe(cell)) hits.Add(cell);
                }
            foreach (int hit in hits)
            {
                int c0 = hit % COLS, r0 = hit / COLS;
                for (int r = Math.Max(0, r0 - 2); r <= Math.Min(ROWS - 1, r0 + 2); r++)
                    for (int c = Math.Max(0, c0 - 2); c <= Math.Min(COLS - 1, c0 + 2); c++)
                    {
                        int cell = r * COLS + c;
                        if (done[cell]) continue;
                        done[cell] = true;
                        if (probe(cell)) out_.Add(cell);
                    }
            }
            out_.AddRange(hits);
            out_.Sort();
            sim.state = saved;
            return out_;
        }

        static bool kills_at(GameSim sim, int i, int cell)
        {
            var h = sim.room.hazards[i];
            if (!h.alive) return false;
            var saved = sim.state.copy();
            sim.state.x = cx(cell % COLS);
            sim.state.y = cy(cell / COLS);
            bool k = h.kills(sim);
            sim.state = saved;
            return k;
        }

        /// Cells of `now` with no cell of `before` within 2 cells.
        static List<int> onset(List<int> before, List<int> now)
        {
            if (now.Count == 0) return now;
            var near = new bool[COLS * ROWS];
            foreach (int cell in before)
            {
                int c0 = cell % COLS, r0 = cell / COLS;
                for (int r = Math.Max(0, r0 - 2); r <= Math.Min(ROWS - 1, r0 + 2); r++)
                    for (int c = Math.Max(0, c0 - 2); c <= Math.Min(COLS - 1, c0 + 2); c++)
                        near[r * COLS + c] = true;
            }
            return now.Where(cell => !near[cell]).ToList();
        }

        static List<int> thin(List<int> cells)
        {
            if (cells.Count <= MAX_POINTS) return cells;
            var out_ = new List<int>();
            for (int k = 0; k < MAX_POINTS; k++) out_.Add(cells[k * cells.Count / MAX_POINTS]);
            return out_;
        }

        static bool half(List<int> cells, Func<int, bool> seen) => cells.Count(seen) * 2 >= cells.Count;

        /// The world model `ticks` ticks on: on the true line while its bird lives, then a ghost.
        static WorldModel model_ahead(WorldModel w, byte[] line, long from, int ticks)
        {
            var c = w.Copy();
            for (int k = 0; k < ticks; k++)
            {
                long at = from + k;
                bool tap = at < line.Length && line[at] == 1;
                if (c.bird.alive) c.Tick(tap);
                else
                {
                    long n = c.room.StepsAt(c.room.ticks);
                    for (long s = 0; s < n; s++) c.GhostSubstep(null, false);
                    c.room.ticks += 1;
                    c.tick += 1;
                }
            }
            return c;
        }

        static bool model_hits(WorldModel w, int i, int cell)
        {
            var h = w.Find(i);
            if (h == null || !h.alive) return false;
            long x = cx(cell % COLS), y = cy(cell / COLS);
            foreach (var b in h.bodies)
                if (b.on && b.deadly && b.s.Hits(x, y, SimConfig.BIRD_RADIUS + TOL)) return true;
            return false;
        }

        /// Whether Sight expects hazard `h` to kill at `cell` `j` sim steps from now.
        static bool sight_sees(FastSim.Mpc.Sight eye, Hazard h, int cell, int j)
        {
            var p = new MpcParams();
            float x = (float)cx(cell % COLS) / SimConfig.SUB, y = (float)cy(cell / COLS) / SimConfig.SUB;
            float tol = (float)TOL / SimConfig.SUB;
            float m = Math.Min(p.m0 + p.grow * j, p.m_cap) + tol;
            foreach (var b in eye.blobs)
            {
                if (b.owner != h || b.body) continue;
                if (b.life > 0 && b.age + j > b.life + 3) continue;
                float x0 = b.e[0] + b.v[0] * j, x1 = b.e[1] + b.v[1] * j;
                float y0 = b.e[2] + b.v[2] * j, y1 = b.e[3] + b.v[3] * j;
                if (x >= x0 - m && x <= x1 + m && y >= y0 - m && y <= y1 + m) return true;
            }
            float pad = p.warn_pad + tol;
            foreach (var w in eye.warns)
            {
                if (j < w.eta - 1 || j > w.eta + w.dur) continue;
                if (x >= w.x0 - pad && x <= w.x1 + pad && y >= w.y0 - pad && y <= w.y1 + pad) return true;
            }
            return false;
        }

        /// Whether a grid cell is inside the RL bot's danger grid (ahead of the bird, around its height).
        static bool in_rl_grid(GameSim sim, int cell)
        {
            long dir = sim.state.vx > 0 ? 1 : -1;
            long ahead = (cx(cell % COLS) - sim.state.x) * dir;
            long dy = cy(cell / COLS) - sim.state.y;
            long half = Observer.ROW_STEP / 2;
            return ahead >= -half && ahead <= (Observer.COLS - 1) * Observer.COL_STEP + half
                && Math.Abs(dy) <= (Observer.ROWS / 2) * Observer.ROW_STEP + half;
        }

        static float[] rl_frame(GameSim sim)
        {
            var f = new float[Observer.FRAME];
            Observer.frame(sim, f);
            return f;
        }

        static float[] obs(WorldModel w)
        {
            var x = new float[WorldObs.SIZE];
            WorldObs.Fill(w, x);
            return x;
        }

        static bool same(float[] a, float[] b) => a.AsSpan().SequenceEqual(b);

        static string sight_key(FastSim.Mpc.Sight eye)
        {
            var sb = new StringBuilder();
            foreach (var b in eye.blobs)
                sb.Append($"{b.body}:{string.Join(",", b.e)}:{string.Join(",", b.v)};");
            foreach (var w in eye.warns) sb.Append(w.ToString());
            foreach (var d in eye.drafts) sb.Append(d.ToString());
            return sb.ToString();
        }

        static string models_key(WorldModel w)
        {
            var sb = new StringBuilder();
            foreach (var h in w.hz)
            {
                sb.Append(h.alive ? 'a' : 'd');
                foreach (var b in h.bodies) sb.Append($"{b.on}{b.deadly}{b.guess}{b.s.k}{b.s.x0},{b.s.y0},{b.s.x1},{b.s.y1},{b.s.x2},{b.s.y2};");
            }
            return sb.ToString();
        }

        public override JsonObject run(int n)
        {
            var (index, variant, again) = ((int, string, int))cases[n];
            var def = RoomCatalog.all()[index];
            string label = (variant == "" ? def.id : $"{def.id}/{variant}") + (again > 0 ? $" (seed {700 + 31L * index + variant.Length + 1000L * again})" : "");
            long ticks = Passable.CASES.Where(c => c.id == def.id).Select(c => c.ticks).DefaultIfEmpty(DEFAULT_TICKS).First();
            long seed = 700 + 31L * index + variant.Length + 1000L * again;
            var start = new GameSim(seed, def.season, index, variant);
            var clock = System.Diagnostics.Stopwatch.StartNew();
            var search = new SurvivalSearch();
            search.run_quick(start.clone_deep(), ticks);
            byte[] line = search.best_inputs;
            void log(string what)
            {
                if (Environment.GetEnvironmentVariable("FASTSIM_SIGHT_ONLY") is { Length: > 0 })
                    Console.Error.WriteLine($"sight {label}: {what} at {clock.Elapsed.TotalSeconds:F1} s");
            }
            var fails = new List<string>();

            // Pass 1: the truth, every tick on the line, while in the first room.
            var sim = start.clone_deep();
            var truth = new List<List<int>[]>();
            var room_t = new List<long>();
            var cls = new List<Type>();
            while (sim.state.tick < line.Length && !sim.is_over() && sim.state.room_index == 0)
            {
                var hz = sim.room.hazards;
                while (cls.Count < hz.Count) cls.Add(hz[cls.Count].GetType());
                var row = new List<int>[hz.Count];
                for (int i = 0; i < hz.Count; i++) row[i] = danger(sim, i);
                truth.Add(row);
                room_t.Add(sim.room.t);
                sim.step(line[sim.state.tick] == 1);
            }
            long end = truth.Count;
            log($"line {line.Length} ticks, truth {end} ticks");
            List<int> at(long t, int i) => i < truth[(int)t].Length ? truth[(int)t][i] : new List<int>();

            // The samples: deadly ticks and onsets (looked at LEAD ticks before).
            var looks = new Dictionary<long, List<(int i, bool tell, List<int> cells, long onset)>>();
            void add(long t, (int, bool, List<int>, long) s)
            {
                if (!looks.TryGetValue(t, out var l)) looks[t] = l = new();
                l.Add(s);
            }
            for (int i = 0; i < cls.Count; i++)
            {
                long last_onset = -1000, last_deadly = -1000;
                for (long t = 1; t < end; t++)
                {
                    var now = at(t, i);
                    if (now.Count == 0) continue;
                    if (t - last_deadly >= DEADLY_EVERY)
                    {
                        add(t, (i, false, thin(now), t));
                        last_deadly = t;
                    }
                    var fresh = onset(at(t - 1, i), now);
                    if (fresh.Count > 0 && t - last_onset > LEAD && t - LEAD >= 1)
                    {
                        add(t - LEAD, (i, true, thin(fresh), t));
                        last_onset = t;
                    }
                }
            }

            log($"{looks.Sum(l => l.Value.Count)} looks");
            // Pass 2: the eyes, every tick, as each bot keeps them.
            var tally = new Dictionary<string, Tally>();
            var hidden = new Dictionary<string, (int samples, int differed)>();
            var eye = new FastSim.Mpc.Sight();
            var shadow = new FastSim.Mpc.Sight();
            var mem = new Memory();
            var mem_b = new Memory();
            sim = start.clone_deep();
            var leaks = new HashSet<string>();
            for (long t = 0; t < end; t++)
            {
                var blind_now = BlindPlanner.blind_copy(sim, new SimRng(seed * 7919 + t));
                eye.look(sim);
                shadow.look(blind_now);
                mem.Observe(sim);
                mem_b.Observe(blind_now);
                WorldModel w = null;
                if (looks.TryGetValue(t, out var list))
                {
                    w = WorldModel.Read(sim, mem);
                    var x_all = obs(w);
                    var f_all = rl_frame(sim);
                    foreach (var (i, tell, cells, on) in list)
                    {
                        var h = sim.room.hazards[i];
                        string key = cls[i].Name;
                        if (!tally.TryGetValue(key, out var ta)) tally[key] = ta = new Tally();
                        int lead = (int)(on - t);
                        int j = (int)(room_t[(int)on] - room_t[(int)t]);
                        bool pure = at(t, i).Count == 0;
                        var seen = new bool?[BOTS.Length];
                        // blind: a blind copy stepped on the bot's own line.
                        var bc = BlindPlanner.blind_copy(sim, new SimRng(seed * 31 + t * 7 + i));
                        for (long k = 0; k < lead && !bc.is_over(); k++) bc.step(line[t + k] == 1);
                        if (!bc.is_over() && bc.state.room_index == 0) seen[0] = half(cells, c => kills_at(bc, i, c));
                        // world: the models, stepped on.
                        var wa = lead == 0 ? w : model_ahead(w, line, t, lead);
                        seen[1] = half(cells, c => model_hits(wa, i, c));
                        // mpc: shapes and warnings.
                        seen[3] = half(cells, c => sight_sees(eye, h, c, j));
                        // worldobs and rl: does the input change without this hazard?
                        // rl only where some danger point is in its grid (its field of view).
                        if (!tell || pure)
                        {
                            var w2 = w.Copy();
                            var m2 = w2.Find(i);
                            if (m2 != null) m2.alive = false;
                            seen[2] = !same(x_all, obs(w2));
                            var s2 = sim.clone_deep();
                            s2.room.hazards[i].alive = false;
                            if (cells.Any(c => in_rl_grid(sim, c))) seen[4] = !same(f_all, rl_frame(s2));
                        }
                        for (int b = 0; b < BOTS.Length; b++)
                        {
                            if (seen[b] == null) continue;
                            if (tell)
                            {
                                ta.tell_of[b]++;
                                if (seen[b] == true) ta.tell[b]++;
                            }
                            else
                            {
                                ta.deadly_of[b]++;
                                if (seen[b] == true) ta.deadly[b]++;
                            }
                        }
                        if (tell) ta.tell_n++;
                        else ta.deadly_n++;
                    }
                }
                if (t % LEAK_EVERY == 0)
                {
                    // Hidden draws: two blind copies must differ in each.
                    var a = BlindPlanner.blind_copy(sim, new SimRng(seed * 3 + t * 2 + 1));
                    var b = BlindPlanner.blind_copy(sim, new SimRng(seed * 3 + t * 2 + 2));
                    for (int i = 0; i < sim.room.hazards.Count; i++)
                    {
                        var ht = sim.room.hazards[i].GetType();
                        foreach (var f in hidden_fields(ht))
                        {
                            string k = $"{ht.Name}.{f.Name}";
                            hidden.TryGetValue(k, out var hv);
                            bool d = field_value(a.room.hazards[i], f) != field_value(b.room.hazards[i], f);
                            hidden[k] = (hv.samples + 1, hv.differed + (d ? 1 : 0));
                        }
                    }
                    // Every eye reads the same from a blind copy as from the truth.
                    w ??= WorldModel.Read(sim, mem);
                    var wb = WorldModel.Read(blind_now, mem_b);
                    if (!same(rl_frame(sim), rl_frame(blind_now))) leaks.Add($"rl reads a hidden value in {label} (tick {t})");
                    if (!same(obs(w), obs(wb))) leaks.Add($"worldobs reads a hidden value in {label} (tick {t})");
                    if (models_key(model_ahead(w, line, t, LEAD)) != models_key(model_ahead(wb, line, t, LEAD)))
                        leaks.Add($"world (Models.Read) reads a hidden value in {label} (tick {t})");
                    if (sight_key(eye) != sight_key(shadow)) leaks.Add($"mpc (Sight) reads a hidden value in {label} (tick {t})");
                }
                sim.step(line[t] == 1);
                if (t % 200 == 0) log($"pass 2 tick {t}");
            }
            // One message per eye and room.
            fails.AddRange(leaks.GroupBy(l => l[..l.IndexOf(" (tick")]).Select(g => g.First())
                .Where(l => !KNOWN_LEAKS.ContainsKey((l[..l.IndexOf(" reads")], label))));

            var stats = new JsonObject();
            foreach (var (k, ta) in tally)
                stats[k] = new JsonObject
                {
                    ["tell_n"] = ta.tell_n,
                    ["deadly_n"] = ta.deadly_n,
                    ["tell"] = new JsonArray(ta.tell.Select(v => (JsonNode)v).ToArray()),
                    ["tell_of"] = new JsonArray(ta.tell_of.Select(v => (JsonNode)v).ToArray()),
                    ["deadly"] = new JsonArray(ta.deadly.Select(v => (JsonNode)v).ToArray()),
                    ["deadly_of"] = new JsonArray(ta.deadly_of.Select(v => (JsonNode)v).ToArray()),
                };
            var hid = new JsonObject();
            foreach (var (k, (s, d)) in hidden) hid[k] = new JsonArray(s, d);
            var present = new JsonArray(cls.Distinct().Select(c => (JsonNode)c.Name).ToArray());
            return result(fails, new JsonObject
            {
                ["scene"] = label,
                ["ticks"] = end,
                ["seconds"] = clock.Elapsed.TotalSeconds,
                ["stats"] = stats,
                ["hidden"] = hid,
                ["present"] = present,
            });
        }

        /// The matrix over every scene: class -> bot -> (tell seen, of; deadly seen, of).
        static Dictionary<string, Tally> sum(List<JsonNode> results)
        {
            var out_ = new Dictionary<string, Tally>();
            foreach (var r in results)
                foreach (var (k, v) in r["stats"].AsObject())
                {
                    if (!out_.TryGetValue(k, out var ta)) out_[k] = ta = new Tally();
                    ta.tell_n += (int)v["tell_n"];
                    ta.deadly_n += (int)v["deadly_n"];
                    for (int b = 0; b < BOTS.Length; b++)
                    {
                        ta.tell[b] += (int)v["tell"][b];
                        ta.tell_of[b] += (int)v["tell_of"][b];
                        ta.deadly[b] += (int)v["deadly"][b];
                        ta.deadly_of[b] += (int)v["deadly_of"][b];
                    }
                }
            return out_;
        }

        /// "sees", "blind" or "-" (too few samples to judge).
        static string verdict(int seen, int of) => of < MIN_SAMPLES ? "-" : seen >= MIN_RATE * of ? "sees" : "blind";

        public override List<string> combine(List<JsonNode> results)
        {
            var fails = new List<string>();
            var m = sum(results);
            var present = results.SelectMany(r => r["present"].AsArray().Select(x => (string)x)).ToHashSet();
            bool filtered = (Environment.GetEnvironmentVariable("FASTSIM_SIGHT_ONLY") ?? "") != "";
            foreach (var t in classes())
                if (!filtered && !present.Contains(t.Name) && !BASES.ContainsKey(t))
                    fails.Add($"{t.Name}: no room scene holds it (add it to a room, or to SightCheck.BASES if it is only a base)");
            foreach (var (k, ta) in m)
                for (int b = 0; b < BOTS.Length; b++)
                    foreach (var (what, seen, of) in new[] { ("tell", ta.tell[b], ta.tell_of[b]), ("deadly", ta.deadly[b], ta.deadly_of[b]) })
                        if (verdict(seen, of) == "blind" && !KNOWN.ContainsKey((k, BOTS[b], what)))
                            fails.Add($"{BOTS[b]} is blind to {k} {(what == "tell" ? "tells" : "danger")}: sees {seen} of {of}");
            var hidden = new Dictionary<string, (int s, int d)>();
            foreach (var r in results)
                foreach (var (k, v) in r["hidden"].AsObject())
                {
                    hidden.TryGetValue(k, out var hv);
                    hidden[k] = (hv.s + (int)v[0], hv.d + (int)v[1]);
                }
            foreach (var (k, (s, d)) in hidden)
                if (d == 0) fails.Add($"blind_copy keeps the hidden draw {k} (the same in two blind copies, {s} looks)");
            return fails;
        }

        public override string summary(List<JsonNode> results)
        {
            var m = sum(results);
            var sb = new StringBuilder();
            sb.Append($"{results.Count} rooms, {m.Values.Sum(t => t.tell_n)} tells and {m.Values.Sum(t => t.deadly_n)} deadly looks over {m.Count} hazard classes");
            sb.Append("\n      hazard            ").Append(string.Join("", BOTS.Select(b => b.PadRight(18))));
            foreach (var (k, ta) in m.OrderBy(kv => kv.Key))
            {
                sb.Append("\n      ").Append(k.PadRight(18));
                for (int b = 0; b < BOTS.Length; b++)
                {
                    string cell(string what, int seen, int of)
                    {
                        string v = verdict(seen, of);
                        if (v == "-") return "-";
                        string pct = $"{100 * seen / of}";
                        if (v == "blind") return KNOWN.ContainsKey((k, BOTS[b], what)) ? "gap" + pct : "BLIND" + pct;
                        return pct;
                    }
                    sb.Append($"T{cell("tell", ta.tell[b], ta.tell_of[b])} D{cell("deadly", ta.deadly[b], ta.deadly_of[b])}".PadRight(18));
                }
            }
            return sb.ToString();
        }
    }
}
