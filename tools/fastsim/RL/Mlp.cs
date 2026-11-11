using System.Numerics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

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
            int j0 = 0;
            // Four rows at a time share the input loads; each row's sum keeps
            // dot()'s exact order, so the outputs are bit for bit the same.
            if (Vector.IsHardwareAccelerated && n >= Vector<float>.Count)
                for (; j0 + 4 <= m; j0 += 4)
                {
                    dot4(p, k + j0 * n, n, inp, out float a0, out float a1, out float a2, out float a3);
                    a0 += p[bias + j0];
                    a1 += p[bias + j0 + 1];
                    a2 += p[bias + j0 + 2];
                    a3 += p[bias + j0 + 3];
                    bool hidden = l + 1 < L;
                    outp[j0] = hidden ? MathF.Tanh(a0) : a0;
                    outp[j0 + 1] = hidden ? MathF.Tanh(a1) : a1;
                    outp[j0 + 2] = hidden ? MathF.Tanh(a2) : a2;
                    outp[j0 + 3] = hidden ? MathF.Tanh(a3) : a3;
                }
            for (int j = j0; j < m; j++)
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

    /// dot() of four consecutive rows (row length n, from p[at]) with x, same arithmetic.
    static void dot4(float[] p, int at, int n, float[] x, out float s0, out float s1, out float s2, out float s3)
    {
        if (at < 0 || at + 4 * n > p.Length || n > x.Length) throw new ArgumentOutOfRangeException(nameof(at));
        int w = Vector<float>.Count;
        ref float r0 = ref p[at];
        ref float r1 = ref Unsafe.Add(ref r0, n);
        ref float r2 = ref Unsafe.Add(ref r0, 2 * n);
        ref float r3 = ref Unsafe.Add(ref r0, 3 * n);
        ref float xs = ref MemoryMarshal.GetArrayDataReference(x);
        Vector<float> c0 = Vector<float>.Zero, c1 = c0, c2 = c0, c3 = c0;
        int i = 0;
        for (; i <= n - w; i += w)
        {
            var xv = Vector.LoadUnsafe(ref xs, (nuint)i);
            c0 += Vector.LoadUnsafe(ref r0, (nuint)i) * xv;
            c1 += Vector.LoadUnsafe(ref r1, (nuint)i) * xv;
            c2 += Vector.LoadUnsafe(ref r2, (nuint)i) * xv;
            c3 += Vector.LoadUnsafe(ref r3, (nuint)i) * xv;
        }
        s0 = Vector.Dot(c0, Vector<float>.One);
        s1 = Vector.Dot(c1, Vector<float>.One);
        s2 = Vector.Dot(c2, Vector<float>.One);
        s3 = Vector.Dot(c3, Vector<float>.One);
        for (; i < n; i++)
        {
            float xi = Unsafe.Add(ref xs, i);
            s0 += Unsafe.Add(ref r0, i) * xi;
            s1 += Unsafe.Add(ref r1, i) * xi;
            s2 += Unsafe.Add(ref r2, i) * xi;
            s3 += Unsafe.Add(ref r3, i) * xi;
        }
    }

    static void axpy(float k, ReadOnlySpan<float> x, Span<float> y)
    {
        int n = x.Length, i = 0;
        if (y.Length < n) throw new ArgumentOutOfRangeException(nameof(y));
        ref float xr = ref MemoryMarshal.GetReference(x);
        ref float yr = ref MemoryMarshal.GetReference(y);
        if (Vector.IsHardwareAccelerated && n >= Vector<float>.Count)
        {
            var kv = new Vector<float>(k);
            int w = Vector<float>.Count;
            for (; i <= n - w; i += w)
                (Vector.LoadUnsafe(ref yr, (nuint)i) + kv * Vector.LoadUnsafe(ref xr, (nuint)i)).StoreUnsafe(ref yr, (nuint)i);
        }
        for (; i < n; i++) Unsafe.Add(ref yr, i) += k * Unsafe.Add(ref xr, i);
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
