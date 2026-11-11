using System.Text.Json.Nodes;
using FastSim;
using FastSim.Rl;

static partial class Checks
{
    /// The RL bot (docs/RL_BOT.md) reads the sim without changing it: in
    /// every room variant the observer's danger grid (it moves the bird to
    /// probe each hazard's kills()) leaves the checksum as it was. And the
    /// committed policy still loads and plays.
    public sealed class RlBot : Check
    {
        public override string name => "rlbot";
        public override string test => "tools/fastsim/RL/RlCheck.cs";
        public const long TICKS = 600;
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

        public override JsonObject run(int n)
        {
            var (room, variant) = ((long, string))cases[n];
            var fails = new List<string>();
            if (room < 0) return policy_plays(fails);
            var f = new float[Observer.FRAME];
            var bot = new SimRng(77 + n);
            long seed = 1, ticks = 0;
            var sim = new GameSim(seed, Seasons.NONE, room, variant);
            while (ticks < TICKS && fails.Count == 0)
            {
                if (sim.is_over()) sim = new GameSim(++seed, Seasons.NONE, room, variant);
                long before = sim.checksum();
                Observer.frame(sim, f);
                if (sim.checksum() != before)
                    fails.Add($"{RoomCatalog.all()[(int)room].id}/{variant} seed {seed} tick {sim.state.tick}: observing changed the sim");
                sim.step(!sim.state.started || SimBots.random_tapper(sim, bot, 10));
                ticks++;
            }
            return result(fails);
        }

        static JsonObject policy_plays(List<string> fails)
        {
            string path = Path.Combine(RlMain.default_dir(), "policy.json");
            if (!File.Exists(path)) return result(fails, new JsonObject { ["points"] = -1 });
            Policy pol;
            try { pol = Policy.load(path); }
            catch (InvalidDataException e)
            {
                fails.Add(e.Message);
                return result(fails);
            }
            long points = 0;
            for (long s = 1; s <= 3; s++) points += Player.play(pol, Handicap.NONE, new GameSim(s), 3600).points;
            if (points < 10) fails.Add($"the trained policy scores {points} over 3 runs: tools/rlbot/policy.json no longer fits the sim");
            return result(fails, new JsonObject { ["points"] = points });
        }

        public override string summary(List<JsonNode> results)
        {
            var p = results.FirstOrDefault(r => (int)r["n"] == 0)?["points"];
            string pol = p == null || (long)p < 0 ? "no policy" : $"policy {(long)p} points in 3 runs";
            return $"{results.Count - 1} room variants observed without changing the sim, {pol}";
        }
    }
}
