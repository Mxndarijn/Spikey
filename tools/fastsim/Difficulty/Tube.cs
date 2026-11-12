namespace FastSim.Diff;

/// The "tube" of a room entry: every way through it, with exact knowledge.
///
/// A breadth-first search over real sim copies from the entry, one tick at a
/// time, that keeps one copy per bucket of bird state (4 px of height, 1/8 of a
/// flap of vertical speed, 40 px of x and the flight direction) instead of only
/// the best few (SurvivalSearch). Every kept copy is a node; each node records
/// which bucket its tap and its no-tap step landed in. A backward pass then
/// marks the viable nodes: those with a line that still reaches the exit (or,
/// in a boss room, the boss going down).
///
/// From the viable nodes per tick:
///   band:    how many px of bird heights still lead through (the free band);
///            its minimum is the room's bottleneck.
///   paths:   log2 of the number of viable tap sequences (bucket DAG paths), per second.
///   window:  for a tap, the run of neighbouring ticks (no tap in between)
///            at which the tap would still lead through: the timing precision
///            it needs. The maximin line is the line whose tightest tap window
///            is widest: "the most forgiving way through".
///   choice:  ticks where the viable heights form two or more groups (over or
///            under something), a route choice.
/// Taps follow SurvivalSearch's rule (only once the last flap has half worn off).
public sealed class Tube
{
    public const long BUCKET_H = 4 * SimConfig.SUB;
    public const long BUCKET_VY = -SimConfig.FLAP_VY / 8;
    public const long SPEEDS = 24;
    public const long BUCKET_X = 40 * SimConfig.SUB;
    /// Ticks after the entry and before the exit that the band ignores (the
    /// tube fans out from one point at the entry and funnels into the portal).
    public const long SKIP_START = 90, SKIP_END = 40;
    /// A tap window this small or smaller counts as a precise tap (ticks).
    public const long TIGHT_WINDOW = 3;
    /// A route choice: viable heights split by at least this much (px).
    public const long SPLIT_PX = 24;
    public const long WINDOW_CAP = 30;

    const int DEAD = -1, EXIT = -2;

    struct Node
    {
        public int tap, no;      // slot of the child in the next layer (DEAD, EXIT)
        public int parent;       // slot of the node that made this copy in the layer before
        public bool by_tap;      // made by a tap
        public short yb;         // height bucket
        public bool can_tap;
    }

    public sealed class Result
    {
        public bool way;               // some line gets through
        public long ticks;             // ticks searched
        public long first_exit = -1;   // first tick a line gets through
        public long peak;              // most copies in a layer
        public long band_min, band_p10, band_med;   // px, over the measured ticks
        public double tight_s;         // seconds with a band under 60 px
        public double paths_bits;      // log2 viable tap sequences
        public double bits_per_s;
        public long line_window;       // tightest tap window on the most forgiving line (ticks)
        public long line_window_med;   // its median tap window
        public long line_taps;
        public long line_tight;        // its taps with a window <= TIGHT_WINDOW
        public double line_s;          // its length in seconds
        public double choice_s;        // seconds with two or more viable height groups
        public double viable_frac;     // viable copies / alive copies, mean over the measured ticks
    }

    /// Debug: a line per measured tick (tick, copies, viable, band px, height groups, viable y range).
    public Action<string> log;

    public Result run(GameSim start, long cap)
    {
        long room = start.state.room_index;
        var layers = new List<Node[]>();
        var frontier = new List<GameSim> { start.clone_deep() };
        var first = new Node { parent = -1, yb = (short)(start.state.y / BUCKET_H) };
        var cur = new List<Node> { first };
        var res = new Result();
        var slots = new Dictionary<long, int>();
        var next = new List<GameSim>();
        var next_nodes = new List<Node>();
        long t;
        for (t = 0; t < cap && frontier.Count > 0; t++)
        {
            slots.Clear();
            next.Clear();
            next_nodes.Clear();
            var nodes = cur.ToArray();
            for (int k = 0; k < frontier.Count; k++)
            {
                var s = frontier[k];
                bool can = s.state.vy * s.room.gravity > SurvivalSearch.TAP_BELOW_VY || !s.state.started;
                nodes[k].can_tap = can;
                nodes[k].tap = DEAD;
                nodes[k].no = DEAD;
                if (can)
                {
                    var c = s.clone_deep();
                    c.step(true);
                    nodes[k].tap = keep(slots, next, next_nodes, c, k, true, room);
                    if (nodes[k].tap == EXIT && res.first_exit < 0) res.first_exit = t + 1;
                }
                if (!s.state.started) continue;
                s.step(false);
                nodes[k].no = keep(slots, next, next_nodes, s, k, false, room);
                if (nodes[k].no == EXIT && res.first_exit < 0) res.first_exit = t + 1;
            }
            layers.Add(nodes);
            frontier = new List<GameSim>(next);
            cur = new List<Node>(next_nodes);
            res.peak = Math.Max(res.peak, frontier.Count);
        }
        // The last layer: still in the room at the cap, not a way through.
        var last = cur.ToArray();
        for (int k = 0; k < last.Length; k++) { last[k].tap = DEAD; last[k].no = DEAD; }
        layers.Add(last);
        res.ticks = t;
        analyse(layers, res, log, start.state.arrival_hold);
        return res;
    }

