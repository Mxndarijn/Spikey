using System.Text.Json.Nodes;
using FastSim;

/// Portal arrivals played by a slow player: for `delay` ticks it only holds
/// its height (it hasn't read the room yet), then PlannerBot plays on.
///   reaction: tests/support/arrival_bench.gd, the same arrivals per room.
///   odds: real PlannerBot runs; every portal arrival on the way is replayed
///   at each delay (the survival charts).
static class Reaction
{
    public const long AFTER = 120;
    public const long ODDS_RUN_TICKS = 7000;
    /// The benchmark, as ArrivalBench: at EARLY_DELAY (0.75 s) no arrival may
    /// leave no way to live; at SimConfig.ARRIVAL_BLIND (1 s) at most
    /// MAX_EXTRA_PCT of all arrivals may die that an instant reaction survives,
    /// and in no room may more than MAX_EXTRA_PCT leave no way to live.
    public const long EARLY_DELAY = 45;
    public const long MAX_EXTRA_PCT = 2;

    public static List<long> delays(string arg)
    {
        if (arg == "") return new List<long> { 0, EARLY_DELAY, SimConfig.ARRIVAL_BLIND };
        return arg.Split(',').Select(long.Parse).ToList();
    }

    /// Arrival `i` into room `index`, just out of the portal (ArrivalBench.arrival).
    static GameSim arrival(int index, long i)
    {
        var def = RoomCatalog.all()[index];
        var sim = new GameSim(9000 + i * 37);
        sim.step(true);
        sim.state.score = G.maxi(def.from_score, 10) + (i % 3) * 10;
        long y = 130 + (i * 53) % 380;
        while (!def.fits_arrival(y * SimConfig.SUB)) y = 130 + (y - 130 + 53) % 380;
        sim.state.y = y * SimConfig.SUB;
        long side = i % 2;
        long skip = sim._arrival_retries(side, index);
        for (long k = 0; k < skip; k++) sim._rng.next_u32();
        sim._arrive_in(side, index);
        return sim;
    }

    static (long tick, string cause) play(GameSim sim, long delay, PlannerBot bot, long cap)
    {
        long y0 = sim.state.y;
        long n = 0;
        while (n < cap && !sim.is_over())
        {
            bool tap;
            if (n < delay)
            {
                long g = sim.room.def.gravity_sign;
                tap = (sim.state.y - y0) * g > 0 && sim.state.vy * g >= 0;
            }
            else tap = bot.decide(sim);
            sim.step(tap);
            n += 1;
        }
        if (!sim.is_over()) return (-1, "");
        return (n, DeathCause.NAMES[sim.state.death_cause] + (n <= delay ? "@blind" : "@play"));
    }

    /// Whether a death after holding `delay` ticks was forced: SurvivalSearch
    /// finds no way to live to `cap` from the moment the player reacts (or the
    /// bird already died while holding).
    public static bool forced(GameSim at_arrival, long delay, long cap)
    {
        var c = at_arrival.clone_deep();
        long y0 = c.state.y;
        for (long n = 0; n < delay; n++)
        {
            long g = c.room.def.gravity_sign;
            c.step((c.state.y - y0) * g > 0 && c.state.vy * g >= 0);
            if (c.is_over()) return true;
        }
        return !new SurvivalSearch().run(c, cap - delay);
    }

