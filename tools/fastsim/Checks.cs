using System.Diagnostics;
using System.Text.Json.Nodes;
using FastSim;

/// `fastsim check [names] [--filter x]`: every test of tools/check.ps1 that
/// plays a bot (SurvivalSearch, PlannerBot, the gap seeker, the random
/// tapper), on FastSim. Bots no longer play in the GDScript tests: parity
/// (tools/fastsim_parity.gd) proves this sim, these bots and the sims the
/// checks start from (BotSetups, Setups here) match the GDScript ones. Each
/// check keeps the rule and thresholds of the GDScript test it replaced, on
/// more cases. Exits 1 on any failure, with a message like that test's.
///   passable  was tests/sim/test_variants_passable.gd
///   arrival   was tests/sim/test_arrival_reaction.gd (ArrivalBench)
///   points    was tests/sim/test_room_points_cap.gd
///   revive    was tests/sim/test_revive_survivable.gd
///   pairs     was test_every_pair_has_a_way_through in tests/sim/test_double_trouble.gd
///   crawl, gates, isles  were the searches of tests/sim/test_<room>_passable.gd
///   rescued   was tests/sim/test_rooms_survivable.gd
///   runs      was tests/sim/test_bot_runs.gd
/// (CheckSearches.cs has the last five.) ArrivalBench's thresholds are pinned
/// by tests/unit/test_fastsim_checks.gd.
///
/// The cases of every check picked are shared out over --jobs worker
/// processes (this program with --worker), a few chunks per job.
static partial class Checks
{
    public static readonly List<Check> ALL = new()
    {
        new Passable(), new Arrival(), new Points(), new Revive(), new Pairs(),
        new Crawl(), new Gates(), new Isles(), new Rescued(), new Runs(),
    };

    public static int run(List<string> pos, Dictionary<string, string> opts, int jobs, string priority)
    {
        var picked = pick(pos.Count > 1 ? pos[1] : "all", opts.GetValueOrDefault("filter", ""));
        if (picked == null) return 2;
        if (picked.Count == 0)
        {
            Console.WriteLine("fastsim check: no check matches the filter");
            return 0;
        }
        // Every (check, case), interleaved so heavy and light cases mix.
        var flat = new List<(Check c, int n)>();
        int most = picked.Max(c => c.count());
        for (int n = 0; n < most; n++)
            foreach (var c in picked)
                if (n < c.count()) flat.Add((c, n));

        if (opts.ContainsKey("worker"))
        {
            int part = int.Parse(opts["part"]), parts = int.Parse(opts["parts"]);
            var out_ = new JsonArray();
            for (int i = part; i < flat.Count; i += parts)
            {
                var (c, n) = flat[i];
                var r = c.run(n);
                r["check"] = c.name;
                r["n"] = n;
                out_.Add(r);
            }
            File.WriteAllText(opts["out"], out_.ToJsonString());
            return 0;
        }

        var clock = Stopwatch.StartNew();
        var results = jobs <= 1 ? local(flat) : workers(picked, flat.Count, jobs, priority);
        if (results == null) return 3;
        int bad = 0;
        foreach (var c in picked)
        {
            var mine = results.Where(r => (string)r["check"] == c.name).OrderBy(r => (int)r["n"]).ToList();
            var fails = new List<string>();
            if (mine.Count != c.count()) fails.Add($"only {mine.Count} of {c.count()} cases ran");
            foreach (var r in mine)
                foreach (var f in r["fails"].AsArray()) fails.Add((string)f);
            fails.AddRange(c.combine(mine));
            string head = $"fastsim check {c.name} ({c.test}): {c.summary(mine)}";
            if (fails.Count == 0) Console.WriteLine(head + "  ok");
            else
            {
                bad++;
                Console.WriteLine(head + "  FAIL");
                foreach (var f in fails.Take(40)) Console.WriteLine("      " + f);
                if (fails.Count > 40) Console.WriteLine($"      ... and {fails.Count - 40} more");
            }
        }
        Console.WriteLine($"fastsim check: {picked.Count - bad} of {picked.Count} checks pass, {flat.Count} cases in {clock.Elapsed.TotalSeconds:F1} s ({Math.Min(jobs, flat.Count)} workers)");
        return bad == 0 ? 0 : 1;
    }

