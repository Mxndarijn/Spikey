using System.Collections;
using System.Reflection;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using FastSim.Yard;

namespace FastSim.Measure;

/// What the screen shows, deny by default (`visible.tsv` next to this file).
/// A field of the sim (SimState, RoomRuntime, a hazard) is visible only when
/// the game's drawing code reads it: `state.<field>` and `room.<field>` in
/// game/run/*.gd, `h.<field>` in a hazard's painter (game/run/painters/<kind>_painter.gd),
/// and the fields the sim's methods called there read (one level). Every other
/// field is hidden, the new ones too, until a painter draws it.
/// `fastsim measure visibility --write` rebuilds the file from the sources;
/// `fastsim check yardstick` fails when it is stale.
public static class Visibility
{
    /// tools/fastsim/Measure/visible.tsv, found from the build folder (bin/Release/net9.0).
    public static string file
    {
        get
        {
            for (var d = new DirectoryInfo(AppContext.BaseDirectory); d != null; d = d.Parent)
            {
                string p = Path.Combine(d.FullName, "Measure", "visible.tsv");
                if (File.Exists(p) || File.Exists(Path.Combine(d.FullName, "FastSim.csproj"))) return p;
            }
            return Path.Combine(AppContext.BaseDirectory, "visible.tsv");
        }
    }
    public static string source_file(string root) => Path.Combine(root, "tools", "fastsim", "Measure", "visible.tsv");

    static HashSet<string> _vis;
    public static HashSet<string> visible()
    {
        if (_vis != null) return _vis;
        string path = File.Exists(file) ? file : null;
        var set = new HashSet<string>();
        if (path != null)
            foreach (var l in File.ReadAllLines(path))
                if (!l.StartsWith('#') && l.Contains('\t')) set.Add(l.Split('\t')[0]);
        return _vis = set;
    }

    /// Types whose fields make up the game state the bots see.
    public static IEnumerable<Type> state_types()
    {
        yield return typeof(SimState);
        yield return typeof(RoomRuntime);
        foreach (var t in typeof(Hazard).Assembly.GetTypes().Where(t => t.IsSubclassOf(typeof(Hazard)) && !t.IsAbstract).OrderBy(t => t.Name))
            yield return t;
    }

    public static IEnumerable<FieldInfo> fields(Type t)
    {
        for (var x = t; x != null && x != typeof(object); x = x.BaseType)
            foreach (var f in x.GetFields(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.DeclaredOnly))
                if (!f.Name.Contains('<')) yield return f;
    }

    /// Visible names are "Class.field"; a hazard's base fields count under its own class.
    public static bool is_visible(Type t, string field) => visible().Contains(t.Name + "." + field);

    static string pascal(string snake) => string.Concat(snake.Split('_').Select(w => w.Length == 0 ? w : char.ToUpperInvariant(w[0]) + w[1..]));

