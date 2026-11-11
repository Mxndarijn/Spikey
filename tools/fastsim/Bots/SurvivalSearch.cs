namespace FastSim;

/// Port of tests/support/survival_search.gd. Must find the same taps as the
/// GDScript search (the parity check compares them), so the bucket keys, the
/// order copies are tried in and the order of the kept set are the same.
public sealed class SurvivalSearch
{
    public static readonly long TAP_BELOW_VY = SimConfig.FLAP_VY / 2;
    public static readonly long[][] LEVELS =
    {
        new[] { 5 * SimConfig.SUB, -SimConfig.FLAP_VY / 2, 5L },
        new[] { 3 * SimConfig.SUB, -SimConfig.FLAP_VY / 4, 16L },
        new[] { 2 * SimConfig.SUB, -SimConfig.FLAP_VY / 8, 40L },
    };

    public long ticks_survived;
    public long peak_width;
    public GameSim best;
    public byte[] best_inputs = Array.Empty<byte>();
    public List<long> last_rooms = new();
    public Dictionary<string, long> last_deaths = new();
    public long level;
    public long max_level = LEVELS.Length - 1;

    long _bucket_h, _bucket_vy, _speed_buckets;
    List<int> _parents = new();
    List<byte> _taps = new();

    struct Entry
    {
        public GameSim sim;
        public int node;
        public byte tap;
    }

    public bool run(GameSim sim, long ticks)
    {
        for (long i = 0; i < max_level + 1; i++)
        {
            level = i;
            _bucket_h = LEVELS[i][0];
            _bucket_vy = LEVELS[i][1];
            _speed_buckets = LEVELS[i][2];
            if (_run_once(sim, ticks)) return true;
        }
        return false;
    }

    /// tests/support/quick_search.gd (QuickSearch.run): a coarse (fast) first
    /// pass; a line it finds is a real way through, and only when it finds
    /// none does the full search run.
    public bool run_quick(GameSim sim, long ticks)
    {
        level = -1;
        _bucket_h = 10 * SimConfig.SUB;
        _bucket_vy = -SimConfig.FLAP_VY / 2;
        _speed_buckets = 4;
        if (_run_once(sim, ticks)) return true;
        return run(sim, ticks);
    }

    bool _run_once(GameSim sim, long ticks)
    {
        _parents = new List<int>();
        _taps = new List<byte>();
        var frontier = new List<Entry> { new Entry { sim = sim.clone_deep(), node = -1 } };
        ticks_survived = 0;
        peak_width = 1;
        best = null;
        best_inputs = Array.Empty<byte>();
        // Insertion-ordered "dictionary": key -> slot in `next`.
        var slots = new Dictionary<long, int>();
        var next = new List<Entry>();
        for (long t = 0; t < ticks; t++)
        {
            slots.Clear();
            next.Clear();
            foreach (var e in frontier)
            {
                var s = e.sim;
                long grav = s.room.gravity;
                if (s.state.vy * grav > TAP_BELOW_VY || !s.state.started)
                {
                    var c = s.clone_deep();
                    c.step(true);
                    _keep(slots, next, c, e.node, 1);
                }
                if (!s.state.started) continue;
                s.step(false);
                _keep(slots, next, s, e.node, 0);
            }
            if (next.Count == 0)
            {
                last_rooms.Clear();
                last_deaths.Clear();
                foreach (var e in frontier)
                {
                    var st = e.sim.state;
                    if (!last_rooms.Contains(st.room_kind)) last_rooms.Add(st.room_kind);
                    string why = DeathCause.NAMES[st.death_cause];
                    last_deaths[why] = last_deaths.GetValueOrDefault(why) + 1;
                }
                return false;
            }
            frontier = new List<Entry>(next.Count);
            foreach (var e in next)
            {
                _parents.Add(e.node);
                _taps.Add(e.tap);
                frontier.Add(new Entry { sim = e.sim, node = _parents.Count - 1 });
            }
            peak_width = G.maxi(peak_width, frontier.Count);
            ticks_survived = t + 1;
        }
        var top = frontier[0];
        foreach (var e in frontier)
            if (_better(e.sim, top.sim)) top = e;
        best = top.sim;
        best_inputs = _inputs_to(top.node);
        _parents = new List<int>();
        _taps = new List<byte>();
        return true;
    }

    byte[] _inputs_to(int node)
    {
        var out_ = new List<byte>();
        int n = node;
        while (n >= 0)
        {
            out_.Add(_taps[n]);
            n = _parents[n];
        }
        out_.Reverse();
        return out_.ToArray();
    }

    void _keep(Dictionary<long, int> slots, List<Entry> next, GameSim s, int parent, byte tap)
    {
        if (s.is_over()) return;
        var st = s.state;
        long along = st.vy * s.room.gravity - SimConfig.FLAP_VY;
        long speed = G.clampi(along / _bucket_vy, 0, _speed_buckets - 1);
        long key = (st.y / _bucket_h) * _speed_buckets + speed;
        var entry = new Entry { sim = s, node = parent, tap = tap };
        if (slots.TryGetValue(key, out int slot))
        {
            if (_better(s, next[slot].sim)) next[slot] = entry;
        }
        else
        {
            slots[key] = next.Count;
            next.Add(entry);
        }
    }

    public static bool _better(GameSim a, GameSim b)
    {
        if (a.state.room_index != b.state.room_index) return a.state.room_index > b.state.room_index;
        if (a.state.score != b.state.score) return a.state.score > b.state.score;
        return a.state.coins > b.state.coins;
    }
}
