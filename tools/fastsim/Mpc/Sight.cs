namespace FastSim.Mpc;

/// One connected shape the bot has seen (docs/MPC_BOT.md): the cells where
/// the bird would touch it right now, its box with sub-pixel edges, and how
/// each edge has moved over the last steps. A shape that slides moves all
/// four edges alike; one that grows (a gate, a piston) moves one edge.
public sealed class Blob
{
    public const int HISTORY = 12;
    public const int PAD = 5;
    public Hazard owner;
    /// Not deadly: a body the bird bumps into or gets carried by.
    public bool body;
    public int c0, c1, r0, r1, count;
    /// Edges in px: left, right, top, bottom; their speed (px per step) and acceleration.
    public readonly float[] e = new float[4], v = new float[4], a = new float[4];
    /// How unsure the motion is (px per step per step).
    public float wobble;
    public int age;
    /// Px per step this shape moves up or down toward the bird's height (0: it does not follow).
    public float chase;
    /// Steps a shape of this hazard stays, when its last two stayed equally long (a beam,
    /// a piston stroke); 0: not known.
    public int life;
    /// Per edge: at the screen border (its real place is off screen), the
    /// step it was first really seen, and how many sightings its motion rests on.
    public readonly bool[] pin = new bool[4];
    public readonly long[] since = new long[4];
    public readonly int[] fit = new int[4];
    public bool matched;
    public readonly long[] h_t = new long[HISTORY];
    public readonly float[][] h_e = { new float[HISTORY], new float[HISTORY], new float[HISTORY], new float[HISTORY] };
    public int h_len, h_at;
    /// Distance (px) to the nearest cell of the shape, over the box plus PAD cells.
    public float[] dist = new float[Sight.CELLS];
    public int wc0, wr0, ww, wh;

    public void reset(Hazard h, bool is_body)
    {
        owner = h;
        body = is_body;
        h_len = 0;
        h_at = 0;
        age = 0;
        wobble = 1f;
        chase = 0f;
        life = 0;
        Array.Clear(v);
        Array.Clear(a);
        Array.Clear(pin);
        Array.Clear(since);
        Array.Clear(fit);
    }
}

/// The bot's eyes. Every tick it looks at the present sim only: it moves the
/// bird to probe points, asks each live hazard's kills() and puts the bird
/// back. It never copies or steps the sim.
public sealed class Sight
{
    public const int CELL_PX = 8;
    public const long CELL = CELL_PX * SimConfig.SUB;
    public const int COLS = 45, ROWS = 80;
    public const int CELLS = COLS * ROWS;
    const long R = SimConfig.BIRD_RADIUS;

    /// What a hazard looked like at the last look: its scan box and its shapes.
    sealed class Seen
    {
        // How often the hazard's shape moved toward the bird's height, of the
        // steps it moved at all while the bird was clearly above or below it.
        public int chase_yes, chase_all;
        public float chase_speed;
        // How many steps the hazard's last two shapes stayed before they went.
        public int life_a, life_b;
        public long last_full = -1;
        public int c0 = 0, c1 = -1, r0 = 0, r1 = -1;
        public List<Blob> blobs = new(), old = new();
    }

    public readonly List<Blob> blobs = new();
    /// A warning drawn on screen (a glowing piston, a beam charging): the
    /// box a bird must be out of, from `eta` steps on for `dur` steps.
    public readonly record struct Warn(float x0, float y0, float x1, float y1, int eta, int dur);
    public readonly List<Warn> warns = new();
    /// Moving air drawn on screen: an updraft column (x range in px, lift in sub-units per
    /// step, drift in px per step) and wind bands (heights in sub-units, push per step).
    public readonly record struct Draft(float x0, float x1, long lift, float v, int from, int to);
    public readonly List<Draft> drafts = new();
    readonly List<(long y0, long y1, long push)> _winds = new();
    readonly Dictionary<int, (long t, float x0, float v)> _draft_seen = new();

    /// The sideways push (sub-units per step) on a bird at height `y` now.
    public long push_at(long y)
    {
        foreach (var w in _winds)
            if (y >= w.y0 && y <= w.y1) return w.push;
        return 0;
    }
    public bool read_warnings = true, learn_chase = true, learn_life = true;
    // Memory per hazard, by its place in the room's list (not by object: the
    // same room may be handed over as another copy of the sim).
    readonly Dictionary<int, Seen> _by = new();
    readonly Stack<Blob> _pool = new();
    readonly byte[] _coarse = new byte[CELLS];
    readonly byte[] _hit = new byte[CELLS];
    readonly int[] _label = new int[CELLS];
    readonly int[] _stack = new int[CELLS];
    long _room_index = -1, _room_t = -1;
    /// Sim steps between full scans of a hazard; between them only the cells
    /// around its last shape are probed.
    public int full_every = 4;
    public int window = 10;
    public bool use_accel = true;
    public float min_accel = 0.04f;
    public long probes;