    /// Every entry height (both sides, a few scores and layout seeds): the
    /// heights where an arrival leaves no way to live after holding `delay`.
    public static int scan(string id, long delay, long seeds)
    {
        int index = (int)RoomCatalog.index_of(id);
        var def = RoomCatalog.all()[index];
        int bad = 0, total = 0;
        var lines = new List<string>();
        for (long y = SimConfig.KILL_TOP / SimConfig.SUB + SimConfig.ARRIVAL_EDGE / SimConfig.SUB;
             y <= (SimConfig.KILL_BOTTOM - SimConfig.ARRIVAL_EDGE) / SimConfig.SUB; y += 4)
        {
            if (!def.fits_arrival(y * SimConfig.SUB)) continue;
            var hits = new List<string>();
            for (long side = 0; side < 2; side++)
                for (long k = 0; k < seeds; k++)
                {
                    var sim = new GameSim(9100 + k * 37 + y);
                    sim.step(true);
                    sim.state.score = G.maxi(def.from_score, 10) + (k % 3) * 10;
                    sim.state.y = y * SimConfig.SUB;
                    long skip = sim._arrival_retries(side, index);
                    for (long j = 0; j < skip; j++) sim._rng.next_u32();
                    sim._arrive_in(side, index);
                    total++;
                    if (forced(sim, delay, delay + AFTER))
                    {
                        bad++;
                        hits.Add($"s{side}k{k}");
                    }
                }
            if (hits.Count > 0) lines.Add($"  y {y}: {string.Join(" ", hits)}");
        }
        foreach (var l in lines) Console.WriteLine(l);
        Console.WriteLine($"{id}: {bad} of {total} arrivals with no way to live after {delay} ticks");
        return bad > 0 ? 1 : 0;
    }

    public static JsonObject rooms(int count, string filter, string delay_arg, long first)
    {
        var ds = delays(delay_arg);
        var all = RoomCatalog.all();
        var rooms = new JsonArray();
        for (int index = 0; index < all.Count; index++)
        {
            var def = all[index];
            if (!(filter == "*" || filter == "" || def.id == filter)) continue;
            var runs = new JsonArray();
            for (long s = 0; s < count; s++)
            {
                long i = first + s;
                var ticks = new JsonArray();
                var causes = new JsonArray();
                var no_way = new JsonArray();
                var at = arrival(index, i);
                foreach (long d in ds)
                {
                    var (tick, cause) = play(at.clone_deep(), d, new PlannerBot(i + 1), d + AFTER);
                    ticks.Add(tick);
                    causes.Add(cause);
                    no_way.Add(tick >= 0 && forced(at, d, d + AFTER));
                }
                runs.Add(new JsonObject { ["seed"] = i, ["died"] = ticks, ["cause"] = causes, ["forced"] = no_way });
            }
            rooms.Add(new JsonObject { ["id"] = def.id, ["runs"] = runs });
        }
        var dj = new JsonArray();
        foreach (long d in ds) dj.Add(d);
        return new JsonObject { ["mode"] = "reaction", ["delays"] = dj, ["rooms"] = rooms };
    }

    public static JsonObject odds(int seeds, string delay_arg, long first)
    {
        var ds = delay_arg == "" ? new List<long> { 0, 15, 30, 45, 60, 75, 90 } : delays(delay_arg);
        var runs = new JsonArray();
        for (long s = 0; s < seeds; s++)
        {
            long seed_value = 7000 + (first + s) * 131;
            var sim = new GameSim(seed_value);
            var bot = new PlannerBot(seed_value);
            long rooms = 0;
            var arrivals = new JsonArray();
            while (!sim.is_over() && sim.state.tick < ODDS_RUN_TICKS)
            {
                sim.step(bot.decide(sim));
                if (!sim.events.Contains(Event.ROOM_CHANGE)) continue;
                rooms += 1;
                var row = new JsonObject
                {
                    ["room"] = RoomCatalog.all()[(int)sim.state.room_kind].id,
                    ["y"] = sim.state.y / SimConfig.SUB, ["score"] = sim.state.score,
                };
                foreach (long d in ds)
                {
                    long cap = d + AFTER + sim.state.arrival_hold;
                    var (tick, cause) = play(sim.clone_deep(), d, new PlannerBot(seed_value + sim.state.tick), cap);
                    row[d.ToString()] = tick < 0;
                    if (tick >= 0)
                    {
                        row["why" + d] = cause + "@" + tick;
                        row["forced" + d] = forced(sim, d, cap);
                    }
                }
                arrivals.Add(row);
            }
            runs.Add(new JsonObject
            {
                ["seed"] = seed_value, ["ticks"] = sim.state.tick, ["score"] = sim.state.score,
                ["rooms"] = rooms, ["alive"] = !sim.is_over(),
                ["room"] = RoomCatalog.all()[(int)sim.state.room_kind].id, ["arrivals"] = arrivals,
            });
        }
        var dj = new JsonArray();
        foreach (long d in ds) dj.Add(d);
        return new JsonObject { ["mode"] = "odds", ["delays"] = dj, ["runs"] = runs };
    }

