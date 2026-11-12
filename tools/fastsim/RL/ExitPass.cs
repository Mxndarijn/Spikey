using System.Collections.Concurrent;

namespace FastSim.Rl;

/// `rl review exitpass --room stalac`: is a room's exit placed where a bird can
/// take it on the first pass? Tool only. For each variant, seed and random
/// surviving line (as the `reach` check plays them), from the step the exit's
/// ghost shows: can SurvivalSearch go through the exit on the bird's first
/// arrival at the exit's wall (no extra crossing)? Also with the two spare
/// crossings the `reach` check allows.
public static class ExitPass
{
    public static int run(Dictionary<string, string> opts, int seeds, int threads)
    {
        string id = opts.GetValueOrDefault("room", "stalac");
        int lines = int.Parse(opts.GetValueOrDefault("lines", "3"));
        var def = RoomCatalog.all()[(int)RoomCatalog.index_of(id)];
        var variants = def.variants.Count == 0 ? new List<string> { "classic" } : def.variants.Select(v => v.id).ToList();
        var shown = new ConcurrentDictionary<string, int>();
        var first = new ConcurrentDictionary<string, int>();
        var spare = new ConcurrentDictionary<string, int>();
        var bad = new ConcurrentBag<string>();
        var jobs = variants.SelectMany(v => Enumerable.Range(0, seeds).SelectMany(s => Enumerable.Range(0, lines).Select(l => (v, s, l)))).ToList();
        Parallel.ForEach(jobs, new ParallelOptions { MaxDegreeOfParallelism = threads }, job =>
        {
            var (v, s, l) = job;
            long seed = 1000 + s * 61;
            var sim = Checks.Setups.practice(id, seed, v);
            var rnd = new Random((int)seed * 7 + l);
            long done = 0;
            while (!sim.state.exit_preview && !sim.is_over() && done < 1500)
            {
                var ss = new SurvivalSearch { pick = rnd };
                if (!ss.run(sim, 360)) return;
                int n = Math.Min(120, ss.best_inputs.Length);
                for (int i = 0; i < n && !sim.state.exit_preview; i++)
                {
                    sim.step(ss.best_inputs[i] == 1);
                    done++;
                }
            }
            if (!sim.state.exit_preview) return;
            shown.AddOrUpdate(v, 1, (_, x) => x + 1);
            long room = sim.state.room_index;
            long crossing = (sim.room.wall_right() - sim.room.wall_left()) / SimConfig.SPEED_X;
            long to_exit = sim.steps_to_exit(sim.state.exit_side);
            var a = new SurvivalSearch();
            a.run(sim.clone_deep(), to_exit + SimConfig.PORTAL_HOLD + 10);
            bool ok1 = a.best != null && a.best.state.room_index != room;
            var b = new SurvivalSearch();
            b.run(sim.clone_deep(), to_exit + 2 * crossing + SimConfig.PORTAL_HOLD + 10);
            bool ok2 = b.best != null && b.best.state.room_index != room;
            if (ok1) first.AddOrUpdate(v, 1, (_, x) => x + 1);
            if (ok2) spare.AddOrUpdate(v, 1, (_, x) => x + 1);
            if (!ok1) bad.Add($"{v} seed {seed} line {l}: exit {sim.state.exit_a_y / SimConfig.SUB} px, bird {sim.state.y / SimConfig.SUB} px{(ok2 ? "" : " (not even with 2 spare crossings)")}");
        });
        Console.WriteLine($"exit on the first pass from the ghost, room {id}, {seeds} seeds x {lines} lines, gameplay {SimConfig.GAMEPLAY_VERSION}");
        Console.WriteLine("variant\tghosts\tfirst pass\twith 2 spare");
        foreach (var v in variants)
            Console.WriteLine($"{v}\t{shown.GetValueOrDefault(v)}\t{first.GetValueOrDefault(v)}\t{spare.GetValueOrDefault(v)}");
        foreach (var x in bad.OrderBy(x => x)) Console.WriteLine("miss\t" + x);
        return 0;
    }
}