    /// The checks named ("all" or a comma list) that match `filter` (a check
    /// name, or part of the GD test it replaced ("path:method"), as tools/check.ps1
    /// -TestFilter). Null on an unknown name.
    static List<Check> pick(string names, string filter)
    {
        var out_ = new List<Check>();
        foreach (var name in names.Split(','))
        {
            if (name == "all")
            {
                out_.AddRange(ALL);
                continue;
            }
            var c = ALL.Find(x => x.name == name);
            if (c == null)
            {
                Console.Error.WriteLine($"unknown check '{name}': {string.Join(", ", ALL.Select(x => x.name))}");
                return null;
            }
            out_.Add(c);
        }
        if (filter == "" || filter == "fastsim") return out_.Distinct().ToList();
        return out_.Distinct().Where(c => c.name == filter || c.test.Contains(filter)).ToList();
    }

    static List<JsonNode> local(List<(Check c, int n)> flat)
    {
        var out_ = new List<JsonNode>();
        foreach (var (c, n) in flat)
        {
            var r = c.run(n);
            r["check"] = c.name;
            r["n"] = n;
            out_.Add(r);
        }
        return out_;
    }

    /// Splits the cases into chunks (a few per job, so a slow chunk doesn't
    /// hold up the end) and runs `jobs` worker processes at a time.
    static List<JsonNode> workers(List<Check> picked, int cases, int jobs, string priority)
    {
        int parts = Math.Min(cases, jobs * 4);
        string dir = Path.Combine(Path.GetTempPath(), "fastsim_check_" + Environment.ProcessId);
        Directory.CreateDirectory(dir);
        string names = string.Join(",", picked.Select(c => c.name));
        var queue = new Queue<int>(Enumerable.Range(0, parts));
        var running = new List<(Process p, int part)>();
        var results = new List<JsonNode>();
        bool failed = false;
        while (queue.Count > 0 || running.Count > 0)
        {
            while (running.Count < jobs && queue.Count > 0)
            {
                int part = queue.Dequeue();
                var psi = new ProcessStartInfo(Environment.ProcessPath) { UseShellExecute = false, CreateNoWindow = true };
                foreach (var a in new[] { "check", names, "--worker", "1", "--part", part.ToString(), "--parts", parts.ToString(),
                    "--out", Path.Combine(dir, $"part_{part}.json"), "--priority", priority, "--jobs", "1" })
                    psi.ArgumentList.Add(a);
                running.Add((Process.Start(psi), part));
            }
            var done = running.FirstOrDefault(r => r.p.HasExited);
            if (done.p == null)
            {
                Thread.Sleep(20);
                continue;
            }
            running.Remove(done);
            string json = Path.Combine(dir, $"part_{done.part}.json");
            if (done.p.ExitCode != 0 || !File.Exists(json))
            {
                Console.Error.WriteLine($"check worker {done.part} failed (exit {done.p.ExitCode})");
                failed = true;
                continue;
            }
            results.AddRange(JsonNode.Parse(File.ReadAllText(json)).AsArray().Select(x => x.DeepClone()));
        }
        try { Directory.Delete(dir, true); } catch { }
        return failed ? null : results;
    }

    static JsonObject result(List<string> fails, JsonObject extra = null)
    {
        var o = extra ?? new JsonObject();
        o["fails"] = new JsonArray(fails.Select(f => (JsonNode)f).ToArray());
        return o;
    }

    public abstract class Check
    {
        public abstract string name { get; }
        /// The GDScript test it replaced ("path:method"), for -TestFilter.
        public abstract string test { get; }
        public abstract int count();
        /// One case: {fails: [...], plus whatever combine needs}.
        public abstract JsonObject run(int n);
        /// Failures over every case together.
        public virtual List<string> combine(List<JsonNode> results) => new();
        public abstract string summary(List<JsonNode> results);
        List<object> _cases;
        protected List<object> cases => _cases ??= make();
        protected abstract List<object> make();
    }

