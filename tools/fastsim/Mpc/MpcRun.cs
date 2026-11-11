using System.Diagnostics;
using System.Text.Json.Nodes;

namespace FastSim.Mpc;

/// `fastsim mpc <measure|speed> [options]` (tools/mpcbot.ps1, docs/MPC_BOT.md).
/// The only MPC file that steps the sim: it plays the bot's taps on the real
/// run. The bot itself (the other files here) never copies or steps it.
public static class MpcRun
{
    public readonly record struct Result(long seed, long points, long ticks, bool dead, string room, string cause,
        string killer, long doomed, double taps_per_s, int band);

    public static int run(List<string> pos, Dictionary<string, string> opts)
    {
        string what = pos.Count > 1 ? pos[1] : "measure";
        string O(string k, string d) => opts.GetValueOrDefault(k, d);
        int threads = Math.Clamp(int.Parse(O("threads", "8")), 1, 16);
        var motor = new Motor
        {
            sigma = double.Parse(O("sigma", "0"), System.Globalization.CultureInfo.InvariantCulture),
            react = int.Parse(O("react", "0")),
            min_gap = int.Parse(O("mingap", "1")),
        };
        Func<MpcParams> knobs = () =>
        {
            var p = new MpcParams();
            foreach (var kv in O("set", "").Split(',', StringSplitOptions.RemoveEmptyEntries))
            {
                var parts = kv.Split('=');
                p.set(parts[0], parts[1]);
            }
            return p;
        };
        knobs();
        switch (what)
        {
            case "measure":
                return measure(knobs, motor, int.Parse(O("seeds", "400")), long.Parse(O("first", "0")),
                    long.Parse(O("cap", SimConfig.MAX_TICKS.ToString())), threads, O("out", ""), O("room", ""));
            case "speed":
            {
                var clock = Stopwatch.StartNew();
                long ticks = 0, probes = 0, exp = 0;
                for (int i = 0; i < 8; i++)
                {
                    var bot = new MpcBot(knobs(), motor, i + 1);
                    var r = play(bot, new GameSim(i + 1), 6000);
                    ticks += r.ticks;
                    probes += bot.planner.sight.probes;
                    exp += bot.planner.expansions;
                }
                double sec = clock.Elapsed.TotalSeconds;
                Console.WriteLine($"mpc speed: {ticks} ticks in {sec:F2} s = {ticks / sec:F0} ticks/s per thread; " +
                    $"{probes / Math.Max(ticks, 1)} probes and {exp / Math.Max(ticks, 1)} plan steps per tick");
                return 0;
            }
        }
        if (what == "runfile")
        {
            // The bot's run on one seed as a run file for the renderer (docs/RENDERING.md).
            long seed = long.Parse(O("seed", "1"));
            var sim = new GameSim(seed);
            var bot = new MpcBot(knobs(), motor, seed);
            var taps = new List<long>();
            long cap = long.Parse(O("cap", SimConfig.MAX_TICKS.ToString()));
            while (!sim.is_over() && sim.state.tick < cap)
            {
                bool tap = bot.decide(sim);
                if (tap) taps.Add(sim.state.tick);
                sim.step(tap);
            }
            string path = O("out", "mpc_run.json");
            RunFile.write(path, sim, taps, name: "mpc bot");
            Console.WriteLine($"mpc runfile: seed {seed}, score {sim.state.score}, {sim.state.tick} ticks -> {path}");
            return 0;
        }
        if (what == "trace") return trace(knobs(), motor, long.Parse(O("seed", "1")), O("room", ""), long.Parse(O("cap", "3600")), int.Parse(O("last", "60")));
        Console.Error.WriteLine("mpc: unknown mode " + what + " (measure, speed, trace, runfile)");
        return 2;
    }