    static long key(GameSim s)
    {
        var st = s.state;
        long along = st.vy * s.room.gravity - SimConfig.FLAP_VY;
        long speed = G.clampi(along / BUCKET_VY, 0, SPEEDS - 1);
        long k = st.y / BUCKET_H;
        k = k * SPEEDS + speed;
        k = k * 64 + G.clampi(st.x / BUCKET_X, 0, 63);
        k = k * 2 + (st.vx > 0 ? 1 : 0);
        k = k * 2 + (s.room.gravity > 0 ? 1 : 0);
        return k;
    }

    static int keep(Dictionary<long, int> slots, List<GameSim> next, List<Node> nodes, GameSim s, int parent, bool tap, long room)
    {
        if (s.is_over()) return DEAD;
        if (Cases.cleared(s, room)) return EXIT;
        long k = key(s);
        var n = new Node { parent = parent, by_tap = tap, yb = (short)(s.state.y / BUCKET_H) };
        if (slots.TryGetValue(k, out int slot))
        {
            if (SurvivalSearch._better(s, next[slot]))
            {
                next[slot] = s;
                nodes[slot] = n;
            }
            return slot;
        }
        slots[k] = next.Count;
        next.Add(s);
        nodes.Add(n);
        return slot = next.Count - 1;
    }

