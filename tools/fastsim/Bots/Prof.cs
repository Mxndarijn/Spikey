using System.Diagnostics;

namespace FastSim;

/// Timers for the planner speed review (`rl review speed`). The hooks are only
/// compiled with `-p:DefineConstants=PROF`; without it nothing here is called.
/// Per thread, merged into `total` by `flush`. Tool only.
public static class Prof
{
    public const int LOOK = 0, BLIND = 1, BEAM = 2, CLONE = 3, STEP = 4, HZSTEP = 5, COLLIDE = 6, WALLS = 7,
        NEAR = 8, LIVES = 9, W_READ = 10, W_BUILD = 11, W_SEARCH = 12, W_SUB = 13, W_OWN = 14, EXIT = 15, GEN = 16, ONWALL = 17, N = 18;
    public static readonly string[] NAMES =
    {
        "look", "blind_copy", "beam", "clone_deep", "step", "  room.step (hazards)", "  collision", "  walls/bounce",
        "near_death", "lives", "world Read", "world Build timeline", "world search", "  Physics.Substep", "  own copies", "    take exit (portal)", "    generate_wall", "    wall hooks/on_bounce",
    };

    [ThreadStatic] static long[] _t, _c;
    public static readonly long[] total = new long[N], count = new long[N];

    public static long now() => Stopwatch.GetTimestamp();

    public static void add(int k, long since)
    {
        _t ??= new long[N];
        _c ??= new long[N];
        _t[k] += Stopwatch.GetTimestamp() - since;
        _c[k]++;
    }

    public static void flush()
    {
        if (_t == null) return;
        lock (total)
            for (int k = 0; k < N; k++)
            {
                total[k] += _t[k];
                count[k] += _c[k];
                _t[k] = 0;
                _c[k] = 0;
            }
    }

    public static double ms(int k) => total[k] * 1000.0 / Stopwatch.Frequency;
}