    /// Rebuilds the visible list from the drawing code and the sim's sources.
    public static List<string> generate(string root)
    {
        var rows = new List<(string key, string from)>();
        string game = Path.Combine(root, "game", "run");
        // A name the drawing code reads is a field (visible as it is) or a method; a method the
        // view calls without arguments is visible by its result (its inputs may stay hidden:
        // a tide's salt is not on screen, the tide's depth now is). Methods with arguments
        // are geometry of fields already listed.
        void add(Type t, IEnumerable<string> names, string from)
        {
            var fs = fields(t).Select(f => f.Name).ToHashSet();
            foreach (var n in names.Distinct())
            {
                if (fs.Contains(n)) rows.Add(($"{t.Name}.{n}", from));
                else if (no_arg_method(t, n) != null) rows.Add(($"{t.Name}.{n}()", from));
            }
        }
        var views = Directory.GetFiles(game, "*.gd").Concat(Directory.GetFiles(Path.Combine(game, "painters"), "*.gd")).ToList();
        var state_names = new HashSet<string>();
        var room_names = new HashSet<string>();
        foreach (var p in views)
        {
            string s = File.ReadAllText(p);
            // Local names for the state and the room ("var s := _run.sim.state").
            var st = new List<string> { "state", "prev_state" };
            var rm = new List<string> { "room" };
            foreach (Match m in Regex.Matches(s, @"var\s+(\w+)\s*(?::=|:\s*\w+\s*=)\s*[\w.]*\b(?:state|prev_state)\s*\r?$", RegexOptions.Multiline)) st.Add(m.Groups[1].Value);
            foreach (Match m in Regex.Matches(s, @"var\s+(\w+)\s*(?::=|:\s*\w+\s*=)\s*[\w.]*\broom\s*\r?$", RegexOptions.Multiline)) rm.Add(m.Groups[1].Value);
            foreach (Match m in Regex.Matches(s, $@"\b(?:{string.Join("|", st.Distinct())})\.([a-z_][a-z0-9_]*)")) state_names.Add(m.Groups[1].Value);
            foreach (Match m in Regex.Matches(s, $@"\b(?:{string.Join("|", rm.Distinct())})\.([a-z_][a-z0-9_]*)")) room_names.Add(m.Groups[1].Value);
        }
        add(typeof(SimState), state_names, "game/run/*.gd state.<field>");
        add(typeof(RoomRuntime), room_names, "game/run/*.gd room.<field>");
        foreach (var t in state_types().Where(t => t.IsSubclassOf(typeof(Hazard))))
        {
            string kind = Regex.Replace(t.Name, "(?<!^)([A-Z])", "_$1").ToLowerInvariant();
            string painter = Path.Combine(game, "painters", kind + "_painter.gd");
            if (!File.Exists(painter)) continue;
            string s = File.ReadAllText(painter);
            var names = Regex.Matches(s, @"\bh\.([a-z_][a-z0-9_]*)").Select(m => m.Groups[1].Value).ToList();
            // Every hazard's position and life are drawn by the layer itself.
            names.AddRange(new[] { "alive", "x", "y" });
            add(t, names, $"game/run/painters/{kind}_painter.gd");
        }
        return rows.Distinct().OrderBy(r => r.key).Select(r => $"{r.key}\t{r.from}").ToList();
    }

    public static MethodInfo no_arg_method(Type t, string name) =>
        t.GetMethods(BindingFlags.Public | BindingFlags.Instance)
            .FirstOrDefault(m => m.Name == name && m.ReturnType != typeof(void) && m.GetParameters().All(p => p.IsOptional));

    public static string header => "# Fields the screen shows (deny by default: every other field is hidden). Built by `fastsim measure visibility --write` from game/run.\n";

    // ------------------------------------------------------------ hashing

    static long hash_value(long h, object v)
    {
        switch (v)
        {
            case null: return SimHash.mix(h, 0);
            case long l: return SimHash.mix(h, l);
            case int i: return SimHash.mix(h, i);
            case bool b: return SimHash.mix(h, b ? 1 : 0);
            case string s: foreach (char ch in s) h = SimHash.mix(h, ch); return h;
            case IList list:
                h = SimHash.mix(h, list.Count);
                foreach (var e in list) h = hash_value(h, e);
                return h;
            default:
                if (v.GetType().IsEnum) return SimHash.mix(h, Convert.ToInt64(v));
                return h; // objects (defs, RNGs) are not values on screen
        }
    }

    static readonly Dictionary<Type, (FieldInfo[] f, MethodInfo[] m)> _shown = new();

    /// The visible fields and no-argument methods of a type.
    static (FieldInfo[] f, MethodInfo[] m) shown(Type t)
    {
        lock (_shown)
        {
            if (_shown.TryGetValue(t, out var x)) return x;
            var f = fields(t).Where(f => is_visible(t, f.Name)).ToArray();
            var m = visible().Where(k => k.StartsWith(t.Name + ".") && k.EndsWith("()"))
                .Select(k => no_arg_method(t, k[(t.Name.Length + 1)..^2])).Where(m => m != null).ToArray();
            return _shown[t] = (f, m);
        }
    }

    static long hash_obj(long h, Type t, object o)
    {
        var (fs, ms) = shown(t);
        foreach (var f in fs) h = hash_value(h, f.GetValue(o));
        foreach (var m in ms)
        {
            object v;
            try { v = m.Invoke(o, m.GetParameters().Select(p => p.DefaultValue).ToArray()); }
            catch (TargetInvocationException) { v = null; }
            h = hash_value(h, v);
        }
        return h;
    }

