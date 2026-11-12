namespace FastSim.Model;

/// A planner bot on the structured world model (docs/WORLD_MODEL.md). Each
/// tick it reads the present (WorldModel.Read), then searches tap/wait
/// sequences tick by tick: the bird's own path is exact physics, the hazards
/// move by their models. It never copies or steps the sim.
///
/// The search keeps the best path per (height, speed) bucket (a beam), drops
/// paths that die, charges a cost for passing inside the safety margin of
/// anything deadly or the ceiling and floor, and at the end prefers paths that
/// took the exit, then ones that bounced near the middle (the next wall's gap
/// is drawn near the bird's height, so the middle keeps the most options open).
///
/// Skill: human limits on top (reaction delay, tap timing noise, dropped taps,
/// a shorter look-ahead, a smaller margin, misjudged height), see Skill.
public sealed class WorldPlanner
{
    /// A skill level. delay: the bot sees the world this many ticks late (it
    /// replays its own taps since on the model, as a player knows what they
    /// pressed, so only what it could not foresee comes late); sigma: tap timing
    /// error, a tap lands |N(0, sigma)| ticks late; min_gap: at least this many
    /// ticks between taps (humans tap at most ~7.7 times a second); miss: chance a tap is
    /// dropped; horizon: look-ahead in ticks; margin_px: safety margin; beam:
    /// paths kept per tick; misjudge_px: the bird's height is misread by up to
    /// this much (a new error at every wall); slip: chance per wall of a bad
    /// misjudgement (3x).
    public sealed record Skill(string name, int delay, double sigma, double miss, int horizon, long margin_px, int beam,
        double misjudge_px, double slip, int min_gap = 0)
    {
        /// Every limit from one number: k = 1 is the planner with no limits (beast),
        /// k = 0 the most limited player (reacts 12 ticks late to what it could not
        /// foresee, tap timing error sigma 3 ticks, drops 2% of taps, looks 80 ticks
        /// ahead, misreads its height by up to 12 px). Below k = 1 taps are at
        /// least 8 ticks apart (a human's top tap rate). The tiers are k values calibrated to their target medians
        /// (`fastsim world calibrate`).
        public double k { get; init; } = 1;

        public static Skill At(string name, double k)
        {
            double u = 1 - Math.Clamp(k, 0, 1);
            return new Skill(name, (int)Math.Round(12 * u), 3 * u, 0.02 * u, (int)Math.Round(150 - 70 * u),
                (long)Math.Round(6 - 4 * u), (int)Math.Round(32 + 224 * (1 - u) * (1 - u)), 12 * u, 0.08 * u,
                u > 0 ? 8 : 0) { k = k };
        }

        // k per tier from `fastsim world calibrate 48 --cap 30000` on gameplay 21+
        // (seed-only generation): medians 32 / ~60 / 118 / 251 at k 0.81 / 0.88 / 0.922 / 0.99.
        public static readonly Skill BEAST = At("beast", 1);
        public static readonly Skill EXPERT = At("expert", 0.99);
        public static readonly Skill GOOD = At("good", 0.922);
        public static readonly Skill NORMAL = At("normal", 0.88);
        public static readonly Skill BEGINNER = At("beginner", 0.81);
        public static readonly Skill[] ALL = { BEGINNER, NORMAL, GOOD, EXPERT, BEAST };

        public static Skill Named(string n) => ALL.FirstOrDefault(s => s.name == n) ?? BEAST;

        public override string ToString() =>
            $"k {k:F3}: delay {delay}, sigma {sigma:F2}, min gap {min_gap}, miss {miss:F3}, horizon {horizon}, margin {margin_px}px, beam {beam}, misjudge {misjudge_px}px, slip {slip:F3}";
    }

    // Costs, in "px of distance" units.
    public const double NEAR_COST = 40;
    public const double NEAR_GUESS_COST = 80;
    public const double EDGE_ZONE = 70;
    public const double EDGE_COST = 0.6;
    public const double MIDDLE_COST = 0.35;
    public const double EXIT_BONUS = 100000;
    public const long POST_TICKS = 90;
    public const long MID_Y = (SimConfig.KILL_TOP + SimConfig.KILL_BOTTOM) / 2;

