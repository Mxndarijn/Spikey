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
    /// pressed); jitter: a tap lands 0..jitter ticks late; miss: chance a tap is
    /// dropped; horizon: look-ahead in ticks; margin_px: safety margin; beam:
    /// paths kept per tick; misjudge_px: the bird's height is misread by up to
    /// this much (a new error at every wall); slip: chance per wall of a bad
    /// misjudgement (3x).
    public sealed record Skill(string name, int delay, int jitter, double miss, int horizon, long margin_px, int beam,
        double misjudge_px, double slip)
    {
        public static readonly Skill BEAST = new("beast", 0, 0, 0, 150, 6, 64, 0, 0);
        public static readonly Skill EXPERT = new("expert", 6, 2, 0.01, 110, 5, 48, 6, 0.04);
        public static readonly Skill GOOD = new("good", 10, 3, 0.02, 90, 4, 40, 10, 0.06);
        public static readonly Skill NORMAL = new("normal", 14, 4, 0.04, 70, 3, 32, 14, 0.08);
        public static readonly Skill BEGINNER = new("beginner", 18, 5, 0.06, 50, 2, 24, 18, 0.10);
        public static readonly Skill[] ALL = { BEGINNER, NORMAL, GOOD, EXPERT, BEAST };

        public static Skill Named(string n) => ALL.FirstOrDefault(s => s.name == n) ?? BEAST;

        public override string ToString() =>
            $"delay {delay}, jitter {jitter}, miss {miss:F3}, horizon {horizon}, margin {margin_px}px, beam {beam}, misjudge {misjudge_px}px, slip {slip:F3}";
    }

    // Costs, in "px of distance" units.
    public const double NEAR_COST = 40;
    public const double NEAR_GUESS_COST = 80;
    public const double EDGE_ZONE = 70;
    public const double EDGE_COST = 0.6;
    public const double MIDDLE_COST = 0.35;
    public const double EXIT_BONUS = 100000;
    public const long POST_TICKS = 24;
    public const long MID_Y = (SimConfig.KILL_TOP + SimConfig.KILL_BOTTOM) / 2;

    readonly Skill _sk;
    readonly Random _noise;
    readonly List<WorldModel> _seen = new();
    readonly List<bool> _taps_since = new();
    long _pending_at = -1;
    long _bias;
    long _last_vx;

    public long decisions, nodes_expanded;
    /// The last plan: finished paths, how deep the deaths of wait/tap went, the best cost.
    public long last_done, last_deep_wait, last_deep_tap, last_left;
    public double last_best;

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
            _pending_at = s.tick + (_sk.jitter > 0 ? _noise.Next(_sk.jitter + 1) : 0);
        if (_pending_at >= 0 && s.tick >= _pending_at)
        {
            tap = true;
            _pending_at = -1;
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
        public int first;
        public double cost;
        public double h;
        public HazardModel[] own;
    }

    /// The shared timeline: the room and every hazard that does not depend on
    /// the bird, at each substep ahead (index 0 = now).
    sealed class Timeline
    {
        public RoomModel[] room;
        public HazardModel[][] hz;
    }

    Timeline Build(WorldModel w, long substeps)
    {
        var ghost = new WorldModel
        {
            room = w.room.Copy(),
            bird = w.bird,
            hz = w.CopyHazards(h => !h.reactive),
            tick = w.tick,
        };
        Models.Link(ghost);
        var tl = new Timeline { room = new RoomModel[substeps + 1], hz = new HazardModel[substeps + 1][] };
        tl.room[0] = ghost.room.Copy();
        tl.hz[0] = ghost.hz;
        for (long s = 1; s <= substeps; s++)
        {
            long at = s;
            ghost.GhostSubstep(() =>
            {
                tl.room[at] = ghost.room.Copy();
                var snap = new HazardModel[ghost.hz.Length];
                for (int i = 0; i < snap.Length; i++) snap[i] = ghost.hz[i].Copy();
                tl.hz[at] = snap;
            });
        }
        return tl;
    }

    /// The best first move from `w`: true = tap.
    public bool Plan(WorldModel w)
    {
        decisions++;
        var room = w.room;
        if (!room.started) return true;
        if (room.hold > 0) return false;
        long horizon = _sk.horizon;
        long substeps = 0;
        for (long d = 0; d < horizon; d++) substeps += room.StepsAt(room.ticks + d);
        var tl = Build(w, substeps);
        long margin = _sk.margin_px * SimConfig.SUB;
        var scratch = new WorldModel { room = room, hz = Array.Empty<HazardModel>() };
        var own0 = w.CopyHazards(h => h.reactive);

        long ahead = w.bird.vx > 0 ? 1 : 0;
        var gaps = room.ExitAhead(ahead) && !room.unknown[ahead]
            ? new List<long> { room.exit_a_y, room.exit_b_kind != ExitKind.NORMAL ? room.exit_b_y : room.exit_a_y }
            : WorldDesc.Gaps(room.Mask(ahead), Physics.Shift(w.hz, null, ahead), room.half_base).Select(g => g.mid).ToList();
        var nodes = new List<Node> { new Node { b = w.bird, grav = room.gravity, first = -1, own = own0 } };
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
                    var c = node;
                    if (d == 0) c.first = act;
                    if (c.own.Length > 0)
                    {
                        c.own = new HazardModel[node.own.Length];
                        for (int i = 0; i < c.own.Length; i++) c.own[i] = node.own[i].Copy();
                    }
                    scratch.hz = c.own;
                    scratch.room = tl.room[sbase];
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
                        scratch.room = tl.room[s];
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
                                c.cost += MIDDLE_COST * Math.Abs(c.b.y - MID_Y) / SimConfig.SUB;
                            }
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
                    if (c.exited || (c.bounced && d - c.bounce_d >= POST_TICKS))
                    {
                        done.Add(c);
                        continue;
                    }
                    c.h = c.bounced ? 0 : GAP_PULL * GapDist(gaps, c.b.y) / SimConfig.SUB;
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
            if (next.Count > _sk.beam)
            {
                Prune(next, _sk.beam);
            }
            (nodes, next) = (next, nodes);
        }
        // Paths still flying at the horizon: how well placed they are for the wall ahead.
        foreach (var n in nodes)
        {
            var c = n;
            if (!c.bounced) c.cost += WallCost(w, c.b);
            done.Add(c);
        }
        last_done = done.Count;
        last_deep_wait = deepest[0];
        last_deep_tap = deepest[1];
        last_left = nodes.Count;
        if (done.Count == 0) return deepest[1] > deepest[0];
        double best = double.MaxValue;
        int pick = 0;
        foreach (var n in done)
        {
            double v = n.cost + (n.bounced || n.exited ? 0 : 0.0);
            if (v < best)
            {
                best = v;
                pick = n.first;
            }
        }
        last_best = best;
        return pick == 1;
    }

    public const double GAP_PULL = 0.5;

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
            if (bands.Add((list[i].b.y >> 10) * 2 + (list[i].bounced ? 1 : 0)))
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
