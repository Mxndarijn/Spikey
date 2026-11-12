using System.Collections.Concurrent;
using FastSim.Human;

namespace FastSim;

/// fastsim boss run|fair (research/planner-review/07-bosses.md). Each run starts
/// in the portal into one boss room (score = 100 * tier) and ends when the bird
/// takes the boss exit (cleared) or dies.
///   run:  --bots leaky,honest,expert-leaky,expert,beast,search --seeds 200 --tier 1 --jobs 4
///   fair: the honest planner plays; at each new tell the bird keeps its old plan
///         for R ticks (--react 0,20,40,60), then SurvivalSearch looks for a way
///         through the told attack (up to 59 ticks past the next tell).
public static class BossRuns
{
    public static readonly string[] BOSSES = { "boss_watcher", "boss_crusher", "boss_saw" };
    const long CAP = 3200;

    public static GameSim arrive(string boss, long seed, long tier)
    {
        var sim = new GameSim(seed);
        sim.step(true);
        sim.state.score = SimConfig.BOSS_EVERY * tier;
        long want = RoomCatalog.boss_bit(RoomCatalog.index_of(boss));
        sim.state.bosses_met = 7 & ~want;
        var r = new SimRng(seed * 31 + 7);
        sim._go_through(1, ExitKind.NORMAL, (200 + r.next_below(261)) * SimConfig.SUB);
        if (sim.room.def.id != boss) throw new Exception($"wanted {boss}, got {sim.room.def.id}");
        return sim;
    }

    public static Boss boss_of(GameSim s) => s.room.hazards.OfType<Boss>().FirstOrDefault();

    static Func<GameSim, bool> make(string bot, long seed)
    {
        BlindPlanner honest(bool blind) => new BlindPlanner(seed) { horizon = 200, past = 110, margin = 10, boss_leak = !blind };
        MotorPlayer human(string tier, bool blind)
        {
            var mp = new MotorPlayer(MotorTiers.of(tier), seed);
            mp.planner.boss_leak = !blind;
            return mp;
        }
        return bot switch
        {
            "leaky" => honest(false).decide,
            "honest" => honest(true).decide,
            "expert-leaky" => human("expert", false).decide,
            "expert" => human("expert", true).decide,
            "beast-leaky" => human("beast", false).decide,
            "beast" => human("beast", true).decide,
            "good" => human("good", true).decide,
            _ => throw new Exception("unknown bot " + bot),
        };
    }

    /// What killed the bird (state after the death step).
    public static string cause(GameSim s)
    {
        long dc = s.state.death_cause;
        if (dc != DeathCause.HAZARD) return dc == DeathCause.CEILING || dc == DeathCause.FLOOR ? "edge" : "spikes";
        var b = boss_of(s);
        switch (b)
        {
            case BossWatcher w:
                if (w.dart == BossWatcher.Dart.FLY)
                {
                    long back = w.dart_side == 1 ? w.dart_x + BossWatcher.DART_LEN : w.dart_x - BossWatcher.DART_LEN;
                    if (s.bird_touches_rect(w.dart_x, w.dart_lane - BossWatcher.DART_HALF, back, w.dart_lane + BossWatcher.DART_HALF)) return "dart";
                }
                return "beam";
            case BossCrusher c:
                if (s.state.y - SimConfig.BIRD_RADIUS <= c.press_y + BossCrusher.BITE) return c.phase == 1 ? "slam" : "press";
                if (s.state.y + SimConfig.BIRD_RADIUS >= c.plate_y - BossCrusher.BITE) return "plate";
                return "crate";
            case BossSaw sw:
                return s.bird_touches_circle(BossSaw.KING_X, sw.king_y, BossSaw.KING_R) ? "king" : "blades";
        }
        return "hazard";
    }

    public record Result(string bot, string boss, long seed, bool cleared, long points, long phase, string cause, long tick);

    public static Result play(string bot, string boss, long seed, long tier)
    {
        var sim = arrive(boss, seed, tier);
        long room = sim.state.room_index, start = sim.state.score;
        if (bot == "search")
        {
            var ss = new SurvivalSearch();
            // The room is beaten once the boss is down (the exit opens on the wall ahead).
            bool ok = ss.run(sim, 2100);
            var e = ss.best;
            bool cl = e != null && (e.state.room_index > room || (boss_of(e)?.down_at ?? -1) >= 0);
            return new(bot, boss, seed, cl, cl ? SimConfig.BOSS_POINTS : (e?.room.points ?? 0), cl ? 0 : boss_of(e)?.phase ?? 0, cl ? "" : ok ? "cap" : "search", ss.ticks_survived);
        }
        var d = make(bot, seed);
        for (long t = 0; t < CAP; t++)
        {
            long phase = boss_of(sim).phase, pts = sim.room.points;
            sim.step(d(sim));
            if (sim.state.room_index > room) return new(bot, boss, seed, true, SimConfig.BOSS_POINTS, 0, "", t);
            if (sim.is_over()) return new(bot, boss, seed, false, sim.state.score - start, phase, cause(sim), t);
        }
        return new(bot, boss, seed, false, sim.state.score - start, boss_of(sim).phase, "cap", CAP);
    }