    public void look(GameSim sim)
    {
        var room = sim.room;
        if (sim.state.room_index != _room_index || room.t < _room_t)
        {
            foreach (var s in _by.Values)
            {
                foreach (var b in s.blobs) _pool.Push(b);
            }
            _by.Clear();
            _draft_seen.Clear();
            _room_index = sim.state.room_index;
        }
        _room_t = room.t;
        blobs.Clear();
        long x0 = sim.state.x, y0 = sim.state.y;
        var hz = room.hazards;
        for (int i = 0; i < hz.Count; i++)
        {
            var h = hz[i];
            if (!h.alive) continue;
            if (!_by.TryGetValue(i, out var seen))
            {
                seen = new Seen();
                _by[i] = seen;
            }
            long t_before = seen.blobs.Count == 1 ? seen.blobs[0].h_t[seen.blobs[0].h_at] : -1;
            scan(sim, h, seen, room.t);
            if (learn_chase) chase(seen, room.t, t_before, y0);
            blobs.AddRange(seen.blobs);
        }
        sim.state.x = x0;
        sim.state.y = y0;
        air(sim);
        warns.Clear();
        if (read_warnings)
            for (int i = 0; i < hz.Count; i++)
                if (hz[i].alive) warnings(sim, hz[i]);
    }

    /// Learns whether a one-shape hazard follows the bird's height (the
    /// stalker): its shape keeps moving toward where the bird is.
    void chase(Seen seen, long t, long t_before, long bird_y)
    {
        if (seen.blobs.Count != 1) return;
        var b = seen.blobs[0];
        float by = (float)bird_y / SimConfig.SUB;
        if (t_before >= 0 && b.h_t[b.h_at] == t && t_before < t && b.fit[2] >= 6 && b.fit[3] >= 6)
        {
            // Both edges must move alike: a shape that slides, not one that grows.
            float d2 = b.v[2], d3 = b.v[3];
            float mid = (b.e[2] + b.e[3]) / 2f, off = by - mid;
            if (Math.Abs(off) > 16f && Math.Abs(d2 - d3) < 0.3f)
            {
                float d = (d2 + d3) / 2f;
                seen.chase_all++;
                if (Math.Abs(d) > 0.3f && (d > 0) == (off > 0))
                {
                    seen.chase_yes++;
                    seen.chase_speed = seen.chase_speed == 0f ? Math.Abs(d) : 0.9f * seen.chase_speed + 0.1f * Math.Abs(d);
                }
            }
        }
        b.chase = seen.chase_all >= 30 && seen.chase_yes >= 0.85f * seen.chase_all ? Math.Min(seen.chase_speed, 4f) : 0f;
    }

    /// Updrafts and wind as they are now. An updraft's drift is its column's
    /// movement since the last look.
    void air(GameSim sim)
    {
        drafts.Clear();
        _winds.Clear();
        long t = sim.room.t;
        var hz = sim.room.hazards;
        for (int i = 0; i < hz.Count; i++)
        {
            var h = hz[i];
            if (!h.alive) continue;
            if (h is Updraft u)
            {
                float x0 = (float)u.x0 / SimConfig.SUB;
                float v = 0;
                if (_draft_seen.TryGetValue(i, out var was))
                {
                    v = was.v;
                    if (t > was.t) v = 0.5f * was.v + 0.5f * (x0 - was.x0) / (t - was.t);
                    else x0 = was.x0;
                }
                _draft_seen[i] = (t, (float)u.x0 / SimConfig.SUB, v);
                // A gusting updraft shows when it is about to blow; it blows from `from` to `to` steps on.
                int from = 0, to = int.MaxValue;
                if (u.gust != Updraft.Gust.NONE)
                {
                    int m = (int)u.gust_step(), on = (int)(Updraft.GUST_OFF + Updraft.GUST_WARN);
                    if (u.gust == Updraft.Gust.OFF) continue;
                    from = Math.Max(on - m, 0);
                    to = (int)Updraft.GUST_PERIOD - m;
                }
                drafts.Add(new Draft((float)u.x0 / SimConfig.SUB, (float)u.x1 / SimConfig.SUB, -u.lift, v, from, to));
            }
            else if (h is Wind w && w.blowing())
            {
                _winds.Add((w.a_y0, w.a_y1, w.a_dir * Wind.PUSH));
                if (w.b_dir != 0) _winds.Add((w.b_y0, w.b_y1, w.b_dir * Wind.PUSH));
            }
        }
    }

