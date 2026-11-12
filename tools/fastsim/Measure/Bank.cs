using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using FastSim.Yard;

namespace FastSim.Measure;

/// Bots for `fastsim measure`: every yardstick bot, plus `blind` (the
/// BlindPlanner as `rl review atlas` plays it) with knobs after a colon:
/// `blind:fine=0,lines=4` sets the knobs `rl review atlas --fine 0 --lines 4` sets.
public static class MBots
{
    public static BotSpec find(string name)
    {
        if (name == "blind" || name.StartsWith("blind:"))
        {
            var knobs = new Dictionary<string, string>();
            if (name.Length > 6)
                foreach (var kv in name[6..].Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                {
                    var p = kv.Split('=');
                    if (p.Length != 2) throw new ArgumentException($"bad knob '{kv}' in '{name}' (want key=value)");
                    knobs[p[0]] = p[1];
                }
            // configure() also sets a static (know_exits): run it once here, the same for every run.
            string about = Rl.Review.configure(new BlindPlanner(1), knobs);
            return new BotSpec(name, "BlindPlanner [" + about + "]", Copies.SCRAMBLED, seed =>
            {
                var b = new BlindPlanner(seed);
                Rl.Review.configure(b, knobs);
                return b.decide;
            });
        }
        return Bots.find(name) ?? throw new ArgumentException($"no bot '{name}' (blind[:k=v,...] or a yardstick bot)");
    }
}

/// Seed sets of the protocol (docs/BOT_TESTING.md). Tune on dev, report once
/// on the holdout, check leaks on their own seeds.
public static class SeedSets
{
    public const long DEV = 10_000, HOLDOUT = 0, LEAK = 900_000;
    public const int HOLDOUT_N = 400;
}

/// One room visit seen in a run: the tick whose step entered the room (the
/// state before that step is the entry snapshot), the stratum, and how the
/// visit ended.
public sealed record Visit(long tick, bool tap, long score, string key, bool died, bool censored, long points, long ticks, double ms);

/// One bank run: the bot's taps (so any port can rebuild every state by
/// replaying them), its outcome and its room visits.
public sealed class BankRun
{
    public long seed, season, points, ticks;
    public bool dead;
    public double ms;
    public long[] taps = Array.Empty<long>();
    public List<Visit> visits = new();
    public string room = "";
}

/// The snapshot bank (`*.bank.json`, format `flapjaw_bank` 1). Full runs of
/// one bot to death, a point cap or a tick cap, with every room entry.
/// Everything in it is plain data: seed, taps, entry ticks. Rebuilding a
/// state is "new GameSim(seed, season), step(taps contains tick) until the
/// tick", so the Rust port reads and writes the same file.
public sealed class Bank
{
    public const string FORMAT = "flapjaw_bank";
    public const int VERSION = 1;
    public string bot = "", about = "";
    public long cap, point_cap, gameplay = SimConfig.GAMEPLAY_VERSION, first;
    public List<BankRun> runs = new();
    public double seconds;

    /// Stratum of the room the sim just entered: room/variant, plus the score
    /// class. Below PLATEAU the band of ten (spikes still grow), boss rooms
    /// their tier, everything else "p" (the plateau: same rules at any score).
    public static string key(GameSim sim)
    {
        string name = Run.room_name(sim);
        long s = sim.room.entry_score;
        if (sim.room.def.boss) return name + "@t" + SimConfig.boss_tier(s);
        if (s < Strat.PLATEAU) return name + "@b" + (s / 10 * 10);
        return name + "@p";
    }

    /// Plays one run of `bot` and records its visits. Stops at death, `cap`
    /// ticks or the first room entry at or past `point_cap` points (0 = none).
    public static BankRun play(BotSpec bot, long seed, long cap, long point_cap)
    {
        var decide = bot.make(seed);
        var sim = new GameSim(seed);
        var taps = new List<long>();
        var r = new BankRun { seed = seed, season = sim.season };
        var clock = Stopwatch.StartNew();
        long v_tick = -1, v_score = 0, v_start = 0;
        bool v_tap = false;
        string v_key = null;
        double v_ms = 0;
        while (sim.state.tick < cap && !sim.is_over())
        {
            long t = sim.state.tick;
            bool tap = decide(sim);
            if (tap) taps.Add(t);
            long ri = sim.state.room_index;
            sim.step(tap);
            if (sim.state.room_index != ri)
            {
                double now = clock.Elapsed.TotalMilliseconds;
                if (v_key != null)
                    r.visits.Add(new Visit(v_tick, v_tap, v_score, v_key, false, false, sim.state.score - v_score, t + 1 - v_start, now - v_ms));
                v_tick = t;
                v_tap = tap;
                v_score = sim.state.score;
                v_start = t + 1;
                v_key = key(sim);
                v_ms = now;
                if (point_cap > 0 && sim.state.score >= point_cap) { v_key = null; break; }
            }
        }
        if (v_key != null)
        {
            double now = clock.Elapsed.TotalMilliseconds;
            r.visits.Add(new Visit(v_tick, v_tap, v_score, v_key, sim.is_over(), !sim.is_over(), sim.state.score - v_score, sim.state.tick - v_start, now - v_ms));
        }
        r.taps = taps.ToArray();
        r.points = sim.state.score;
        r.ticks = sim.state.tick;
        r.dead = sim.is_over();
        r.room = Run.room_name(sim);
        r.ms = clock.Elapsed.TotalMilliseconds;
        return r;
    }

