using System.Text.Json;
using System.Text.Json.Nodes;

namespace FastSim.Rl;

/// A small MLP (tanh) from an observation to one number: tap when > 0.
/// The weights are one flat array so evolution strategies can perturb them.
public sealed class Policy
{
    public static readonly int[] SIZES = { Observer.INPUTS, 32, 16, 1 };
    public readonly float[] w;

    public Policy(float[] weights) => w = weights;

    public static int count()
    {
        int n = 0;
        for (int l = 0; l + 1 < SIZES.Length; l++) n += SIZES[l] * SIZES[l + 1] + SIZES[l + 1];
        return n;
    }

    /// Random start: scaled so every layer starts near unit variance.
    public static float[] init(int seed)
    {
        var rng = new Random(seed);
        var w = new float[count()];
        int k = 0;
        for (int l = 0; l + 1 < SIZES.Length; l++)
        {
            float scale = 1f / MathF.Sqrt(SIZES[l]);
            for (int i = 0; i < SIZES[l] * SIZES[l + 1]; i++) w[k++] = (float)Gauss(rng) * scale;
            k += SIZES[l + 1];
        }
        return w;
    }

    public static double Gauss(Random rng)
    {
        double u = 1.0 - rng.NextDouble(), v = rng.NextDouble();
        return Math.Sqrt(-2.0 * Math.Log(u)) * Math.Cos(2.0 * Math.PI * v);
    }

    /// The output for `x` (INPUTS floats). `h1`, `h2`: scratch of the hidden sizes.
    public float act(float[] x, float[] h1, float[] h2)
    {
        int k = 0;
        layer(x, SIZES[0], h1, SIZES[1], ref k, true);
        layer(h1, SIZES[1], h2, SIZES[2], ref k, true);
        float o = w[k + SIZES[2]];
        for (int i = 0; i < SIZES[2]; i++) o += w[k + i] * h2[i];
        return o;
    }

    void layer(float[] x, int n, float[] y, int m, ref int k, bool tanh)
    {
        for (int j = 0; j < m; j++)
        {
            float a = 0f;
            int row = k + j * n;
            for (int i = 0; i < n; i++) a += w[row + i] * x[i];
            y[j] = a;
        }
        k += n * m;
        for (int j = 0; j < m; j++)
        {
            float a = y[j] + w[k + j];
            y[j] = tanh ? MathF.Tanh(a) : a;
        }
        k += m;
    }

    public static JsonObject to_json(float[] w, JsonObject extra = null)
    {
        var o = new JsonObject
        {
            ["layout"] = Observer.LAYOUT,
            ["gameplay_version"] = SimConfig.GAMEPLAY_VERSION,
            ["sizes"] = new JsonArray(SIZES.Select(s => (JsonNode)s).ToArray()),
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
        var o = JsonNode.Parse(File.ReadAllText(path)).AsObject();
        if ((int)o["layout"] != Observer.LAYOUT)
            throw new InvalidDataException($"{path}: observation layout {(int)o["layout"]}, this build uses {Observer.LAYOUT}: train again");
        var sizes = o["sizes"].AsArray().Select(n => (int)n).ToArray();
        if (!sizes.SequenceEqual(SIZES)) throw new InvalidDataException($"{path}: network sizes differ: train again");
        var w = o["weights"].AsArray().Select(n => (float)n).ToArray();
        if (w.Length != count()) throw new InvalidDataException($"{path}: {w.Length} weights, expected {count()}");
        return new Policy(w);
    }

    public static readonly JsonSerializerOptions PRETTY = new() { WriteIndented = true };
}
