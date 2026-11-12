using FastSim.Yard;

namespace FastSim.Model;

/// Registers the world planner with the shared yardstick (docs/YARDSTICK.md):
/// `world:beginner` .. `world:beast`, and `world:all` through the yardstick's own
/// grouping. No sim copies: it plans on the world model only.
static class WorldYardstick
{
    [System.Runtime.CompilerServices.ModuleInitializer]
    internal static void Init()
    {
        foreach (var sk in WorldPlanner.Skill.ALL)
        {
            var skill = sk;
            Bots.add(new BotSpec($"world:{skill.name}",
                $"beam planner on the structured world model (World/), {skill}", Copies.NONE,
                seed =>
                {
                    var p = new WorldPlanner(skill, seed);
                    var mem = new Memory();
                    return sim => p.Decide(sim, mem);
                }));
        }
    }
}