    readonly Skill _sk;
    readonly Random _noise;
    readonly List<WorldModel> _seen = new();
    readonly List<bool> _taps_since = new();
    long _pending_at = -1;
    long _bias;
    long _last_vx;
    long _last_tap = -1000;

    double Gauss()
    {
        double a = 1 - _noise.NextDouble(), b = _noise.NextDouble();
        return Math.Sqrt(-2 * Math.Log(a)) * Math.Cos(2 * Math.PI * b);
    }

    public long decisions, nodes_expanded;
    /// The last plan: paths that finished alive, the deepest tick (from now) at
    /// which a dying path that started with wait / tap died (-1: none died),
    /// paths still flying at the horizon, the best cost.
    public long last_done, last_deep_wait, last_deep_tap, last_left;
    public double last_best;
    public long[] last_causes = new long[6];
    /// The last plan's best final cost of the paths that start with wait / with
    /// a tap (lower is better; +infinity when every such path dies). The
    /// difference is how sure the choice is: near-equal costs mean both moves
    /// are fine, one infinite means only the other move lives (a decisive tick).
    public double last_cost_wait = double.PositiveInfinity, last_cost_tap = double.PositiveInfinity;
    public long last_bounced_deaths;

    public WorldPlanner(Skill skill, long seed)
    {
        _sk = skill;
        _noise = new Random(unchecked((int)(seed * 2654435761L) ^ 0x2f6b1d3));
    }

    public Skill skill => _sk;

    /// Tap this tick? Call once per tick with the sim as it is now (and the
    /// same Memory, updated once per tick before or by this call).
    public bool Decide(GameSim sim, Memory mem)
    {
        var s = sim.state;
        if (!s.started) return true;
        if (mem.last_tick != s.tick) mem.Observe(sim);
        var now = WorldModel.Read(sim, mem);
        // A new misjudgement at every wall.
        if (_last_vx != 0 && Math.Sign(_last_vx) != Math.Sign(s.vx) && _sk.misjudge_px > 0)
        {
            double size = _sk.misjudge_px * (_noise.NextDouble() < _sk.slip ? 3 : 1);
            _bias = (long)((_noise.NextDouble() * 2 - 1) * size * SimConfig.SUB);
        }
        _last_vx = s.vx;

        // Reaction delay: plan on the world as it was `delay` ticks ago, moved on by the model with the taps made since.
        var world = now;
        if (_sk.delay > 0)
        {
            _seen.Add(now);
            if (_seen.Count > _sk.delay + 1) _seen.RemoveAt(0);
            if (_seen.Count == _sk.delay + 1 && _seen[0].room_index == now.room_index)
            {
                world = _seen[0].Copy();
                for (int i = _taps_since.Count - _sk.delay; i < _taps_since.Count; i++)
                    if (i >= 0) world.Tick(_taps_since[i]);
                if (!world.bird.alive || world.exited) world = now;
            }
        }
        if (_bias != 0) world.bird.y += _bias;

        bool want = _pending_at < 0 && Plan(world);
        bool tap = false;
        if (want && !(_sk.miss > 0 && _noise.NextDouble() < _sk.miss))
            _pending_at = s.tick + (_sk.sigma > 0 ? (long)Math.Round(Math.Abs(Gauss()) * _sk.sigma) : 0);
        if (_pending_at >= 0 && s.tick >= _pending_at && s.tick - _last_tap >= _sk.min_gap)
        {
            tap = true;
            _pending_at = -1;
            _last_tap = s.tick;
        }
        _taps_since.Add(tap);
        if (_taps_since.Count > 64) _taps_since.RemoveRange(0, 32);
        return tap;
    }

    // --- The search ---

