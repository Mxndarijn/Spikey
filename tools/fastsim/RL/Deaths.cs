using System.Diagnostics;
using System.Text.Json.Nodes;

namespace FastSim.Rl;

/// `rl deaths`: were the bot's deaths avoidable? Plays the policy on full
/// runs; for each death, the full SurvivalSearch (every level) starts from
/// the state where the bird entered that room (at most LOOK_BACK ticks before
/// the death) and must live AFTER ticks past the tick it died. If it can't,
/// no player in that room could have saved that run from there: an
/// impossible situation. Prints a table per room variant.
public static class Deaths
{
    public const long LOOK_BACK = 1200;
    public const long AFTER = 240;

    public static int run(string dir, int seeds, long first, long cap, int threads, string out_path)
    {
        var pol = Policy.load(Path.Combine(dir, "policy.json"));
        var clock = Stopwatch.StartNew();
        var rows = new (long seed, string room, bool dead, bool saved, long tick, long entry, string cause, long level)[seeds];
        Parallel.For(0, seeds, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            long seed = first + 1 + i;
            var sim = new GameSim(seed);
            var eyes = new Player(pol, Handicap.NONE, seed);
            var taps = new List<bool>();
            long entry = 0;
            while (!sim.is_over() && taps.Count < cap)
            {
                bool tap = eyes.decide(sim);
                taps.Add(tap);
                sim.step(tap);
                if (sim.events.Contains(Event.ROOM_CHANGE) || sim.events.Contains(Event.REVIVE)) entry = taps.Count;
            }
            string room = sim.room.def.id + (sim.room.variant_id() != "" ? "/" + sim.room.variant_id() : "");
            if (!sim.is_over())
            {
                rows[i] = (seed, room, false, true, taps.Count, entry, "", 0);
                return;
            }
            long T = taps.Count;
            long from = Math.Max(entry, T - LOOK_BACK);
            var start = new GameSim(seed);
            for (long t = 0; t < from; t++) start.step(taps[(int)t]);
            var search = new SurvivalSearch();
            bool saved = search.run(start, T - from + AFTER);
            rows[i] = (seed, room, true, saved, T, from, DeathCause.NAMES[sim.state.death_cause], search.level);
        });
        var deaths = rows.Where(r => r.dead).ToList();
        int lost = deaths.Count(r => !r.saved);
        Console.WriteLine($"rl deaths: {seeds} full runs (seeds {first + 1}..{first + seeds}), {deaths.Count} deaths, {lost} with no way to live from room entry (full SurvivalSearch, {AFTER} ticks past the death)");
        Console.WriteLine($"  {"room/variant",-26} {"deaths",6} {"no way",7}  example seeds (no way)");
        foreach (var g in deaths.GroupBy(r => r.room).OrderByDescending(g => g.Count(r => !r.saved)).ThenByDescending(g => g.Count()))
        {
            var bad = g.Where(r => !r.saved).Select(r => r.seed).Take(6);
            Console.WriteLine($"  {g.Key,-26} {g.Count(),6} {g.Count(r => !r.saved),7}  {string.Join(" ", bad)}");
        }
        Console.WriteLine($"rl deaths: {clock.Elapsed.TotalSeconds:F0} s");
        if (out_path != "")
        {
            var arr = new JsonArray(rows.Select(r => (JsonNode)new JsonObject
            {
                ["seed"] = r.seed, ["room"] = r.room, ["dead"] = r.dead, ["avoidable"] = r.saved, ["tick"] = r.tick,
                ["search_from"] = r.entry, ["cause"] = r.cause, ["search_level"] = r.level,
            }).ToArray());
            File.WriteAllText(out_path, new JsonObject { ["runs"] = arr }.ToJsonString(Policy.PRETTY));
        }
        return 0;
    }
}
