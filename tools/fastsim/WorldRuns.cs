using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;
using FastSim.Model;

namespace FastSim;

/// `fastsim world runs|tiers|describe|runfile`: the world planner in full runs.
///   world runs [seeds] --skill beast|expert|good|normal|beginner [--cap ticks] [--first n]
///   world tiers [seeds]             every skill level, with the targets
///   world describe <seed> [tick]    the structured world at one tick (what the bot reads)
///   world runfile <seed> --skill s --out file.json   one run as a run file (docs/RENDERING.md)
public static partial class WorldCheck
{
    public static readonly (string name, double target)[] TARGETS =
    {
        ("beginner", 30), ("normal", 60), ("good", 120), ("expert", 250), ("beast", 500),
    };

    public readonly record struct RunResult(long seed, long points, long ticks, bool dead, string room, string cause, double ms_per_tick);

    static int RunMore(string what, List<string> pos, Dictionary<string, string> opts, int threads)
    {
        string O(string k, string d) => opts.GetValueOrDefault(k, d);
        long cap = long.Parse(O("cap", SimConfig.MAX_TICKS.ToString()));
        long first = long.Parse(O("first", "0"));
        double minutes = double.Parse(O("minutes", "55"), System.Globalization.CultureInfo.InvariantCulture);
        switch (what)
        {
            case "runs":
            {
                var sk = Skill(opts);
                var runs = Play(sk, first, int.Parse(pos.Count > 2 ? pos[2] : "40"), cap, threads, minutes);
                Report(sk.name, sk, runs, O("out", ""));
                return 0;
            }
            case "tiers":
            {
                int n = int.Parse(pos.Count > 2 ? pos[2] : "40");
                var sb = new StringBuilder();
                foreach (var (name, target) in TARGETS)
                {
                    var sk = WorldPlanner.Skill.Named(name);
                    var runs = Play(sk, first, n, cap, threads, minutes);
                    sb.Append(Report(name, sk, runs, "", target));
                }
                Console.WriteLine();
                Console.Write(sb.ToString());
                if (O("out", "") != "") File.WriteAllText(O("out", ""), sb.ToString());
                return 0;
            }
            case "debug":
            {
                long seed = long.Parse(pos.Count > 2 ? pos[2] : "1");
                var sk = Skill(opts);
                var sim = new GameSim(seed);
                var bot = new WorldPlanner(sk, seed);
                var mem = new Memory();
                var log = new List<string>();
                while (!sim.is_over() && sim.state.tick < cap)
                {
                    bool tap = bot.Decide(sim, mem);
                    var st = sim.state;
                    log.Add($"t{st.tick} x {st.x / 64.0:F0} y {st.y / 64.0:F1} vy {st.vy / 64.0:F2} tap {(tap ? 1 : 0)} done {bot.last_done} left {bot.last_left} deep w{bot.last_deep_wait} t{bot.last_deep_tap} best {bot.last_best:F0} mask {Convert.ToString(sim.wall_mask(st.vx > 0 ? 1 : 0), 2).PadLeft(13, '0')}");
                    sim.step(tap);
                }
                Console.WriteLine($"seed {seed}: score {sim.state.score} died {DeathCause.NAMES[sim.state.death_cause]} in {sim.room.def.id}/{sim.room.variant_id()} at tick {sim.state.tick}");
                foreach (var l in log.Skip(Math.Max(0, log.Count - int.Parse(O("last", "70"))))) Console.WriteLine("  " + l);
                return 0;
            }
            case "describe":
                return Describe(long.Parse(pos.Count > 2 ? pos[2] : "1"), long.Parse(pos.Count > 3 ? pos[3] : "300"));
            case "runfile":
            {
                var sk = Skill(opts);
                long seed = long.Parse(pos.Count > 2 ? pos[2] : "1");
                var sim = new GameSim(seed);
                var bot = new WorldPlanner(sk, seed);
                var mem = new Memory();
                var taps = new List<long>();
                while (!sim.is_over() && sim.state.tick < cap)
                {
                    bool tap = bot.Decide(sim, mem);
                    if (tap) taps.Add(sim.state.tick);
                    sim.step(tap);
                }
                string out_ = O("out", "world_run.json");
                RunFile.write(out_, sim, taps, name: "world planner (" + sk.name + ")");
                Console.WriteLine($"world runfile: seed {seed}, skill {sk.name}, score {sim.state.score}, {sim.state.tick} ticks -> {out_}");
                return 0;
            }
        }
        Console.Error.WriteLine($"unknown world mode '{what}'");
        return 2;
    }

