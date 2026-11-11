using System.Diagnostics;

namespace FastSim.Rl;

/// `rl heights`: where does the bird fly? Share of ticks in each height band
/// (8 bands from the ceiling line to the floor line) for the policy and for
/// SurvivalSearch's line, the policy's deaths per band, and at each death
/// whether the nearest free gap on the wall ahead was above or below it.
public static class Heights
{
    public const int BANDS = 8;

    static int band(long y)
    {
        long top = SimConfig.KILL_TOP, h = SimConfig.KILL_BOTTOM - SimConfig.KILL_TOP;
        return (int)Math.Clamp((y - top) * BANDS / h, 0, BANDS - 1);
    }

    public static int run(string dir, int seeds, int search_seeds, long search_ticks, long cap, int threads)
    {
        var pol = Policy.load(Path.Combine(dir, "policy.json"));
        var clock = Stopwatch.StartNew();
        var par = new ParallelOptions { MaxDegreeOfParallelism = threads };
        var bot = new long[BANDS];
        var died = new long[BANDS];
        var gap_above = new long[BANDS];
        var gap_below = new long[BANDS];
        var taps = new long[2];
        object lk = new();
        Parallel.For(0, seeds, par, i =>
        {
            var sim = new GameSim(i + 1);
            var eyes = new Player(pol, Handicap.NONE, i + 1);
            var mine = new long[BANDS];
            long n = 0, tapped = 0;
            while (!sim.is_over() && n < cap)
            {
                bool tap = eyes.decide(sim);
                if (sim.state.started) mine[band(sim.state.y)]++;
                if (tap) tapped++;
                var before = sim.state.copy();
                long side = before.vx > 0 ? 1 : 0;
                long mask = sim.wall_mask(side), shift = sim.wall_shift(side);
                sim.step(tap);
                n++;
                if (sim.is_over())
                {
                    int b = band(before.y);
                    var (gy, _) = Observer.nearest_gap(mask, before.y - shift);
                    lock (lk)
                    {
                        died[b]++;
                        if (gy + shift < before.y) gap_above[b]++;
                        else gap_below[b]++;
                    }
                }
            }
            lock (lk)
            {
                for (int b = 0; b < BANDS; b++) bot[b] += mine[b];
                taps[0] += tapped;
                taps[1] += n;
            }
        });
        var search = new long[BANDS];
        long sticks = 0, staps = 0;
        Parallel.For(0, search_seeds, par, i =>
        {
            long seed = 5000 + i * 131;
            var s = new SurvivalSearch();
            if (!s.run(new GameSim(seed), search_ticks)) return;
            var sim = new GameSim(seed);
            var mine = new long[BANDS];
            long t = 0;
            foreach (byte tap in s.best_inputs)
            {
                if (sim.state.started) mine[band(sim.state.y)]++;
                sim.step(tap == 1);
                t += tap;
            }
            lock (lk)
            {
                for (int b = 0; b < BANDS; b++) search[b] += mine[b];
                sticks += s.best_inputs.Length;
                staps += t;
            }
        });
        double bt = bot.Sum(), st = search.Sum(), dt = Math.Max(1, died.Sum());
        long px = (SimConfig.KILL_BOTTOM - SimConfig.KILL_TOP) / BANDS / SimConfig.SUB;
        Console.WriteLine($"rl heights: policy {seeds} runs, SurvivalSearch {search_seeds} runs x {search_ticks} ticks; band = {px} px, 1 = top (ceiling) .. {BANDS} = bottom (floor)");
        Console.WriteLine($"  {"band",4} {"policy",8} {"search",8} {"deaths",8} {"gap above",10} {"gap below",10}");
        for (int b = 0; b < BANDS; b++)
            Console.WriteLine($"  {b + 1,4} {100 * bot[b] / bt,7:F1}% {100 * search[b] / Math.Max(1, st),7:F1}% {100 * died[b] / dt,7:F1}% {gap_above[b],10} {gap_below[b],10}");
        Console.WriteLine($"  taps per second: policy {60.0 * taps[0] / Math.Max(1, taps[1]):F2}, search {60.0 * staps / Math.Max(1, sticks):F2}");
        Console.WriteLine($"rl heights: {clock.Elapsed.TotalSeconds:F0} s");
        return 0;
    }
}
