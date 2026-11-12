using FastSim.Human;

namespace FastSim.Diff;

/// Bot survival per room entry: the human-like tiers (MotorPlayer on
/// BlindPlanner, docs/HUMAN_BOT.md) and the honest BlindPlanner.
public static class BotPlay
{
    public static readonly string[] BOTS = { "beginner", "normal", "good", "expert", "beast", "honest" };

    public static Func<GameSim, bool> make(string bot, long seed) => bot switch
    {
        "honest" => new BlindPlanner(seed) { horizon = 200, past = 110, margin = 10 }.decide,
        _ => new MotorPlayer(MotorTiers.of(bot), seed).decide,
    };

    /// (cleared, ticks, death cause or "cap").
    public static (bool ok, long ticks, string why) play(Target target, long trial, string bot)
    {
        var sim = Cases.arrive(target, trial);
        long room = sim.state.room_index;
        var d = make(bot, 1000 + trial * 7919 + target.index);
        for (long t = 0; t < target.cap; t++)
        {
            sim.step(d(sim));
            if (Cases.cleared(sim, room)) return (true, t + 1, "");
            if (sim.is_over()) return (false, t + 1, DeathCause.NAMES[sim.state.death_cause]);
        }
        return (false, target.cap, "cap");
    }
}

/// The reaction sweep (the boss review's fairness sweep, BossRuns.fair, for
/// every room). The honest planner plays the entry. Each time something new
/// shows (new spikes on the wall ahead, a hazard appearing, a boss tell), the
/// bird keeps the plan it had before for R ticks, then SurvivalSearch (exact
/// knowledge) looks for a way to live until the next new thing plus 1 s.
///   verdict at R: 1 a way, 0 no way, -1 the old plan died within R.
/// At R = 0 a "no way" means the bird was already doomed when the thing showed
/// (the planner's own earlier mistake, or a room that dooms before it shows).
public static class ReactSweep
{
    public static readonly long[] REACTS = { 0, 20, 40, 60 };
    public const long AFTER = 59;

    public record Row(long tick, string kind, long[] verdict);

    sealed record Shown(long tick, string kind, GameSim sim, byte[] plan);

    public static List<Row> run(Target target, long trial)
    {
        var sim = Cases.arrive(target, trial);
        long room = sim.state.room_index;
        var bp = new BlindPlanner(2000 + trial * 104729 + target.index) { horizon = 200, past = 110, margin = 10 };
        var shown = new List<Shown>();
        var known = new HashSet<Hazard>(ReferenceEqualityComparer.Instance);
        foreach (var h in sim.room.hazards) if (h.alive) known.Add(h);
        long score = sim.state.score;
        long tell = boss_key(sim);
        for (long t = 0; t < target.cap; t++)
        {
            sim.step(bp.decide(sim));
            if (sim.is_over() || Cases.cleared(sim, room)) break;
            string kind = null;
            if (sim.state.score != score) kind = "wall";
            foreach (var h in sim.room.hazards)
                if (h.alive && known.Add(h)) kind ??= "hazard";
            long k = boss_key(sim);
            if (k != tell) kind ??= "tell";
            score = sim.state.score;
            tell = k;
            if (kind != null && sim.state.arrival_hold <= 0)
                shown.Add(new(sim.state.tick, kind, sim.clone_deep(), bp.plan.Select(x => (byte)(x ? 1 : 0)).ToArray()));
        }
        var rows = new List<Row>();
        for (int i = 0; i < shown.Count; i++)
        {
            var s = shown[i];
            long next = i + 1 < shown.Count ? shown[i + 1].tick : s.tick + 120;
            var v = new long[REACTS.Length];
            for (int j = 0; j < REACTS.Length; j++)
            {
                long r = REACTS[j];
                var c = s.sim.clone_deep();
                int verdict = 1;
                for (long u = 0; u < r && verdict == 1; u++)
                {
                    c.step(u < s.plan.Length && s.plan[u] != 0);
                    if (Cases.cleared(c, room)) break;
                    if (c.is_over()) verdict = -1;
                }
                if (verdict == 1 && !Cases.cleared(c, room))
                {
                    long h = Math.Max(30, next + AFTER - (s.tick + r));
                    if (!new SurvivalSearch().run(c, h)) verdict = 0;
                }
                v[j] = verdict;
            }
            rows.Add(new(s.tick, s.kind, v));
        }
        return rows;
    }

    static long boss_key(GameSim s)
    {
        foreach (var h in s.room.hazards)
            if (h is Boss b) return b.down_at >= 0 ? -1 : BossBlind.tell_key(b);
        return 0;
    }
}
