using FastSim.Model;

namespace FastSim.Yard;

/// The world-model planner's tiers (World/, docs/WORLD_MODEL.md) as yardstick
/// bots: world:beginner .. world:beast. It models only what it has seen.
static class WorldBots
{
    [System.Runtime.CompilerServices.ModuleInitializer]
    internal static void Init()
    {
        foreach (var sk in WorldPlanner.Skill.ALL)
        {
            var skill = sk;
            Bots.add(new($"world:{skill.name}", $"WorldPlanner, skill {skill.name}: a world model from what was seen", Copies.NONE,
                seed =>
                {
                    var bot = new WorldPlanner(skill, seed);
                    var mem = new Memory();
                    return sim => bot.Decide(sim, mem);
                }));
        }
    }
}