    struct Node
    {
        public Bird b;
        public long grav;
        public bool bounced, exited;
        public long bounce_d;
        public bool back;
        public int first;
        public double cost;
        public double h;
        public HazardModel[] own;
        /// The path's taps (bit d = tap at depth d) and its length in ticks.
        public ulong a0, a1, a2;
        public int len;
        /// Depth of the path's last tap (negative: a real tap that many ticks ago).
        public long last_tap;
    }

    static int Bit(ulong[] a, long d) => (int)((a[d >> 6] >> (int)(d & 63)) & 1);

    /// The shared timeline: the room and every hazard that does not depend on
    /// the bird, at each substep ahead (index 0 = now).
    sealed class Timeline
    {
        public RoomModel[] room;
        /// The same room as a path sees it after its bounce off the wall ahead:
        /// that wall cleared, the next one not drawn yet (or the known exit), one more point.
        public RoomModel[] after;
        /// After a bounce off the wall behind (a bumper sent the bird back): that wall cleared, the other one redrawn.
        public RoomModel[] after_back;
        public HazardModel[][] hz;
    }

    Timeline Build(WorldModel w, long substeps, long next_exit)
    {
        var ghost = new WorldModel
        {
            room = w.room.Copy(),
            bird = w.bird,
            hz = w.CopyHazards(h => !h.reactive),
            tick = w.tick,
        };
        Models.Link(ghost);
        int ahead = w.bird.vx > 0 ? 1 : 0;
        var tl = new Timeline
        {
            room = new RoomModel[substeps + 1],
            after = new RoomModel[substeps + 1],
            after_back = new RoomModel[substeps + 1],
            hz = new HazardModel[substeps + 1][],
        };
        void Keep(long at)
        {
            var pre = ghost.room.Copy();
            tl.room[at] = pre;
            tl.after[at] = AfterBounce(pre, ahead);
            tl.after_back[at] = AfterBounce(pre, 1 - ahead);
            var snap = new HazardModel[ghost.hz.Length];
            for (int i = 0; i < snap.Length; i++) snap[i] = ghost.hz[i].Copy();
            tl.hz[at] = snap;
        }
        Keep(0);
        tl.hz[0] = ghost.hz.Select(h => h.Copy()).ToArray();
        for (long s = 1; s <= substeps; s++)
        {
            long at = s;
            ghost.GhostSubstep(() => Keep(at), bounce: false);
        }
        return tl;
    }

    /// The room as a path sees it after it bounced off wall `side`: the room's
    /// own bounce rule (WorldModel.ApplyBounce) on a copy. The new wall is not
    /// drawn yet; an exit shown as a preview opens now, on its known wall.
    static RoomModel AfterBounce(RoomModel pre, int side)
    {
        var r = pre.Copy();
        r.anchor = RoomModel.NewAnchor(pre.Drawn(side), pre.anchor);
        r.spikes[side] = 0;
        r.unknown[side] = false;
        bool was_open = r.exit_open;
        if (!was_open)
        {
            r.score += 1;
            r.points += 1;
        }
        r.unknown[1 - side] = true;
        if (!was_open)
        {
            long every = SimConfig.POINTS_PER_ROOM;
            if (r.exit_preview)
            {
                if (r.score % every == 0)
                {
                    r.exit_preview = false;
                    r.exit_open = true;
                    r.unknown[r.exit_side] = false;
                }
            }
            else if ((r.score + 1) % every == 0 || r.score % every == 0) r.exit_unknown = true;
        }
        return r;
    }

