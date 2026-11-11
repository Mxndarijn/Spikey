using System.Text.Json;
using System.Text.Json.Nodes;

namespace FastSim;

/// Writes a run file, the same JSON as meta/run_file.gd (RunFile): what a bot
/// writes when it wants a run rendered or checked by tools/render_run.ps1
/// (docs/RENDERING.md). Record every tick the bot tapped on (and the tick of
/// every revive) while it plays, then call write() with the sim as it ended.
///
///     var taps = new List<long>();
///     while (!sim.is_over() && sim.state.tick < SimConfig.MAX_TICKS)
///     {
///         bool tap = bot(sim);
///         if (tap) taps.Add(sim.state.tick);
///         sim.step(tap);
///     }
///     RunFile.write("run.json", sim, taps, loadout: new() { ["flyer"] = "..." }, name: "tier 3");
public static class RunFile
{
    public const string FORMAT = "flapjaw_run";
    public const long FORMAT_VERSION = 1;

    /// The run file of `sim` (as it ended) played with `taps` (and `revives`).
    /// `loadout`: ItemKind -> id (flyer, world, trail, portal, music, crash,
    /// plate); a kind left out uses the game's default. `settings`:
    /// color_blind_spikes, reduced_flashing, large_buttons.
    public static JsonObject make(GameSim sim, IList<long> taps, IList<long> revives = null,
        Dictionary<string, string> loadout = null, string name = "", Dictionary<string, bool> settings = null)
    {
        var look = new JsonObject();
        foreach (var kv in loadout ?? new()) look[kv.Key] = kv.Value;
        var flags = new JsonObject();
        foreach (var kv in settings ?? new()) flags[kv.Key] = kv.Value;
        return new JsonObject
        {
            ["format"] = FORMAT,
            ["format_version"] = FORMAT_VERSION,
            ["gameplay_version"] = SimConfig.GAMEPLAY_VERSION,
            ["seed"] = sim.seed_value,
            ["season"] = sim.season,
            ["taps"] = new JsonArray(taps.Select(t => (JsonNode)t).ToArray()),
            ["revives"] = new JsonArray((revives ?? new List<long>()).Select(t => (JsonNode)t).ToArray()),
            ["score"] = sim.state.score,
            ["coins"] = sim.state.coins,
            ["end_tick"] = sim.state.tick,
            ["checksum"] = sim.checksum(),
            ["name"] = name,
            ["loadout"] = look,
            ["settings"] = flags,
        };
    }

    public static void write(string path, GameSim sim, IList<long> taps, IList<long> revives = null,
        Dictionary<string, string> loadout = null, string name = "", Dictionary<string, bool> settings = null)
    {
        var json = make(sim, taps, revives, loadout, name, settings);
        File.WriteAllText(path, json.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + "\n");
    }

    /// `fastsim runfile <seed> [bot_seed]`: a gap_seeker run (SimBots.play) to
    /// --out, as an example run file and for tests of the renderer.
    public static int run_mode(long seed_value, long bot_seed, string out_path)
    {
        var sim = new GameSim(seed_value);
        var rng = new SimRng(bot_seed);
        var taps = new List<long>();
        while (!sim.is_over() && sim.state.tick < SimConfig.MAX_TICKS)
        {
            bool tap = SimBots.gap_seeker(sim, rng);
            if (tap) taps.Add(sim.state.tick);
            sim.step(tap);
        }
        write(out_path, sim, taps, name: "gap seeker");
        Console.WriteLine($"fastsim runfile: seed {seed_value}, score {sim.state.score}, {sim.state.tick} ticks -> {out_path}");
        return 0;
    }
}