/// `rl review bosstell --boss boss_watcher --tier 3 --seed 3 --tick 1694`: replays
/// the bossfair gate's tell at `tick` (the planner's old plan for 60 steps) and
/// prints the bird, the boss and the death, step by step. Tool only.
public static class BossTell
{
    public static int run(Dictionary<string, string> opts)
    {
        string boss = opts.GetValueOrDefault("boss", "boss_watcher");
        long tier = long.Parse(opts.GetValueOrDefault("tier", "3"));
        long seed = long.Parse(opts.GetValueOrDefault("seed", "3"));
        long at = long.Parse(opts.GetValueOrDefault("tick", "0"));
        long react = long.Parse(opts.GetValueOrDefault("react", "60"));
        var sim = FastSim.BossRuns.arrive(boss, seed, tier);
        var bp = new BlindPlanner(seed) { horizon = 200, past = 110, margin = 10 };
        bool[] plan = null;
        while (!sim.is_over() && sim.state.tick < at)
        {
            sim.step(bp.decide(sim));
            if (sim.state.tick == at) plan = bp.plan.ToArray();
        }
        if (plan == null) { Console.WriteLine("tick not reached"); return 1; }
        Console.WriteLine($"tell at {at}: plan {plan.Length} steps, bird y {sim.state.y / SimConfig.SUB} x {sim.state.x / SimConfig.SUB} vx {sim.state.vx}");
        var c = sim.clone_deep();
        for (long u = 0; u < react + 40 && !c.is_over(); u++)
        {
            bool tap = u < plan.Length && plan[u];
            long vx0 = c.state.vx;
            c.step(tap);
            if (c.state.vx != vx0 && FastSim.BossRuns.boss_of(c) is Boss bb)
            {
                long side = c.state.vx > 0 ? 1 : 0, at2 = c.steps_to_wall(side), safe = 0;
                for (long sl = 0; sl < SimConfig.SLOT_COUNT; sl++)
                    if (bb._safe_span(SimConfig.slot_center_y(sl), at2)) safe |= 1L << (int)sl;
                Console.WriteLine($"    bounce at {u}: wall {side} drawn {Convert.ToString(c.wall_mask(side), 2).PadLeft(13, (char)48)} safe {Convert.ToString(safe, 2).PadLeft(13, (char)48)} at {at2}");
            }
            var b = FastSim.BossRuns.boss_of(c);
            string info = b switch
            {
                BossWatcher w => $"beam {w.beam} lit {Convert.ToString(w.lit, 2)} dart {w.dart} lane {w.dart_lane / SimConfig.SUB} dx {w.dart_x / SimConfig.SUB} clock {w.clock()}",
                BossCrusher k => $"press {k.press_y / SimConfig.SUB} plate {k.plate_y / SimConfig.SUB} lane {k.lane_from / SimConfig.SUB}->{k.lane_to / SimConfig.SUB} clock {k.clock()}",
                BossSaw s => $"king {s.king_y / SimConfig.SUB} {s.from_y / SimConfig.SUB}->{s.to_y / SimConfig.SUB} ring {s.ring / SimConfig.SUB} clock {s.clock()}",
                _ => "",
            };
            if (u % 5 == 0 || c.is_over())
                Console.WriteLine($"{u,3} {(tap ? "T" : ".")} y {c.state.y / SimConfig.SUB} x {c.state.x / SimConfig.SUB} vy {c.state.vy} L {Convert.ToString(c.wall_mask(0), 2).PadLeft(13, (char)48)} R {Convert.ToString(c.wall_mask(1), 2).PadLeft(13, (char)48)} {info}{(c.is_over() ? " DEAD " + DeathCause.NAMES[c.state.death_cause] : "")}");
        }
        return 0;
    }
}
