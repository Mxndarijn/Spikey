using FastSim.Rl;

namespace FastSim.Yard;

/// The review's first honest planner (bot-review.md, `rl review honest` in
/// RL/Review.cs on claude/quirky-yonath-3b526e), as a yardstick bot. It knows
/// the rules but not the hidden draws: it looks ahead on `n` copies of the sim
/// whose RNG and crate / dart salts are its own random numbers ("scrambled
/// copies"), never more than `past` ticks past the next bounce, and wants a
/// line of taps that lives in every copy. Re-plans every `k` ticks.
/// It still leaks hidden draws (Drop, Firework and Orchard RNGs,
/// Bubble.next_x, Stalactite.target_y, beam order): yardstick bot honest-v1.
public sealed class HonestBot
{
    readonly long _h, _past;
    readonly int _k, _n;
    readonly SimRng _own;
    readonly Queue<bool> _plan = new();
    int _since;

    public HonestBot(long seed, long h = 90, int k = 4, int n = 3, long past = 40)
    {
        _h = h;
        _k = k;
        _n = n;
        _past = past;
        _since = k;
        _own = new SimRng(977 * seed + 5);
    }

    public bool decide(GameSim sim)
    {
        if (!sim.state.started) return true;
        if (_since >= _k || _plan.Count == 0)
        {
            long want = Math.Min(_h, sim.steps_to_wall(sim.state.vx > 0 ? 1 : 0) + _past);
            byte[] found = null;
            for (int copies = _n; copies >= 1 && found == null; copies = copies == 1 ? 0 : 1)
                for (long t = want; t >= 2 && found == null; t = t * 3 / 4)
                {
                    var roots = new GameSim[copies];
                    for (int j = 0; j < copies; j++) roots[j] = blind_copy(sim, _own);
                    found = beam(roots, t);
                }
            _plan.Clear();
            if (found != null)
                foreach (byte b in found) _plan.Enqueue(b != 0);
            _since = 0;
        }
        _since++;
        return _plan.Count > 0 && _plan.Dequeue();
    }

    public static GameSim blind_copy(GameSim sim, SimRng own)
    {
        var c = sim.clone_deep();
        c._rng = new SimRng(own.next_u32());
        foreach (var hz in c.room.hazards)
        {
            if (hz is CrateDrop cd) cd.salt = own.next_u32();
            if (hz is Dart d) d.salt = own.next_u32();
        }
        return c;
    }

    struct Node
    {
        public GameSim[] sims;
        public int parent;
        public byte tap;
    }

    /// Beam search over tap / wait for `ticks` ticks: a line lives only if the
    /// bird lives in every copy. One survivor per height and speed bucket. Of
    /// the lines that live, the one ending nearest the middle height.
    static byte[] beam(GameSim[] roots, long ticks)
    {
        var parents = new List<int>();
        var taps = new List<byte>();
        var frontier = new List<Node> { new Node { sims = roots, parent = -1 } };
        var slots = new Dictionary<long, int>();
        var next = new List<Node>();
        for (long t = 0; t < ticks; t++)
        {
            slots.Clear();
            next.Clear();
            foreach (var e in frontier)
            {
                var s0 = e.sims[0];
                bool can_tap = s0.state.vy * s0.room.gravity > SurvivalSearch.TAP_BELOW_VY;
                for (int a = can_tap ? 1 : 0; a >= 0; a--)
                {
                    var sims = e.sims;
                    if (a == 1)
                    {
                        sims = new GameSim[e.sims.Length];
                        for (int j = 0; j < sims.Length; j++) sims[j] = e.sims[j].clone_deep();
                    }
                    bool dead = false;
                    foreach (var s in sims)
                    {
                        s.step(a == 1);
                        if (s.is_over()) dead = true;
                    }
                    if (dead) continue;
                    var st = sims[0].state;
                    long along = st.vy * sims[0].room.gravity - SimConfig.FLAP_VY;
                    long speed = G.clampi(along / Teacher.BUCKET_VY, 0, Teacher.SPEED_BUCKETS - 1);
                    long key = (st.room_index * 1000 + st.y / Teacher.BUCKET_H) * Teacher.SPEED_BUCKETS + speed;
                    if (slots.ContainsKey(key)) continue;
                    slots[key] = next.Count;
                    next.Add(new Node { sims = sims, parent = e.parent, tap = (byte)a });
                }
            }
            if (next.Count == 0) return null;
            frontier = new List<Node>(next.Count);
            foreach (var e in next)
            {
                parents.Add(e.parent);
                taps.Add(e.tap);
                frontier.Add(new Node { sims = e.sims, parent = parents.Count - 1 });
            }
        }
        long mid = (SimConfig.KILL_TOP + SimConfig.KILL_BOTTOM) / 2;
        var top = frontier[0];
        foreach (var e in frontier)
        {
            var (a, b) = (e.sims[0].state, top.sims[0].state);
            if (a.room_index > b.room_index || (a.room_index == b.room_index && Math.Abs(a.y - mid) < Math.Abs(b.y - mid))) top = e;
        }
        var out_ = new List<byte>();
        for (int nd = top.parent; nd >= 0; nd = parents[nd]) out_.Add(taps[nd]);
        out_.Reverse();
        return out_.ToArray();
    }
}
