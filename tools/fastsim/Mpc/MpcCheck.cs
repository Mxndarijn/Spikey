using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using FastSim;
using FastSim.Mpc;

static partial class Checks
{
    /// The MPC bot (docs/MPC_BOT.md) never uses the future: its code never
    /// copies or steps the GameSim (only MpcRun.cs, which plays the bot's
    /// taps on the real run, may step), and in every room variant a decision
    /// leaves the sim's checksum as it was.
    public sealed class MpcBotCheck : Check
    {
        public override string name => "mpcbot";
        public override string test => "tools/fastsim/Mpc/MpcCheck.cs";
        public const long TICKS = 400;
        /// The one file allowed to step the sim, and this check itself.
        static readonly string[] RUNNERS = { "MpcRun.cs", "MpcCheck.cs" };
        public override int count() => cases.Count;

        protected override List<object> make()
        {
            var out_ = new List<object> { (-1L, "") };
            var all = RoomCatalog.all();
            for (int i = 0; i < all.Count; i++)
            {
                if (all[i].variants.Count == 0) out_.Add(((long)i, ""));
                foreach (var v in all[i].variants) out_.Add(((long)i, v.id));
            }
            return out_;
        }

        public static string source_dir() => Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../Mpc"));

        /// Calls that would let the bot see the future, found in the bot's source.
        public static List<string> future_calls(string dir)
        {
            var bad = new List<string>();
            var banned = new Regex(@"\bclone_deep\s*\(|\.step\s*\(|\.revive\s*\(|\b_rng\b|\bSimRng\b|\bSurvivalSearch\b|new\s+GameSim\b");
            foreach (string path in Directory.GetFiles(dir, "*.cs"))
            {
                if (RUNNERS.Contains(Path.GetFileName(path))) continue;
                string[] lines = File.ReadAllLines(path);
                for (int i = 0; i < lines.Length; i++)
                {
                    string code = lines[i];
                    int at = code.IndexOf("//");
                    if (at >= 0) code = code[..at];
                    if (banned.IsMatch(code)) bad.Add($"{Path.GetFileName(path)}:{i + 1}: {lines[i].Trim()}");
                }
            }
            return bad;
        }

        public override JsonObject run(int n)
        {
            var (room, variant) = ((long, string))cases[n];
            var fails = new List<string>();
            if (room < 0)
            {
                string dir = source_dir();
                if (!Directory.Exists(dir)) fails.Add("no MPC source at " + dir);
                else
                    foreach (string b in future_calls(dir)) fails.Add("the MPC bot may not copy or step the sim: " + b);
                return result(fails);
            }
            long seed = 1, ticks = 0;
            var sim = new GameSim(seed, Seasons.NONE, room, variant);
            var bot = new MpcBot(new MpcParams(), null, seed);
            while (ticks < TICKS && fails.Count == 0)
            {
                if (sim.is_over())
                {
                    sim = new GameSim(++seed, Seasons.NONE, room, variant);
                    bot = new MpcBot(new MpcParams(), null, seed);
                }
                long before = sim.checksum();
                bool tap = bot.decide(sim);
                if (sim.checksum() != before)
                    fails.Add($"{RoomCatalog.all()[(int)room].id}/{variant} seed {seed} tick {sim.state.tick}: deciding changed the sim");
                sim.step(tap);
                ticks++;
            }
            return result(fails);
        }

        public override string summary(List<JsonNode> results) =>
            $"no clone or step in the bot's source, {results.Count - 1} room variants decided on without changing the sim";
    }
}