    /// tests/sim/test_variants_passable.gd: SurvivalSearch gets through each
    /// practice seed of every variant and takes the first portal.
    public sealed class Passable : Check
    {
        public override string name => "passable";
        public override string test => "tests/sim/test_variants_passable.gd:test_rooms_are_passable_in_every_variant";
        /// Practice seeds per room variant (the GD test played the first 2 of these).
        public const long SEEDS_EACH = 6;
        /// test_variants_passable.gd CASES: [room id, ticks].
        public static readonly (string id, long ticks)[] CASES =
        {
            ("narrow", 900), ("tide", 1150), ("cloud", 1150), ("bramble", 1150), ("rain", 1150),
            ("swing", 1150), ("updraft", 1150), ("crosswind", 1150), ("belt", 1150), ("lockexit", 1700),
            ("lava", 1150), ("echo", 1150), ("bubbles", 1150), ("garden", 1150), ("slowmo", 2300),
            ("court", 1150), ("crowded", 1150), ("squeeze", 1150), ("blink", 1150), ("hunter", 1150),
            ("flip", 1150), ("midnight", 1150), ("sawring", 1150), ("bats", 1150), ("cupid", 1150),
            ("fireworks", 1150), ("crawl", 1150), ("crabs", 1150), ("pumpkin", 1150), ("keepy", 1150),
            ("beachball", 1150), ("hearts", 1150), ("isles", 1150), ("eggs", 1150), ("gates", 1150),
            ("ghostdoors", 1150), ("piston", 1150), ("stalac", 1150), ("crates", 1150), ("gifts", 1150),
        };

        public override int count() => cases.Count;

        /// [room id, practice seed, ticks] (seed -1: a variant with too few seeds),
        /// picked as test_variants_passable.gd _cases().
        protected override List<object> make()
        {
            var out_ = new List<object>();
            foreach (var (id, ticks) in CASES)
            {
                int index = (int)RoomCatalog.index_of(id);
                var def = RoomCatalog.all()[index];
                var wanted = new Dictionary<long, long>();
                for (long v = 0; v < Math.Max(def.variants.Count, 1); v++) wanted[v] = SEEDS_EACH;
                long seed_value = 500;
                while (wanted.Count > 0 && seed_value < 6000)
                {
                    seed_value += 37;
                    long v = new GameSim(seed_value, def.season, index).room.variant;
                    if (!wanted.ContainsKey(v)) continue;
                    wanted[v] -= 1;
                    if (wanted[v] == 0) wanted.Remove(v);
                    out_.Add((id, seed_value, ticks));
                }
                foreach (var v in wanted.Keys) out_.Add((id, -1L, v));
            }
            return out_;
        }

        public override JsonObject run(int n)
        {
            var (id, seed_value, ticks) = ((string, long, long))cases[n];
            if (seed_value < 0) return result(new() { $"{id}: variant {ticks} has fewer than {SEEDS_EACH} seeds" });
            int index = (int)RoomCatalog.index_of(id);
            var def = RoomCatalog.all()[index];
            var sim = new GameSim(seed_value, def.season, index);
            string what = $"{id} seed {seed_value} ({sim.room.variant_id()})";
            var search = new SurvivalSearch();
            bool ok = search.run(sim, ticks);
            var fails = new List<string>();
            if (!ok) fails.Add($"{what}: all died at tick {search.ticks_survived}");
            else if (search.best.state.room_index < 1) fails.Add($"{what}: took no portal");
            return result(fails);
        }

        public override string summary(List<JsonNode> results) =>
            $"{results.Count} searches, {SEEDS_EACH} practice seeds per variant of {CASES.Length} rooms";
    }

    /// tests/sim/test_arrival_reaction.gd (ArrivalBench): out of a portal a
    /// 0.75 s reaction is never killed by the room, and at 1 s at most
    /// MAX_EXTRA_PCT of arrivals leave no way to live; every room and every
    /// variant on its own.
    public sealed class Arrival : Check
    {
        public override string name => "arrival";
        public override string test => "tests/sim/test_arrival_reaction.gd:test_every_room_allows_a_slow_reaction_out_of_a_portal";
        /// Arrivals per room variant (the GD test played 8).
        public const long COUNT = 32;
        /// test_arrival_reaction.gd: the lighter PlannerBot. Only its deaths are
        /// searched, and a death with no way to live kills every bot, so the
        /// result does not hang on the bot.
        public const long AFTER = 120;
        public const long HORIZON = 45;
        public const long ROLLOUTS = 2;

        public override int count() => cases.Count;

        /// ArrivalBench.cases(): each variant of a room on its own, or just the
        /// room ("") when it has none.
        protected override List<object> make()
        {
            var out_ = new List<object>();
            var rooms = RoomCatalog.all();
            for (int index = 0; index < rooms.Count; index++)
            {
                if (rooms[index].variants.Count == 0) out_.Add((index, ""));
                foreach (var v in rooms[index].variants) out_.Add((index, v.id));
            }
            return out_;
        }

