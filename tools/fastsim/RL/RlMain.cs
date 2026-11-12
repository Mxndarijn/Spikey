using System.Diagnostics;

namespace FastSim.Rl;

/// `fastsim rl <train|teach|deaths|heights|calibrate|measure|speed> [options]` (tools/rlbot.ps1, docs/RL_BOT.md).
public static class RlMain
{
    /// tools/rlbot, next to the build (bin/Release/net9.0).
    public static string default_dir() => Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../rlbot"));

    public static int run(List<string> pos, Dictionary<string, string> opts)
    {
        string what = pos.Count > 1 ? pos[1] : "measure";
        string dir = Path.GetFullPath(opts.GetValueOrDefault("dir", default_dir()));
        int threads = Math.Clamp(int.Parse(opts.GetValueOrDefault("threads", "4")), 1, 16);
        string O(string k, string d) => opts.GetValueOrDefault(k, d);
        if (!opts.ContainsKey("throttle")) Power.full_speed();
        try
        {
            switch (what)
            {
                case "train":
                {
                    var t = new Ppo(dir) { threads = threads };
                    if (opts.ContainsKey("lr")) t.lr = float.Parse(opts["lr"]);
                    if (opts.ContainsKey("cap")) t.cap = long.Parse(opts["cap"]);
                    if (opts.ContainsKey("envs")) t.envs = int.Parse(opts["envs"]);
                    if (opts.ContainsKey("entropy")) t.entropy = float.Parse(opts["entropy"]);
                    if (opts.ContainsKey("practice")) t.practice = double.Parse(opts["practice"]);
                    if (opts.ContainsKey("every")) t.every = int.Parse(opts["every"]);
                    if (opts.ContainsKey("tapcost")) t.tap_cost = float.Parse(opts["tapcost"]);
                    if (opts.ContainsKey("shape")) t.shape = float.Parse(opts["shape"]);
                    if (opts.ContainsKey("expert")) t.expert = double.Parse(opts["expert"]);
                    if (opts.ContainsKey("from")) t.from_policy = true;
                    if (opts.ContainsKey("delay")) t.delay = int.Parse(opts["delay"]);
                    return t.run(opts.ContainsKey("resume"), double.Parse(O("minutes", "45")), int.Parse(O("init", "1")));
                }
                case "teach":
                {
                    var t = new Dagger(dir) { threads = threads };
                    Teacher.blind = opts.ContainsKey("blind");
                    if (opts.ContainsKey("lr")) t.lr = float.Parse(opts["lr"]);
                    if (opts.ContainsKey("cap")) t.cap = long.Parse(opts["cap"]);
                    if (opts.ContainsKey("runs")) t.runs = int.Parse(opts["runs"]);
                    if (opts.ContainsKey("horizon")) t.horizon = long.Parse(opts["horizon"]);
                    return t.run(opts.ContainsKey("resume"), double.Parse(O("minutes", "45")));
                }
                case "deaths":
                    return Deaths.run(dir, int.Parse(O("seeds", "200")), long.Parse(O("first", "0")),
                        long.Parse(O("cap", "54000")), threads, O("out", ""));
                case "heights":
                    return Heights.run(dir, int.Parse(O("seeds", "200")), int.Parse(O("search", "32")),
                        long.Parse(O("ticks", "6000")), long.Parse(O("cap", "54000")), threads);
                case "calibrate":
                    return Tiers.calibrate(dir, int.Parse(O("seeds", "200")), long.Parse(O("cap", "36000")), threads,
                        double.Parse(O("expert", "0")));
                case "measure":
                    return Tiers.measure(dir, O("tier", "all"), int.Parse(O("seeds", "400")), long.Parse(O("first", "0")),
                        long.Parse(O("cap", BotCaps.RUN_CAP.ToString())), threads, O("out", ""));
                case "review":
                    return Review.run(pos.Count > 2 ? pos[2] : "", dir, opts);
                case "imitate":
                {
                    var t = new Imitation(dir) { threads = threads };
                    if (opts.ContainsKey("lr")) t.lr = float.Parse(opts["lr"]);
                    if (opts.ContainsKey("cap")) t.cap = long.Parse(opts["cap"]);
                    if (opts.ContainsKey("runs")) t.runs = int.Parse(opts["runs"]);
                    if (opts.ContainsKey("horizon")) t.horizon = long.Parse(opts["horizon"]);
                    if (opts.ContainsKey("every")) t.label_every = int.Parse(opts["every"]);
                    Imitation.by_width = O("style", "aim") == "width";
                    Imitation.by_world = O("style", "aim") == "world";
                    if (opts.ContainsKey("wbeam") || opts.ContainsKey("whorizon"))
                        Imitation.world_skill = Imitation.world_skill with { beam = int.Parse(O("wbeam", "64")), horizon = int.Parse(O("whorizon", "150")) };
                    Imitation.wobs = O("wobs", "0") == "1";
                    if (opts.ContainsKey("margin")) Imitation.MARGIN = double.Parse(opts["margin"]);
                    Imitation.arc = O("arc", "0") != "0";
                    Imitation.arc_past = O("arc", "0") == "2";
                    t.sizes[0] = Imitation.inputs;
                    if (opts.ContainsKey("forced")) t.forced_weight = float.Parse(opts["forced"]);
                    if (opts.ContainsKey("back")) t.back = int.Parse(opts["back"]);
                    if (opts.ContainsKey("batches")) t.max_batches = int.Parse(opts["batches"]);
                    if (opts.ContainsKey("free")) t.free_weight = float.Parse(opts["free"]);
                    if (opts.ContainsKey("beta")) t.beta0 = double.Parse(opts["beta"]);
                    if (opts.ContainsKey("sizes")) t.sizes = new[] { Imitation.inputs }.Concat(opts["sizes"].Split('-').Select(int.Parse)).Append(1).ToArray();
                    return t.run(opts.ContainsKey("resume"), double.Parse(O("minutes", "45")));
                }
                case "imeasure":
                    return Imitation.measure(dir, int.Parse(O("seeds", "400")), long.Parse(O("first", "0")),
                        long.Parse(O("cap", BotCaps.RUN_CAP.ToString())), threads);
                case "diagnose":
                    return Imitation.diagnose(dir, int.Parse(O("seeds", "64")), long.Parse(O("first", "0")), long.Parse(O("cap", "54000")),
                        long.Parse(O("horizon", "90")), int.Parse(O("back", "240")), threads);
                case "expert":
                    Imitation.by_width = O("style", "aim") == "width";
                    return Imitation.expert_score(int.Parse(O("seeds", "32")), long.Parse(O("first", "0")), long.Parse(O("cap", "20000")),
                        long.Parse(O("horizon", "90")), threads);
                case "bench":
                    return Bench.run(dir, int.Parse(O("seeds", "40")), long.Parse(O("cap", "20000")), int.Parse(O("teach", "16")));
                case "speed":
                {
                    // Ticks per second of one thread with a random policy (sizing training).
                    var pol = new Policy(Policy.init(1));
                    var clock = Stopwatch.StartNew();
                    long ticks = 0;
                    for (int i = 0; i < 40; i++)
                    {
                        long room = i % 2 == 0 ? -1 : Ppo.rooms()[i % Ppo.rooms().Count];
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
        Console.Error.WriteLine("rlbot: unknown mode " + what + " (train, teach, deaths, heights, calibrate, measure, speed)");
        return 2;
    }
}