    public static Result play(MpcBot bot, GameSim sim, long cap)
    {
        long start = sim.state.score;
        long n = 0, doomed = 0;
        while (n < cap && !sim.is_over())
        {
            bool tap = bot.decide(sim);
            doomed = bot.planner.doomed ? doomed + 1 : 0;
            sim.step(tap);
            n++;
        }
        string room = sim.room.def.id;
        if (sim.room.variant_id() != "") room += "/" + sim.room.variant_id();
        string cause = "", killer = "";
        int band = 0;
        if (sim.is_over())
        {
            cause = DeathCause.NAMES[sim.state.death_cause].ToLower();
            if (sim.state.death_cause == DeathCause.HAZARD)
                foreach (var h in sim.room.hazards)
                    if (h.alive && h.kills(sim))
                    {
                        killer = h.kind;
                        break;
                    }
            band = (int)Math.Clamp((sim.state.y - SimConfig.KILL_TOP) * 8 / (SimConfig.KILL_BOTTOM - SimConfig.KILL_TOP) + 1, 1, 8);
        }
        return new Result(sim.seed_value, sim.state.score - start, n, sim.is_over(), room, cause, killer, doomed,
            bot.taps * 60.0 / Math.Max(n, 1), band);
    }

    static (long, string) find_room(string room)
    {
        if (room == "") return (-1, "");
        var parts = room.Split('/');
        var all = RoomCatalog.all();
        for (int i = 0; i < all.Count; i++)
            if (all[i].id == parts[0]) return (i, parts.Length > 1 ? parts[1] : "");
        throw new ArgumentException("no room " + parts[0]);
    }

    /// Prints the last ticks before a death: the bird, the tap, and each shape's edges and speeds.
    static int trace(MpcParams p, Motor motor, long seed, string room, long cap, int last)
    {
        var (practice, variant) = find_room(room);
        var sim = new GameSim(seed, Seasons.NONE, practice, variant);
        var bot = new MpcBot(p, motor, seed);
        var lines = new Queue<string>();
        long n = 0;
        while (n < cap && !sim.is_over())
        {
            bool tap = bot.decide(sim);
            var s = sim.state;
            var sb = new System.Text.StringBuilder();
            sb.Append($"t{s.tick} x{s.x / 64} y{s.y / 64} vy{s.vy / 64.0:F1} vx{s.vx / 64} {(tap ? "TAP" : "   ")} first{bot.planner.first_tap} {(bot.planner.doomed ? "DOOM@" + bot.planner.doom_tick : "")} mask{Convert.ToString(sim.wall_mask(s.vx > 0 ? 1 : 0), 2).PadLeft(13, '0')}");
            foreach (var b in bot.planner.sight.blobs)
                sb.Append($" | {b.owner.kind}{(b.body ? "*" : "")} x[{b.e[0]:F0},{b.e[1]:F0}] y[{b.e[2]:F0},{b.e[3]:F0}] v({b.v[0]:F1},{b.v[1]:F1},{b.v[2]:F1},{b.v[3]:F1}) w{b.wobble:F2} ch{b.chase:F1}");
            lines.Enqueue(sb.ToString());
            if (lines.Count > last) lines.Dequeue();
            sim.step(tap);
            n++;
        }
        foreach (var l in lines) Console.WriteLine(l);
        Console.WriteLine($"end: score {sim.state.score} dead {sim.is_over()} {DeathCause.NAMES[sim.state.death_cause]} at x{sim.state.x / 64} y{sim.state.y / 64} room {sim.room.def.id}/{sim.room.variant_id()}");
        return 0;
    }

    static double pct(IEnumerable<long> xs, double p) => FastSim.Rl.Tiers.pct(xs, p);