        /// ArrivalBench.play(..., check_forced = true) at EARLY_DELAY and at
        /// SimConfig.ARRIVAL_BLIND: arrivals the bot dies in with no way to live.
        static long forced(int index, string variant, long delay)
        {
            long n = 0;
            for (long i = 0; i < COUNT; i++)
            {
                var at = Reaction.arrival(index, i, variant);
                var (tick, _) = Reaction.play(at.clone_deep(), delay, new PlannerBot(i + 1, HORIZON, ROLLOUTS), delay + AFTER);
                if (tick >= 0 && Reaction.forced(at, delay, delay + AFTER)) n++;
            }
            return n;
        }

        public override JsonObject run(int n)
        {
            var (index, variant) = ((int, string))cases[n];
            var def = RoomCatalog.all()[index];
            string id = variant == "" ? def.id : $"{def.id}/{variant}";
            long early = forced(index, variant, Reaction.EARLY_DELAY);
            long late = forced(index, variant, SimConfig.ARRIVAL_BLIND);
            var fails = new List<string>();
            if (early > 0) fails.Add($"a 0.75 s reaction is killed in: {id} ({early} of {COUNT})");
            return result(fails, new JsonObject { ["id"] = id, ["total"] = COUNT, ["no_way"] = late });
        }

        /// The 1 s benchmark over every room and variant together.
        public override List<string> combine(List<JsonNode> results)
        {
            long total = results.Sum(r => (long)r["total"]);
            long no_way = results.Sum(r => (long)r["no_way"]);
            if (no_way * 100 > Reaction.MAX_EXTRA_PCT * total)
            {
                var worst = results.Where(r => (long)r["no_way"] > 0).OrderByDescending(r => (long)r["no_way"])
                    .Take(12).Select(r => $"{r["id"]} {r["no_way"]}");
                return new() { $"a 1 s reaction leaves no way to live in {no_way} of {total} arrivals (most: {string.Join(", ", worst)})" };
            }
            return new();
        }

        public override string summary(List<JsonNode> results)
        {
            long total = results.Sum(r => (long)r["total"]);
            long no_way = results.Sum(r => (long)r["no_way"]);
            return $"{results.Count} rooms/variants x {COUNT} arrivals, no way to live at 1 s in {no_way} of {total} ({100.0 * no_way / Math.Max(1, total):F2}%, limit {Reaction.MAX_EXTRA_PCT}%)";
        }
    }

    /// tests/sim/test_room_points_cap.gd: no room stay pays more than
    /// POINTS_PER_ROOM, in every room and variant and across a revive.
    public sealed class Points : Check
    {
        public override string name => "points";
        public override string test => "tests/sim/test_room_points_cap.gd:test_";
        /// Practice seeds per variant and revive runs (the GD test played 3
        /// and 40).
        public const long SEEDS_PER_VARIANT = 12;
        public const long REVIVE_RUNS = 160;
        public const long MAX_TICKS = 6000;

        public override int count() => cases.Count;

        /// [label, sim maker, revive]: every room x ("" + each variant) x seed,
        /// then the revive runs.
        protected override List<object> make()
        {
            var out_ = new List<object>();
            var rooms = RoomCatalog.all();
            for (int index = 0; index < rooms.Count; index++)
            {
                var def = rooms[index];
                var variants = new List<string> { "" };
                variants.AddRange(def.variants.Select(v => v.id));
                foreach (var variant in variants)
                    for (long s = 0; s < SEEDS_PER_VARIANT; s++)
                    {
                        int i = index;
                        long seed_value = 1000 + index * 37 + s;
                        string v = variant;
                        out_.Add(($"{def.id}/{variant} seed {s}", (Func<GameSim>)(() => new GameSim(seed_value, rooms[i].season, i, v)), false));
                    }
            }
            var seeds = new SimRng(4242);
            for (long run = 0; run < REVIVE_RUNS; run++)
            {
                long seed_value = seeds.next_u32();
                out_.Add(($"run {run}", (Func<GameSim>)(() => new GameSim(seed_value)), true));
            }
            return out_;
        }