    static void analyse(List<Node[]> layers, Result res, Action<string> log, long hold)
    {
        int L = layers.Count;
        var viable = new bool[L][];
        var tap_ok = new bool[L][];
        var no_ok = new bool[L][];
        var fw = new int[L][];
        for (int t = L - 1; t >= 0; t--)
        {
            var ns = layers[t];
            viable[t] = new bool[ns.Length];
            tap_ok[t] = new bool[ns.Length];
            no_ok[t] = new bool[ns.Length];
            fw[t] = new int[ns.Length];
            for (int k = 0; k < ns.Length; k++)
            {
                bool a = ns[k].tap == EXIT || (ns[k].tap >= 0 && viable[t + 1][ns[k].tap]);
                bool b = ns[k].no == EXIT || (ns[k].no >= 0 && viable[t + 1][ns[k].no]);
                tap_ok[t][k] = a;
                no_ok[t][k] = b;
                viable[t][k] = a || b;
                // Ticks from here on (no tap in between) at which a tap still leads through.
                fw[t][k] = a ? 1 + (b && ns[k].no >= 0 ? fw[t + 1][ns[k].no] : 0) : 0;
            }
        }
        res.way = viable[0][0];
        if (!res.way) return;

        // Forward: the earlier half of each tap window, and the viable path counts (log2).
        var bw = new int[L][];
        var logn = new double[L][];
        double exits = double.NegativeInfinity;
        for (int t = 0; t < L; t++)
        {
            var ns = layers[t];
            bw[t] = new int[ns.Length];
            if (logn[t] == null) logn[t] = Enumerable.Repeat(double.NegativeInfinity, ns.Length).ToArray();
            if (t == 0) logn[0][0] = 0;
            if (t + 1 < L) logn[t + 1] = Enumerable.Repeat(double.NegativeInfinity, layers[t + 1].Length).ToArray();
            for (int k = 0; k < ns.Length; k++)
            {
                if (!viable[t][k]) continue;
                int p = ns[k].parent;
                bool chain = t > 0 && p >= 0 && !ns[k].by_tap && viable[t - 1][p];
                bw[t][k] = tap_ok[t][k] ? 1 + (chain ? bw[t - 1][p] : 0) : 0;
                double me = logn[t][k];
                if (double.IsNegativeInfinity(me)) continue;
                foreach (var (child, ok) in new[] { (ns[k].tap, tap_ok[t][k]), (ns[k].no, no_ok[t][k]) })
                {
                    if (!ok) continue;
                    if (child == EXIT) exits = lse(exits, me);
                    else logn[t + 1][child] = lse(logn[t + 1][child], me);
                }
            }
        }
        res.paths_bits = exits;

        // Backward: the maximin line (widest tightest tap window).
        var best = new int[L][];
        var pick = new sbyte[L][]; // 1 tap, 0 no tap
        for (int t = L - 1; t >= 0; t--)
        {
            var ns = layers[t];
            best[t] = new int[ns.Length];
            pick[t] = new sbyte[ns.Length];
            for (int k = 0; k < ns.Length; k++)
            {
                if (!viable[t][k]) continue;
                int v_tap = -1, v_no = -1;
                if (tap_ok[t][k])
                {
                    int w = (int)Math.Min(WINDOW_CAP, fw[t][k] + bw[t][k] - 1);
                    int after = ns[k].tap == EXIT ? int.MaxValue : best[t + 1][ns[k].tap];
                    v_tap = Math.Min(w, after);
                }
                if (no_ok[t][k]) v_no = ns[k].no == EXIT ? int.MaxValue : best[t + 1][ns[k].no];
                // Ties: hold rather than tap (fewer taps).
                if (v_no >= v_tap) { best[t][k] = v_no; pick[t][k] = 0; }
                else { best[t][k] = v_tap; pick[t][k] = 1; }
            }
        }
        var windows = new List<long>();
        {
            int k = 0;
            for (int t = 0; t < L; t++)
            {
                var n = layers[t][k];
                int child;
                if (pick[t][k] == 1)
                {
                    windows.Add(Math.Min(WINDOW_CAP, fw[t][k] + bw[t][k] - 1));
                    child = n.tap;
                }
                else child = n.no;
                if (child == EXIT)
                {
                    res.line_s = (t + 1) / (double)SimConfig.TICKS_PER_SECOND;
                    break;
                }
                k = child;
            }
        }
        // The arrival tap (before the bird moves) isn't a timed tap.
        res.line_taps = windows.Count;
        res.line_window = windows.Count == 0 ? WINDOW_CAP : windows.Min();
        res.line_window_med = windows.Count == 0 ? WINDOW_CAP : windows.OrderBy(x => x).ElementAt(windows.Count / 2);
        res.line_tight = windows.Count(w => w <= TIGHT_WINDOW);
        res.bits_per_s = res.line_s > 0 ? res.paths_bits / Math.Max(1.0, res.first_exit / (double)SimConfig.TICKS_PER_SECOND) : 0;

        // Bands over the measured ticks: the end of the arrival hold + SKIP_START to the first exit - SKIP_END.
        long t0 = hold + SKIP_START;
        long t1 = Math.Max(t0 + 1, (res.first_exit < 0 ? L : res.first_exit) - SKIP_END);
        var bands = new List<long>();
        double fr = 0;
        long choice = 0, tight = 0;
        var ys = new HashSet<short>();
        for (int t = (int)t0; t < t1 && t < L; t++)
        {
            ys.Clear();
            int alive = layers[t].Length, v = 0;
            for (int k = 0; k < layers[t].Length; k++)
                if (viable[t][k]) { ys.Add(layers[t][k].yb); v++; }
            long band = ys.Count * BUCKET_H / SimConfig.SUB;
            bands.Add(band);
            if (band < 60) tight++;
            fr += alive == 0 ? 0 : v / (double)alive;
            if (groups(ys) >= 2) choice++;
            if (log != null && ys.Count > 0)
                log($"{t}	{alive}	{v}	{band}	{groups(ys)}	{ys.Min() * BUCKET_H / SimConfig.SUB}-{(ys.Max() + 1) * BUCKET_H / SimConfig.SUB}");
        }
        if (bands.Count == 0) bands.Add(0);
        bands.Sort();
        res.band_min = bands[0];
        res.band_p10 = bands[bands.Count / 10];
        res.band_med = bands[bands.Count / 2];
        res.tight_s = tight / (double)SimConfig.TICKS_PER_SECOND;
        res.choice_s = choice / (double)SimConfig.TICKS_PER_SECOND;
        res.viable_frac = fr / Math.Max(1, bands.Count);
    }

    static int groups(HashSet<short> ys)
    {
        if (ys.Count == 0) return 0;
        var s = ys.OrderBy(x => x).ToList();
        int g = 1;
        long split = SPLIT_PX * SimConfig.SUB / BUCKET_H;
        for (int i = 1; i < s.Count; i++)
            if (s[i] - s[i - 1] > split) g++;
        return g;
    }

    static double lse(double a, double b)
    {
        if (double.IsNegativeInfinity(a)) return b;
        if (double.IsNegativeInfinity(b)) return a;
        double m = Math.Max(a, b);
        return m + Math.Log2(Math.Pow(2, a - m) + Math.Pow(2, b - m));
    }
}
