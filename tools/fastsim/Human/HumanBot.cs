namespace FastSim.Human;

/// The human limits of one skill level (docs/HUMAN_BOT.md). Ticks are 1/60 s.
public sealed record Skill(
    double lag,       // ticks from deciding to the earliest tap that decision can place (reaction time)
    double think,     // ticks between two looks at the screen (re-plans)
    double horizon,   // ticks the habits look ahead
    double jitter,    // sd of the tap's timing error, ticks (motor noise)
    double perr,      // sd of the misjudged own height, px (fresh at each look)
    double lapse,     // chance a look is skipped (attention lapse: the old plan runs out)
    double comfort,   // weight of staying near the comfort height (px of cost per px)
    double tapcost,   // cost per tap (players don't tap for no reason)
    double margin,    // px of room the habits want around the imagined flight (checked at +-margin)
    double focus,     // ticks of the careful search when every habit dies (0 = none)
    double plan,      // ticks of the careful search used at every look (0 = habits first)
    double width)     // lines the careful search juggles per tick
{
    /// Skill knob s in 0..1 (0 = weakest, 1 = beast). Every limit moves together.
    public static Skill at(double s)
    {
        double k = Math.Clamp(1.0 - s, 0.0, 1.0);
        return new Skill(
            lag: 1 + 10 * k,
            think: 4 + 4 * k,
            horizon: 70 - 30 * k,
            jitter: 1.5 * k,
            perr: 5 * k,
            lapse: 0.02 * k,
            comfort: 1.0,
            tapcost: 4,
            margin: 10 * Math.Min(1, 4 * k),
            focus: 0,
            plan: 120 - 50 * k,
            width: 32);
    }

    public override string ToString() =>
        $"lag {lag:F1}, think {think:F1}, plan {plan:F0}, jitter {jitter:F2}, perr {perr:F1}px, lapse {lapse:F3}";
}

/// A player model on top of a short look-ahead: it looks at the screen every
/// `think` ticks, imagines a few ways to fly on (aim at the gap a bit higher or
/// lower, tap now or wait), and keeps the one that lives and stays near its
/// comfort height. Human limits: a decision lands no earlier than `lag` ticks
/// later, taps land with timing noise, the own height is misjudged, looks can
/// be skipped, and it never uses what is not on screen yet: the imagined
/// flight stops at the next bounce (new spikes appear there) and at a room change.
public sealed class HumanBot
{
    public const long PX = SimConfig.SUB;
    public const long MID = (SimConfig.KILL_TOP + SimConfig.KILL_BOTTOM) / 2;
    public const long MIN_GAP = 6;
    public static double MIDPULL = 0.25;
    /// Experiments only: let the imagined flight see spikes before they are up.
    public static bool FORESIGHT = false;
    /// Experiments: ticks of the careful search used for every look (0 = habits first).
    public static long BEAM = 0;
    public static long SPEEDS = 6;
    /// Most lines the careful search keeps per tick (0 = all buckets).
    public static long WIDTH = 0;
    /// How many finer searches to try when the coarse one finds no line (0..2).
    public static int ESCALATE = 2;
    /// Aim at the gap's point nearest mid screen (else the gap's centre).
    public static bool GAPMID = false;
    /// px of margin the careful search wants (-1 = the skill's margin).
    public static double BMARGIN = -1; // ticks: a thumb can't tap faster than ~10 per second

    static readonly long[] OFFSETS = { -90, -60, -30, 0, 30, 60, 90 };
    // First move after the lag: -1 = aim at once, 0 = tap at once, w > 0 = hold w ticks.
    static readonly long[] FIRSTS = { -1, 0, 6, 14, 24 };

    readonly Skill _k;
    readonly Random _rng;
    readonly SortedSet<long> _intended = new(); // taps the player decided on (their own mental tick)
    readonly Dictionary<long, long> _actual = new(); // intended tick -> tick the tap lands
    readonly HashSet<long> _fire = new();
    long _next_think;
    long _last_tap = -100;
    public long thinks, lapses, focuses, escalations;

    public HumanBot(Skill k, long seed)
    {
        _k = k;
        _rng = new Random(unchecked((int)(seed * 2654435761L) ^ 0x2545F491));
    }

    double gauss()
    {
        double u = 1.0 - _rng.NextDouble(), v = _rng.NextDouble();
        return Math.Sqrt(-2 * Math.Log(u)) * Math.Cos(2 * Math.PI * v);
    }

    public bool decide(GameSim sim)
    {
        var s = sim.state;
        if (!s.started) return true;
        long t = s.tick;
        if (t >= _next_think)
        {
            think(sim);
            double gap = _k.think * (0.7 + 0.6 * _rng.NextDouble());
            _next_think = t + Math.Max(1, (long)Math.Round(gap));
        }
        bool tap = _fire.Remove(t);
        if (tap) _last_tap = t;
        return tap;
    }

