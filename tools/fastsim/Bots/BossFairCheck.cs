using System.Text.Json.Nodes;
using FastSim;

static partial class Checks
{
    /// `bossfair`: every boss tell is fair with a 1 s reaction
    /// (research/planner-review/07-bosses.md, `fastsim boss fair`). The honest
    /// planner plays each boss room; at every new tell the bird keeps its old
    /// plan for REACT ticks, then SurvivalSearch must still find a way through
    /// the told attack. A tell fails when there is no way (verdict 0) or the old
    /// plan is hit by the boss within the reaction (-1). Tiers 1 and 3.
    public sealed class BossFair : Check
    {
        public override string name => "bossfair";
        public override string test => "tools/fastsim/Bots/BossFairCheck.cs";
        public const long REACT = 60;
        public const int SEEDS = 20;
        public static readonly long[] TIERS = { 1, 3 };

        /// Unfair tells allowed while their fix is in flight: (boss, tier, seed, tell kind, phase) -> owner.
        /// One entry per case, so any other unfair tell still fails. Remove an entry when its fix lands.
        public static readonly Dictionary<(string boss, long tier, long seed, string kind, long phase), string> KNOWN = new()
        {
            [("boss_watcher", 3, 3, "dart", 3)] = "room-fixes (hit during the reaction)",
            [("boss_watcher", 3, 19, "rows", 3)] = "room-fixes (no way through)",
            [("boss_crusher", 3, 1, "jaw", 2)] = "room-fixes (no way through)",
            [("boss_crusher", 3, 2, "jaw", 3)] = "room-fixes (no way through)",
            [("boss_saw", 1, 10, "hop", 3)] = "room-fixes (no way through)",
            [("boss_saw", 3, 6, "hop", 3)] = "room-fixes (hit during the reaction)",
            // Met once the planner's copies stopped reading the room's wall count (its lines changed).
            [("boss_watcher", 3, 18, "dart", 2)] = "room-fixes (no way through)",
            [("boss_crusher", 3, 5, "jaw", 3)] = "room-fixes (no way through)",
            [("boss_crusher", 3, 19, "jaw", 2)] = "room-fixes (hit during the reaction)",
        };

        public override int count() => cases.Count;

        protected override List<object> make() =>
            (from b in BossRuns.BOSSES from t in TIERS from s in Enumerable.Range(1, SEEDS) select (object)(b, t, (long)s)).ToList();

        public override JsonObject run(int n)
        {
            var (boss, tier, seed) = ((string, long, long))cases[n];
            var rows = BossRuns.fair_rows(boss, seed, tier, new[] { REACT });
            var fails = new List<string>();
            var tells = new JsonArray();
            foreach (var r in rows)
            {
                bool known = KNOWN.ContainsKey((boss, tier, seed, r.kind, r.phase));
                tells.Add(new JsonArray(r.kind, r.phase, r.verdict, known));
                if ((r.verdict == 0 || r.verdict == -1) && !KNOWN.ContainsKey((boss, tier, seed, r.kind, r.phase)))
                    fails.Add($"{boss} tier {tier} seed {seed}: {r.kind} tell (phase {r.phase}) at tick {r.tick} is unfair at R={REACT} ({(r.verdict == 0 ? "no way through" : "hit during the reaction")})");
            }
            return result(fails, new JsonObject { ["boss"] = boss, ["tells"] = tells });
        }

        public override string summary(List<JsonNode> results)
        {
            var all = results.SelectMany(r => r["tells"].AsArray().Select(t => ((int)t[2], (bool)t[3]))).ToList();
            int bad = all.Count(t => t.Item1 == 0 || t.Item1 == -1);
            int known = all.Count(t => (t.Item1 == 0 || t.Item1 == -1) && t.Item2);
            return $"{all.Count} boss tells (3 bosses, tiers 1 and 3, seeds 1..{SEEDS}), {bad} unfair at R={REACT}" + (known > 0 ? $" ({known} known)" : "");
        }
    }
}
