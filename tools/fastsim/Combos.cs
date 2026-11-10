using FastSim;

/// The Double Trouble fairness gate (`fastsim combos`). Every pair (each of
/// the room's variants) is built as its own room, and each of its hazards alone, all
/// at Double Trouble's settings. A pair fails when:
/// - PlannerBot crashes in it more than MAX_FACTOR times its two hazards added
///   up (plus SLACK, for pairs whose parts are nearly free): the two make each
///   other worse instead of just adding up;
/// - a 1 s reaction costs more than Reaction.MAX_EXTRA_PCT of portal arrivals,
///   or any arrival at 0.75 s leaves no way to live (the portal benchmark);
/// - without falling drops in it, more than MAX_NO_LANE_PCT of ticks leave no
///   full-width lane (LANE px of bird heights) that no hazard touches for the
///   next second. A falling drop crosses every row for a moment, so pairs with
///   rain are left to the other checks.
static class Combos
{
    public const double MAX_FACTOR = 1.5;
    public const double SLACK = 0.5;
    public const double MAX_NO_LANE_PCT = 1.0;
    const long ROOM_TICKS = 3600;
    const long ROOM_POINTS = 25;
    const long LANE_TICKS = 1200;
    const int LANE_SEEDS = 32;

    // The lane grid: bird-centre positions every STEP px.
    const int X0 = 40, X1 = 320, Y0 = 60, Y1 = 580, STEP = 10;
    static readonly int NX = (X1 - X0) / STEP + 1, NY = (Y1 - Y0) / STEP + 1;
    const int WIN = 60, LANE = 60;

    public static int run(int seeds, int arrivals, int jobs)
    {
        var all = RoomCatalog.all();
        var dbl = all.Find(d => d.id == "double");
        var par = new ParallelOptions { MaxDegreeOfParallelism = jobs };
        int bad = 0;
        for (int p = 0; p < dbl.variants.Count; p++)
        {
            var v = dbl.variants[p];
            int both = add(all, dbl, $"double#{p}", v, v.hazards);
            var alone = v.hazards.Select((f, k) => add(all, dbl, $"double#{p}.{k}", v, new List<Func<Hazard>> { f })).ToList();
            var probe = new GameSim(1000, dbl.season, both);
            string name = v.id;
            bool rain = probe.room.hazards.Any(h => h is Drop);

            double rate = bot_rate(both, seeds, par);
            double parts = alone.Sum(i => bot_rate(i, seeds, par));
            double limit = MAX_FACTOR * parts + SLACK;
            var (extra_pct, no_way) = reaction(both, arrivals, par);
            double no_lane = rain ? -1 : no_lane_pct(both, par);

            var why = new List<string>();
            if (rate > limit) why.Add($"bot {rate:F1} > {limit:F1}");
            if (extra_pct > Reaction.MAX_EXTRA_PCT) why.Add($"1 s reaction {extra_pct:F1}% > {Reaction.MAX_EXTRA_PCT}%");
            if (no_way > 0) why.Add($"{no_way} arrivals with no way to live at 0.75 s");
            if (no_lane > MAX_NO_LANE_PCT) why.Add($"no free lane {no_lane:F1}% > {MAX_NO_LANE_PCT}%");
            string lane = rain ? "  lane n/a (rain)" : $"  no lane {no_lane,4:F1}%";
            Console.WriteLine($"{name,-16} bot {rate,4:F1} / 100 pts (parts {parts:F1}, limit {limit:F1})  1 s reaction {extra_pct,4:F1}%  no way {no_way}{lane}  {(why.Count == 0 ? "ok" : "FAIL: " + string.Join("; ", why))}");
            if (why.Count > 0) bad++;
        }
        Console.WriteLine(bad == 0 ? "combos: every pair is fair" : $"combos: {bad} unfair pair(s)");
        return bad == 0 ? 0 : 1;
    }

    /// A copy of Double Trouble playing only these hazards (with pair `v`'s
    /// arrival skips), added to the catalog (weight 0: never picked in a run).
    /// Returns its index.
    static int add(List<RoomDef> all, RoomDef dbl, string id, RoomVariant v, List<Func<Hazard>> hazards)
    {
        var d = new RoomDef(id, dbl.group, dbl.from_score);
        d.weight = 0;
        d.season = dbl.season;
        d.max_spikes = dbl.max_spikes;
        d.reach = dbl.reach;
        d.arrival_skip = new List<long>(dbl.arrival_skip);
        d.variants = new List<RoomVariant> { new RoomVariant(v.id).with(hazards).skipping(new List<long>(v.arrival_skip)) };
        all.Add(d);
        return all.Count - 1;
    }