    /// A checksum of what the screen shows: every visible field and method result.
    public static long checksum(GameSim sim)
    {
        long h = SimHash.SEED;
        h = hash_obj(h, typeof(SimState), sim.state);
        h = hash_obj(h, typeof(RoomRuntime), sim.room);
        h = SimHash.mix(h, sim.room.hazards.Count);
        foreach (var hz in sim.room.hazards)
        {
            h = hash_value(h, hz.GetType().Name);
            h = hash_obj(h, hz.GetType(), hz);
        }
        return h;
    }

    /// Copies every hidden field of `dst`'s state, room and hazards from `donor`
    /// (same room and variant, hazards matched by place and type). Returns the
    /// number of fields copied, or -1 when the hazards do not line up.
    /// Fields a transplant never copies: whether the bird is alive is not a hidden draw.
    static readonly HashSet<string> LIFE = new() { "SimState.alive", "SimState.death_cause", "SimState.revives" };

    static IEnumerable<(string name, Type t, FieldInfo f, object a, object b)> candidates(GameSim dst, GameSim donor)
    {
        IEnumerable<(string, Type, FieldInfo, object, object)> of(Type t, object a, object b, string tag)
        {
            foreach (var f in fields(t))
            {
                if (is_visible(t, f.Name) || f.IsInitOnly || f.IsLiteral || LIFE.Contains($"{t.Name}.{f.Name}")) continue;
                // Plain values, RNGs and lists of numbers only: references to other objects
                // (a gate's partner, the room's def) belong to the donor's world.
                var ft = f.FieldType;
                if (!(ft.IsValueType || ft == typeof(SimRng) || ft == typeof(List<long>) || ft == typeof(long[]))) continue;
                object v = f.GetValue(b), old = f.GetValue(a);
                if (Equals(v, old) || v is List<long> l1 && old is List<long> l2 && l1.SequenceEqual(l2)) continue;
                yield return ($"{t.Name}{tag}.{f.Name}", t, f, a, b);
            }
        }
        foreach (var x in of(typeof(SimState), dst.state, donor.state, "")) yield return x;
        foreach (var x in of(typeof(RoomRuntime), dst.room, donor.room, "")) yield return x;
        for (int i = 0; i < dst.room.hazards.Count; i++)
            foreach (var x in of(dst.room.hazards[i].GetType(), dst.room.hazards[i], donor.room.hazards[i], $"[{i}]")) yield return x;
    }

    static bool lines_up(GameSim dst, GameSim donor)
    {
        if (dst.room.hazards.Count != donor.room.hazards.Count) return false;
        for (int i = 0; i < dst.room.hazards.Count; i++)
            if (dst.room.hazards[i].GetType() != donor.room.hazards[i].GetType()) return false;
        return true;
    }

    /// The hidden fields a transplant from `donor` would change.
    public static List<string> transplant_fields(GameSim dst, GameSim donor) =>
        lines_up(dst, donor) ? candidates(dst, donor).Select(c => c.name).ToList() : new List<string>();

    /// Copies every hidden field of `dst`'s state, room and hazards from `donor`
    /// (same room and variant, hazards matched by place and type), or only the
    /// field `only`. One field at a time, kept only when the screen stays the
    /// same (a hidden input of something shown, such as a tide's salt, would
    /// change it). Returns the number of fields copied, or -1 when the hazards
    /// do not line up.
    public static int transplant(GameSim dst, GameSim donor)
    {
        if (!lines_up(dst, donor)) return -1;
        long screen = checksum(dst);
        int n = 0;
        foreach (var c in candidates(dst, donor).ToList())
            if (set(dst, c, screen)) n++;
        return n;
    }

    public static bool transplant(GameSim dst, GameSim donor, string only)
    {
        if (!lines_up(dst, donor)) return false;
        long screen = checksum(dst);
        var c = candidates(dst, donor).FirstOrDefault(c => c.name == only);
        return c.name != null && set(dst, c, screen);
    }

    static bool set(GameSim dst, (string name, Type t, FieldInfo f, object a, object b) c, long screen)
    {
        object v = c.f.GetValue(c.b), old = c.f.GetValue(c.a);
        c.f.SetValue(c.a, v switch { SimRng r => r.Clone(), List<long> l => new List<long>(l), long[] arr => (long[])arr.Clone(), _ => v });
        if (checksum(dst) == screen) return true;
        c.f.SetValue(c.a, old);
        return false;
    }

