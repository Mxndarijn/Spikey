using System.Text.Json.Nodes;
using FastSim;

static partial class Checks
{
    /// The seed scan (Honesty.seedscan): a blind copy carries no true random
    /// state. Every SimRng, every *seed* / *salt* field and every raw draw
    /// found in the sim's state by reflection, in every room and variant, must
    /// be replaced or dropped by BlindPlanner.blind_copy. A new hazard that
    /// keeps its own seed fails this until blind_copy replaces it (or, when the
    /// value is on screen, until it is listed in Honesty.SEEDS_SHOWN with the reason).
    /// The scan itself is tested too: with the boss seed left in, it must say so.
    public sealed class BlindSeeds : Check
    {
        public override string name => "blind_seeds";
        public override string test => "tools/fastsim/HonestyCheck.cs";
        public override int count() => 1;
        protected override List<object> make() => new() { 0 };

        public override JsonObject run(int n)
        {
            var fails = new List<string>();
            var lines = new List<string>();
            bool boss = BlindPlanner.hide_boss;
            try
            {
                BlindPlanner.hide_boss = true;
                if (Honesty.seedscan(1, 600, lines) > 0) fails.AddRange(lines.Where(l => l.Contains("UNCHANGED")).Select(l => l.Trim()));
                var open = new List<string>();
                BlindPlanner.hide_boss = false;
                Honesty.seedscan(1, 600, open);
                if (!open.Any(l => l.Contains("UNCHANGED") && l.Contains("Boss")))
                    fails.Add("the seed scan does not notice a boss seed left in the blind copy");
            }
            finally
            {
                BlindPlanner.hide_boss = boss;
            }
            return result(fails, new JsonObject { ["scan"] = lines.FirstOrDefault() ?? "" });
        }

        public override string summary(List<JsonNode> results) => $"blind copies carry no true seed ({results.FirstOrDefault()?["scan"]})";
    }
}