    /// The warnings the game draws before a hazard strikes, as boxes of bird
    /// positions to be out of. Only what is on screen now: where it glows and
    /// how far the glow has got.
    void warnings(GameSim sim, Hazard h)
    {
        const float RP = (float)R / SimConfig.SUB, S = SimConfig.SUB;
        if (h is Piston p && p.state() == Piston.State.GLOW)
        {
            int eta = (int)(Piston.IDLE_TICKS + p.glow_ticks - p.cycle_pos());
            int dur = (int)(Piston.EXTEND_TICKS + Piston.HOLD_TICKS + Piston.RETRACT_TICKS);
            float bx = p.base_x() / S, tip = (p.side == 0 ? p.base_x() + p.reach : p.base_x() - p.reach) / S;
            warns.Add(new Warn(Math.Min(bx, tip) - RP, (p.y - Piston.HALF_H) / S - RP, Math.Max(bx, tip) + RP, (p.y + Piston.HALF_H) / S + RP, eta, dur));
        }
        else if (h is Beam b)
        {
            for (int i = 0; i < b.rows.Count; i++)
            {
                if (b.state(i) != Beam.State.WARN) continue;
                int eta = (int)(b.warn_ticks - b.cycle_pos(i));
                warns.Add(new Warn(sim.room.wall_left() / S - RP, (b.rows[i] - Beam.HALF_H) / S - RP,
                    sim.room.wall_right() / S + RP, (b.rows[i] + Beam.HALF_H) / S + RP, eta, (int)Beam.ON_TICKS));
            }
        }
    }

    /// A body the bird bumps into without dying (the cloud bumper, a carrying bubble).
    static bool is_body(Hazard h) => h is Bumper || (h is Bubble u && !u.spiked);

    /// Whether the bird, where it stands in the sim now, touches the hazard.
    bool touches(GameSim sim, Hazard h)
    {
        probes++;
        if (h is Bumper b) return sim.bird_touches_circle(b.x, b.y, b.radius);
        if (h is Bubble u && !u.spiked) return sim.bird_touches_circle(u.x, u.y, u.radius - R);
        return h.kills(sim);
    }

    bool probe(GameSim sim, Hazard h, int c, int r)
    {
        sim.state.x = c * CELL + CELL / 2;
        sim.state.y = r * CELL + CELL / 2;
        return touches(sim, h);
    }