    /// PlannerBot crashes per 100 points, as `fastsim rooms`.
    static double bot_rate(int index, int seeds, ParallelOptions par)
    {
        var def = RoomCatalog.all()[index];
        long dead = 0, points = 0;
        Parallel.For(0, seeds, par, s =>
        {
            long seed_value = 1000 + s * 77;
            var sim = new GameSim(seed_value, def.season, index);
            var bot = new PlannerBot(seed_value);
            long start = sim.state.score;
            while (!sim.is_over() && sim.state.tick < ROOM_TICKS && sim.state.score - start < ROOM_POINTS)
                sim.step(bot.decide(sim));
            Interlocked.Add(ref points, sim.state.score - start);
            if (sim.is_over()) Interlocked.Increment(ref dead);
        });
        return 100.0 * dead / Math.Max(1, points);
    }

    /// The portal benchmark for one room: extra crashes at 1 s over an instant
    /// reaction (percent of arrivals), and arrivals with no way to live at 0.75 s.
    static (double, long) reaction(int index, int arrivals, ParallelOptions par)
    {
        long extra = 0, no_way = 0;
        Parallel.For(0, arrivals, par, s =>
        {
            var at = Reaction.arrival(index, s);
            var (fast, _) = Reaction.play(at.clone_deep(), 0, new PlannerBot(s + 1), Reaction.AFTER);
            var (early, _) = Reaction.play(at.clone_deep(), Reaction.EARLY_DELAY, new PlannerBot(s + 1), Reaction.EARLY_DELAY + Reaction.AFTER);
            var (slow, _) = Reaction.play(at.clone_deep(), SimConfig.ARRIVAL_BLIND, new PlannerBot(s + 1), SimConfig.ARRIVAL_BLIND + Reaction.AFTER);
            if (slow >= 0 && fast < 0) Interlocked.Increment(ref extra);
            if (early >= 0 && Reaction.forced(at, Reaction.EARLY_DELAY, Reaction.EARLY_DELAY + Reaction.AFTER)) Interlocked.Increment(ref no_way);
        });
        return (100.0 * extra / Math.Max(1, arrivals), no_way);
    }

    /// Percent of ticks along PlannerBot runs with no full-width lane LANE px
    /// tall that no hazard touches for the next WIN ticks (wall spikes aside).
    static double no_lane_pct(int index, ParallelOptions par)
    {
        var def = RoomCatalog.all()[index];
        long ticks = 0, none = 0;
        Parallel.For(0, LANE_SEEDS, par, s =>
        {
            long seed_value = 1000 + s * 77;
            var sim = new GameSim(seed_value, def.season, index);
            var bot = new PlannerBot(seed_value);
            var frames = new List<bool[]>();
            while (!sim.is_over() && frames.Count < LANE_TICKS)
            {
                sim.step(bot.decide(sim));
                if (sim.events.Contains(Event.ROOM_CHANGE)) break;
                frames.Add(probe(sim));
            }
            long n = 0, z = 0;
            for (int t = 0; t + WIN <= frames.Count; t++)
            {
                int run_ = 0, best = 0;
                for (int r = 0; r < NY; r++)
                {
                    bool ok = true;
                    for (int c = 0; c < NX && ok; c++)
                        for (int k = 0; k < WIN && ok; k++)
                            if (frames[t + k][r * NX + c]) ok = false;
                    run_ = ok ? run_ + 1 : 0;
                    best = Math.Max(best, run_);
                }
                n++;
                if ((best - 1) * STEP < LANE) z++;
            }
            Interlocked.Add(ref ticks, n);
            Interlocked.Add(ref none, z);
        });
        return 100.0 * none / Math.Max(1, ticks);
    }

    /// Which grid spots a hazard would kill a bird at right now.
    static bool[] probe(GameSim sim)
    {
        var f = new bool[NX * NY];
        long sx = sim.state.x, sy = sim.state.y;
        for (int r = 0; r < NY; r++)
            for (int c = 0; c < NX; c++)
            {
                sim.state.x = (X0 + c * STEP) * SimConfig.SUB;
                sim.state.y = (Y0 + r * STEP) * SimConfig.SUB;
                foreach (var h in sim.room.hazards)
                    if (h.alive && h.kills(sim))
                    {
                        f[r * NX + c] = true;
                        break;
                    }
            }
        sim.state.x = sx;
        sim.state.y = sy;
        return f;
    }
}
