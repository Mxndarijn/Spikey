using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using FastSim;

// FastSim: the playtest bots on the C# copy of the sim. See PORTING.md.
//   fastsim parity <cases.txt>                       check against Godot's sim
//   fastsim search [seeds] [room] [ticks]           can anyone survive each room?
//   fastsim searchruns [seeds] [ticks]              full runs through the portals
//   fastsim rooms [seeds] [room]                    PlannerBot per room
//   fastsim runs [seeds]                            PlannerBot full runs
//   fastsim bench
//   fastsim reaction [arrivals] [room] [delays]     portal arrivals, slow vs instant reaction
//   fastsim odds [runs] [delays]                    real runs, every arrival at each reaction
//   fastsim combos [seeds] [arrivals]               Double Trouble fairness gate (Combos.cs)
//   fastsim check [all|passable,arrival,...]        the check's bot tests (Checks.cs);
//                                                   --filter x as tools/check.ps1 -TestFilter
//   fastsim runfile <seed> [bot_seed] --out <file>  a gap_seeker run as a run file
//                                                   (Bots/RunFile.cs, docs/RENDERING.md)
// Options: --out <file.json>, --jobs <n> (worker processes), --first <n>
//   (skip seeds), --priority idle|belownormal|normal (default belownormal),
//   --variant <id>|all (search, rooms, reaction; scan: one id: play that room variant
//   instead of the drawn one; "all" plays each variant in turn, one report
//   line per variant).
// Seeds and JSON match tools/playtest.gd, so results line up with Godot sweeps.
//
// The sweeps run as worker processes (one seed slice each), not threads: the
// searches keep many sims alive, and with one shared heap the garbage
// collector stalls every thread. Separate processes each have a small heap.

var opts = new Dictionary<string, string>();
var pos = new List<string>();
for (int i = 0; i < args.Length; i++)
{
    if (args[i].StartsWith("--") && i + 1 < args.Length) opts[args[i][2..]] = args[++i];
    else pos.Add(args[i]);
}
string mode = pos.Count > 0 ? pos[0] : "search";
string P(int i, string d) => pos.Count > i ? pos[i] : d;

var priority = opts.GetValueOrDefault("priority", "belownormal").ToLowerInvariant();
try
{
    Process.GetCurrentProcess().PriorityClass = priority switch
    {
        "idle" => ProcessPriorityClass.Idle,
        "normal" => ProcessPriorityClass.Normal,
        _ => ProcessPriorityClass.BelowNormal,
    };
}
catch { }
// Default: a quarter of the cores, so the PC stays usable (--jobs for more).
int jobs = int.Parse(opts.GetValueOrDefault("jobs", Math.Max(1, Environment.ProcessorCount / 4).ToString()));
long first = long.Parse(opts.GetValueOrDefault("first", "0"));
bool worker = opts.ContainsKey("worker");
RoomCatalog.all();
RoomCatalog.first_index();
Targets.variant = opts.GetValueOrDefault("variant", "");
if (mode == "check") return Checks.run(pos, opts, jobs, priority);
if (mode == "runfile")
    return RunFile.run_mode(long.Parse(P(1, "1")), long.Parse(P(2, "1")), opts.GetValueOrDefault("out", "run.json"));
if (Targets.variant != "")
{
    if (mode != "search" && mode != "rooms" && mode != "reaction" && mode != "scan")
    {
        Console.Error.WriteLine("--variant works with the search, rooms, reaction and scan modes only");
        return 2;
    }
    string filter = mode == "scan" ? P(1, "*") : P(2, "*");
    if (Targets.pick(filter, mode == "reaction").Count == 0)
    {
        Console.Error.WriteLine($"no room matching '{filter}' has a variant '{Targets.variant}'");
        foreach (var d in RoomCatalog.all())
            if (d.variants.Count > 0 && Targets.matches(d, filter, mode == "reaction"))
                Console.Error.WriteLine($"  {d.id}: {string.Join(", ", d.variants.Select(v => v.id))}");
        return 2;
    }
}