    /// The best first move from `w`: true = tap. Easy ticks are planned with a
    /// small beam; when that plan is tight (one move dies on every path, or the
    /// best path passes inside a safety margin) the full beam plans again.
    public bool Plan(WorldModel w)
    {
        // Follow the last plan while it still holds on the new present (the model
        // is exact for everything visible, so a plan stays good until something
        // new shows up); search again every FOLLOW ticks or when it got worse.
        if (reuse && _plan != null && w.tick == _plan_tick + 1 && w.tick - _search_tick < FOLLOW && _plan_len > 2)
        {
            var shifted = new ulong[3];
            for (long d = 0; d < 191; d++)
                if (Bit(_plan, d + 1) == 1) shifted[d >> 6] |= 1UL << (int)(d & 63);
            double before = _plan_cost;
            bool tap = PlanBeam(w, 1, shifted);
            if (last_done > 0 && last_best <= before + FOLLOW_SLACK)
            {
                follows++;
                return tap;
            }
        }
        _search_tick = w.tick;
        int small = Math.Max(16, _sk.beam / 8);
        if (small >= _sk.beam) return PlanBeam(w, _sk.beam);
        bool quick = PlanBeam(w, small);
        bool tight = double.IsInfinity(last_cost_wait) || double.IsInfinity(last_cost_tap) || last_best >= 3 * NEAR_COST;
        if (!tight) return quick;
        replans++;
        return PlanBeam(w, _sk.beam);
    }

    public const long FOLLOW = 8;
    public const double FOLLOW_SLACK = 20;
    ulong[] _plan;
    int _plan_len;
    double _plan_cost;
    long _plan_tick = -10, _search_tick = -10;
    public long follows;
    /// Follow the last plan between searches (off: search every tick, so
    /// last_cost_wait/last_cost_tap compare both moves every tick).
    public bool reuse = true;

    public long replans;

