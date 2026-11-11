namespace FastSim;

/// A planner that knows the rules but not the hidden future. It looks ahead
/// on a copy of the sim whose RNG (and the hidden values already drawn, see
/// `blind_copy`) are replaced by its own random numbers: the copy moves
/// everything visible exactly as the game does, and every random outcome in
/// it is a guess. Beam search over tap / wait, re-planned every `replan`
/// ticks. Tool only (playtest bots).
public sealed class BlindPlanner
{
    /// Ticks looked ahead at most, and at most `past` ticks past the next bounce.
    public long horizon = 160, past = 40;
    public int replan = 4;
    /// Cost per tick of each px away from the middle height, and per tap (px).
    public long mid_cost = 1, tap_cost = 0;
    /// Extra cost per tick while a bird `margin` px higher or lower would die (0 = not checked).
    public long margin = 0, margin_cost = 40;
    /// Buckets: one survivor per height (px) and speed bucket; the finer set is tried when the first finds no line.
    public long bucket_px = 8, speed_buckets = 6, fine_px = 3, fine_speeds = 12;

    readonly SimRng _own;
    readonly Queue<bool> _plan = new();
    int _since = int.MaxValue;
    /// How the last look ended: 0 = a line for the whole look, 1 = only with fine buckets, 2 = only a shorter look, 3 = none.
    public int last_look;
    public long looks, fine_looks, short_looks, no_looks;

    public BlindPlanner(long seed) => _own = new SimRng(977 * seed + 5);

    public bool decide(GameSim sim)
    {
        if (!sim.state.started) return true;
        if (_since >= replan || _plan.Count == 0) look(sim);
        _since++;
        return _plan.Count > 0 && _plan.Dequeue();
    }

    void look(GameSim sim)
    {
        long want = Math.Min(horizon, sim.steps_to_wall(sim.state.vx > 0 ? 1 : 0) + past);
        looks++;
        last_look = 0;
        byte[] found = beam(blind_copy(sim, _own), want, bucket_px, speed_buckets);
        if (found == null && fine_px > 0)
        {
            last_look = 1;
            fine_looks++;
            found = beam(blind_copy(sim, _own), want, fine_px, fine_speeds);
        }
        for (long t = want * 3 / 4; t >= 2 && found == null; t = t * 3 / 4)
        {
            last_look = 2;
            found = beam(blind_copy(sim, _own), t, bucket_px, speed_buckets);
        }
        if (last_look == 2) short_looks++;
        if (found == null)
        {
            last_look = 3;
            no_looks++;
        }
        _plan.Clear();
        if (found != null)
            foreach (byte b in found) _plan.Enqueue(b != 0);
        _since = 0;
    }

    /// A copy of `sim` with every hidden random value replaced by `own`'s.
    public static GameSim blind_copy(GameSim sim, SimRng own)
    {
        var c = sim.clone_deep();
        c._rng = new SimRng(own.next_u32());
        // Values the sim has already drawn but not yet shown. A value that is
        // on screen (a warning, a marked column, a moving thing) stays.
        foreach (var hz in c.room.hazards)
        {
            switch (hz)
            {
                // Hash salts and private RNGs: where every later crate, dart, drop, rocket and coin goes.
                case CrateDrop cd: cd.salt = own.next_u32(); break;
                case Dart d: d.salt = own.next_u32(); break;
                case Drop dr: dr._rng.reseed(own.next_u32()); break;
                case Firework fw: fw._rng.reseed(own.next_u32()); break;
                case OrchardSpawner os: os._rng.reseed(own.next_u32()); break;
                // Where the bubble comes back after its next pop.
                case Bubble b: b.next_x = Bubble.MIN_X + own.next_below(Bubble.MAX_X - Bubble.MIN_X + 1); break;
                // Where a sliding gap stops: the side it slides to is visible, how far is not.
                case Stalactite st when st.gap_y != st.target_y:
                {
                    long far = own.next_below(Stalactite.REACH + Stalactite.MAX_STEP + 1);
                    long to = st.gap_y + (st.target_y > st.gap_y ? far : -far);
                    st.target_y = G.clampi(to, Stalactite.GAP_MIN, Stalactite.GAP_MAX);
                    break;
                }
                // The second ball's column before it drops in.
                case KeepyBall kb when kb.waiting > 0 && c.room.t < KeepyBall.SECOND_DROP:
                    kb.x = KeepyBall.MIN_X + own.next_below(KeepyBall.MAX_X - KeepyBall.MIN_X + 1);
                    break;
                // The order rows fire in, among rows that have not warned yet.
                case Beam bm:
                {
                    var idle = new List<int>();
                    for (int i = 0; i < bm.delays.Count; i++)
                        if (bm.t < bm.delays[i]) idle.Add(i);
                    for (int i = idle.Count - 1; i > 0; i--)
                    {
                        int j = (int)own.next_below(i + 1);
                        (bm.delays[idle[i]], bm.delays[idle[j]]) = (bm.delays[idle[j]], bm.delays[idle[i]]);
                    }
                    break;
                }
                // A gusty updraft's first gust: no countdown is shown.
                case Updraft up when up.drift_span == 0 && up.gust != Updraft.Gust.NONE && up.t + up.phase < Updraft.GUST_OFF:
                    up.phase = own.next_below(Updraft.GUST_OFF - up.t);
                    break;
            }
        }
        return c;
    }