var clock = Stopwatch.StartNew();
if (mode == "parity")
    return Parity.run(P(1, "parity.txt"), new ParallelOptions { MaxDegreeOfParallelism = jobs });
if (mode == "scan")
    return Reaction.scan(P(1, "ghostdoors"), long.Parse(P(2, "45")), long.Parse(P(3, "4")));
if (mode == "combos")
    return Combos.run(int.Parse(P(1, "256")), int.Parse(P(2, "240")), jobs);
if (mode == "bench")
{
    Bench.run();
    return 0;
}
int seeds = int.Parse(P(1, mode == "search" || mode == "searchruns" ? "64" : mode == "reaction" ? "60" : "4"));
JsonObject report;
if (worker || jobs <= 1 || seeds <= 1)
{
    report = mode switch
    {
        "search" => Modes.search_rooms(seeds, P(2, "*"), long.Parse(P(3, "1500")), first),
        "searchruns" => Modes.search_runs(seeds, long.Parse(P(2, "16000")), first),
        "rooms" => Modes.planner_rooms(seeds, P(2, "*"), first),
        "runs" => Modes.planner_runs(seeds, first),
        "reaction" => Reaction.rooms(seeds, P(2, "*"), P(3, ""), first),
        "odds" => Reaction.odds(seeds, P(2, ""), first),
        _ => null,
    };
    if (report == null)
    {
        Console.Error.WriteLine("unknown mode " + mode);
        return 2;
    }
}
else
{
    report = Workers.run(mode, pos, seeds, jobs, first, priority);
    if (report == null) return 3;
}
report["seconds"] = Math.Round(clock.Elapsed.TotalSeconds, 1);
if (opts.TryGetValue("out", out var outPath))
    File.WriteAllText(outPath, report.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
if (worker) return 0;
int exit = mode == "reaction" || mode == "odds" ? Reaction.print(report) : Summary.print(report);
Console.WriteLine($"fastsim {mode}: {seeds} seeds in {clock.Elapsed.TotalSeconds:F1} s ({Math.Min(jobs, seeds)} workers, {priority} priority)");
return exit;

/// Splits the seeds over worker processes (this program, `--worker`) and
/// merges their JSON.
static class Workers
{
    public static JsonObject run(string mode, List<string> pos, int seeds, int jobs, long first, string priority)
    {
        jobs = Math.Min(jobs, seeds);
        int per = (seeds + jobs - 1) / jobs;
        string exe = Environment.ProcessPath;
        string dir = Path.Combine(Path.GetTempPath(), "fastsim_" + Environment.ProcessId);
        Directory.CreateDirectory(dir);
        var procs = new List<(Process p, string json)>();
        for (int k = 0; k < jobs; k++)
        {
            int count = Math.Min(per, seeds - k * per);
            if (count <= 0) break;
            string json = Path.Combine(dir, $"job_{k}.json");
            var psi = new ProcessStartInfo(exe) { UseShellExecute = false, CreateNoWindow = true };
            psi.ArgumentList.Add(mode);
            psi.ArgumentList.Add(count.ToString());
            for (int i = 2; i < pos.Count; i++) psi.ArgumentList.Add(pos[i]);
            var pass = new List<(string, string)> { ("first", (first + (long)k * per).ToString()), ("priority", priority),
                ("jobs", "1"), ("worker", "1"), ("out", json) };
            if (Targets.variant != "") pass.Add(("variant", Targets.variant));
            foreach (var (k2, v) in pass)
            {
                psi.ArgumentList.Add("--" + k2);
                psi.ArgumentList.Add(v);
            }
            procs.Add((Process.Start(psi), json));
        }
        JsonObject merged = null;
        bool failed = false;
        foreach (var (p, json) in procs)
        {
            p.WaitForExit();
            if (p.ExitCode != 0 || !File.Exists(json))
            {
                Console.Error.WriteLine($"worker failed (exit {p.ExitCode})");
                failed = true;
                continue;
            }
            var part = JsonNode.Parse(File.ReadAllText(json)).AsObject();
            merged = merged == null ? part : merge(merged, part);
        }
        try { Directory.Delete(dir, true); } catch { }
        if (failed || merged == null) return null;
        if (merged.ContainsKey("seeds")) merged["seeds"] = seeds;
        return merged;
    }

    static JsonObject merge(JsonObject a, JsonObject b)
    {
        if (a.ContainsKey("rooms"))
        {
            var rooms = a["rooms"].AsArray();
            var other = b["rooms"].AsArray();
            for (int i = 0; i < rooms.Count; i++)
            {
                var runs = rooms[i]["runs"].AsArray();
                foreach (var r in other[i]["runs"].AsArray().ToList()) runs.Add(r.DeepClone());
            }
        }
        else
        {
            var runs = a["runs"].AsArray();
            foreach (var r in b["runs"].AsArray().ToList()) runs.Add(r.DeepClone());
        }
        return a;
    }
}

/// The rooms a per-room mode plays, and with --variant, which variant of each.
public static class Targets
{
    /// "" (the drawn variant), a variant id, or "all".
    public static string variant = "";
    /// Room label width in the report lines (wider for "room/variant").
    public static int width => variant == "" ? 11 : 20;

    public static bool matches(RoomDef def, string filter, bool exact) =>
        filter == "*" || filter == "" || (exact ? def.id == filter : def.id.Contains(filter));

    /// [index, def, forced variant id ("" = drawn), report label].
    public static List<(int index, RoomDef def, string variant, string label)> pick(string filter, bool exact)
    {
        var out_ = new List<(int, RoomDef, string, string)>();
        var all = RoomCatalog.all();
        for (int index = 0; index < all.Count; index++)
        {
            var def = all[index];
            if (!matches(def, filter, exact)) continue;
            if (variant == "") out_.Add((index, def, "", def.id));
            else
                foreach (var v in def.variants)
                    if (variant == "all" || v.id == variant) out_.Add((index, def, v.id, def.id + "/" + v.id));
        }
        return out_;
    }

    public static JsonObject room(string label, RoomDef def, string v, JsonArray runs)
    {
        var o = new JsonObject { ["id"] = label, ["group"] = def.group, ["from"] = def.from_score };
        if (v != "") o["variant"] = v;
        o["runs"] = runs;
        return o;
    }
}

/// The same report lines as tools/sweep.ps1. Returns 1 when something failed.
static class Summary
{
    public static int print(JsonObject report)
    {
        string mode = (string)report["mode"];
        int bad_total = 0;
        if (report.ContainsKey("rooms"))
        {
            foreach (var room in report["rooms"].AsArray())
            {
                var runs = room["runs"].AsArray();
                var bad = new List<long>();
                double points = 0;
                int fine = 0;
                foreach (var r in runs)
                {
                    points += (double)r["points"];
                    bool isBad = mode == "search" ? !(bool)r["ok"] : (bool)r["dead"];
                    if (isBad) bad.Add((long)r["seed"]);
                    if (mode == "search" && (long)r["level"] > 0) fine++;
                }
                string label = mode == "search" ? "impossible" : "died";
                string line = $"{((string)room["id"]).PadRight(Targets.width)} {label} {bad.Count,4} / {runs.Count,-4} avg points {points / Math.Max(1, runs.Count),5:F1}";
                if (fine > 0) line += $"  (narrow: {fine})";
                if (bad.Count > 0) line += "  seeds " + string.Join(",", bad);
                Console.WriteLine(line);
                if (mode == "search") bad_total += bad.Count;
            }
        }
        else
        {
            var runs = report["runs"].AsArray();
            int good = 0;
            foreach (var r in runs)
            {
                bool ok = mode == "searchruns" ? (bool)r["ok"] : !(bool)r["dead"];
                if (ok)
                {
                    good++;
                    continue;
                }
                string where = r["died_in"] is JsonArray a ? string.Join("/", a.Select(x => (string)x)) : (string)r["died_in"];
                Console.WriteLine($"seed {(long)r["seed"]}: ended at tick {(long)r["ticks"]} in {where}");
            }
            Console.WriteLine($"{good} of {runs.Count} runs made it");
            if (mode == "searchruns") bad_total = runs.Count - good;
        }
        return bad_total > 0 ? 1 : 0;
    }
}

static class Modes
{
    const long ROOM_TICKS = 3600;
    const long ROOM_POINTS = 25;
    const long RUN_TICKS = 9000;
    const long ARRIVAL_TICKS = 90;

    public static JsonObject search_rooms(int seeds, string filter, long ticks, long first)
    {
        var rooms = new JsonArray();
        foreach (var (index, def, v, label) in Targets.pick(filter, false))
        {
            var runs = new JsonArray();
            for (int s = 0; s < seeds; s++)
            {
                long seed_value = 1000 + (first + s) * 77;
                var sim = new GameSim(seed_value, def.season, index, v);
                var search = new SurvivalSearch();
                bool ok = search.run(sim, ticks);
                runs.Add(new JsonObject
                {
                    ["seed"] = seed_value, ["ok"] = ok, ["ticks"] = search.ticks_survived,
                    ["width"] = search.peak_width, ["level"] = search.level,
                    ["points"] = ok ? search.best.state.score - sim.state.score : 0,
                });
            }
            rooms.Add(Targets.room(label, def, v, runs));
        }
        return new JsonObject { ["mode"] = "search", ["seeds"] = seeds, ["ticks"] = ticks, ["rooms"] = rooms };
    }

    public static JsonObject search_runs(int seeds, long ticks, long first)
    {
        var runs = new JsonArray();
        for (int s = 0; s < seeds; s++)
        {
            long seed_value = 5000 + (first + s) * 131;
            var sim = new GameSim(seed_value);
            var search = new SurvivalSearch();
            bool ok = search.run(sim, ticks);
            var run = new JsonObject { ["seed"] = seed_value, ["ok"] = ok, ["ticks"] = search.ticks_survived };
            if (ok)
            {
                var rooms = new JsonArray { "open" };
                var replay = new GameSim(seed_value);
                foreach (byte tap in search.best_inputs)
                {
                    replay.step(tap == 1);
                    if (replay.events.Contains(Event.ROOM_CHANGE)) rooms.Add(RoomCatalog.all()[(int)replay.state.room_kind].id);
                }
                run["rooms"] = rooms;
                run["score"] = replay.state.score;
            }
            else
            {
                var died = new JsonArray();
                foreach (long k in search.last_rooms) died.Add(RoomCatalog.all()[(int)k].id);
                run["died_in"] = died;
                var deaths = new JsonObject();
                foreach (var (why, n) in search.last_deaths) deaths[why] = n;
                run["deaths"] = deaths;
            }
            runs.Add(run);
        }
        return new JsonObject { ["mode"] = "searchruns", ["runs"] = runs };
    }

    public static JsonObject planner_rooms(int seeds, string filter, long first)
    {
        var rooms = new JsonArray();
        foreach (var (index, def, v, label) in Targets.pick(filter, false))
        {
            var runs = new JsonArray();
            for (int s = 0; s < seeds; s++)
            {
                long seed_value = 1000 + (first + s) * 77;
                var sim = new GameSim(seed_value, def.season, index, v);
                var bot = new PlannerBot(seed_value);
                long start_score = sim.state.score;
                long since_room = 0;
                while (!sim.is_over() && sim.state.tick < ROOM_TICKS)
                {
                    sim.step(bot.decide(sim));
                    since_room += 1;
                    if (sim.events.Contains(Event.ROOM_CHANGE)) since_room = 0;
                    if (sim.state.score - start_score >= ROOM_POINTS) break;
                }
                bool dead = sim.is_over();
                runs.Add(new JsonObject
                {
                    ["seed"] = seed_value, ["points"] = sim.state.score - start_score, ["ticks"] = sim.state.tick,
                    ["dead"] = dead, ["cause"] = dead ? DeathCause.NAMES[sim.state.death_cause] : "",
                    ["after_exit"] = dead && since_room < ARRIVAL_TICKS && sim.state.room_index > 0,
                    ["y"] = sim.state.y / SimConfig.SUB, ["x"] = sim.state.x / SimConfig.SUB,
                });
            }
            rooms.Add(Targets.room(label, def, v, runs));
        }
        return new JsonObject { ["mode"] = "rooms", ["seeds"] = seeds, ["rooms"] = rooms };
    }

    public static JsonObject planner_runs(int seeds, long first)
    {
        var runs = new JsonArray();
        for (int s = 0; s < seeds; s++)
        {
            long seed_value = 5000 + (first + s) * 131;
            var sim = new GameSim(seed_value);
            var bot = new PlannerBot(seed_value);
            var rooms = new JsonArray { "open" };
            string last = "open";
            long since_room = 0, forks = 0;
            while (!sim.is_over() && sim.state.tick < RUN_TICKS)
            {
                sim.step(bot.decide(sim));
                since_room += 1;
                if (sim.events.Contains(Event.EXIT_OPEN) && sim.state.exit_b_kind != 0) forks += 1;
                if (sim.events.Contains(Event.ROOM_CHANGE))
                {
                    since_room = 0;
                    last = RoomCatalog.all()[(int)sim.state.room_kind].id;
                    rooms.Add(last);
                }
            }
            bool dead = sim.is_over();
            runs.Add(new JsonObject
            {
                ["seed"] = seed_value, ["score"] = sim.state.score, ["coins"] = sim.state.coins,
                ["ticks"] = sim.state.tick, ["rooms"] = rooms, ["forks"] = forks, ["route"] = sim.state.route,
                ["dead"] = dead, ["cause"] = dead ? DeathCause.NAMES[sim.state.death_cause] : "",
                ["died_in"] = last, ["arrival_death"] = dead && since_room < ARRIVAL_TICKS && rooms.Count > 1,
                ["ticks_in_room"] = since_room,
            });
        }
        return new JsonObject { ["mode"] = "runs", ["runs"] = runs };
    }
}

/// Replays tools/fastsim_parity.gd's recording and reports the first tick
/// where this sim differs from Godot's.
static class Parity
{
    public static int run(string path, ParallelOptions par)
    {
        var lines = File.ReadAllLines(path).Where(l => l.Length > 0).ToArray();
        var fails = new System.Collections.Concurrent.ConcurrentBag<string>();
        long ticks = 0;
        Parallel.ForEach(lines, par, line =>
        {
            var f = line.Split(' ');
            string name = f[1];
            if (f[0] == "case" || f[0] == "csearch" || f[0] == "qsearch")
            {
                string fail = f[0] == "case" ? play_case(f) : search_case(f);
                if (fail != null) fails.Add($"{f[0]} {name} ({f[2]}): {fail}");
                long n = f[0] == "case" ? f[4].Length : long.Parse(f[3]);
                Interlocked.Add(ref ticks, n);
                return;
            }
            long seed = long.Parse(f[2]), season = long.Parse(f[3]), practice = long.Parse(f[4]);
            string tag = $"{f[0]} {name} seed {seed} season {season}";
            if (f[0] == "run")
            {
                string actions = f[5];
                var sums = f.Length > 6 && f[6].Length > 0 ? f[6].Split(',') : Array.Empty<string>();
                var sim = new GameSim(seed, season, practice);
                for (int i = 0; i < actions.Length; i++)
                {
                    char a = actions[i];
                    if (a == 'r') sim.revive();
                    else sim.step(a == '1');
                    Interlocked.Increment(ref ticks);
                    if (sim.checksum() != long.Parse(sums[i]))
                    {
                        string room = RoomCatalog.all()[(int)sim.state.room_kind].id;
                        fails.Add($"{tag}: differs at action {i} ('{a}'), tick {sim.state.tick}, room {room}");
                        return;
                    }
                }
            }
            else if (f[0] == "search")
            {
                long n = long.Parse(f[5]);
                bool ok = f[6] == "1";
                long survived = long.Parse(f[7]);
                string taps = f[8];
                var search = new SurvivalSearch();
                bool got_ok = search.run(new GameSim(seed, season, practice), n);
                string got_taps = got_ok ? string.Concat(search.best_inputs.Select(b => b == 1 ? '1' : '0')) : "-";
                if (got_ok != ok || search.ticks_survived != survived || got_taps != taps)
                {
                    int at = 0;
                    while (at < Math.Min(got_taps.Length, taps.Length) && got_taps[at] == taps[at]) at++;
                    fails.Add($"{tag}: search ok {got_ok}/{ok}, survived {search.ticks_survived}/{survived}, taps differ from {at}");
                }
            }
        });
        foreach (var m in fails.OrderBy(x => x)) Console.WriteLine("  DIFF " + m);
        Console.WriteLine($"parity: {lines.Length - fails.Count} of {lines.Length} cases match ({ticks} ticks replayed)");
        return fails.IsEmpty ? 0 : 1;
    }

    /// A sim from a `case` setup (tools/fastsim_parity.gd setup()).
    static GameSim setup(string text)
    {
        var f = text.Split(':');
        string variant = f[^1] == "-" ? "" : f[^1];
        return f[0] switch
        {
            "p" => new GameSim(long.Parse(f[1]), long.Parse(f[2]), long.Parse(f[3]), variant),
            "a" => Reaction.arrival(int.Parse(f[1]), long.Parse(f[3]), f[2] == "-" ? "" : f[2]),
            "r" => Checks.Setups.revived(int.Parse(f[1]), long.Parse(f[2]), f[3], long.Parse(f[4])),
            "cr" => Checks.Setups.crawl_revived(int.Parse(f[1]), long.Parse(f[2]), f[3], long.Parse(f[4]), long.Parse(f[5])),
            "gr" => Checks.Setups.gates_revived(long.Parse(f[1]), f[2] == "1", long.Parse(f[3]), long.Parse(f[4]), f[5]),
            "ir" => Checks.Setups.isles_revived(f[1], long.Parse(f[2]), f[3], long.Parse(f[4]), f[5]),
            "n" => near(f),
            _ => throw new Exception("unknown setup " + text),
        };
    }

    static GameSim near(string[] f)
    {
        var sim = Checks.Setups.practice(f[1], long.Parse(f[2]), f[3] == "-" ? "" : f[3]);
        sim.state.score += long.Parse(f[4]);
        return sim;
    }

    /// Replays a `case` line; with a bot driver the C# bot must also choose
    /// every tap itself. Null when it matches, else where it differs.
    static string play_case(string[] f)
    {
        var sim = setup(f[2]);
        string driver = f[3], actions = f[4];
        var sums = f.Length > 5 && f[5].Length > 0 ? f[5].Split(',') : Array.Empty<string>();
        var d = driver.Split(':');
        var gap = new SimRng(7);
        var tapper = d[0] == "tap" ? new SimRng(long.Parse(d[1])) : null;
        PlannerBot planner = d[0] == "planner" ? new PlannerBot(long.Parse(d[1]), long.Parse(d[2]), long.Parse(d[3])) : null;
        long hold = d[0] == "planner" ? long.Parse(d[4]) : 0;
        long y0 = sim.state.y;
        long n = 0;
        for (int i = 0; i < actions.Length; i++)
        {
            char a = actions[i];
            if (driver != "replay")
            {
                char want;
                if (d[0] == "gap") want = sim.is_over() ? 'r' : SimBots.gap_seeker(sim, gap) ? '1' : '0';
                else if (d[0] == "tap") want = SimBots.random_tapper(sim, tapper) ? '1' : '0';
                else if (n < hold)
                {
                    long g = sim.room.gravity;
                    want = (sim.state.y - y0) * g > 0 && sim.state.vy * g >= 0 ? '1' : '0';
                }
                else want = planner.decide(sim) ? '1' : '0';
                if (want != a) return $"the {d[0]} bot chose '{want}', not '{a}', at action {i} (tick {sim.state.tick})";
            }
            if (a == 'r') sim.revive();
            else
            {
                sim.step(a == '1');
                n++;
            }
            if (sim.checksum() != long.Parse(sums[i]))
                return $"differs at action {i} ('{a}'), tick {sim.state.tick}, room {RoomCatalog.all()[(int)sim.state.room_kind].id}";
        }
        // The bot must also stop where the GDScript one stopped.
        if (d[0] == "gap" && (sim.is_over() ? sim.can_revive() : sim.state.tick < 1500)) return "the gap run ended early";
        if (d[0] == "planner" && !sim.is_over() && n < hold + long.Parse(d[5])) return "the planner run ended early";
        if (d[0] == "tap" && !sim.is_over() && sim.state.tick < 20000) return "the tapper run ended early";
        return null;
    }

    static string search_case(string[] f)
    {
        long n = long.Parse(f[3]);
        bool ok = f[4] == "1";
        long survived = long.Parse(f[5]);
        string taps = f[6];
        var search = new SurvivalSearch();
        bool got_ok = f[0] == "qsearch" ? search.run_quick(setup(f[2]), n) : search.run(setup(f[2]), n);
        string got_taps = got_ok ? string.Concat(search.best_inputs.Select(b => b == 1 ? '1' : '0')) : "-";
        if (got_ok == ok && search.ticks_survived == survived && got_taps == taps) return null;
        int at = 0;
        while (at < Math.Min(got_taps.Length, taps.Length) && got_taps[at] == taps[at]) at++;
        return $"search ok {got_ok}/{ok}, survived {search.ticks_survived}/{survived}, taps differ from {at}";
    }
}

static class Bench
{
    public static void run()
    {
        var rng = new SimRng(7);
        var rooms = RoomCatalog.all();
        long copies = 0, steps = 0;
        var copy_t = new Stopwatch();
        var step_t = new Stopwatch();
        for (int index = 0; index < rooms.Count; index++)
        {
            var sim = new GameSim(1077, rooms[index].season, index);
            for (int i = 0; i < 40; i++) sim.step(PlannerBot.aim(sim, rng));
            if (sim.is_over()) sim = new GameSim(1077, rooms[index].season, index);
            copy_t.Start();
            for (int i = 0; i < 2000; i++) sim.clone_deep();
            copy_t.Stop();
            copies += 2000;
            var c = sim.clone_deep();
            step_t.Start();
            for (int i = 0; i < 20000; i++)
            {
                if (c.is_over()) c = sim.clone_deep();
                c.step(PlannerBot.aim(c, rng));
            }
            step_t.Stop();
            steps += 20000;
        }
        Console.WriteLine($"copy      {copy_t.Elapsed.TotalMilliseconds * 1000 / copies,8:F2} us");
        Console.WriteLine($"step      {step_t.Elapsed.TotalMilliseconds * 1000 / steps,8:F2} us");

        var play = new GameSim(5000);
        var bot = new PlannerBot(5000);
        var t = Stopwatch.StartNew();
        int made = 0;
        while (made < 300 && !play.is_over())
        {
            play.step(bot.decide(play));
            made++;
        }
        double decide_ms = t.Elapsed.TotalMilliseconds / Math.Max(made, 1);
        Console.WriteLine($"decide    {decide_ms,8:F3} ms  ({1000 / decide_ms:F0} decisions/s)");
        var search = new SurvivalSearch();
        t.Restart();
        bool ok = search.run(new GameSim(5000), 1500);
        Console.WriteLine($"search    {t.Elapsed.TotalSeconds,8:F3} s   (1500 ticks, ok {ok}, width {search.peak_width})");
        long taps = 0;
        foreach (byte b in search.best_inputs) taps = (taps * 31 + b + 1) & 0x7FFFFFFF;
        Console.WriteLine($"planner checksum {play.state.checksum()}  tick {play.state.tick} score {play.state.score}");
        Console.WriteLine($"search checksum  {taps}  inputs {search.best_inputs.Length}");
    }
}