    bool PlanBeam(WorldModel w, int beam, ulong[] forced = null)
    {
        decisions++;
        var room = w.room;
        if (!room.started) return true;
        if (room.hold > 0) return false;
        long horizon = _sk.horizon;
        long substeps = 0;
        for (long d = 0; d < horizon; d++) substeps += room.StepsAt(room.ticks + d);
        long ahead = w.bird.vx > 0 ? 1 : 0;
        // An exit shown as a preview on the wall behind opens at the next bounce: its height is known.
        long next_exit = -1;
        if (room.exit_preview && !room.exit_open && room.exit_side == 1 - ahead
            && (room.score + 1) % SimConfig.POINTS_PER_ROOM == 0)
            next_exit = room.exit_b_kind == ExitKind.WILD ? room.exit_b_y : room.exit_a_y;
        var tl = Build(w, substeps, next_exit);
        long margin = _sk.margin_px * SimConfig.SUB;
        var scratch = new WorldModel { room = room, hz = Array.Empty<HazardModel>() };
        var own0 = w.CopyHazards(h => h.reactive);

        var gaps = room.ExitAhead(ahead) && !room.unknown[ahead]
            ? new List<long> { room.exit_a_y, room.exit_b_kind != ExitKind.NORMAL ? room.exit_b_y : room.exit_a_y }
            : WorldDesc.Gaps(room.Mask(ahead), Physics.Shift(w.hz, null, ahead), room.half_base).Select(g => g.mid).ToList();
        Array.Clear(last_causes);
        last_bounced_deaths = 0;
        var nodes = new List<Node> { new Node { b = w.bird, grav = room.gravity, first = -1, own = own0, last_tap = _last_tap - w.tick } };
        var done = new List<Node>();
        long[] deepest = { -1, -1 };
        long sbase = 0;
        var next = new List<Node>();
        var slot = new Dictionary<long, int>();
        for (long d = 0; d < horizon && nodes.Count > 0; d++)
        {
            long n_sub = room.StepsAt(room.ticks + d);
            next.Clear();
            slot.Clear();
            foreach (var node in nodes)
            {
                for (int act = 0; act < 2; act++)
                {
                    if (forced != null && act != Bit(forced, d)) continue;
                    // A human can't tap faster than min_gap: plan only taps they can make.
                    if (act == 1 && _sk.min_gap > 0 && d - node.last_tap < _sk.min_gap) continue;
                    var c = node;
                    if (d == 0) c.first = act;
                    c.len = (int)d + 1;
                    if (act == 1)
                    {
                        c.last_tap = d;
                        if (d < 64) c.a0 |= 1UL << (int)d;
                        else if (d < 128) c.a1 |= 1UL << (int)(d - 64);
                        else c.a2 |= 1UL << (int)(d - 128);
                    }
                    if (c.own.Length > 0)
                    {
                        c.own = new HazardModel[node.own.Length];
                        for (int i = 0; i < c.own.Length; i++) c.own[i] = node.own[i].Copy();
                    }
                    scratch.hz = c.own;
                    scratch.room = !c.bounced ? tl.room[sbase] : c.back ? tl.after_back[sbase] : tl.after[sbase];
                    if (act == 1)
                    {
                        c.b.vy = SimConfig.FLAP_VY * c.grav;
                        scratch.bird = c.b;
                        foreach (var h in c.own)
                            if (h.alive) h.OnFlap(scratch);
                    }
                    bool dead = false;
                    for (long j = 1; j <= n_sub; j++)
                    {
                        long s = sbase + j;
                        scratch.room = !c.bounced ? tl.room[s] : c.back ? tl.after_back[s] : tl.after[s];
                        scratch.bird = c.b;
                        foreach (var h in c.own)
                        {
                            if (!h.alive) continue;
                            h.t = scratch.room.t;
                            h.Step(scratch);
                        }
                        var r = new SubResult { bounced = -1 };
                        Physics.Substep(scratch, ref c.b, c.grav, tl.hz[s], c.own, margin, ref r, true);
                        nodes_expanded++;
                        if (r.dead)
                        {
                            last_causes[r.cause]++;
                            if (c.bounced) last_bounced_deaths++;
                            dead = true;
                            break;
                        }
                        if (r.exited)
                        {
                            c.exited = true;
                            c.cost -= EXIT_BONUS - d * 10;
                            break;
                        }
                        if (r.near) c.cost += r.near_guess ? NEAR_GUESS_COST : NEAR_COST;
                        if (r.bounced >= 0)
                        {
                            if (scratch.room.flip_flop) c.grav = -c.grav;
                            if (!c.bounced)
                            {
                                c.bounced = true;
                                c.bounce_d = d;
                                c.back = r.bounced != ahead;
                                // The next gap is drawn around the room's anchor: be near it.
                                var view = c.back ? tl.after_back[s] : tl.after[s];
                                c.cost += next_exit >= 0 ? EXIT_PULL * Math.Abs(c.b.y - next_exit) / SimConfig.SUB : MIDDLE_COST * Math.Abs(c.b.y - view.anchor) / SimConfig.SUB;
                            }
                            scratch.bird = c.b;
                            scratch.room = c.back ? tl.after_back[s] : tl.after[s];
                            foreach (var h in c.own)
                                if (h.alive) h.OnBounce(scratch);
                        }
                    }
                    if (dead)
                    {
                        int f = d == 0 ? act : node.first;
                        deepest[f] = Math.Max(deepest[f], d);
                        continue;
                    }
                    // Edges: the ceiling and floor are deadly.
                    double top = (c.b.y - SimConfig.KILL_TOP) / (double)SimConfig.SUB - 14;
                    double bottom = (SimConfig.KILL_BOTTOM - c.b.y) / (double)SimConfig.SUB - 14;
                    double edge = Math.Min(top, bottom);
                    if (edge < EDGE_ZONE) c.cost += EDGE_COST * (EDGE_ZONE - edge) / 10;
                    if (c.exited || (c.bounced && next_exit < 0 && d - c.bounce_d >= POST_TICKS))
                    {
                        done.Add(c);
                        continue;
                    }
                    c.h = c.bounced ? (next_exit >= 0 ? EXIT_PULL * Math.Abs(c.b.y - next_exit) / SimConfig.SUB : 0) : GAP_PULL * GapDist(gaps, c.b.y) / SimConfig.SUB;
                    long key = ((c.b.y >> 8) * 1024 + ((c.b.vy + 4096) >> 5)) * 8 + (c.bounced ? 4 : 0) + ((c.b.x >> 8) & 3);
                    if (slot.TryGetValue(key, out int at))
                    {
                        if (c.cost < next[at].cost) next[at] = c;
                    }
                    else
                    {
                        slot[key] = next.Count;
                        next.Add(c);
                    }
                }
            }
            sbase += n_sub;
            if (next.Count > beam)
            {
                Prune(next, beam);
            }
            (nodes, next) = (next, nodes);
        }
        // Paths still flying at the horizon: how well placed they are for the wall ahead.
        foreach (var n in nodes)
        {
            var c = n;
            if (!c.bounced) c.cost += WallCost(w, c.b);
            else if (next_exit >= 0 && !c.exited) c.cost += EXIT_PULL * Math.Abs(c.b.y - next_exit) / SimConfig.SUB;
            done.Add(c);
        }
        last_done = done.Count;
        last_deep_wait = deepest[0];
        last_deep_tap = deepest[1];
        last_left = nodes.Count;
        last_cost_wait = last_cost_tap = double.PositiveInfinity;
        if (done.Count == 0) return deepest[1] > deepest[0];
        double best = double.MaxValue;
        int pick = 0;
        Node chosen = default;
        foreach (var n in done)
        {
            if (n.first == 0) last_cost_wait = Math.Min(last_cost_wait, n.cost);
            else last_cost_tap = Math.Min(last_cost_tap, n.cost);
            double v = n.cost + (n.bounced || n.exited ? 0 : 0.0);
            if (v < best)
            {
                best = v;
                pick = n.first;
                chosen = n;
            }
        }
        last_best = best;
        _plan = new[] { chosen.a0, chosen.a1, chosen.a2 };
        _plan_len = chosen.len;
        _plan_cost = best;
        _plan_tick = w.tick;
        return pick == 1;
    }