    static WorldPlanner.Skill Skill(Dictionary<string, string> opts)
    {
        var sk = WorldPlanner.Skill.Named(opts.GetValueOrDefault("skill", "beast"));
        // Overrides for tuning: --delay 8 --jitter 3 ...
        int I(string k, int d) => opts.ContainsKey(k) ? int.Parse(opts[k]) : d;
        double D(string k, double d) => opts.ContainsKey(k) ? double.Parse(opts[k], System.Globalization.CultureInfo.InvariantCulture) : d;
        return sk with
        {
            delay = I("delay", sk.delay),
            jitter = I("jitter", sk.jitter),
            miss = D("miss", sk.miss),
            horizon = I("horizon", sk.horizon),
            margin_px = I("margin", (int)sk.margin_px),
            beam = I("beam", sk.beam),
            misjudge_px = D("misjudge", sk.misjudge_px),
            slip = D("slip", sk.slip),
        };
    }

    public static RunResult[] Play(WorldPlanner.Skill sk, long first, int n, long cap, int threads, double minutes = 55)
    {
        var out_ = new RunResult[n];
        var clock = Stopwatch.StartNew();
        int finished = 0;
        Parallel.For(0, n, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            if (clock.Elapsed.TotalMinutes > minutes)
            {
                out_[i] = new RunResult(-1, 0, 0, false, "", "", 0);
                return;
            }
            long seed = first + i + 1;
            var sim = new GameSim(seed);
            var bot = new WorldPlanner(sk, seed);
            var mem = new Memory();
            var c = Stopwatch.StartNew();
            while (!sim.is_over() && sim.state.tick < cap) sim.step(bot.Decide(sim, mem));
            string room = sim.room.def.id + (sim.room.variant_id() != "" ? "/" + sim.room.variant_id() : "");
            out_[i] = new RunResult(seed, sim.state.score, sim.state.tick, sim.is_over(), room,
                sim.is_over() ? DeathCause.NAMES[sim.state.death_cause] : "", c.Elapsed.TotalMilliseconds / Math.Max(1, sim.state.tick));
            int k = Interlocked.Increment(ref finished);
            if (k % Math.Max(1, n / 10) == 0)
                Console.WriteLine($"  {sk.name}: {k}/{n} runs, {clock.Elapsed.TotalSeconds:F0} s");
        });
        return out_.Where(r => r.seed >= 0).ToArray();
    }

    public static double Pct(IEnumerable<long> xs, double q)
    {
        var a = xs.OrderBy(x => x).ToArray();
        if (a.Length == 0) return 0;
        return a[(int)Math.Min(a.Length - 1, Math.Floor(q * a.Length))];
    }

    static string Report(string name, WorldPlanner.Skill sk, RunResult[] runs, string out_path, double target = -1)
    {
        var sb = new StringBuilder();
        var pts = runs.Select(r => r.points).ToArray();
        double med = Pct(pts, 0.5), p90 = Pct(pts, 0.9), p25 = Pct(pts, 0.25);
        sb.AppendLine($"world runs {name}: {runs.Length} full runs, median {med}, p25 {p25}, p90 {p90}, mean {pts.DefaultIfEmpty(0).Average():F1}, " +
            $"max {pts.DefaultIfEmpty(0).Max()}, alive at cap {runs.Count(r => !r.dead)}" + (target > 0 ? $"  (target {target})" : ""));
        sb.AppendLine($"  skill: {sk}");
        sb.AppendLine($"  speed: {runs.Select(r => r.ms_per_tick).DefaultIfEmpty(0).Average():F3} ms per tick, {runs.Sum(r => r.ticks)} ticks");
        var rooms = runs.Where(r => r.dead).GroupBy(r => r.room).OrderByDescending(g => g.Count()).Take(14);
        sb.AppendLine("  deaths by room: " + string.Join(", ", rooms.Select(g => $"{g.Key} {g.Count()}")));
        var causes = runs.Where(r => r.dead).GroupBy(r => r.cause).OrderByDescending(g => g.Count());
        sb.AppendLine("  causes: " + string.Join(", ", causes.Select(g => $"{g.Key} {g.Count()}")));
        Console.Write(sb.ToString());
        if (out_path != "") File.WriteAllText(out_path, sb.ToString());
        return sb.ToString();
    }

    /// Prints the structured world the bot reads at one tick of a run.
    static int Describe(long seed, long at)
    {
        var sim = new GameSim(seed);
        var bot = new WorldPlanner(WorldPlanner.Skill.BEAST, seed);
        var mem = new Memory();
        while (!sim.is_over() && sim.state.tick < at) sim.step(bot.Decide(sim, mem));
        mem.Observe(sim);
        var w = WorldModel.Read(sim, mem);
        var d = WorldDesc.Of(w);
        Console.WriteLine(d.ToText());
        var obs = new float[WorldObs.SIZE];
        WorldObs.Fill(w, obs);
        Console.WriteLine($"observation ({WorldObs.SIZE} values): " + string.Join(" ", obs.Select(v => v.ToString("F2"))));
        return 0;
    }
}