    void scan(GameSim sim, Hazard h, Seen seen, long t)
    {
        bool full = seen.last_full < 0 || t - seen.last_full >= full_every;
        if (!full && seen.c1 < seen.c0) return;
        int c0 = 0, c1 = COLS - 1, r0 = 0, r1 = ROWS - 1;
        if (!full)
        {
            // Around the last shapes: they move less than 3 cells a step.
            c0 = Math.Max(0, (seen.c0 - 3) & ~1);
            r0 = Math.Max(0, (seen.r0 - 3) & ~1);
            c1 = Math.Min(COLS - 1, seen.c1 + 3);
            r1 = Math.Min(ROWS - 1, seen.r1 + 3);
        }
        else seen.last_full = t;
        var hit = _hit;
        Array.Clear(hit);
        // Coarse pass: every other cell. Anything a bird can touch is at
        // least a bird wide, so it covers a coarse point.
        bool any = false;
        for (int r = r0; r <= r1; r += 2)
            for (int c = c0; c <= c1; c += 2)
            {
                bool k = probe(sim, h, c, r);
                _coarse[r * COLS + c] = k ? (byte)1 : (byte)0;
                any |= k;
            }
        int bc0 = COLS, bc1 = -1, br0 = ROWS, br1 = -1;
        if (any)
            for (int r = r0; r <= r1; r += 2)
                for (int c = c0; c <= c1; c += 2)
                {
                    // Fine pass where this coarse point or a neighbour is touched.
                    bool near = false;
                    for (int dr = -2; dr <= 2 && !near; dr += 2)
                        for (int dc = -2; dc <= 2; dc += 2)
                        {
                            int rr = r + dr, cc = c + dc;
                            if (rr < r0 || rr > r1 || cc < c0 || cc > c1) continue;
                            if (_coarse[rr * COLS + cc] != 0)
                            {
                                near = true;
                                break;
                            }
                        }
                    if (!near) continue;
                    for (int dr = 0; dr < 2; dr++)
                        for (int dc = 0; dc < 2; dc++)
                        {
                            int rr = r + dr, cc = c + dc;
                            if (rr >= ROWS || cc >= COLS) continue;
                            bool k = dr == 0 && dc == 0 ? _coarse[r * COLS + c] != 0 : probe(sim, h, cc, rr);
                            if (!k) continue;
                            hit[rr * COLS + cc] = 1;
                            if (cc < bc0) bc0 = cc;
                            if (cc > bc1) bc1 = cc;
                            if (rr < br0) br0 = rr;
                            if (rr > br1) br1 = rr;
                        }
                }
        seen.c0 = bc0;
        seen.c1 = bc1;
        seen.r0 = br0;
        seen.r1 = br1;
        (seen.blobs, seen.old) = (seen.old, seen.blobs);
        seen.blobs.Clear();
        foreach (var o in seen.old) o.matched = false;
        if (bc1 >= bc0)
        {
            if (!full && (bc0 <= c0 && c0 > 0 || bc1 >= c1 && c1 < COLS - 1 || br0 <= r0 && r0 > 0 || br1 >= r1 && r1 < ROWS - 1))
                seen.last_full = -1;
            shapes(sim, h, seen, t, bc0, bc1, br0, br1);
        }
        else if (!full) seen.last_full = -1;
        foreach (var o in seen.old)
            if (!o.matched)
            {
                // Gone (not just out of a partial scan's box): remember how long it stayed.
                if (full || bc1 < bc0)
                {
                    seen.life_b = seen.life_a;
                    seen.life_a = o.age;
                }
                _pool.Push(o);
            }
        seen.old.Clear();
        int life = learn_life && seen.life_a >= 8 && Math.Abs(seen.life_a - seen.life_b) <= 2 ? Math.Max(seen.life_a, seen.life_b) : 0;
        foreach (var b in seen.blobs) b.life = life;
    }

    /// Splits the touched cells into connected shapes and follows each one.
    void shapes(GameSim sim, Hazard h, Seen seen, long t, int bc0, int bc1, int br0, int br1)
    {
        var hit = _hit;
        var label = _label;
        for (int r = br0; r <= br1; r++) Array.Clear(label, r * COLS + bc0, bc1 - bc0 + 1);
        int next = 0;
        bool body = is_body(h);
        for (int r = br0; r <= br1; r++)
            for (int c = bc0; c <= bc1; c++)
            {
                int i0 = r * COLS + c;
                if (hit[i0] == 0 || label[i0] != 0) continue;
                next++;
                int c0 = c, c1 = c, r0 = r, r1 = r, n = 0, top = 0;
                _stack[top++] = i0;
                label[i0] = next;
                while (top > 0)
                {
                    int i = _stack[--top];
                    int cc = i % COLS, rr = i / COLS;
                    n++;
                    if (cc < c0) c0 = cc;
                    if (cc > c1) c1 = cc;
                    if (rr < r0) r0 = rr;
                    if (rr > r1) r1 = rr;
                    for (int dr = -1; dr <= 1; dr++)
                        for (int dc = -1; dc <= 1; dc++)
                        {
                            int r2 = rr + dr, c2 = cc + dc;
                            if (r2 < br0 || r2 > br1 || c2 < bc0 || c2 > bc1) continue;
                            int k = r2 * COLS + c2;
                            if (hit[k] == 0 || label[k] != 0) continue;
                            label[k] = next;
                            _stack[top++] = k;
                        }
                }
                // The shape seen before that this one overlaps most.
                Blob b = null;
                int best = 0;
                foreach (var o in seen.old)
                {
                    if (o.matched) continue;
                    int ow = Math.Min(c1, o.c1 + 2) - Math.Max(c0, o.c0 - 2) + 1;
                    int oh = Math.Min(r1, o.r1 + 2) - Math.Max(r0, o.r0 - 2) + 1;
                    if (ow <= 0 || oh <= 0) continue;
                    if (ow * oh > best)
                    {
                        best = ow * oh;
                        b = o;
                    }
                }
                if (b == null)
                {
                    b = _pool.Count > 0 ? _pool.Pop() : new Blob();
                    b.reset(h, body);
                }
                b.matched = true;
                b.owner = h;
                b.c0 = c0;
                b.c1 = c1;
                b.r0 = r0;
                b.r1 = r1;
                b.count = n;
                seen.blobs.Add(b);
                edges(sim, h, b, next);
                motion(b, t);
                distances(b, next);
            }
    }