        public override JsonObject run(int n)
        {
            var (label, make_sim, revive) = ((string, Func<GameSim>, bool))cases[n];
            var sim = make_sim();
            var bot = new SimRng(7);
            long room_index = sim.state.room_index;
            long entry_score = sim.state.score;
            long full = 0;
            var fails = new List<string>();
            while (sim.state.tick < MAX_TICKS)
            {
                if (sim.is_over())
                    if (!(revive && sim.can_revive() && sim.revive())) break;
                sim.step(SimBots.gap_seeker(sim, bot));
                if (sim.state.room_index != room_index)
                {
                    if (sim.state.score - entry_score == SimConfig.POINTS_PER_ROOM) full++;
                    room_index = sim.state.room_index;
                    entry_score = sim.state.score;
                }
                long gained = sim.state.score - entry_score;
                if (gained > SimConfig.POINTS_PER_ROOM || sim.room.points > SimConfig.POINTS_PER_ROOM)
                {
                    fails.Add($"{label}: {gained} points in one room (tick {sim.state.tick})");
                    break;
                }
            }
            return result(fails, new JsonObject { ["full"] = revive ? 0 : full });
        }

        /// The bot reaches the cap in many rooms (else the check proves little).
        public override List<string> combine(List<JsonNode> results)
        {
            long full = results.Sum(r => (long)r["full"]);
            return full > RoomCatalog.all().Count ? new() : new() { $"the bot reaches the cap in many rooms: only {full} stays did" };
        }

        public override string summary(List<JsonNode> results) =>
            $"{results.Count} runs ({SEEDS_PER_VARIANT} seeds per room variant, {REVIVE_RUNS} with a revive), {results.Sum(r => (long)r["full"])} stays hit the cap";
    }

    /// tests/sim/test_revive_survivable.gd: after a revive, in every room,
    /// whatever the exit was doing, SurvivalSearch finds a way to live on.
    /// The GD test played one exit case and wall per room; this plays all.
    public sealed class Revive : Check
    {
        public override string name => "revive";
        public override string test => "tests/sim/test_revive_survivable.gd:test_every_room_is_survivable_after_a_revive";
        public static readonly long TICKS = SimConfig.ARRIVAL_HOLD + 180;
        public static readonly string[] CASES = { "none", "open", "ghost" };

        public override int count() => cases.Count;

        protected override List<object> make()
        {
            var out_ = new List<object>();
            for (int index = 0; index < RoomCatalog.all().Count; index++)
                foreach (var exit in CASES)
                    for (long side = 0; side < 2; side++) out_.Add((index, exit, side));
            return out_;
        }

        public override JsonObject run(int n)
        {
            var (index, exit, side) = ((int, string, long))cases[n];
            var sim = Setups.revived(index, 9000 + index, exit, side);
            var search = new SurvivalSearch();
            var fails = new List<string>();
            if (!search.run(sim, TICKS))
            {
                string deaths = string.Join(", ", search.last_deaths.Select(kv => $"{kv.Key}: {kv.Value}"));
                fails.Add($"{RoomCatalog.all()[index].id}, exit {exit} on wall {side}: all died {search.ticks_survived} ticks after the revive ({deaths})");
            }
            return result(fails);
        }

        public override string summary(List<JsonNode> results) =>
            $"{results.Count} revives (every room x {CASES.Length} exit cases x both walls)";
    }

    /// tests/sim/test_double_trouble.gd test_every_pair_has_a_way_through:
    /// SurvivalSearch lives through each pair's practice seeds.
    public sealed class Pairs : Check
    {
        public override string name => "pairs";
        public override string test => "tests/sim/test_double_trouble.gd:test_every_pair_has_a_way_through";
        /// Seeds searched per pair (the GD test played the first 2) and how long.
        public const long SEARCH_SEEDS = 8;
        public const long SEARCH_TICKS = 600;

        public override int count() => cases.Count;

        protected override List<object> make()
        {
            int n = RoomCatalog.find("double").variants.Count;
            return Enumerable.Range(0, n * (int)SEARCH_SEEDS).Select(i => (object)i).ToList();
        }

        public override JsonObject run(int n)
        {
            int index = (int)RoomCatalog.index_of("double");
            var def = RoomCatalog.all()[index];
            long pairs = def.variants.Count;
            long i = (int)cases[n];
            long p = i % pairs;
            var fails = new List<string>();
            // The first practice seed whose pair is `p`, by the hazards the room built.
            for (long s = 1000 + i * 7; s < 3000; s++)
            {
                var sim = new GameSim(s, def.season, index);
                if (sim.room.variant != p) continue;
                var search = new SurvivalSearch();
                if (!search.run(sim, SEARCH_TICKS)) fails.Add($"pair {p} seed {s}: all died at tick {search.ticks_survived}");
                return result(fails);
            }
            return result(new() { $"no seed for pair {p}" });
        }

        public override string summary(List<JsonNode> results) =>
            $"{results.Count} searches ({SEARCH_SEEDS} seeds per pair)";
    }
}
