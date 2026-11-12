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
    /// Ticks between looks when the last look was calm, and when it was not
    /// (no line in some guessed future, or only a fine / shorter line).
    public int replan = 4, replan_danger = 1;
    /// Guessed futures per look, lines compared per look, and the tap timing
    /// error (ticks early and late) a line is tried with. The line played is
    /// the one that lives in the most (future, timing) trials; then the cheapest.
    public int copies = 1, lines = 1, wobble = 0;
    /// Lines differ when they part within this many ticks.
    public int part = 16;
    /// Two-stage look (0 = off): the next wall is unknown until the bounce, so
    /// the bird should reach this wall where most next walls stay reachable.
    /// Stage one finds lines to just before the bounce, one per `band` px of
    /// height there (`lines` of them). Stage two gives each of them `copies`
    /// guessed futures and asks whether some line lives `after` ticks in each
    /// (a coarse search). The line with the most futures alive is played.
    public long after = 0, band = 40, coarse_px = 12, coarse_speeds = 4;
    /// Cost per tick of each px away from the middle height, and per tap (px).
    public long mid_cost = 1, tap_cost = 0;
    /// Extra cost per tick while a bird `margin` px higher or lower would die (0 = not checked).
    public long margin = 0, margin_cost = 40;
    /// The margin also counts the spikes of the wall ahead, the ceiling and the floor.
    public bool spike_margin = false;
    /// The taps planned for the next ticks (read only; the human layer lands them with timing noise).
    public IReadOnlyCollection<bool> plan => _plan;
    /// One-sided stalactite fangs re-aim at every bounce. In an imagined bounce
    /// the planner takes the worst case: 1 = the column met first comes out as
    /// far as the rule allows, 2 = both columns do. 0 = whatever the copy draws.
    public int worst_fangs = 1;
    /// Rules from the death traces (research/families/*.md), each with a switch:
    /// no_pingpong: a line may not bounce twice on the same wall so that the
    ///   exit opens there, unless its preview was on screen when the look began
    ///   (its height is a guess until then; the wall fills with spikes around it).
    /// keep_plan: when no line lives the whole look, the rest of the old plan
    ///   stays if it still lives in the new copy.
    /// bounce_look: a new look at every change of direction.
    /// wide_key: the bucket also holds the flight direction and x (bumpers and
    ///   wind send lines to different places at the same height).
    /// aim_exit: the height cost pulls to an exit that is on screen instead of the middle.
    /// wall_look: when no line lives the whole look, search to just past the
    ///   wall ahead (the part with nothing to guess) with coarse, fine and
    ///   very fine buckets before trying shorter looks.
    /// full_speeds: the speed buckets span the whole range of fall speeds
    ///   (before, every fall above 3.3 px a tick shared one bucket).
    /// aim_anchor: with no exit on screen the height cost pulls to the room's
    ///   anchor (the next gaps are drawn around it) instead of the middle.
    public bool wall_look = true, full_speeds = true, aim_anchor = false;
    public long wall_looks;
    public bool no_pingpong = true, keep_plan = true, bounce_look = true, wide_key = true, aim_exit = true;
    public long kept_plans;
    /// Buckets: one survivor per height (px) and speed bucket; the finer set is tried when the first finds no line.
    public long bucket_px = 8, speed_buckets = 6, fine_px = 3, fine_speeds = 12;

    readonly SimRng _own;
    readonly Queue<bool> _plan = new();
    int _since = int.MaxValue;
    int _wait = 1;
    long _bounce_y = -1, _vx;
    readonly List<(byte[] taps, long cost, GameSim sim)> _found = new();
    public long two_stage_looks;
    /// How the last look ended: 0 = a line for the whole look, 1 = only with fine buckets, 2 = only a shorter look, 3 = none.
    public int last_look;
    /// In how many of the guessed futures the played line lived (of `copies`).
    public int last_agree;
    public long looks, fine_looks, short_looks, no_looks, split_looks;

    public BlindPlanner(long seed) => _own = new SimRng(977 * seed + 5);

    public bool decide(GameSim sim)
    {
        if (!sim.state.started) return true;
        // The height at the last bounce: a player remembers it (stalactite gaps slide to it).
        if (sim.state.vx != _vx)
        {
            if (_vx != 0) _bounce_y = sim.state.y;
            if (_vx != 0 && bounce_look) _since = int.MaxValue;
            _vx = sim.state.vx;
        }
        if (_since >= _wait || _plan.Count == 0) look(sim);
        _since++;
        bool tap = _plan.Count > 0 && _plan.Dequeue();
        // The sim ignores taps during the wait out of a portal: don't make them.
        return tap && sim.state.arrival_hold == 0;
    }

    void look(GameSim sim)
    {
        long want = Math.Min(horizon, sim.steps_to_wall(sim.state.vx > 0 ? 1 : 0) + past);
        looks++;
        last_look = 0;
        int n = Math.Max(1, copies);
        var seeds = new long[n];
        for (int j = 0; j < n; j++) seeds[j] = _own.next_u32();
        GameSim copy(int j) => blind_copy(sim, new SimRng(seeds[j]), _bounce_y);
        long to_wall = sim.steps_to_wall(sim.state.vx > 0 ? 1 : 0);
        if (after > 0 && to_wall >= 3 && to_wall - 1 <= horizon)
        {
            beam(copy(0), to_wall - 1, bucket_px, speed_buckets, band);
            if (_found.Count > 0)
            {
                two_stage_looks++;
                var cands = _found.ToList();
                byte[] pick = null;
                int pick_ok = -1;
                long pick_cost = 0;
                foreach (var (taps, cost, at) in cands)
                {
                    int ok = 0;
                    for (int j = 0; j < n; j++)
                    {
                        beam(blind_copy(at, new SimRng(seeds[j] + 1), _bounce_y), after, coarse_px, coarse_speeds, 0, true);
                        if (_found.Count > 0) ok++;
                    }
                    if (ok > pick_ok || (ok == pick_ok && cost < pick_cost))
                    {
                        pick = taps;
                        pick_ok = ok;
                        pick_cost = cost;
                    }
                    if (ok == n) break;
                }
                last_agree = pick_ok;
                if (pick_ok < n) split_looks++;
                _wait = pick_ok < n ? replan_danger : replan;
                _plan.Clear();
                foreach (byte b in pick) _plan.Enqueue(b != 0);
                _since = 0;
                return;
            }
        }
        // Lines from the first guessed future (fine buckets when the coarse ones find none).
        beam(copy(0), want, bucket_px, speed_buckets);
        if (_found.Count == 0 && fine_px > 0)
        {
            last_look = 1;
            fine_looks++;
            beam(copy(0), want, fine_px, fine_speeds);
        }
        byte[] found = null;
        last_agree = 0;
        int trials = n * (1 + 2 * (wobble > 0 ? 1 : 0));
        if (_found.Count > 0 && trials == 1)
        {
            found = _found[0].taps;
            last_agree = 1;
        }
        else if (_found.Count > 0)
        {
            long best_cost = 0;
            foreach (var (taps, cost, _) in _found.ToList())
            {
                int ok = 0;
                for (int j = 0; j < n; j++)
                    for (int w = -1; w <= 1; w++)
                    {
                        if (w != 0 && wobble == 0) continue;
                        if (lives(copy(j), taps, w * wobble)) ok++;
                    }
                if (found == null || ok > last_agree || (ok == last_agree && cost < best_cost))
                {
                    found = taps;
                    last_agree = ok;
                    best_cost = cost;
                }
            }
        }
        if (found == null && keep_plan && _plan.Count >= 8)
        {
            var rest = _plan.Select(b => (byte)(b ? 1 : 0)).ToArray();
            if (lives(copy(0), rest, 0))
            {
                kept_plans++;
                last_look = 2;
                short_looks++;
                _wait = replan_danger;
                _since = 0;
                return;
            }
        }
        if (found == null && wall_look && to_wall + 26 < want)
        {
            foreach (var (px, sp) in new[] { (bucket_px, speed_buckets), (fine_px, fine_speeds), (2L, 40L) })
            {
                beam(copy(0), to_wall + 26, px, sp);
                if (_found.Count == 0) continue;
                found = _found[0].taps;
                last_look = 2;
                wall_looks++;
                break;
            }
        }
        for (long t = want * 3 / 4; t >= 2 && found == null; t = t * 3 / 4)
        {
            last_look = 2;
            beam(copy(0), t, bucket_px, speed_buckets);
            if (_found.Count == 0 && fine_px > 0 && keep_plan) beam(copy(0), t, fine_px, fine_speeds);
            if (_found.Count > 0) found = _found[0].taps;
        }
        if (last_look == 2) short_looks++;
        if (found == null)
        {
            last_look = 3;
            no_looks++;
        }
        bool danger = last_look != 0 || last_agree < trials;
        if (last_look == 0 && last_agree < trials) split_looks++;
        _wait = danger ? replan_danger : replan;
        _plan.Clear();
        if (found != null)
            foreach (byte b in found) _plan.Enqueue(b != 0);
        _since = 0;
    }

    /// After a bounce in a copy: one-sided fangs aim as far out as their rule
    /// allows (within REACH of the anchor for the column met first, MAX_STEP
    /// past that for the other when `both`).
    static void fangs_out(GameSim c, bool both)
    {
        List<Stalactite> cols = null;
        foreach (var hz in c.room.hazards)
            if (hz is Stalactite st && st.fixed_lo < 0 && st.top != st.bottom) (cols ??= new()).Add(st);
        if (cols == null) return;
        cols.Sort((p, q) => c.state.vx > 0 ? p.x.CompareTo(q.x) : q.x.CompareTo(p.x));
        long center = c.state.anchor_y, spread = Stalactite.REACH;
        for (int i = 0; i < cols.Count; i++)
        {
            var st = cols[i];
            if (i == 0 || both)
                st.target_y = st.bottom ? Math.Max(Stalactite.GAP_MIN, center - spread) : Math.Min(Stalactite.GAP_MAX, center + spread);
            center = st.target_y;
            spread = Stalactite.MAX_STEP;
        }
    }

    /// Whether the bird lives through `taps` on `c`, with every tap `shift` ticks late (early if negative).
    static bool lives(GameSim c, byte[] taps, int shift)
    {
        for (int t = 0; t < taps.Length; t++)
        {
            int from = t - shift;
            c.step(from >= 0 && from < taps.Length && taps[from] != 0);
            if (c.is_over()) return false;
        }
        return true;
    }

    /// A copy of `sim` with every hidden random value replaced by `own`'s.
    /// `bounce_y`: the bird's height at its last bounce if the player saw it (-1 = not).
    public static GameSim blind_copy(GameSim sim, SimRng own, long bounce_y = -1)
    {
        var c = sim.clone_deep();
        c._rng = new SimRng(own.next_u32());
        // Seed-only generation: each wall reseeds from the room's seed, the
        // spine picks the next rooms, and the exits are planned from the room's
        // seed at room start. All three are hidden: replace them and plan again
        // (plan_room keeps an exit already on screen as it is).
        c.room.rng_seed = own.next_u32();
        c._spine = new SimRng(own.next_u32());
        if (c.state.plan_at != 0) ExitPlanner.plan_room(c, c.state.plan_at);
        // Sliding stalactite gaps: the column the bird met first slides to
        // within REACH of the height it bounced at, the other to within
        // MAX_STEP of that (the room's rule, which a player learns).
        // On seed-only generation the room slides them to state.anchor_y (the
        // exit taken or the open run on the last wall: on screen), so that is used.
        bounce_y = c.state.anchor_y;
        if (bounce_y >= 0)
        {
            var cols = c.room.hazards.OfType<Stalactite>().Where(st => st.fixed_lo < 0).ToList();
            cols.Sort((p, q) => c.state.vx > 0 ? p.x.CompareTo(q.x) : q.x.CompareTo(p.x));
            long center = bounce_y, spread = Stalactite.REACH;
            foreach (var st in cols)
            {
                if (st.gap_y != st.target_y)
                {
                    long lo = Math.Max(Stalactite.GAP_MIN, center - spread), hi = Math.Min(Stalactite.GAP_MAX, center + spread);
                    // Only the side it is seen sliding to.
                    if (st.target_y > st.gap_y) lo = Math.Max(lo, st.gap_y + 1);
                    else hi = Math.Min(hi, st.gap_y - 1);
                    // A fang from one side only: the worst case (its tip as far out as it may go).
                    if (lo > hi) st.target_y = st.gap_y + (st.target_y > st.gap_y ? 1 : -1) * own.next_below(Stalactite.SLIDE * 8 + 1);
                    else if (st.bottom && !st.top) st.target_y = lo;
                    else if (st.top && !st.bottom) st.target_y = hi;
                    else st.target_y = lo + own.next_below(hi - lo + 1);
                }
                center = st.target_y;
                spread = Stalactite.MAX_STEP;
            }
        }
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
                case Bubble b:
                    b.next_x = Bubble.MIN_X + own.next_below(Bubble.MAX_X - Bubble.MIN_X + 1);
                    // A late spiky bubble under the floor: its glow (bubble_painter.gd) is
                    // under half size until 3 * WARN ticks before it rises.
                    if (b.spiked && b.wait > 3 * Bubble.WARN) b.x = Bubble.MIN_X + own.next_below(Bubble.MAX_X - Bubble.MIN_X + 1);
                    break;
                // Where a sliding gap stops: the side it slides to is visible, how far is not.
                case Stalactite st when st.gap_y != st.target_y && (bounce_y < 0 || st.fixed_lo >= 0):
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
                    // Sorted first, so the result does not depend on the true order.
                    var waits = idle.Select(i => bm.delays[i]).OrderBy(x => x).ToList();
                    for (int i = 0; i < idle.Count; i++) bm.delays[idle[i]] = waits[i];
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

    /// Fills `_found` with up to `lines` lines that live `ticks` ticks,
    /// cheapest first: the cheapest of each family of lines that share their first `part` ticks.
    /// With `by_band` > 0: the cheapest line per `by_band` px of end height instead.
    /// With `any`: stops at the first line found (only "is there one").
    void beam(GameSim root, long ticks, long bpx, long speeds, long by_band = 0, bool any = false)
    {
        _found.Clear();
        var layer = new List<int>();
        long bh = bpx * SimConfig.SUB;
        long bvy = full_speeds ? (SimConfig.MAX_FALL_VY - SimConfig.FLAP_VY) / speeds + 1 : -SimConfig.FLAP_VY * 2 / speeds;
        long mid = (SimConfig.KILL_TOP + SimConfig.KILL_BOTTOM) / 2;
        bool exit_shown = root.state.exit_open || root.state.exit_preview;
        if (aim_exit && exit_shown) mid = root.state.exit_a_y;
        else if (aim_anchor) mid = root.state.anchor_y;
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
                long vx0 = e.sim.state.vx, room0 = e.sim.state.room_index;
                bool e_open = e.sim.state.exit_open;
                for (int a = can_tap ? 1 : 0; a >= 0; a--)
                {
                    var s = a == 1 ? e.sim.clone_deep() : e.sim;
                    s.step(a == 1);
                    if (s.is_over()) continue;
                    // The exit opened on the wall the bird just bounced off, at a height nobody has seen.
                    if (no_pingpong && !exit_shown && s.state.exit_open && !e_open && s.state.exit_side == (s.state.vx > 0 ? 0 : 1)) continue;
                    if (worst_fangs > 0 && (s.state.vx != vx0 || s.state.room_index != room0)) fangs_out(s, worst_fangs > 1);
                    var st = s.state;
                    long cost = e.cost + Math.Abs(st.y - mid) / SimConfig.SUB * mid_cost + a * tap_cost;
                    if (margin > 0 && near_death(s)) cost += margin_cost;
                    long along = st.vy * s.room.gravity - SimConfig.FLAP_VY;
                    long speed = G.clampi(along / bvy, 0, speeds - 1);
                    long key = (st.room_index * 1000 + st.y / bh) * speeds + speed;
                    if (wide_key) key = (key * 64 + st.x / (16 * SimConfig.SUB)) * 2 + (st.vx > 0 ? 1 : 0);
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
            if (next.Count == 0) return;
            layer.Add(parents.Count);
            frontier = new List<Node>(next.Count);
            foreach (var e in next)
            {
                parents.Add(e.parent);
                taps.Add(e.tap);
                frontier.Add(new Node { sim = e.sim, parent = parents.Count - 1, cost = e.cost });
            }
        }
        if (any)
        {
            _found.Add((Array.Empty<byte>(), 0, null));
            return;
        }
        // The family of a line: its node `part` ticks in.
        long depth = Math.Min(part, ticks) - 1;
        int family_end = depth + 1 < layer.Count ? layer[(int)depth + 1] : parents.Count;
        long room = frontier.Max(e => e.sim.state.room_index);
        var best = new Dictionary<int, Node>();
        foreach (var e in frontier)
        {
            if (e.sim.state.room_index != room) continue;
            int f = e.parent;
            if (by_band > 0) f = (int)(e.sim.state.y / (by_band * SimConfig.SUB));
            else
                while (f >= family_end) f = parents[f];
            if (!best.TryGetValue(f, out var have) || e.cost < have.cost) best[f] = e;
        }
        foreach (var e in best.Values.OrderBy(e => e.cost).Take(Math.Max(1, lines)))
        {
            var out_ = new List<byte>();
            for (int nd = e.parent; nd >= 0; nd = parents[nd]) out_.Add(taps[nd]);
            out_.Reverse();
            _found.Add((out_.ToArray(), e.cost, e.sim));
        }
    }

    static bool near_spikes(GameSim s, long y, long m)
    {
        var st = s.state;
        long r = SimConfig.BIRD_RADIUS;
        if (y - m - r <= SimConfig.KILL_TOP || y + m + r >= SimConfig.KILL_BOTTOM) return true;
        long side = st.vx > 0 ? 1 : 0;
        long dist = (side == 1 ? s.room.wall_right() - st.x : st.x - s.room.wall_left()) - r;
        if (dist > s.room.max_spike_depth()) return false;
        long mask = s.wall_mask(side);
        if (mask == 0) return false;
        long shift = s.wall_shift(side), hb = s.room.spike_half_base();
        return Rl.Observer.wall_hits(mask, shift, hb, y - m) || Rl.Observer.wall_hits(mask, shift, hb, y + m);
    }

    /// Whether a bird `margin` px above or below this one would be killed by a hazard now
    /// (or, with `spike_margin`, by the spikes of the wall ahead, the ceiling or the floor).
    bool near_death(GameSim s)
    {
        var hz = s.room.hazards;
        long y = s.state.y;
        if (spike_margin && near_spikes(s, y, margin * SimConfig.SUB)) return true;
        if (hz.Count == 0) return false;
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
