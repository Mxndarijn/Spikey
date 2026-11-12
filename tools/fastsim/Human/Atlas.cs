namespace FastSim.Human;

/// `fastsim human atlas`: what does the beast lack at each death?
/// Each run is replayed to `back` ticks before its death; from there a fresh
/// bot plays on with the copy's hidden values (BlindPlanner.Reveal) left as
/// they truly are, one kind at a time. Verdicts:
///   luck     - the same bot with nothing revealed lives in most tries (a bad guess)
///   doomed   - even with every hidden value true it dies (too late at `back`, or the search fails)
///   <kind>   - revealing that one kind saves it in most tries (what it lacked)
///   combo    - only all kinds together save it
public static class Atlas
{
    const int TRIES = 3;

    public static int run(Func<string, string, string> opt, int threads)
    {
        int seeds = int.Parse(opt("seeds", "64"));
        long first = long.Parse(opt("first", "0"));
        long cap = long.Parse(opt("cap", "30000"));
        long back = long.Parse(opt("back", "240"));
        long after = long.Parse(opt("after", "300"));
        string tier = opt("tier", "beast");
        var motor = MotorTiers.of(tier);
        var runs = new Trace[seeds];
        Parallel.For(0, seeds, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            long seed = first + 1 + i;
            runs[i] = Trace.play(new GameSim(seed), new MotorPlayer(motor, seed).decide, cap, false);
        });
        var dead = runs.Where(r => r.dead).ToList();
        long pts = runs.Sum(r => r.points);
        Console.WriteLine($"{tier}: {seeds} runs, {dead.Count} deaths, {pts} points, {100.0 * dead.Count / Math.Max(1, pts):F3} deaths/100 pt" +
                          $" (know_exits {BlindPlanner.know_exits})");
        var rows = new string[dead.Count];
        var verdicts = new string[dead.Count];
        Parallel.For(0, dead.Count, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            var r = dead[i];
            long death = r.ticks; // the tick it died on (runs start at tick 0)
            long from = Math.Max(1, death - back);
            var taps = new HashSet<long>(r.taps);
            int tries(int reveal)
            {
                int ok = 0;
                for (int k = 1; k <= TRIES; k++)
                {
                    var sim = new GameSim(r.seed);
                    while (sim.state.tick < from && !sim.is_over()) sim.step(taps.Contains(sim.state.tick));
                    if (sim.is_over()) return 0;
                    long bot_seed = r.seed * 7919 + k * 104729;
                    var bp = MotorPlayer.make_planner(bot_seed, motor);
                    bp.reveal = reveal;
                    var mp = new MotorPlayer(motor, bot_seed, bp);
                    while (sim.state.tick < death + after && !sim.is_over()) sim.step(mp.decide(sim));
                    if (!sim.is_over()) ok++;
                }
                return ok;
            }
            string v;
            int base_ok = tries(0);
            if (base_ok * 2 > TRIES) v = "luck";
            else if (tries(BlindPlanner.Reveal.ALL) * 2 <= TRIES) v = "doomed";
            else
            {
                var hit = new List<string>();
                foreach (var (name, bit) in BlindPlanner.Reveal.KINDS)
                    if (tries(bit) * 2 > TRIES) hit.Add(name);
                v = hit.Count == 0 ? "combo" : string.Join("+", hit);
            }
            verdicts[i] = v;
            rows[i] = $"  seed {r.seed} at {r.points} pts, tick {death}: {r.cause} in {r.room} -> {v}";
        });
        foreach (var row in rows) Console.WriteLine(row);
        Console.WriteLine("verdicts: " + string.Join(", ", verdicts.GroupBy(v => v).OrderByDescending(g => g.Count())
            .Select(g => $"{g.Key} {g.Count()}")));
        Console.WriteLine("rooms: " + string.Join(", ", dead.GroupBy(d => d.room).OrderByDescending(g => g.Count()).Take(12)
            .Select(g => $"{g.Key} {g.Count()}")));
        return 0;
    }
}