    struct Node
    {
        public GameSim sim;
        public int parent;
        public byte tap;
        public long cost;
    }

    byte[] beam(GameSim root, long ticks, long bpx, long speeds)
    {
        long bh = bpx * SimConfig.SUB;
        long bvy = -SimConfig.FLAP_VY * 2 / speeds;
        long mid = (SimConfig.KILL_TOP + SimConfig.KILL_BOTTOM) / 2;
        var parents = new List<int>();
        var taps = new List<byte>();
        var frontier = new List<Node> { new Node { sim = root, parent = -1 } };
        var slots = new Dictionary<long, int>();
        var next = new List<Node>();
        for (long t = 0; t < ticks; t++)
        {
            slots.Clear();
            next.Clear();
            foreach (var e in frontier)
            {
                bool can_tap = e.sim.state.vy * e.sim.room.gravity > SurvivalSearch.TAP_BELOW_VY;
                for (int a = can_tap ? 1 : 0; a >= 0; a--)
                {
                    var s = a == 1 ? e.sim.clone_deep() : e.sim;
                    s.step(a == 1);
                    if (s.is_over()) continue;
                    var st = s.state;
                    long cost = e.cost + Math.Abs(st.y - mid) / SimConfig.SUB * mid_cost + a * tap_cost;
                    if (margin > 0 && near_death(s)) cost += margin_cost;
                    long along = st.vy * s.room.gravity - SimConfig.FLAP_VY;
                    long speed = G.clampi(along / bvy, 0, speeds - 1);
                    long key = (st.room_index * 1000 + st.y / bh) * speeds + speed;
                    var node = new Node { sim = s, parent = e.parent, tap = (byte)a, cost = cost };
                    if (slots.TryGetValue(key, out int at))
                    {
                        if (cost < next[at].cost) next[at] = node;
                    }
                    else
                    {
                        slots[key] = next.Count;
                        next.Add(node);
                    }
                }
            }
            if (next.Count == 0) return null;
            frontier = new List<Node>(next.Count);
            foreach (var e in next)
            {
                parents.Add(e.parent);
                taps.Add(e.tap);
                frontier.Add(new Node { sim = e.sim, parent = parents.Count - 1, cost = e.cost });
            }
        }
        var top = frontier[0];
        foreach (var e in frontier)
        {
            long ra = e.sim.state.room_index, rb = top.sim.state.room_index;
            if (ra > rb || (ra == rb && e.cost < top.cost)) top = e;
        }
        var out_ = new List<byte>();
        for (int nd = top.parent; nd >= 0; nd = parents[nd]) out_.Add(taps[nd]);
        out_.Reverse();
        return out_.ToArray();
    }

    /// Whether a bird `margin` px above or below this one would be killed by a hazard now.
    bool near_death(GameSim s)
    {
        var hz = s.room.hazards;
        if (hz.Count == 0) return false;
        long y = s.state.y;
        bool bad = false;
        for (int d = -1; d <= 1 && !bad; d += 2)
        {
            s.state.y = y + d * margin * SimConfig.SUB;
            for (int h = 0; h < hz.Count && !bad; h++)
                if (hz[h].alive && hz[h].kills(s)) bad = true;
        }
        s.state.y = y;
        return bad;
    }
}