    /// Hidden fields (not on screen) that the bot's own blind_copy leaves as they are:
    /// the blind spots of the old leak check, which only tested blind_copy's list.
    public static List<string> unscrambled(GameSim sim)
    {
        var res = new List<string>();
        var b = BlindPlanner.blind_copy(sim, new SimRng(12345));
        void cmp(Type t, object a, object c)
        {
            foreach (var f in fields(t))
            {
                if (is_visible(t, f.Name) || f.IsLiteral) continue;
                var va = f.GetValue(a);
                if (va is SimRng || va is RoomDef || va is IList) continue;
                if (Equals(va, f.GetValue(c))) res.Add($"{t.Name}.{f.Name}");
            }
        }
        cmp(typeof(SimState), sim.state, b.state);
        cmp(typeof(RoomRuntime), sim.room, b.room);
        for (int i = 0; i < Math.Min(sim.room.hazards.Count, b.room.hazards.Count); i++) cmp(sim.room.hazards[i].GetType(), sim.room.hazards[i], b.room.hazards[i]);
        return res;
    }
}

/// The whole-run leak check (`fastsim measure leak`, docs/BOT_TESTING.md).
/// On its own seeds (900 001 and up) the bot plays whole runs once (a bank).
/// Forks are spread over the whole run: random bounces, plus every boss room
/// (a bounce soon after entry) and every exit draw (the bounce before the exit
/// preview shows). At a fork two fresh copies of the bot (same seed) play two
/// sims that show the same screen: A is the real one, B has every hidden draw
/// replaced: the RNGs and seeds (BlindPlanner.blind_copy) and then, deny by
/// default, every field the screen does not show (`visible.tsv`) copied from a
/// donor: the same room and variant drawn again from the room's entry with
/// another spine, flown with the same taps to the fork tick. Until the
/// visible checksum differs, an honest bot taps the same in both; a tap that
/// differs earlier is a leak.
public static class LeakRun
{
    public const long WINDOW = 400;
    public sealed record Fork(long seed, long at, string why, string room, string verdict, long first_diff, long visible_from, int transplanted, string cause);