    /// reaction: per room, deaths at each delay and the benchmark (last delay
    /// against the first); returns 1 when a room is over it. odds: deaths per
    /// delay over every arrival.
    public static int print(JsonObject report)
    {
        var ds = report["delays"].AsArray().Select(x => (long)x).ToList();
        if ((string)report["mode"] == "odds")
        {
            var runs = report["runs"].AsArray();
            int total = 0;
            var dead = new int[ds.Count];
            foreach (var r in runs)
                foreach (var a in r["arrivals"].AsArray())
                {
                    total++;
                    for (int k = 0; k < ds.Count; k++)
                        if (!(bool)a[ds[k].ToString()]) dead[k]++;
                }
            int alive = runs.Count(r => (bool)r["alive"]);
            Console.WriteLine($"{runs.Count} runs, {alive} alive at {ODDS_RUN_TICKS} ticks, {total} portal arrivals");
            var forced_n = new int[ds.Count];
            foreach (var r in runs)
                foreach (var a in r["arrivals"].AsArray())
                    for (int k = 0; k < ds.Count; k++)
                        if (a["forced" + ds[k]] is JsonNode f && (bool)f) forced_n[k]++;
            for (int k = 0; k < ds.Count; k++)
                Console.WriteLine($"  reaction {ds[k],3} ticks: {dead[k],4} died ({100.0 * dead[k] / Math.Max(1, total):F1}%), {forced_n[k],4} with no way to live ({100.0 * forced_n[k] / Math.Max(1, total):F2}%)");
            return 0;
        }
        int over = 0;
        long sum_extra = 0, sum_n = 0, sum_forced_early = 0;
        foreach (var room in report["rooms"].AsArray())
        {
            var runs = room["runs"].AsArray();
            var dead = new int[ds.Count];
            var no_way = new int[ds.Count];
            var causes = new Dictionary<string, int>();
            foreach (var r in runs)
            {
                var died = r["died"].AsArray();
                for (int k = 0; k < ds.Count; k++)
                {
                    if ((long)died[k] >= 0) dead[k]++;
                    if ((bool)r["forced"].AsArray()[k]) no_way[k]++;
                }
                string c = (string)r["cause"].AsArray()[ds.Count - 1];
                if (c != "") causes[c] = causes.GetValueOrDefault(c) + 1;
            }
            long extra = dead[ds.Count - 1] - dead[0];
            int early = ds.IndexOf(EARLY_DELAY);
            bool ok = no_way[ds.Count - 1] * 100 <= MAX_EXTRA_PCT * runs.Count && (early < 0 || no_way[early] == 0);
            sum_forced_early += early < 0 ? 0 : no_way[early];
            if (!ok) over++;
            sum_extra += Math.Max(0, extra);
            sum_n += runs.Count;
            string per = string.Join(" ", ds.Select((d, k) => $"{d}:{dead[k]}" + (no_way[k] > 0 ? $"({no_way[k]} no way)" : "")));
            string why = string.Join(", ", causes.Select(kv => $"{kv.Key} {kv.Value}"));
            Console.WriteLine($"{(string)room["id"],-11} extra {extra,3} of {runs.Count}  ({per})  {(ok ? "ok" : "FAIL")}  {why}");
        }
        Console.WriteLine($"all rooms: extra deaths at {ds[^1]} ticks {sum_extra} of {sum_n} ({100.0 * sum_extra / Math.Max(1, sum_n):F2}%, limit {MAX_EXTRA_PCT}%); no way to live at {EARLY_DELAY} ticks: {sum_forced_early} (limit 0); {over} rooms fail");
        bool total_ok = sum_extra * 100 <= MAX_EXTRA_PCT * sum_n;
        return over > 0 || !total_ok ? 1 : 0;
    }
}