    public static int run(List<string> pos, Dictionary<string, string> opts)
    {
        string what = pos.Count > 1 ? pos[1] : "run";
        int seeds = int.Parse(opts.GetValueOrDefault("seeds", "100"));
        long first = long.Parse(opts.GetValueOrDefault("first", "1"));
        long tier = long.Parse(opts.GetValueOrDefault("tier", "1"));
        int jobs = int.Parse(opts.GetValueOrDefault("jobs", "4"));
        var bosses = opts.GetValueOrDefault("boss", "all") == "all" ? BOSSES : opts["boss"].Split(new[] { ',', ' ' }, StringSplitOptions.RemoveEmptyEntries);
        var po = new ParallelOptions { MaxDegreeOfParallelism = jobs };
        if (what == "fair") return fair(bosses, seeds, first, tier, po, opts);
        var bots = opts.GetValueOrDefault("bots", "leaky,honest,expert-leaky,expert").Split(new[] { ',', ' ' }, StringSplitOptions.RemoveEmptyEntries);
        var work = (from b in bots from bo in bosses from s in Enumerable.Range(0, seeds) select (b, bo, first + s)).ToList();
        var res = new ConcurrentBag<Result>();
        var clock = System.Diagnostics.Stopwatch.StartNew();
        Parallel.ForEach(work, po, w => res.Add(play(w.b, w.bo, w.Item3, tier)));
        Console.WriteLine($"boss run: tier {tier}, seeds {first}..{first + seeds - 1}, {clock.Elapsed.TotalSeconds:F0} s");
        Console.WriteLine($"{"bot",-13} {"boss",-13} {"clear",6} {"p1 die",7} {"p2 die",7} {"p3 die",7} {"pts",5}  causes");
        foreach (var b in bots)
            foreach (var bo in bosses)
            {
                var rs = res.Where(r => r.bot == b && r.boss == bo).ToList();
                int n = rs.Count;
                string pct(int k) => $"{100.0 * k / n,5:F1}%";
                var dead = rs.Where(r => !r.cleared).ToList();
                // Death rate per phase among birds that reached it.
                string ph(long p)
                {
                    int reach = rs.Count(r => r.cleared || r.phase >= p);
                    int died = dead.Count(r => r.phase == p);
                    return reach == 0 ? "   -" : $"{100.0 * died / reach,6:F1}%";
                }
                var causes = string.Join(" ", dead.GroupBy(r => r.cause).OrderByDescending(g => g.Count()).Select(g => $"{g.Key}:{g.Count()}"));
                Console.WriteLine($"{b,-13} {bo,-13} {pct(rs.Count(r => r.cleared))} {ph(1)} {ph(2)} {ph(3)} {rs.Average(r => r.points),5:F1}  {causes}");
            }
        if (opts.TryGetValue("out", out var path))
            File.WriteAllLines(path, res.OrderBy(r => r.bot).ThenBy(r => r.boss).ThenBy(r => r.seed)
                .Select(r => $"{r.bot}\t{r.boss}\t{r.seed}\t{(r.cleared ? 1 : 0)}\t{r.points}\t{r.phase}\t{r.cause}\t{r.tick}"));
        return 0;
    }

    record Tell(long tick, long phase, string kind, GameSim sim, byte[] plan);
    public record FairRow(string boss, long seed, long tick, long phase, string kind, long react, int verdict, long y);

    static string tell_kind(Boss b)
    {
        switch (b)
        {
            case BossWatcher w: return w.dart == BossWatcher.Dart.MARK ? "dart" : w.beam == BossWatcher.Beam.WARN ? "rows" : "other";
            case BossCrusher c: return c.crate.Any(x => x == BossCrusher.Crate.MARK) ? "crate" : c.telling ? (c.phase == 1 ? "slam" : "jaw") : "other";
            case BossSaw s: return s.telling ? (s.phase == 2 ? "ring" : "hop") : "other";
        }
        return "other";
    }