    void think(GameSim sim)
    {
        long t = sim.state.tick;
        thinks++;
        if (_rng.NextDouble() < _k.lapse)
        {
            lapses++;
            return;
        }
        long lag = Math.Max(1, (long)Math.Round(_k.lag));
        long lockt = t + lag;
        // Taps decided before lockt stay; later ones are re-decided now.
        foreach (long i in _intended.Where(i => i >= lockt).ToList())
        {
            _intended.Remove(i);
            if (_actual.Remove(i, out long a)) _fire.Remove(a);
        }
        long perr = (long)Math.Round(gauss() * _k.perr * PX);
        long horizon = Math.Max(lag + 4, (long)Math.Round(_k.horizon));
        double best = double.NegativeInfinity;
        List<long> best_taps = null;
        long plan = BEAM > 0 ? BEAM : (long)Math.Round(_k.plan);
        if (plan > 0)
        {
            best_taps = focus(sim, perr, lockt, plan);
            if (best_taps != null) best = 1e6;
        }
        if (best_taps == null)
        foreach (long first in FIRSTS)
            foreach (long off in OFFSETS)
            {
                var taps = new List<long>();
                long m = (long)Math.Round(_k.margin * PX);
                double v = rollout(sim, perr - m, lockt, horizon, first, off * PX, taps);
                if (m > 0 && v > best)
                    v = Math.Min(v, rollout(sim, perr + m, lockt, horizon, first, off * PX, new List<long>()));
                if (v > best)
                {
                    best = v;
                    best_taps = taps;
                }
            }
        // Every habit dies: the player concentrates (a finer search over taps).
        if (best < 1e6 && _k.focus > 0)
        {
            focuses++;
            var f = focus(sim, perr, lockt, (long)Math.Round(_k.focus));
            if (f != null) best_taps = f;
        }
        // Commit the taps up to the next look (+ lag): the rest is re-planned then.
        long until = lockt + (long)Math.Ceiling(_k.think * 1.3) + 1;
        foreach (long i in best_taps)
        {
            if (i >= until) break;
            _intended.Add(i);
            long a = i + (long)Math.Round(gauss() * _k.jitter);
            a = Math.Max(a, t + 1);
            while (_fire.Contains(a)) a++;
            _actual[i] = a;
            _fire.Add(a);
        }
        _intended.RemoveWhere(i => i < t - 200);
    }

    struct Node
    {
        public GameSim sim;
        public int parent;
        public long tap_tick; // -1 = no tap at this node
        public long last;
        public double cost;
    }

    /// A careful search: from the locked-in taps on, every tick tap or not,
    /// one survivor kept per height x speed bucket (the one nearest its comfort
    /// height). The same rules as the habits: spikes not yet up are unknown,
    /// a new room ends the look. Returns the taps of the best line, or null.
    List<long> focus(GameSim sim, long perr, long lockt, long ticks)
    {
        // Coarse first; if no line lives, look harder (finer, wider).
        var r = focus_at(sim, perr, lockt, ticks, 8 * PX, SPEEDS, WIDTH > 0 ? WIDTH : (long)Math.Round(_k.width));
        for (int lv = 0; r == null && lv < ESCALATE; lv++)
        {
            escalations++;
            r = lv == 0 ? focus_at(sim, perr, lockt, ticks, 4 * PX, 12, 160) : focus_at(sim, perr, lockt, ticks, 2 * PX, 24, 0);
        }
        return r;
    }

