using System.Text.Json.Nodes;
using FastSim;
using FastSim.Yard;

static partial class Checks
{
    /// The yardstick (docs/YARDSTICK.md) measures what was played: a replay
    /// of a bot's taps scores what the bot scored, tiers map as documented and
    /// the human-vs-bot classifier can tell different players apart but not
    /// two halves of one.
    public sealed class Yardstick : Check
    {
        public override string name => "yardstick";
        public override string test => "tools/fastsim/Yardstick/YardstickCheck.cs";
        public override int count() => 1;
        protected override List<object> make() => new() { 0 };

        public override JsonObject run(int n)
        {
            var fails = new List<string>();
            fails.AddRange(Survival.self_test());
            foreach (var (m, want) in new[] { (20.0, "below beginner"), (30, "beginner"), (50, "normal"), (120, "good"), (300, "expert"), (354, "beast"), (900, "beast") })
                if (Stats.tier_of(m) != want) fails.Add($"tier_of({m}) is {Stats.tier_of(m)}, not {want}");
            var gap = Bots.find("gap");
            var runs = new List<Run>();
            for (long s = 1; s <= 40 && fails.Count == 0; s++)
            {
                var decide = gap.make(s);
                var sim = new GameSim(s);
                var taps = new List<long>();
                while (!sim.is_over() && sim.state.tick < 20_000)
                {
                    bool t = decide(sim);
                    if (t) taps.Add(sim.state.tick);
                    sim.step(t);
                }
                var r = Run.analyze(new RunInput(s, Seasons.NONE, taps.ToArray()), 20_000);
                if (r.points != sim.state.score || r.ticks != sim.state.tick)
                    fails.Add($"seed {s}: the replay scored {r.points} in {r.ticks} ticks, the bot {sim.state.score} in {sim.state.tick}");
                runs.Add(r);
            }
            if (fails.Count == 0)
            {
                var same = Compare.classify(runs.Where((_, i) => i % 2 == 0).ToList(), runs.Where((_, i) => i % 2 == 1).ToList());
                if ((double)same["balanced_accuracy"] > 0.75)
                    fails.Add($"the classifier tells two halves of one bot's runs apart ({same["balanced_accuracy"]})");
                var rl = Bots.find("rl:beast");
                if (rl != null)
                {
                    var other = Enumerable.Range(1, 20).Select(s => Run.analyze(Run.play(rl, s, 20_000), 20_000)).ToList();
                    var apart = Compare.classify(runs, other);
                    if ((double)apart["balanced_accuracy"] < 0.9)
                        fails.Add($"the classifier cannot tell the gap seeker from the RL bot ({apart["balanced_accuracy"]})");
                }
                // The leak check: PlannerBot rolls out real copies, so it must be caught; the gap seeker reads only the screen.
                var lp = Leak.check(Bots.find("planner"), 2, 1);
                if ((string)lp["leaks"] != "yes") fails.Add($"the leak check misses PlannerBot's real copies ({lp.ToJsonString()})");
                var lg = Leak.check(gap, 4, 1);
                if ((string)lg["leaks"] != "no") fails.Add($"the leak check flags the gap seeker ({lg.ToJsonString()})");
                var t = Timing.judge(runs[0].input, runs[0], 10);
                if (t.taps_judged == 0) fails.Add("no tap of a gap seeker run could be timed");
            }
            return result(fails, new JsonObject { ["runs"] = runs.Count });
        }

        public override string summary(List<JsonNode> results) =>
            $"yardstick: replays match {results.FirstOrDefault()?["runs"]} bot runs, tiers and classifier behave";
    }
}