    public static JsonObject check(BotSpec bot, Dictionary<string, string> opts, int threads, Action<string> log)
    {
        int seeds = int.Parse(opts.GetValueOrDefault("seeds", "12"));
        int random_forks = int.Parse(opts.GetValueOrDefault("forks", "40"));
        long cap = long.Parse(opts.GetValueOrDefault("cap", BotCaps.RUN_CAP.ToString()));
        long points = long.Parse(opts.GetValueOrDefault("points", "400"));
        Bank bank;
        if (opts.TryGetValue("bank", out var bp) && File.Exists(bp)) bank = Bank.load(bp);
        else
        {
            bank = Bank.make(bot, SeedSets.LEAK, seeds, cap, points, threads, log);
            if (opts.ContainsKey("bank")) bank.save(opts["bank"]);
        }
        if (Visibility.visible().Count == 0) throw new InvalidDataException($"no visible list at {Visibility.file}");
        // Pick the forks per run.
        var jobs = new List<(int run, long tick, string why)>();
        foreach (var (r, i) in bank.runs.Select((r, i) => (r, i)))
        {
            var marks = fork_points(r, random_forks, new Random((int)(r.seed % 100000)));
            jobs.AddRange(marks.Select(m => (i, m.tick, m.why)));
        }
        var res = new Fork[jobs.Count];
        int done = 0;
        Parallel.ForEach(jobs.Select((j, i) => (j, i)).GroupBy(x => x.j.run), new ParallelOptions { MaxDegreeOfParallelism = threads }, g =>
        {
            var r = bank.runs[g.Key];
            foreach (var (j, i) in g)
            {
                res[i] = fork(bot, r, j.tick, j.why);
                int d = Interlocked.Increment(ref done);
                if (d % 50 == 0) log?.Invoke($"  leak forks {d}/{jobs.Count}");
            }
        });
        var tested = res.Where(f => f.verdict is "leak" or "same").ToList();
        int leaks = tested.Count(f => f.verdict == "leak");
        double power(int every) => 1 - Math.Pow(1 - 1.0 / every, tested.Count);
        var by_room = new JsonObject();
        foreach (var g in tested.GroupBy(f => f.room.Split('@')[0]).OrderByDescending(g => g.Count()))
            by_room[g.Key] = $"{g.Count()} forks, {g.Count(f => f.verdict == "leak")} leaks";
        var by_why = new JsonObject();
        foreach (var g in res.GroupBy(f => f.why)) by_why[g.Key] = $"{g.Count(f => f.verdict is "leak" or "same")} tested of {g.Count()}, {g.Count(f => f.verdict == "leak")} leaks";
        // Fields the screen does not show that the bot's own blind_copy keeps: the old check never varied them.
        var blind_spots = new SortedSet<string>();
        foreach (var r in bank.runs.Take(4))
            foreach (var v in r.visits.Where((v, k) => k % 3 == 0))
            {
                var pre = Bank.replay(r, v.tick + 30);
                if (!pre.is_over()) foreach (var f in Visibility.unscrambled(pre)) blind_spots.Add(f);
            }
        var ex = res.FirstOrDefault(f => f.verdict == "leak");
        var o = new JsonObject
        {
            ["leaks"] = tested.Count == 0 ? "untested" : leaks > 0 ? "yes" : "no",
            ["bot"] = bot.name,
            ["seeds"] = $"{SeedSets.LEAK + 1}..{SeedSets.LEAK + bank.runs.Count}",
            ["forks_tested"] = tested.Count,
            ["forks_leaking"] = leaks,
            ["forks_untested"] = res.Length - tested.Count,
            ["deepest_fork_points"] = tested.Count == 0 ? 0 : tested.Max(f => bank.runs.First(r => r.seed == f.seed).visits.LastOrDefault(v => v.tick <= f.at)?.score ?? 0),
            ["with_donor"] = tested.Count(f => f.transplanted >= 0),
            ["power"] = new JsonObject { ["leak_1_in_100_flights"] = Math.Round(power(100), 3), ["1_in_200"] = Math.Round(power(200), 3), ["1_in_1000"] = Math.Round(power(1000), 3) },
            ["by_reason"] = by_why,
            ["by_room"] = by_room,
            ["hidden_but_kept_by_blind_copy"] = new JsonArray(blind_spots.Select(s => (JsonNode)s).ToArray()),
            ["how"] = "forks over whole runs (random bounces, boss rooms, exit draws); B gets new RNGs and, deny by default, every field visible.tsv does not list from a redrawn donor of the same room; a tap differing before the visible checksum does is a leak",
        };
        o["leak_forks"] = new JsonArray(res.Where(f => f.verdict == "leak").Select(f =>
            (JsonNode)$"seed {f.seed} tick {f.at} ({f.why}, {f.room}): taps differ at {f.first_diff}; read: {f.cause}").ToArray());
        if (ex != null)
            o["example"] = $"seed {ex.seed} ({ex.why}, {ex.room}), fork at tick {ex.at}: taps differ at {ex.first_diff}, " +
                (ex.visible_from < 0 ? "nothing visible differed yet" : $"the screen differed only from {ex.visible_from}");
        return o;
    }

    /// Bounce ticks to fork at: `n` random ones, the first bounce 30+ ticks into
    /// every boss room, and the bounce before every exit preview.
    static List<(long tick, string why)> fork_points(BankRun r, int n, Random rng)
    {
        var sim = new GameSim(r.seed, r.season);
        var set = new HashSet<long>(r.taps);
        var bounces = new List<long>();
        var res = new List<(long, string)>();
        long boss_from = -1, last_bounce = -1;
        long end = r.ticks;
        while (sim.state.tick < end && !sim.is_over())
        {
            long t = sim.state.tick;
            long ri = sim.state.room_index;
            sim.step(set.Contains(t));
            bool bounce = sim.events.Contains(Event.BOUNCE) && sim.state.room_index == ri;
            if (sim.state.room_index != ri && sim.room.def.boss) boss_from = sim.state.tick + 30;
            if (sim.events.Contains(Event.EXIT_PREVIEW) && last_bounce > 0) res.Add((last_bounce, "exit draw"));
            if (bounce)
            {
                bounces.Add(sim.state.tick);
                last_bounce = sim.state.tick;
                if (boss_from >= 0 && sim.state.tick >= boss_from) { res.Add((sim.state.tick, "boss room")); boss_from = -1; }
            }
        }
        // Forks need a whole flight before the death.
        bounces = bounces.Where(b => b < end - 100).ToList();
        for (int i = 0; i < n && bounces.Count > 0; i++) res.Add((bounces[rng.Next(bounces.Count)], "random"));
        // Exit draws are many (one per room): keep every boss fork, a sample of the rest.
        var exits = res.Where(x => x.Item2 == "exit draw").OrderBy(_ => rng.Next()).Take(n).ToList();
        return res.Where(x => x.Item2 != "exit draw").Concat(exits).Where(x => x.Item1 < end - 100).Distinct().ToList();
    }

