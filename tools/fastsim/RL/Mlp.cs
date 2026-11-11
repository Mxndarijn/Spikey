using System.Numerics;

namespace FastSim.Rl;

/// A plain MLP with tanh hidden layers and one linear output, on one flat
/// parameter array (per layer: weights out x in, row-major, then biases).
/// Forward for play, forward + backward for training.
public sealed class Mlp
{
    public readonly int[] sizes;
    public readonly int count;

    public Mlp(int[] sizes)
    {
        this.sizes = sizes;
        count = params_for(sizes);
    }

    public static int params_for(int[] sizes)
    {
        int n = 0;
        for (int l = 0; l + 1 < sizes.Length; l++) n += sizes[l] * sizes[l + 1] + sizes[l + 1];
        return n;
    }

    /// Random start, scaled so each layer keeps about unit variance; the
    /// last layer starts small (`out_scale`) so the first outputs are near 0.
    public float[] init(int seed, float out_scale = 0.01f)
    {
        var rng = new Random(seed);
        var w = new float[count];
        int k = 0;
        for (int l = 0; l + 1 < sizes.Length; l++)
        {
            bool last = l + 2 == sizes.Length;
            float scale = (last ? out_scale : 1f) / MathF.Sqrt(sizes[l]);
            for (int i = 0; i < sizes[l] * sizes[l + 1]; i++) w[k++] = (float)gauss(rng) * scale;
            k += sizes[l + 1];
        }
        return w;
    }

    public static double gauss(Random rng)
    {
        double u = 1.0 - rng.NextDouble(), v = rng.NextDouble();
        return Math.Sqrt(-2.0 * Math.Log(u)) * Math.Cos(2.0 * Math.PI * v);
    }

    /// Scratch for one forward pass: the activations of every layer.
    public float[][] scratch()
    {
        var a = new float[sizes.Length][];
        for (int l = 0; l < sizes.Length; l++) a[l] = new float[sizes[l]];
        return a;
    }

    /// The output for `x`. Leaves every layer's activation in `acts`
    /// (acts[0] = the input) for backward.
    public float forward(float[] p, ReadOnlySpan<float> x, float[][] acts)
    {
        x.CopyTo(acts[0]);
        int k = 0;
        int L = sizes.Length - 1;
        for (int l = 0; l < L; l++)
        {
            int n = sizes[l], m = sizes[l + 1];
            var inp = acts[l];
            var outp = acts[l + 1];
            int bias = k + n * m;
            for (int j = 0; j < m; j++)
            {
                float a = dot(p.AsSpan(k + j * n, n), inp) + p[bias + j];
                outp[j] = l + 1 < L ? MathF.Tanh(a) : a;
            }
            k = bias + m;
        }
        return acts[L][0];
    }

    /// Adds d(output)/d(params) * `dout` to `grad`, for the pass in `acts`.
    public void backward(float[] p, float[][] acts, float dout, float[] grad, float[][] deltas)
    {
        int L = sizes.Length - 1;
        // Offsets of each layer's weights.
        Span<int> offs = stackalloc int[L];
        int k = 0;
        for (int l = 0; l < L; l++)
        {
            offs[l] = k;
            k += sizes[l] * sizes[l + 1] + sizes[l + 1];
        }
        deltas[L][0] = dout;
        for (int l = L - 1; l >= 0; l--)
        {
            int n = sizes[l], m = sizes[l + 1];
            int w0 = offs[l], b0 = w0 + n * m;
            var d = deltas[l + 1];
            var inp = acts[l];
            for (int j = 0; j < m; j++)
            {
                float dj = d[j];
                if (dj == 0f) continue;
                axpy(dj, inp, grad.AsSpan(w0 + j * n, n));
                grad[b0 + j] += dj;
            }
            if (l == 0) break;
            // Delta of the layer below, through its tanh.
            var below = deltas[l];
            Array.Clear(below, 0, n);
            for (int j = 0; j < m; j++)
            {
                float dj = d[j];
                if (dj == 0f) continue;
                axpy(dj, p.AsSpan(w0 + j * n, n), below);
            }
            for (int i = 0; i < n; i++) below[i] *= 1f - inp[i] * inp[i];
        }
    }

    public float[][] delta_scratch() => scratch();

    /// Worst relative gap between backward() and a finite difference, over
    /// some parameters of a small random net (the rlbot check holds it small).
    public static double gradient_error(int seed = 3)
    {
        var net = new Mlp(new[] { 6, 5, 4, 1 });
        var p = net.init(seed, 1f);
        var rng = new Random(seed);
        var x = Enumerable.Range(0, 6).Select(_ => (float)gauss(rng)).ToArray();
        var acts = net.scratch();
        var g = new float[net.count];
        net.forward(p, x, acts);
        net.backward(p, acts, 1f, g, net.delta_scratch());
        double worst = 0;
        for (int i = 0; i < net.count; i++)
        {
            float keep = p[i];
            const float H = 1e-2f;
            p[i] = keep + H;
            double up = net.forward(p, x, acts);
            p[i] = keep - H;
            double down = net.forward(p, x, acts);
            p[i] = keep;
            double num = (up - down) / (2 * H);
            worst = Math.Max(worst, Math.Abs(num - g[i]) / Math.Max(1e-3, Math.Abs(num) + Math.Abs(g[i])));
        }
        return worst;
    }

    static float dot(ReadOnlySpan<float> a, ReadOnlySpan<float> b)
    {
        int n = a.Length, i = 0;
        float s = 0f;
        if (Vector.IsHardwareAccelerated && n >= Vector<float>.Count)
        {
            var acc = Vector<float>.Zero;
            int w = Vector<float>.Count;
            for (; i <= n - w; i += w) acc += new Vector<float>(a.Slice(i)) * new Vector<float>(b.Slice(i));
            s = Vector.Dot(acc, Vector<float>.One);
        }
        for (; i < n; i++) s += a[i] * b[i];
        return s;
    }

    static void axpy(float k, ReadOnlySpan<float> x, Span<float> y)
    {
        int n = x.Length, i = 0;
        if (Vector.IsHardwareAccelerated && n >= Vector<float>.Count)
        {
            var kv = new Vector<float>(k);
            int w = Vector<float>.Count;
            for (; i <= n - w; i += w) (new Vector<float>(y.Slice(i)) + kv * new Vector<float>(x.Slice(i))).CopyTo(y.Slice(i));
        }
        for (; i < n; i++) y[i] += k * x[i];
    }
}

/// Adam on a flat parameter array.
public sealed class Adam
{
    public float[] m, v;
    public long t;
    public float lr, b1 = 0.9f, b2 = 0.999f, eps = 1e-8f;

    public Adam(int n, float lr)
    {
        m = new float[n];
        v = new float[n];
        this.lr = lr;
    }

    /// Steps `p` against `g` (a gradient of something to minimise).
    public void step(float[] p, float[] g, float clip_norm = 0.5f)
    {
        double norm = 0;
        for (int i = 0; i < g.Length; i++) norm += (double)g[i] * g[i];
        norm = Math.Sqrt(norm);
        float scale = norm > clip_norm ? (float)(clip_norm / norm) : 1f;
        t++;
        float c1 = 1f - MathF.Pow(b1, t), c2 = 1f - MathF.Pow(b2, t);
        for (int i = 0; i < p.Length; i++)
        {
            float gi = g[i] * scale;
            m[i] = b1 * m[i] + (1 - b1) * gi;
            v[i] = b2 * v[i] + (1 - b2) * gi * gi;
            p[i] -= lr * (m[i] / c1) / (MathF.Sqrt(v[i] / c2) + eps);
        }
    }
}