    public static Bank make(BotSpec bot, long first, int seeds, long cap, long point_cap, int threads, Action<string> log = null)
    {
        var b = new Bank { bot = bot.name, about = bot.about, cap = cap, point_cap = point_cap, first = first };
        var res = new BankRun[seeds];
        var clock = Stopwatch.StartNew();
        int done = 0;
        Parallel.For(0, seeds, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            res[i] = play(bot, first + i + 1, cap, point_cap);
            int d = Interlocked.Increment(ref done);
            log?.Invoke($"[{d}/{seeds}] seed {first + i + 1}: {res[i].points} points{(res[i].dead ? "" : " (alive)")}, {res[i].ms / 1000:F0} s");
        });
        b.runs = res.ToList();
        b.seconds = clock.Elapsed.TotalSeconds;
        return b;
    }

    /// Rebuilds the state before the step at `tick` of run `r`.
    public static GameSim replay(BankRun r, long tick)
    {
        var sim = new GameSim(r.seed, r.season);
        var set = new HashSet<long>(r.taps);
        while (sim.state.tick < tick) sim.step(set.Contains(sim.state.tick));
        return sim;
    }

    /// The states before each of `ticks` (ascending) of run `r`, in one replay.
    public static Dictionary<long, GameSim> replay_all(BankRun r, IEnumerable<long> ticks)
    {
        var want = new SortedSet<long>(ticks);
        var res = new Dictionary<long, GameSim>();
        var sim = new GameSim(r.seed, r.season);
        var set = new HashSet<long>(r.taps);
        foreach (long t in want)
        {
            while (sim.state.tick < t) sim.step(set.Contains(sim.state.tick));
            res[t] = sim.clone_deep();
        }
        return res;
    }

    // ----------------------------------------------------------------- files

    public JsonObject to_json()
    {
        var runs = new JsonArray();
        foreach (var r in runs_())
        {
            var vis = new JsonArray();
            foreach (var v in r.visits)
                vis.Add(new JsonArray(v.tick, v.tap ? 1 : 0, v.score, v.key, v.died ? 1 : v.censored ? 2 : 0, v.points, v.ticks, Math.Round(v.ms, 1)));
            runs.Add(new JsonObject
            {
                ["seed"] = r.seed, ["season"] = r.season, ["points"] = r.points, ["dead"] = r.dead, ["ticks"] = r.ticks,
                ["room"] = r.room, ["ms"] = Math.Round(r.ms, 1),
                ["taps"] = new JsonArray(r.taps.Select(t => (JsonNode)t).ToArray()),
                ["visits"] = vis,
            });
        }
        return new JsonObject
        {
            ["format"] = FORMAT, ["version"] = VERSION, ["gameplay_version"] = gameplay,
            ["bot"] = bot, ["about"] = about, ["cap"] = cap, ["point_cap"] = point_cap, ["first_seed"] = first + 1,
            ["seeds"] = this.runs.Count, ["seconds"] = Math.Round(seconds, 1),
            ["visit_columns"] = "tick (state before this tick's step is the entry snapshot), tap at that tick, score after entry, stratum, end (0 lived, 1 died, 2 cut by the cap), points, ticks, ms",
            ["runs"] = runs,
        };
        IEnumerable<BankRun> runs_() => this.runs;
    }

    public void save(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        File.WriteAllText(path, to_json().ToJsonString() + "\n");
    }

    public static Bank load(string path)
    {
        if (!File.Exists(path)) throw new FileNotFoundException($"no bank {path}");
        var o = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        if ((string)o["format"] != FORMAT) throw new InvalidDataException($"{path}: not a {FORMAT} file");
        var b = new Bank
        {
            bot = (string)o["bot"], about = (string)o["about"] ?? "", cap = (long)o["cap"]!, point_cap = (long)o["point_cap"]!,
            gameplay = (long)o["gameplay_version"]!, first = (long)o["first_seed"]! - 1, seconds = (double?)o["seconds"] ?? 0,
        };
        if (b.gameplay != SimConfig.GAMEPLAY_VERSION)
            Console.Error.WriteLine($"warning: {path} is gameplay {b.gameplay}, this build is {SimConfig.GAMEPLAY_VERSION}");
        foreach (var rn in o["runs"]!.AsArray())
        {
            var r = new BankRun
            {
                seed = (long)rn!["seed"]!, season = (long)rn["season"]!, points = (long)rn["points"]!, dead = (bool)rn["dead"]!,
                ticks = (long)rn["ticks"]!, room = (string)rn["room"] ?? "", ms = (double?)rn["ms"] ?? 0,
                taps = rn["taps"]!.AsArray().Select(t => (long)t!).ToArray(),
            };
            foreach (var vn in rn["visits"]!.AsArray())
            {
                var v = vn!.AsArray();
                int end = (int)v[4]!;
                r.visits.Add(new Visit((long)v[0]!, (int)v[1]! == 1, (long)v[2]!, (string)v[3]!, end == 1, end == 2, (long)v[5]!, (long)v[6]!, (double)v[7]!));
            }
            b.runs.Add(r);
        }
        return b;
    }

    /// The runs as a survival set (Survival.describe), points from 0.
    public Survival.Set as_set(string name = null) => new()
    {
        name = name ?? bot + "_bank", source = "bank", cap = cap,
        runs = runs.Select(r => new Survival.Obs(r.seed, r.points, r.dead)).ToList(),
    };
}