    public static Fork fork(BotSpec bot, BankRun r, long at, string why)
    {
        var sa = Bank.replay(r, at);
        if (sa.is_over()) return new Fork(r.seed, at, why, "", "dead", -1, -1, -1, "");
        string room = Bank.key(sa);
        // The donor: the room this fork is in, drawn again from its entry, flown with the run's taps.
        GameSim donor = null;
        var entry = r.visits.LastOrDefault(v => v.tick < at);
        if (entry != null)
        {
            var pre = Bank.replay(r, entry.tick);
            var set = new HashSet<long>(r.taps);
            for (long k = 0; k < 64 && donor == null; k++)
            {
                var c = Strat.redraw(pre, entry.tap, Strat.spine_seed(r.seed, entry.tick, 50_000 + k));
                if (c == null || Run.room_name(c) != Run.room_name(sa)) continue;
                long ri = c.state.room_index;
                while (c.state.tick < at && !c.is_over() && c.state.room_index == ri) c.step(set.Contains(c.state.tick));
                if (c.state.tick == at && !c.is_over() && c.state.room_index == ri) donor = c;
            }
        }
        var A0 = sa.clone_deep();
        var B0 = BlindPlanner.blind_copy(sa, new SimRng(Strat.spine_seed(r.seed, at, 99)));
        var B = B0.clone_deep();
        int moved = donor == null ? -1 : Visibility.transplant(B, donor);
        if (Visibility.checksum(A0) != Visibility.checksum(B))
            return new Fork(r.seed, at, why, room, "visible at fork", -1, at, moved, "");
        // Two fresh bots (same seed) on A and B, until a tap or the screen differs.
        (long diff, long vis, bool crash) pair(GameSim b_sim)
        {
            var a = bot.make(r.seed + 77);
            var b = bot.make(r.seed + 77);
            var A = A0.clone_deep();
            var Bs = b_sim.clone_deep();
            try
            {
                while (A.state.tick < at + WINDOW && !A.is_over() && !Bs.is_over())
                {
                    long t = A.state.tick;
                    if (Visibility.checksum(A) != Visibility.checksum(Bs)) return (-1, t, false);
                    bool ta = a(A), tb = b(Bs);
                    if (ta != tb) return (t, -1, false);
                    A.step(ta);
                    Bs.step(tb);
                }
            }
            catch (Exception e) when (e is IndexOutOfRangeException or ArgumentOutOfRangeException or NullReferenceException or InvalidOperationException)
            {
                return (-1, -1, true);
            }
            return (-1, -1, false);
        }
        var (first_diff, visible_from, crashed) = pair(B);
        if (crashed) return new Fork(r.seed, at, why, room, "crash", -1, -1, moved, "");
        bool leak = first_diff >= 0;
        string cause = "";
        if (leak)
        {
            // What did it read? First the replaced RNGs and seeds alone, then each copied field alone.
            if (pair(B0).diff >= 0) cause = "an RNG or seed blind_copy replaces";
            else if (donor != null)
            {
                var hits = new List<string>();
                foreach (var f in Visibility.transplant_fields(B0, donor))
                {
                    var one = B0.clone_deep();
                    if (!Visibility.transplant(one, donor, f)) continue;
                    if (pair(one).diff >= 0) hits.Add(f);
                }
                cause = hits.Count > 0 ? string.Join(" ", hits) : "only several fields together";
            }
        }
        return new Fork(r.seed, at, why, room, leak ? "leak" : "same", first_diff, visible_from, moved, cause);
    }
}
