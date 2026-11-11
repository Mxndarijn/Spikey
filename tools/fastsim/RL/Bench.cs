using System.Diagnostics;

namespace FastSim.Rl;

/// `fastsim rl bench`: times the parts of a training iteration on one thread
/// (sim step, observer base + grid, policy forward, teacher search) and
/// prints a fingerprint of every observation float and teacher answer, so a
/// speed-up can be shown to give the same values (same fingerprint).
public static class Bench
{
    public static int run(string dir, int seeds, long cap, int teach_runs)
    {
        var pol = Policy.load(Path.Combine(dir, "policy.json"));
        var acts = pol.net.scratch();
        long t_step = 0, t_obs = 0, t_fwd = 0, ticks = 0;
        ulong h = 1469598103934665603UL, zh = h;
        var sw = new Stopwatch();
        var deaths = new List<(long seed, long room, byte[] taps)>();
        var all = Stopwatch.StartNew();
        for (int i = 0; i < seeds; i++)
        {
            long seed = 30_000_000 + i;
            long room = i % 2 == 0 ? -1 : Ppo.rooms()[i % Ppo.rooms().Count];
            var sim = new GameSim(seed, Seasons.NONE, room);
            var eyes = new Player(null, Handicap.NONE, seed);
            var taps = new List<byte>();
            while (!sim.is_over() && taps.Count < cap)
            {
                sw.Restart();
                var x = eyes.observe(sim);
                t_obs += sw.ElapsedTicks;
                for (int k = 0; k < x.Length; k++) h = (h ^ (uint)BitConverter.SingleToInt32Bits(x[k])) * 1099511628211UL;
                sw.Restart();
                float z = pol.act(x, acts);
                t_fwd += sw.ElapsedTicks;
                zh = (zh ^ (uint)BitConverter.SingleToInt32Bits(z)) * 1099511628211UL;
                bool tap = !sim.state.started || z > 0f;
                taps.Add(tap ? (byte)1 : (byte)0);
                sw.Restart();
                sim.step(tap);
                t_step += sw.ElapsedTicks;
                ticks++;
            }
            if (sim.is_over()) deaths.Add((seed, room, taps.ToArray()));
        }
        double play_s = all.Elapsed.TotalSeconds;
        double f = Stopwatch.Frequency;
        Console.WriteLine($"bench play: {seeds} runs, {ticks} ticks, {deaths.Count} deaths in {play_s:F2} s = {ticks / play_s:F0} ticks/s");
        Console.WriteLine($"  step {t_step / f:F2} s, observe {t_obs / f:F2} s, forward {t_fwd / f:F2} s");
        Console.WriteLine($"  observation fingerprint {h:x16}, logit fingerprint {zh:x16}");

        {
            // Observer split: whole frame vs grid alone, on the first deaths' runs.
            long tf = 0, tg = 0;
            var buf = new float[Observer.FRAME];
            foreach (var d in deaths.Take(10))
            {
                var sim = new GameSim(d.seed, Seasons.NONE, d.room);
                foreach (var tp in d.taps)
                {
                    sw.Restart();
                    Observer.frame(sim, buf);
                    tf += sw.ElapsedTicks;
                    sw.Restart();
                    Observer.grid(sim, buf, Observer.BASE);
                    tg += sw.ElapsedTicks;
                    sim.step(tp != 0);
                }
            }
            Console.WriteLine($"  observer split: frame {tf / f:F3} s, grid alone {tg / f:F3} s");
            var tw = Stopwatch.StartNew();
            float acc = 0f;
            for (int i = 0; i < 165625 * 128; i++) acc += MathF.Tanh((i & 1023) / 256f - 2f);
            Console.WriteLine($"  tanh x {165625 * 128}: {tw.Elapsed.TotalSeconds:F2} s ({acc:F0})");
        }
        {
            // Every room variant, 2000 ticks of a random tapper: the observer's
            // frames and the policy's logits.
            ulong vh = 1469598103934665603UL;
            var buf = new float[Observer.FRAME];
            var catalog = RoomCatalog.all();
            int cases = 0;
            for (int ri = 0; ri < catalog.Count; ri++)
            {
                var vs = catalog[ri].variants.Count == 0 ? new List<string> { "" } : catalog[ri].variants.Select(v => v.id).ToList();
                foreach (var v in vs)
                {
                    cases++;
                    var bot = new SimRng(77 + cases);
                    long sd = 1;
                    var sim = new GameSim(sd, Seasons.NONE, ri, v);
                    var eyes = new Player(null, Handicap.NONE, sd);
                    for (int t = 0; t < 2000; t++)
                    {
                        if (sim.is_over())
                        {
                            sim = new GameSim(++sd, Seasons.NONE, ri, v);
                            eyes = new Player(null, Handicap.NONE, sd);
                        }
                        var x = eyes.observe(sim);
                        for (int k = 0; k < x.Length; k++) vh = (vh ^ (uint)BitConverter.SingleToInt32Bits(x[k])) * 1099511628211UL;
                        vh = (vh ^ (uint)BitConverter.SingleToInt32Bits(pol.act(x, acts))) * 1099511628211UL;
                        sim.step(!sim.state.started || SimBots.random_tapper(sim, bot, 10));
                    }
                }
            }
            Console.WriteLine($"  every room variant ({cases}): observation + logit fingerprint {vh:x16}");
        }
        // The teacher's part, as Dagger.teach does it (replay + safe_moves on a binary search, then extras).
        long t_replay = 0, t_search = 0, searches = 0;
        ulong th = 1469598103934665603UL;
        var tc = Stopwatch.StartNew();
        foreach (var d in deaths.Take(teach_runs))
        {
            long T = d.taps.Length;
            bool savable(long t)
            {
                sw.Restart();
                var sim = new GameSim(d.seed, Seasons.NONE, d.room);
                for (long i = 0; i < t; i++) sim.step(d.taps[i] != 0);
                t_replay += sw.ElapsedTicks;
                sw.Restart();
                (bool tap, bool wait) m = sim.state.started ? Teacher.safe_moves(sim, 90) : (true, false);
                t_search += sw.ElapsedTicks;
                searches++;
                th = (th ^ (ulong)((m.tap ? 2 : 0) + (m.wait ? 1 : 0) + t * 4)) * 1099511628211UL;
                return m.tap || m.wait;
            }
            long lo = Math.Max(1, T - 240), hi = T;
            if (!savable(lo)) continue;
            while (hi - lo > 1)
            {
                long mid = (lo + hi) / 2;
                if (savable(mid)) lo = mid;
                else hi = mid;
            }
            for (int j = 1; j <= 20 && lo - j * 2 >= 1; j++) savable(lo - j * 2);
        }
        Console.WriteLine($"bench teach: {Math.Min(teach_runs, deaths.Count)} deaths, {searches} searches in {tc.Elapsed.TotalSeconds:F2} s (replay {t_replay / f:F2} s, search {t_search / f:F2} s)");
        Console.WriteLine($"  teacher fingerprint {th:x16}");
        return 0;
    }
}