    static int measure(Func<MpcParams> knobs, Motor motor, int seeds, long first, long cap, int threads, string out_path, string room)
    {
        long practice = -1;
        string variant = "";
        if (room != "")
        {
            var parts = room.Split('/');
            var all = RoomCatalog.all();
            for (int i = 0; i < all.Count; i++)
                if (all[i].id == parts[0]) practice = i;
            if (practice < 0)
            {
                Console.Error.WriteLine("mpc: no room " + parts[0]);
                return 2;
            }
            if (parts.Length > 1) variant = parts[1];
        }
        var clock = Stopwatch.StartNew();
        var runs = new Result[seeds];
        Parallel.For(0, seeds, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            long seed = first + 1 + i;
            runs[i] = play(new MpcBot(knobs(), motor, seed), new GameSim(seed, Seasons.NONE, practice, variant), cap);
        });
        var pts = runs.Select(r => r.points).ToList();
        long ticks = runs.Sum(r => r.ticks);
        int capped = runs.Count(r => !r.dead);
        Console.WriteLine($"mpc measure: {seeds} {(room == "" ? "full runs" : "runs of " + room)} (seeds {first + 1}..{first + seeds}), cap {cap} ticks, no revives; " +
            $"sigma {motor.sigma}, react {motor.react}, min gap {motor.min_gap}");
        Console.WriteLine($"  median {pct(pts, 0.5):F1}  p90 {pct(pts, 0.9):F1}  p25 {pct(pts, 0.25):F1}  mean {pts.Average():F1}  max {pts.Max()}" +
            $"  taps/s {runs.Average(r => r.taps_per_s):F2}" + (capped > 0 ? $"  ({capped} reached the cap)" : ""));
        var dead = runs.Where(r => r.dead).ToList();
        // Deaths per 100 points by score band: deaths that ended in the band over the points played in it.
        long[] edges = { 0, 10, 20, 40, 80, 160, long.MaxValue };
        var bands = new List<string>();
        for (int i = 0; i + 1 < edges.Length; i++)
        {
            long lo = edges[i], hi = edges[i + 1];
            long played = runs.Sum(r => Math.Max(0, Math.Min(r.points, hi) - lo));
            int died = runs.Count(r => r.dead && r.points >= lo && r.points < hi);
            if (played > 0) bands.Add($"{lo}{(hi == long.MaxValue ? "+" : ".." + hi)}: {100.0 * died / played:F2}");
        }
        Console.WriteLine($"  deaths per 100 points: {100.0 * dead.Count / Math.Max(pts.Sum(), 1):F2} overall; by score {string.Join(", ", bands)}; {capped} of {seeds} runs reached the cap; no sim copies");
        if (dead.Count > 0)
        {
            Console.WriteLine("  causes: " + string.Join(", ", dead.GroupBy(r => r.cause).OrderByDescending(g => g.Count())
                .Select(g => $"{g.Key} {100.0 * g.Count() / dead.Count:F0}%")));
            Console.WriteLine("  killers: " + string.Join(", ", dead.Where(r => r.killer != "").GroupBy(r => r.killer)
                .OrderByDescending(g => g.Count()).Take(12).Select(g => $"{g.Key} {g.Count()}")));
            Console.WriteLine($"  saw it coming (no living plan at death): {100.0 * dead.Count(r => r.doomed > 0) / dead.Count:F0}%, " +
                $"median {pct(dead.Where(r => r.doomed > 0).Select(r => r.doomed), 0.5):F0} ticks before");
            Console.WriteLine("  deaths by room (count: causes):");
            foreach (var g in dead.GroupBy(r => r.room).OrderByDescending(g => g.Count()).Take(25))
                Console.WriteLine($"    {g.Key,-28} {g.Count(),4}  " + string.Join(", ", g.GroupBy(r => r.killer != "" ? r.killer : r.cause)
                    .OrderByDescending(x => x.Count()).Select(x => $"{x.Key} {x.Count()}")));
        }
        Console.WriteLine($"mpc measure: {clock.Elapsed.TotalSeconds:F0} s ({threads} threads), {ticks / clock.Elapsed.TotalSeconds:F0} ticks/s");
        if (out_path != "")
        {
            var arr = new JsonArray(runs.Select(r => (JsonNode)new JsonObject
            {
                ["seed"] = r.seed, ["points"] = r.points, ["ticks"] = r.ticks, ["dead"] = r.dead, ["room"] = r.room,
                ["cause"] = r.cause, ["killer"] = r.killer, ["doomed"] = r.doomed, ["band"] = r.band,
            }).ToArray());
            File.WriteAllText(out_path, new JsonObject
            {
                ["seeds"] = seeds, ["first"] = first, ["cap"] = cap, ["sigma"] = motor.sigma, ["react"] = motor.react,
                ["min_gap"] = motor.min_gap, ["median"] = pct(pts, 0.5), ["p90"] = pct(pts, 0.9), ["mean"] = pts.Average(), ["runs"] = arr,
            }.ToJsonString(new System.Text.Json.JsonSerializerOptions { WriteIndented = true }));
        }
        return 0;
    }
}