    /// The four edges to half a pixel: bisect between the outermost touched
    /// cell and the free cell beyond it.
    void edges(GameSim sim, Hazard h, Blob b, int id)
    {
        var label = _label;
        // Left and right: on the middle row among those reaching the edge column.
        for (int k = 0; k < 2; k++)
        {
            int c = k == 0 ? b.c0 : b.c1;
            int lo = -1, hi = -1;
            for (int r = b.r0; r <= b.r1; r++)
                if (label[r * COLS + c] == id)
                {
                    if (lo < 0) lo = r;
                    hi = r;
                }
            int row = (lo + hi) / 2;
            if (label[row * COLS + c] != id) row = lo;
            long y = row * CELL + CELL / 2;
            long inside = c * CELL + CELL / 2, outside = inside + (k == 0 ? -CELL : CELL);
            if (outside < 0 || outside > SimConfig.WORLD_W)
            {
                b.e[k] = k == 0 ? 0 : SimConfig.WORLD_W / SimConfig.SUB;
                continue;
            }
            for (int it = 0; it < 6; it++)
            {
                long mid = (inside + outside) / 2;
                sim.state.x = mid;
                sim.state.y = y;
                if (touches(sim, h)) inside = mid;
                else outside = mid;
            }
            b.e[k] = (inside + outside) / 2f / SimConfig.SUB;
        }
        for (int k = 2; k < 4; k++)
        {
            int r = k == 2 ? b.r0 : b.r1;
            int lo = -1, hi = -1;
            for (int c = b.c0; c <= b.c1; c++)
                if (label[r * COLS + c] == id)
                {
                    if (lo < 0) lo = c;
                    hi = c;
                }
            int col = (lo + hi) / 2;
            if (label[r * COLS + col] != id) col = lo;
            long x = col * CELL + CELL / 2;
            long inside = r * CELL + CELL / 2, outside = inside + (k == 2 ? -CELL : CELL);
            if (outside < 0 || outside > SimConfig.WORLD_H)
            {
                b.e[k] = k == 2 ? 0 : SimConfig.WORLD_H / SimConfig.SUB;
                continue;
            }
            for (int it = 0; it < 6; it++)
            {
                long mid = (inside + outside) / 2;
                sim.state.x = x;
                sim.state.y = mid;
                if (touches(sim, h)) inside = mid;
                else outside = mid;
            }
            b.e[k] = (inside + outside) / 2f / SimConfig.SUB;
        }
    }