    List<long> focus_at(GameSim sim, long perr, long lockt, long ticks, long BH, long speeds, long width)
    {
        long bm = (long)Math.Round((BMARGIN >= 0 ? BMARGIN : _k.margin) * PX);
        var c = sim.clone_deep();
        c.state.y += perr;
        long score0 = c.state.score, room0 = c.state.room_index;
        long last = _last_tap;
        while (c.state.tick < lockt)
        {
            bool tap = _intended.Contains(c.state.tick);
            if (tap) last = c.state.tick;
            c.step(tap);
            if (c.is_over()) return null;
            if (c.state.room_index != room0) return null;
        }
        var nodes = new List<Node> { new Node { sim = c, parent = -1, tap_tick = -1, last = last } };
        var frontier = new List<int> { 0 };
        var slots = new Dictionary<long, int>();
        var next = new List<int>();
        var done = new List<int>();
        long BV = Math.Max(1, (-SimConfig.FLAP_VY / 2) * 6 / speeds);
        for (long t = 0; t < ticks && frontier.Count > 0; t++)
        {
            slots.Clear();
            next.Clear();
            foreach (int ni in frontier)
            {
                var e = nodes[ni];
                long u = e.sim.state.tick;
                long grav = e.sim.room.gravity;
                bool can_tap = u - e.last >= MIN_GAP && e.sim.state.vy * grav > SurvivalSearch.TAP_BELOW_VY;
                for (int k = can_tap ? 0 : 1; k < 2; k++)
                {
                    bool tap = k == 0;
                    var s2 = tap ? e.sim.clone_deep() : e.sim;
                    s2.step(tap);
                    bool bounced = s2.state.score != score0;
                    if (s2.is_over())
                    {
                        if (FORESIGHT || !(bounced && ahead_spike(s2))) continue;
                    }
                    var n = new Node
                    {
                        sim = s2, parent = ni, tap_tick = tap ? u : -1, last = tap ? u : e.last,
                        cost = e.cost + (s2.is_over() ? 0 : comfort_cost(s2, bounced && !FORESIGHT)),
                    };
                    if (bm > 0 && !s2.is_over() && tight(s2, bm, bounced && !FORESIGHT)) n.cost += TIGHT_COST;
                    nodes.Add(n);
                    int id = nodes.Count - 1;
                    if (s2.is_over() || s2.state.room_index != room0)
                    {
                        done.Add(id);
                        continue;
                    }
                    long along = s2.state.vy * grav - SimConfig.FLAP_VY;
                    long key = (s2.state.y / BH) * 64 + G.clampi(along / BV, 0, speeds - 1) + (bounced ? 1L << 40 : 0);
                    if (slots.TryGetValue(key, out int at))
                    {
                        if (n.cost < nodes[next[at]].cost) next[at] = id;
                    }
                    else
                    {
                        slots[key] = next.Count;
                        next.Add(id);
                    }
                }
            }
            if (width > 0 && next.Count > width)
            {
                next.Sort((a, b) => nodes[a].cost.CompareTo(nodes[b].cost));
                next.RemoveRange((int)width, next.Count - (int)width);
            }
            frontier = new List<int>(next);
        }
        int bestn = -1;
        foreach (int ni in frontier.Concat(done))
            if (bestn < 0 || nodes[ni].cost < nodes[bestn].cost) bestn = ni;
        if (bestn < 0) return null;
        var taps = new List<long>();
        for (int ni = bestn; ni >= 0; ni = nodes[ni].parent)
            if (nodes[ni].tap_tick >= 0) taps.Add(nodes[ni].tap_tick);
        taps.Reverse();
        return taps;
    }

    public const double TIGHT_COST = 400;

    /// Whether the bird `m` above or below where it is would be dead: a
    /// hazard, the ceiling or floor, or (unless they went up after the last
    /// look) the spikes of the wall ahead. Puts the bird back.
    static bool tight(GameSim c, long m, bool unseen)
    {
        var saved = c.state.copy();
        var st = c.state;
        long r = SimConfig.BIRD_RADIUS;
        long y0 = st.y;
        long side = st.vx > 0 ? 1 : 0;
        long left = c.room.wall_left(), right = c.room.wall_right();
        long dist = (side == 1 ? right - st.x : st.x - left) - r;
        bool near_wall = !unseen && dist <= c.room.max_spike_depth();
        long mask = near_wall ? c.wall_mask(side) : 0;
        long shift = near_wall ? c.wall_shift(side) : 0;
        long hb = c.room.spike_half_base();
        bool bad = false;
        var hz = c.room.hazards;
        for (int d = -1; d <= 1 && !bad; d += 2)
        {
            long y = y0 + d * m;
            if (y - r <= SimConfig.KILL_TOP || y + r >= SimConfig.KILL_BOTTOM) { bad = true; break; }
            if (near_wall && mask != 0 && Rl.Observer.wall_hits(mask, shift, hb, y)) { bad = true; break; }
            st.y = y;
            for (int h = 0; h < hz.Count; h++)
                if (hz[h].alive && hz[h].kills(c)) { bad = true; break; }
        }
        c.state = saved;
        return bad;
    }

