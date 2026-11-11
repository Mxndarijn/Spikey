using System.Diagnostics;

namespace FastSim.Rl;

/// `fastsim rl <train|calibrate|measure|speed> [options]` (tools/rlbot.ps1, docs/RL_BOT.md).
public static class RlMain
{
    /// tools/rlbot, next to the build (bin/Release/net9.0).
    public static string default_dir() => Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../rlbot"));

    public static int run(List<string> pos, Dictionary<string, string> opts)
    {
        string what = pos.Count > 1 ? pos[1] : "measure";
        string dir = Path.GetFullPath(opts.GetValueOrDefault("dir", default_dir()));
        int threads = Math.Clamp(int.Parse(opts.GetValueOrDefault("threads", "4")), 1, 4);
        string O(string k, string d) => opts.GetValueOrDefault(k, d);
        try
        {
            switch (what)
            {
                case "train":
                {
                    var t = new Trainer(dir) { threads = threads };
                    if (opts.ContainsKey("pairs")) t.pairs = int.Parse(opts["pairs"]);
                    if (opts.ContainsKey("sigma")) t.sigma = float.Parse(opts["sigma"]);
                    if (opts.ContainsKey("lr")) t.lr = float.Parse(opts["lr"]);
                    if (opts.ContainsKey("cap")) t.cap = long.Parse(opts["cap"]);
                    if (opts.ContainsKey("full")) t.full_runs = int.Parse(opts["full"]);
                    if (opts.ContainsKey("practice")) t.practice_runs = int.Parse(opts["practice"]);
                    return t.run(opts.ContainsKey("resume"), double.Parse(O("minutes", "45")), int.Parse(O("init", "1")));
                }
                case "calibrate":
                    return Tiers.calibrate(dir, int.Parse(O("seeds", "200")), long.Parse(O("cap", "36000")), threads,
                        double.Parse(O("expert", "0")));
                case "measure":
                    return Tiers.measure(dir, O("tier", "all"), int.Parse(O("seeds", "400")), long.Parse(O("first", "0")),
                        long.Parse(O("cap", SimConfig.MAX_TICKS.ToString())), threads, O("out", ""));
                case "speed":
                {
                    // Ticks per second of one thread with a random policy (sizing training).
                    var pol = new Policy(Policy.init(1));
                    var clock = Stopwatch.StartNew();
                    long ticks = 0;
                    for (int i = 0; i < 40; i++)
                    {
                        long room = i % 2 == 0 ? -1 : Trainer.rooms()[i % Trainer.rooms().Count];
                        ticks += Player.play(pol, Handicap.NONE, new GameSim(i + 1, Seasons.NONE, room), 3600).ticks;
                    }
                    Console.WriteLine($"rlbot speed: {ticks} ticks in {clock.Elapsed.TotalSeconds:F2} s = {ticks / clock.Elapsed.TotalSeconds:F0} ticks/s per thread");
                    return 0;
                }
            }
        }
        catch (Exception e) when (e is FileNotFoundException || e is InvalidDataException)
        {
            Console.Error.WriteLine("rlbot: " + e.Message);
            return 2;
        }
        Console.Error.WriteLine("rlbot: unknown mode " + what + " (train, calibrate, measure, speed)");
        return 2;
    }
}