    public const double GAP_PULL = 0.5;
    public const double EXIT_PULL = 1.0;

    static double GapDist(List<long> gaps, long y)
    {
        if (gaps.Count == 0) return 0;
        long best = long.MaxValue;
        foreach (long g in gaps) best = Math.Min(best, Math.Abs(g - y));
        return best;
    }

    /// Keeps `beam` paths: first the best of each 16 px height band, then the best of the rest.
    static void Prune(List<Node> list, int beam)
    {
        list.Sort((a, b) => (a.cost + a.h).CompareTo(b.cost + b.h));
        var keep = new List<Node>(beam);
        var used = new bool[list.Count];
        var bands = new HashSet<long>();
        for (int i = 0; i < list.Count && keep.Count < beam / 2; i++)
            if (bands.Add((list[i].b.y >> 10) * 4 + (list[i].bounced ? 2 : 0) + (list[i].b.vx > 0 ? 1 : 0)))
            {
                keep.Add(list[i]);
                used[i] = true;
            }
        for (int i = 0; i < list.Count && keep.Count < beam; i++)
            if (!used[i]) keep.Add(list[i]);
        list.Clear();
        list.AddRange(keep);
    }

    /// Before the wall: distance from the middle of the nearest gap (or the exit) on the wall ahead.
    static double WallCost(WorldModel w, in Bird b)
    {
        var room = w.room;
        long side = b.vx > 0 ? 1 : 0;
        long target;
        if (room.ExitAhead(side) && !room.unknown[side]) target = room.exit_b_kind == ExitKind.WILD ? room.exit_b_y : room.exit_a_y;
        else
        {
            long mask = room.Mask(side);
            long shift = Physics.Shift(w.hz, null, side);
            target = NearestGap(mask, b.y - shift) + shift;
        }
        return 0.5 * Math.Abs(b.y - target) / SimConfig.SUB;
    }

    public static long NearestGap(long mask, long y)
    {
        long best = MID_Y, best_d = long.MaxValue;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            if (RoomRules.has_slot(mask, slot)) continue;
            bool up = slot == 0 || !RoomRules.has_slot(mask, slot - 1);
            bool down = slot == SimConfig.SLOT_COUNT - 1 || !RoomRules.has_slot(mask, slot + 1);
            if (!up && !down) continue;
            long cy = SimConfig.slot_center_y(slot);
            long d = Math.Abs(cy - y);
            if (d < best_d)
            {
                best_d = d;
                best = cy;
            }
        }
        return best;
    }
}