    /// One boss room on one seed: a row per (tell, reaction) with its verdict
    /// (1 = a way through, 0 = no way after the reaction, -1/-2 = the old plan
    /// dies within the reaction, by the boss / by the edge or spikes).
    public static List<FairRow> fair_rows(string boss, long seed, long tier, long[] reacts)
    {
        var rows = new List<FairRow>();
        var sim = arrive(boss, seed, tier);
        long room = sim.state.room_index;
        var bp = new BlindPlanner(seed) { horizon = 200, past = 110, margin = 10 };
        var tells = new List<Tell>();
        long key = BossBlind.tell_key(boss_of(sim));
        for (long t = 0; t < CAP && !sim.is_over() && sim.state.room_index == room; t++)
        {
            sim.step(bp.decide(sim));
            if (sim.is_over() || sim.state.room_index != room) break;
            var b = boss_of(sim);
            long k = BossBlind.tell_key(b);
            if (k != key && b.down_at < 0)
            {
                string kind = tell_kind(b);
                if (kind != "other") tells.Add(new(sim.state.tick, b.phase, kind, sim.clone_deep(), bp.plan.Select(x => (byte)(x ? 1 : 0)).ToArray()));
            }
            key = k;
        }
        for (int i = 0; i < tells.Count; i++)
        {
            var tl = tells[i];
            long next = i + 1 < tells.Count ? tells[i + 1].tick : tl.tick + 240;
            foreach (long r in reacts)
            {
                var c = tl.sim.clone_deep();
                int verdict = 1;
                for (long u = 0; u < r && verdict == 1; u++)
                {
                    c.step(u < tl.plan.Length && tl.plan[u] != 0);
                    if (c.is_over()) verdict = c.state.death_cause == DeathCause.HAZARD ? -1 : -2;
                }
                if (verdict == 1)
                {
                    long h = Math.Max(30, next + 59 - (tl.tick + r));
                    var ss = new SurvivalSearch();
                    if (!ss.run(c, h)) verdict = 0;
                }
                rows.Add(new(boss, seed, tl.tick, tl.phase, tl.kind, r, verdict, tl.sim.state.y / SimConfig.SUB));
            }
        }
        return rows;
    }

    static int fair(string[] bosses, int seeds, long first, long tier, ParallelOptions po, Dictionary<string, string> opts)
    {
        var reacts = opts.GetValueOrDefault("react", "0,20,40,60").Split(new[] { ',', ' ' }, StringSplitOptions.RemoveEmptyEntries).Select(long.Parse).ToArray();
        var rows = new ConcurrentBag<FairRow>();
        var work = (from bo in bosses from s in Enumerable.Range(0, seeds) select (bo, first + s)).ToList();
        var clock = System.Diagnostics.Stopwatch.StartNew();
        Parallel.ForEach(work, po, w =>
        {
            foreach (var row in fair_rows(w.bo, w.Item2, tier, reacts)) rows.Add(row);
        });
        Console.WriteLine($"boss fair: tier {tier}, seeds {first}..{first + seeds - 1}, {clock.Elapsed.TotalSeconds:F0} s");
        Console.WriteLine("verdict per tell: no way = SurvivalSearch finds no line after the reaction; dead in react = the old plan hits the boss within the reaction");
        Console.WriteLine($"{"boss",-13} {"tell",-6} {"ph",3} {"n",5}  " + string.Join("  ", reacts.Select(r => $"R={r,-2} noway/deadR")));
        foreach (var g in rows.GroupBy(x => (x.boss, x.kind, x.phase)).OrderBy(g => g.Key.boss).ThenBy(g => g.Key.phase).ThenBy(g => g.Key.kind))
        {
            int n = g.Count(x => x.react == reacts[0]);
            var cells = reacts.Select(r =>
            {
                var rr = g.Where(x => x.react == r).ToList();
                return $"{100.0 * rr.Count(x => x.verdict == 0) / n,5:F1}%/{100.0 * rr.Count(x => x.verdict < 0) / n,4:F1}%";
            });
            Console.WriteLine($"{g.Key.boss,-13} {g.Key.kind,-6} {g.Key.phase,3} {n,5}  " + string.Join("  ", cells));
        }
        if (opts.TryGetValue("out", out var path))
            File.WriteAllLines(path, rows.OrderBy(r => r.boss).ThenBy(r => r.seed).ThenBy(r => r.tick).ThenBy(r => r.react)
                .Select(r => $"{r.boss}\t{r.seed}\t{r.tick}\t{r.phase}\t{r.kind}\t{r.react}\t{r.verdict}\t{r.y}"));
        return 0;
    }
}
