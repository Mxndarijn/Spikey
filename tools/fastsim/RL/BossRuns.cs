namespace FastSim.Rl;

/// `fastsim rl bosses [--seeds 100] [--cap 20000] [--tells 0]`: the policy
/// plays each boss room on its own (practice start, tier 1), seeds 1..N.
/// A room counts as survived when the boss goes down (BOSS_POINTS bounces)
/// before a death or the cap. --tells 0 hides the boss tells from the
/// danger grid (Observer.tells), to compare.
public static class BossRuns
{
    public static int run(string dir, string file, int seeds, long cap, int threads)
    {
        var pol = Policy.load(Path.Combine(dir, file));
        Console.WriteLine($"rlbot bosses: {file}, tells {(Observer.tells ? "on, warned cells " + Observer.WARN : "off")}, {seeds} seeds, cap {cap}");
        foreach (var id in new[] { "boss_watcher", "boss_crusher", "boss_saw" })
        {
            long index = RoomCatalog.index_of(id);
            var won = new bool[seeds];
            var pts = new long[seeds];
            var causes = new string[seeds];
            Parallel.For(0, seeds, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
            {
                var sim = new GameSim(i + 1, Seasons.NONE, index);
                var boss = (Boss)sim.room.hazards.First(h => h is Boss);
                var p = new Player(pol, Handicap.NONE, sim.seed_value);
                long n = 0;
                while (n < cap && !sim.is_over() && boss.down_at < 0)
                {
                    sim.step(p.decide(sim));
                    n++;
                }
                won[i] = boss.down_at >= 0 && !sim.is_over();
                pts[i] = sim.room.points;
                causes[i] = sim.is_over() ? DeathCause.NAMES[sim.state.death_cause] : "";
            });
            var sorted = pts.OrderBy(x => x).ToArray();
            string top = string.Join(", ", causes.Where(c => c != "").GroupBy(c => c).OrderByDescending(g => g.Count())
                .Take(3).Select(g => $"{g.Key} {g.Count()}"));
            Console.WriteLine($"  {id}: survived {won.Count(w => w)}/{seeds}, median bounces {sorted[seeds / 2]}, mean {pts.Average():F1}; deaths: {top}");
        }
        return 0;
    }
}
