using System.Text.Json.Nodes;

namespace FastSim.Diff;

/// One thing to score: a room, or one variant of it.
public sealed record Target(int index, RoomDef def, string variant, string label, long cap)
{
    public bool boss => def.boss;
}

/// The rooms and variants the difficulty tool scores, and the room entries
/// every measure starts from (the same entries for every measure and bot, so
/// they can be compared trial by trial).
public static class Cases
{
    /// Ticks a trial may last: well past the room's own exit (Passable.CASES
    /// ticks plus the arrival hold and some spare), so a slow line still counts.
    public const long SPARE = 450;
    public const long DEFAULT_TICKS = 1150;

    public static List<Target> all(string filter = "*")
    {
        var caps = Checks.Passable.CASES.ToDictionary(c => c.id, c => c.ticks);
        var out_ = new List<Target>();
        var defs = RoomCatalog.all();
        var wanted = filter == "*" || filter == "" || filter == "all" ? null : filter.Split(',').ToHashSet();
        for (int i = 0; i < defs.Count; i++)
        {
            var def = defs[i];
            long cap = caps.GetValueOrDefault(def.id, DEFAULT_TICKS) + SPARE;
            if (def.variants.Count == 0)
            {
                if (keep(wanted, def.id, "")) out_.Add(new(i, def, "", def.id, cap));
                continue;
            }
            foreach (var v in def.variants)
                if (keep(wanted, def.id, v.id)) out_.Add(new(i, def, v.id, def.id + "/" + v.id, cap));
        }
        return out_;
    }

    static bool keep(HashSet<string> wanted, string id, string v) =>
        wanted == null || wanted.Contains(id) || wanted.Contains(id + "/" + v);

    /// Entry `i` into the target: a portal arrival as in a real run (Reaction.arrival:
    /// heights spread over the screen, both sides, a few scores and layout seeds),
    /// at a height the game would bring this variant in at. Bosses: through the
    /// boss portal at 100 (as the boss review, BossRuns.arrive).
    public static GameSim arrive(Target t, long i)
    {
        if (t.boss) return arrive_boss(t, i);
        var def = t.def;
        var sim = new GameSim(9000 + i * 37, def.season);
        sim.forced_variant = t.variant;
        sim.step(true);
        long score = G.maxi(def.from_score, 10) + (i % 3) * 10;
        if (score % SimConfig.BOSS_EVERY == 0) score += 10;
        sim.state.score = score;
        long y = 130 + (i * 53) % 380;
        var forced = def.variants.FirstOrDefault(v => v.id == t.variant);
        for (int n = 0; n < 380; n++)
        {
            if (def.fits_arrival(y * SimConfig.SUB) && (forced == null || forced.fits_arrival(y * SimConfig.SUB))) break;
            y = 130 + (y - 130 + 53) % 380;
        }
        sim.state.anchor_y = y * SimConfig.SUB;
        sim.state.y = GameSim._arrival_y(sim.state.anchor_y + Reaction.OFFSETS[(int)(i / 2 % Reaction.OFFSETS.Length)] * SimConfig.SUB);
        long side = i % 2;
        long skip = sim._arrival_retries(side, t.index);
        for (long k = 0; k < skip; k++) sim._rng.next_u32();
        sim._arrive_in(side, t.index);
        if (sim.room.def.id != def.id || sim.room.variant_id() != t.variant)
            throw new Exception($"wanted {t.label}, got {sim.room.def.id}/{sim.room.variant_id()}");
        return sim;
    }

    static GameSim arrive_boss(Target t, long i)
    {
        // Some seeds still bring another boss in (the spine's own draws): try the next
        // seed in a fixed order until it is this one.
        for (long k = 0; k < 64; k++)
        {
            long seed = 1 + i + k * 100003;
            var sim = new GameSim(seed);
            sim.step(true);
            sim.state.score = SimConfig.BOSS_EVERY;
            sim.state.bosses_met = 7 & ~RoomCatalog.boss_bit(t.index);
            var r = new SimRng(seed * 31 + 7);
            sim._go_through(1, ExitKind.NORMAL, (200 + r.next_below(261)) * SimConfig.SUB);
            if (sim.room.def.id == t.def.id) return sim;
        }
        throw new Exception($"no seed brings {t.label} in");
    }

    /// The room is beaten: the bird went through the exit, or (boss rooms) the boss is down.
    public static bool cleared(GameSim s, long room)
    {
        if (s.state.room_index > room) return true;
        if (!s.room.def.boss) return false;
        foreach (var h in s.room.hazards)
            if (h is Boss b && b.down_at >= 0) return true;
        return false;
    }
}

/// `fastsim check difficulty`: the tube finds a way through a plain room, and a
/// room with shutter gates leaves a narrower band than Open Sky on the same entries.
sealed class DifficultyCheck : Checks.Check
{
    public override string name => "difficulty";
    public override string test => "tools/fastsim/Difficulty:tube";
    static readonly (string room, long entry)[] CASES = { ("open", 0), ("open", 1), ("gates/classic", 0), ("gates/classic", 1) };
    public override int count() => CASES.Length;
    protected override List<object> make() => CASES.Select(c => (object)c).ToList();

    public override JsonObject run(int n)
    {
        var (room, entry) = CASES[n];
        var t = Cases.all(room)[0];
        var r = new Tube().run(Cases.arrive(t, entry), t.cap);
        var fails = new List<string>();
        if (!r.way) fails.Add($"{room} entry {entry}: the tube found no way through");
        return new JsonObject
        {
            ["fails"] = new JsonArray(fails.Select(f => (JsonNode)f).ToArray()),
            ["room"] = room, ["band"] = r.band_p10,
        };
    }

    public override List<string> combine(List<JsonNode> results)
    {
        double band(string room) => results.Where(r => (string)r["room"] == room).Average(r => (double)r["band"]);
        var f = new List<string>();
        if (band("gates/classic") >= band("open"))
            f.Add($"gates/classic band p10 {band("gates/classic"):F0} px is not below open's {band("open"):F0} px");
        return f;
    }

    public override string summary(List<JsonNode> results) => $"{results.Count} tubes (open, gates/classic)";
}
