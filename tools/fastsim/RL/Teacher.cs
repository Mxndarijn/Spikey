namespace FastSim.Rl;

/// The training teacher (docs/RL_BOT.md): whether a sim can still live
/// `horizon` more ticks, by a beam search over copies of the sim (one copy
/// per height and speed bucket, as SurvivalSearch at a coarse level). Only
/// training uses it, to find the tap that would have saved a run; the bot
/// never looks ahead when it plays.
public static class Teacher
{
    public const long BUCKET_H = 8 * SimConfig.SUB;
    public static readonly long BUCKET_VY = -SimConfig.FLAP_VY / 3;
    public const long SPEED_BUCKETS = 6;
    public static readonly long TAP_BELOW_VY = SimConfig.FLAP_VY / 2;

    /// Scrambled copies (the user's rule: predicting visible motion is fine,
    /// knowing RNG outcomes is not). On, every search starts from a copy whose
    /// RNG, hazard RNGs and crate and dart salts are reseeded, so the teacher
    /// can't see the next wall's spikes or the next drop. Still visible to it:
    /// Bubble.next_x and Stalactite.target_y (not scrambled).
    public static bool blind = false;

    /// A copy of `sim` whose hidden randomness is replaced (when `blind`).
    public static GameSim copy(GameSim sim)
    {
        var c = sim.clone_deep();
        if (!blind) return c;
        var own = new SimRng(sim.checksum() ^ 0x5eed);
        c._rng = new SimRng(own.next_u32());
        foreach (var hz in c.room.hazards)
        {
            if (hz is CrateDrop cd) cd.salt = own.next_u32();
            if (hz is Dart d) d.salt = own.next_u32();
            if (hz is Drop dr) dr._rng = new SimRng(own.next_u32());
            if (hz is Firework fw) fw._rng = new SimRng(own.next_u32());
            if (hz is OrchardSpawner os) os._rng = new SimRng(own.next_u32());
        }
        return c;
    }

    /// Whether `sim` (not changed) survives `horizon` ticks with some taps.
    public static bool survives(GameSim sim, long horizon)
    {
        if (sim.is_over()) return false;
        var frontier = new List<GameSim> { sim.clone_deep() };
        var slots = new Dictionary<long, int>();
        var next = new List<GameSim>();
        for (long t = 0; t < horizon; t++)
        {
            slots.Clear();
            next.Clear();
            foreach (var s in frontier)
            {
                long g = s.room.gravity;
                if (s.state.vy * g > TAP_BELOW_VY || !s.state.started)
                {
                    var c = s.clone_deep();
                    c.step(true);
                    keep(slots, next, c);
                }
                if (!s.state.started) continue;
                s.step(false);
                keep(slots, next, s);
            }
            if (next.Count == 0) return false;
            (frontier, next) = (new List<GameSim>(next), frontier);
        }
        return true;
    }

    static void keep(Dictionary<long, int> slots, List<GameSim> next, GameSim s)
    {
        if (s.is_over()) return;
        var st = s.state;
        long along = st.vy * s.room.gravity - SimConfig.FLAP_VY;
        long speed = G.clampi(along / BUCKET_VY, 0, SPEED_BUCKETS - 1);
        long key = (st.room_index * 1000 + st.y / BUCKET_H) * SPEED_BUCKETS + speed;
        if (slots.TryGetValue(key, out int slot))
        {
            if (SurvivalSearch._better(s, next[slot])) next[slot] = s;
        }
        else
        {
            slots[key] = next.Count;
            next.Add(s);
        }
    }

    /// Which moves at `sim` keep the bird alive for `horizon` ticks after it:
    /// (tap is safe, wait is safe).
    public static (bool tap, bool wait) safe_moves(GameSim sim, long horizon)
    {
        var a = copy(sim);
        a.step(true);
        var b = copy(sim);
        b.step(false);
        return (survives(a, horizon), survives(b, horizon));
    }

    /// Slack: how many height/speed buckets are still alive after `horizon`
    /// ticks (0 if none). More means more room for error.
    public static long width(GameSim sim, long horizon)
    {
        if (sim.is_over()) return 0;
        var frontier = new List<GameSim> { sim.clone_deep() };
        var slots = new Dictionary<long, int>();
        var next = new List<GameSim>();
        for (long t = 0; t < horizon; t++)
        {
            slots.Clear();
            next.Clear();
            foreach (var s in frontier)
            {
                long g = s.room.gravity;
                if (s.state.vy * g > TAP_BELOW_VY || !s.state.started)
                {
                    var c = s.clone_deep();
                    c.step(true);
                    keep(slots, next, c);
                }
                if (!s.state.started) continue;
                s.step(false);
                keep(slots, next, s);
            }
            if (next.Count == 0) return 0;
            (frontier, next) = (new List<GameSim>(next), frontier);
        }
        return frontier.Count;
    }

    /// The slack after a tap and after a wait at `sim`.
    public static (long tap, long wait) slack_moves(GameSim sim, long horizon)
    {
        var a = copy(sim);
        a.step(true);
        var b = copy(sim);
        b.step(false);
        return (width(a, horizon), width(b, horizon));
    }
}
