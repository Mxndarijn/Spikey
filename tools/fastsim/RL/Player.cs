namespace FastSim.Rl;

/// A human-like handicap (docs/RL_BOT.md): the policy sees the world `delay`
/// ticks late, each tap lands 0..`jitter` ticks late, and a tap is dropped
/// with chance `miss`. All zero: the policy as trained (beast).
public readonly record struct Handicap(int delay, int jitter, double miss)
{
    public static readonly Handicap NONE = new(0, 0, 0);
    public const int MAX_DELAY = 60;
    public const int MAX_JITTER = 20;

    /// The handicap at skill `s` (1 = none, 0 = the most).
    public static Handicap at(double s)
    {
        double k = Math.Clamp(1.0 - s, 0.0, 1.0);
        return new Handicap((int)Math.Round(40 * k), (int)Math.Round(12 * k), 0.35 * k);
    }

    public override string ToString() => $"delay {delay}, jitter {jitter}, miss {miss:F3}";
}

/// One played run: the score gained, the ticks played and where it ended.
public readonly record struct RunResult(long seed, long points, long ticks, bool dead, string room);

/// Plays the policy on a sim, one tick at a time, through a handicap.
public sealed class Player
{
    readonly Policy _policy;
    readonly Handicap _hc;
    readonly float[][] _frames;
    readonly float[] _x = new float[Observer.INPUTS];
    readonly float[] _h1 = new float[Policy.SIZES[1]];
    readonly float[] _h2 = new float[Policy.SIZES[2]];
    readonly bool[] _pending = new bool[Handicap.MAX_JITTER + 1];
    readonly Random _rng;
    long _n;

    public Player(Policy policy, Handicap hc, long seed)
    {
        _policy = policy;
        _hc = hc with { delay = Math.Min(hc.delay, Handicap.MAX_DELAY), jitter = Math.Min(hc.jitter, Handicap.MAX_JITTER) };
        _frames = new float[_hc.delay + Observer.MOTION + 1][];
        for (int i = 0; i < _frames.Length; i++) _frames[i] = new float[Observer.FRAME];
        _rng = new Random(unchecked((int)(seed * 2654435761L) ^ 0x5bd1e995));
    }

    /// Plays to death or `cap` ticks. Practice runs count points from the room's start score.
    public static RunResult play(Policy policy, Handicap hc, GameSim sim, long cap)
    {
        var p = new Player(policy, hc, sim.seed_value);
        long start = sim.state.score;
        long n = 0;
        while (n < cap && !sim.is_over())
        {
            sim.step(p.decide(sim));
            n++;
        }
        string room = sim.room.def.id;
        if (sim.room.variant_id() != "") room += "/" + sim.room.variant_id();
        return new RunResult(sim.seed_value, sim.state.score - start, n, sim.is_over(), room);
    }

    public bool decide(GameSim sim)
    {
        int len = _frames.Length;
        var now = _frames[_n % len];
        Observer.frame(sim, now);
        // The frame the bird reacts to, and the one MOTION ticks before it
        // (clamped to the first frame at the start of a run).
        long seen = Math.Max(0, _n - _hc.delay);
        long before = Math.Max(0, seen - Observer.MOTION);
        Array.Copy(_frames[seen % len], _x, Observer.FRAME);
        Array.Copy(_frames[before % len], Observer.BASE, _x, Observer.FRAME, Observer.GRID);
        bool want = !sim.state.started || _policy.act(_x, _h1, _h2) > 0f;
        _n++;
        if (_hc.jitter == 0 && _hc.miss == 0) return want;
        // Taps wait in a small queue: slot 0 fires this tick.
        if (want && (_hc.miss == 0 || _rng.NextDouble() >= _hc.miss || !sim.state.started))
            _pending[sim.state.started ? _rng.Next(_hc.jitter + 1) : 0] = true;
        bool tap = _pending[0];
        Array.Copy(_pending, 1, _pending, 0, _pending.Length - 1);
        _pending[^1] = false;
        return tap;
    }
}