    /// Speed and acceleration of each edge: a least-squares line or parabola
    /// through its last sightings.
    void motion(Blob b, long t)
    {
        // The same sim step seen twice (a slow room's idle tick, an arrival hold): keep.
        if (b.h_len > 0 && b.h_t[b.h_at] == t) return;
        b.h_at = (b.h_at + 1) % Blob.HISTORY;
        b.h_t[b.h_at] = t;
        for (int k = 0; k < 4; k++) b.h_e[k][b.h_at] = b.e[k];
        if (b.h_len < Blob.HISTORY) b.h_len++;
        b.age++;
        float jump = 0;
        int known = 0;
        for (int k = 0; k < 4; k++)
        {
            float border = k == 0 || k == 2 ? 0f : (k == 1 ? SimConfig.WORLD_W : SimConfig.WORLD_H) / SimConfig.SUB;
            bool pinned = Math.Abs(b.e[k] - border) < 0.5f;
            // An edge that comes free of the screen border was not seen before.
            if (b.pin[k] && !pinned) b.since[k] = t;
            b.pin[k] = pinned;
            b.fit[k] = 0;
            if (pinned)
            {
                b.v[k] = 0;
                b.a[k] = 0;
                continue;
            }
            // Sums for the fit over time tau = (sighting - now) <= 0.
            int n = 0;
            double s0 = 0, s1 = 0, s2 = 0, s3 = 0, s4 = 0, y0 = 0, y1 = 0, y2 = 0;
            for (int q = 0; q < b.h_len; q++)
            {
                int i = (b.h_at - q + Blob.HISTORY) % Blob.HISTORY;
                long ht = b.h_t[i];
                if (t - ht > window || ht < b.since[k]) break;
                double x = ht - t, y = b.h_e[k][i] - b.e[k];
                n++;
                s0 += 1;
                s1 += x;
                s2 += x * x;
                s3 += x * x * x;
                s4 += x * x * x * x;
                y0 += y;
                y1 += x * y;
                y2 += x * x * y;
            }
            if (n < 2) continue;
            float v, acc = 0;
            double det1 = s0 * s2 - s1 * s1;
            v = (float)((s0 * y1 - s1 * y0) / det1);
            if (use_accel && n >= 5)
            {
                // Parabola c0 + c1 x + c2 x^2 by Cramer's rule.
                double det = s0 * (s2 * s4 - s3 * s3) - s1 * (s1 * s4 - s3 * s2) + s2 * (s1 * s3 - s2 * s2);
                if (Math.Abs(det) > 1e-9)
                {
                    double c1 = (s0 * (y1 * s4 - s3 * y2) - y0 * (s1 * s4 - s3 * s2) + s2 * (s1 * y2 - y1 * s2)) / det;
                    double c2 = (s0 * (s2 * y2 - y1 * s3) - s1 * (s1 * y2 - y1 * s2) + y0 * (s1 * s3 - s2 * s2)) / det;
                    if (Math.Abs(2 * c2) >= min_accel)
                    {
                        v = (float)c1;
                        acc = (float)Math.Clamp(2 * c2, -0.5, 0.5);
                    }
                }
            }
            jump = Math.Max(jump, Math.Abs(v - (b.v[k] + b.a[k])));
            b.v[k] = Math.Clamp(v, -30f, 30f);
            b.a[k] = acc;
            b.fit[k] = n;
            known++;
        }
        // An edge with no sightings yet moves like the one across.
        for (int k = 0; k < 4; k++)
            if (b.fit[k] == 0 && !b.pin[k] && b.fit[k ^ 1] > 0)
            {
                b.v[k] = b.v[k ^ 1];
                b.a[k] = b.a[k ^ 1];
            }
        if (known == 0 && b.age < 2) b.wobble = 1f;
        else b.wobble = 0.75f * b.wobble + 0.25f * Math.Min(jump, 2f);
    }

    /// Two-pass chamfer distance to the shape over its box plus PAD cells.
    void distances(Blob b, int id)
    {
        var label = _label;
        const float A = CELL_PX, B = CELL_PX * 1.4142f, FAR = 1000f;
        int c0 = Math.Max(0, b.c0 - Blob.PAD), c1 = Math.Min(COLS - 1, b.c1 + Blob.PAD);
        int r0 = Math.Max(0, b.r0 - Blob.PAD), r1 = Math.Min(ROWS - 1, b.r1 + Blob.PAD);
        int w = c1 - c0 + 1, hh = r1 - r0 + 1;
        b.wc0 = c0;
        b.wr0 = r0;
        b.ww = w;
        b.wh = hh;
        var d = b.dist;
        for (int r = 0; r < hh; r++)
            for (int c = 0; c < w; c++)
            {
                int i = r * w + c;
                int rr = r + r0, cc = c + c0;
                bool inside = rr >= b.r0 && rr <= b.r1 && cc >= b.c0 && cc <= b.c1 && label[rr * COLS + cc] == id;
                if (inside)
                {
                    d[i] = 0;
                    continue;
                }
                float m = FAR;
                if (c > 0) m = Math.Min(m, d[i - 1] + A);
                if (r > 0)
                {
                    m = Math.Min(m, d[i - w] + A);
                    if (c > 0) m = Math.Min(m, d[i - w - 1] + B);
                    if (c < w - 1) m = Math.Min(m, d[i - w + 1] + B);
                }
                d[i] = m;
            }
        for (int r = hh - 1; r >= 0; r--)
            for (int c = w - 1; c >= 0; c--)
            {
                int i = r * w + c;
                float m = d[i];
                if (c < w - 1) m = Math.Min(m, d[i + 1] + A);
                if (r < hh - 1)
                {
                    m = Math.Min(m, d[i + w] + A);
                    if (c < w - 1) m = Math.Min(m, d[i + w + 1] + B);
                    if (c > 0) m = Math.Min(m, d[i + w - 1] + B);
                }
                d[i] = m;
            }
    }
}