    /// Value of one imagined way to fly (higher is better). Taps it makes at or
    /// after lockt go to `taps`.
    double rollout(GameSim sim, long perr, long lockt, long horizon, long first, long off, List<long> taps)
    {
        var c = sim.clone_deep();
        c.state.y += perr;
        long t0 = c.state.tick;
        long score0 = c.state.score;
        long room0 = c.state.room_index;
        long last = _last_tap;
        double cost = 0;
        long n = 0;
        bool lived = true;
        for (long i = 0; i < horizon; i++)
        {
            long u = t0 + i;
            bool tap;
            if (u < lockt) tap = _intended.Contains(u);
            else
            {
                long k = u - lockt;
                if (first == 0 && k == 0) tap = true;
                else if (first > 0 && k < first) tap = false;
                else tap = aim(c, off, !FORESIGHT && c.state.score != score0);
                if (u - last < MIN_GAP) tap = false;
                if (tap) taps.Add(u);
            }
            if (tap) last = u;
            c.step(tap);
            n++;
            if (c.is_over())
            {
                // Spikes put up at the bounce were not on screen when the
                // player looked: a death on them is not something they foresee.
                long dc = c.state.death_cause;
                bool unseen = !FORESIGHT && c.state.score != score0 && ahead_spike(c);
                lived = unseen;
                break;
            }
            cost += comfort_cost(c, !FORESIGHT && c.state.score != score0);
            // A new room is not on screen yet: stop imagining.
            if (c.state.room_index != room0) break;
        }
        double v = lived ? 1e6 : n * 1000.0;
        v -= _k.comfort * cost / Math.Max(1, n);
        v -= _k.tapcost * taps.Count;
        return v;
    }

    /// Died on the spikes of the wall it flies to (put up at the last bounce).
    static bool ahead_spike(GameSim c)
    {
        long dc = c.state.death_cause;
        return (dc == DeathCause.SPIKE_LEFT && c.state.vx < 0) || (dc == DeathCause.SPIKE_RIGHT && c.state.vx > 0);
    }

    /// Where the player likes to be: the gap (or exit) on the wall ahead, pulled
    /// a bit toward the middle of the screen; flying near the floor or ceiling
    /// costs extra.
    static double comfort_cost(GameSim c, bool unseen)
    {
        double y = c.state.y / (double)PX;
        double want = (unseen ? MID : target(c)) / (double)PX;
        double mid = (SimConfig.KILL_TOP + SimConfig.KILL_BOTTOM) / 2.0 / PX;
        // Just after a bounce the player drifts to the middle (any gap can come);
        // nearing the wall it lines up with the gap.
        double left = c.room.wall_left(), right = c.room.wall_right();
        double far = c.state.vx > 0 ? (right - c.state.x) / (right - left) : (c.state.x - left) / (right - left);
        double pull = MIDPULL * Math.Clamp(far * 1.5 - 0.3, 0, 1);
        double pref = (1 - pull) * want + pull * mid;
        double cost = Math.Abs(y - pref);
        double top = y - SimConfig.KILL_TOP / (double)PX;
        double bottom = SimConfig.KILL_BOTTOM / (double)PX - y;
        if (top < 70) cost += (70 - top) * 2;
        if (bottom < 70) cost += (70 - bottom) * 2;
        return cost;
    }

    /// The point of the largest gap nearest mid screen (keeps the bird where
    /// any next gap is in reach), at least 36 px inside the gap.
    public static long gap_point(long mask, long shift)
    {
        long best_start = 0, best_len = 0, run_start = 0, run_len = 0;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            if (RoomRules.has_slot(mask, slot)) run_len = 0;
            else
            {
                if (run_len == 0) run_start = slot;
                run_len += 1;
                if (run_len > best_len)
                {
                    best_len = run_len;
                    best_start = run_start;
                }
            }
        }
        long top = SimConfig.SLOT_TOP + best_start * SimConfig.SLOT_SIZE + shift;
        long bottom = top + best_len * SimConfig.SLOT_SIZE;
        // An edge gap is open to the ceiling/floor kill line only in name.
        top = Math.Max(top, SimConfig.KILL_TOP + 20 * PX);
        bottom = Math.Min(bottom, SimConfig.KILL_BOTTOM - 20 * PX);
        long inset = 36 * PX;
        if (bottom - top <= 2 * inset) return (top + bottom) / 2;
        return Math.Clamp(MID, top + inset, bottom - inset);
    }

    public static long target(GameSim c)
    {
        var s = c.state;
        long side = s.vx > 0 ? 1 : 0;
        long y = GAPMID ? gap_point(c.wall_mask(side), c.wall_shift(side)) : PlannerBot.gap_center_y(c.wall_mask(side));
        if (s.exit_open && s.exit_side == side)
        {
            y = s.exit_a_y;
            if (s.exit_b_kind == ExitKind.WILD) y = s.exit_b_y;
        }
        return y;
    }

    /// The simple habit the player imagines flying with: keep above the target
    /// (plus an offset), tap when falling below it.
    static bool aim(GameSim c, long off, bool unseen)
    {
        var s = c.state;
        long goal = (unseen ? MID : target(c)) + off;
        long margin = 6 * PX;
        long g = c.room.gravity;
        // Below the goal: wait for the top of the hop. Far below: climb hard
        // (tap again once the rise slows to half a flap).
        long below = (s.y - goal) * g;
        long along = s.vy * g;
        if (below > 50 * PX) return along > SimConfig.FLAP_VY / 2;
        return below > margin && along >= 0;
    }
}
