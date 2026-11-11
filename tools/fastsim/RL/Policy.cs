using System.Text.Json;
using System.Text.Json.Nodes;

namespace FastSim.Rl;

/// The trained player: an MLP from an observation to one logit; tap when it
/// is above 0 (tap chance over one half). Saved as tools/rlbot/policy.json.
public sealed class Policy
{
    /// The PPO policy network (the evolution-strategies one was INPUTS,32,16,1).
    public static readonly int[] SIZES = { Observer.INPUTS, 64, 64, 1 };
    public readonly Mlp net;
    public readonly float[] w;

    public Policy(float[] weights, int[] sizes = null)
    {
        net = new Mlp(sizes ?? SIZES);
        if (weights.Length != net.count) throw new InvalidDataException($"{weights.Length} weights, the network needs {net.count}");
        w = weights;
    }

    public static int count() => Mlp.params_for(SIZES);

    public static float[] init(int seed) => new Mlp(SIZES).init(seed, 1f);

    public static double Gauss(Random rng) => Mlp.gauss(rng);

    /// The logit for `x`; `acts` from net.scratch().
    public float act(float[] x, float[][] acts) => net.forward(w, x, acts);

    public static JsonObject to_json(float[] w, int[] sizes, JsonObject extra = null)
    {
        var o = new JsonObject
        {
            ["layout"] = Observer.LAYOUT,
            ["gameplay_version"] = SimConfig.GAMEPLAY_VERSION,
            ["sizes"] = new JsonArray(sizes.Select(s => (JsonNode)s).ToArray()),
        };
        if (extra != null)
            foreach (var kv in extra.ToList())
            {
                extra.Remove(kv.Key);
                o[kv.Key] = kv.Value;
            }
        o["weights"] = new JsonArray(w.Select(x => (JsonNode)x).ToArray());
        return o;
    }

    public static Policy load(string path)
    {
        if (!File.Exists(path)) throw new FileNotFoundException($"{path} not found: train first (tools/rlbot.ps1 -Mode train)");
        var o = JsonNode.Parse(File.ReadAllText(path)).AsObject();
        if ((int)o["layout"] != Observer.LAYOUT)
            throw new InvalidDataException($"{path}: observation layout {(int)o["layout"]}, this build uses {Observer.LAYOUT}: train again");
        var sizes = o["sizes"].AsArray().Select(n => (int)n).ToArray();
        if (sizes[0] != Observer.INPUTS || sizes[^1] != 1) throw new InvalidDataException($"{path}: network inputs differ: train again");
        var w = o["weights"].AsArray().Select(n => (float)n).ToArray();
        return new Policy(w, sizes);
    }

    public static readonly JsonSerializerOptions PRETTY = new() { WriteIndented = true };
}
