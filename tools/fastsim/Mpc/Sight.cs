namespace FastSim.Mpc;

/// What the MPC bot has seen of one hazard (docs/MPC_BOT.md): where a bird
/// would die of it right now (a grid of point tests on the present state),
/// and how that shape has moved over the last ticks.
public sealed class Track
{
    public const int HISTORY = 16;
    public readonly byte[] hit = new byte[Sight.CELLS];
    /// Distance (px) from each cell to the nearest deadly cell, at most FAR.
    public readonly float[] dist = new float[Sight.CELLS];
    public int count;
    public float cx, cy;
    /// Shape motion, px per sim step, from the centroid over the last steps.
    public float vx, vy;
    /// How unsure the motion is (px per step), from how much the estimate jumps.
    public float wobble;
    public int seen;
    public long last_scan = -1;
    public int c0 = 0, c1 = -1, r0 = 0, r1 = -1;
    public readonly long[] h_t = new long[HISTORY];
    public readonly float[] h_x = new float[HISTORY], h_y = new float[HISTORY];
    public readonly int[] h_n = new int[HISTORY];
    public int h_len, h_at;
    /// Cells that were deadly at some point (fades): where a blinking or
    /// swinging hazard comes back.
    public readonly byte[] ghost = new byte[Sight.CELLS];
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
    public const float FAR = 48f;

    public readonly List<Track> tracks = new();
    readonly Dictionary<Hazard, Track> _by = new(ReferenceEqualityComparer.Instance);
    readonly byte[] _coarse = new byte[CELLS];
    long _room_index = -1, _room_t = -1;
    /// Sim steps between full scans of a hazard; between them only the cells
    /// around its last shape are probed.
    public int full_every = 4;
    public int ghost_ticks = 0;
    public long probes;

    public void look(GameSim sim)
    {
        var room = sim.room;
        if (sim.state.room_index != _room_index || room.t < _room_t)
        {
            _by.Clear();
            _room_index = sim.state.room_index;
        }
        _room_t = room.t;
        tracks.Clear();
        long x0 = sim.state.x, y0 = sim.state.y;
        var hz = room.hazards;
        for (int i = 0; i < hz.Count; i++)
        {
            var h = hz[i];
            if (!h.alive) continue;
            if (!_by.TryGetValue(h, out var tr))
            {
                tr = new Track();
                _by[h] = tr;
            }
            scan(sim, h, tr, room.t);
            if (tr.count > 0 || tr.seen > 0) tracks.Add(tr);
        }
        sim.state.x = x0;
        sim.state.y = y0;
    }

    bool probe(GameSim sim, Hazard h, int c, int r)
    {
        probes++;
        sim.state.x = c * CELL + CELL / 2;
        sim.state.y = r * CELL + CELL / 2;
        return h.kills(sim);
    }

    void scan(GameSim sim, Hazard h, Track tr, long t)
    {
        bool full = tr.last_scan < 0 || t - tr.last_scan >= full_every;
        if (!full && tr.c1 < tr.c0)
        {
            // Nothing was deadly at the last full scan: look again at the next one.
            fade(tr);
            return;
        }
        int c0 = 0, c1 = COLS - 1, r0 = 0, r1 = ROWS - 1;
        if (!full)
        {
            // Around the last shape: it moves less than 3 cells a step.
            c0 = Math.Max(0, (tr.c0 - 3) & ~1);
            r0 = Math.Max(0, (tr.r0 - 3) & ~1);
            c1 = Math.Min(COLS - 1, tr.c1 + 3);
            r1 = Math.Min(ROWS - 1, tr.r1 + 3);
        }
        else tr.last_scan = t;
        var hit = tr.hit;
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
        int n = 0;
        long sx = 0, sy = 0;
        int bc0 = COLS, bc1 = -1, br0 = ROWS, br1 = -1;
        if (any)
        {
            for (int r = r0; r <= r1; r += 2)
                for (int c = c0; c <= c1; c += 2)
                {
                    // Fine pass where this coarse point or a neighbour is deadly.
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
                            n++;
                            sx += cc;
                            sy += rr;
                            if (cc < bc0) bc0 = cc;
                            if (cc > bc1) bc1 = cc;
                            if (rr < br0) br0 = rr;
                            if (rr > br1) br1 = rr;
                        }
                }
        }
        tr.count = n;
        tr.c0 = bc0;
        tr.c1 = bc1;
        tr.r0 = br0;
        tr.r1 = br1;
        if (n == 0)
        {
            // Nothing deadly now: the motion history starts over.
            tr.h_len = 0;
            tr.vx = tr.vy = 0;
            tr.wobble = 0;
            fade(tr);
            if (!full) tr.last_scan = -1;
            return;
        }
        tr.seen++;
        tr.cx = (sx / (float)n + 0.5f) * CELL_PX;
        tr.cy = (sy / (float)n + 0.5f) * CELL_PX;
        motion(tr, t);
        distances(tr);
        fade(tr);
    }

    void fade(Track tr)
    {
        if (ghost_ticks <= 0) return;
        var g = tr.ghost;
        var hit = tr.hit;
        for (int i = 0; i < CELLS; i++)
        {
            if (hit[i] != 0) g[i] = (byte)Math.Min(255, ghost_ticks);
            else if (g[i] > 0) g[i]--;
        }
    }

    public int window = 6;

    static void push(Track tr, long t)
    {
        tr.h_at = (tr.h_at + 1) % Track.HISTORY;
        tr.h_t[tr.h_at] = t;
        tr.h_x[tr.h_at] = tr.cx;
        tr.h_y[tr.h_at] = tr.cy;
        tr.h_n[tr.h_at] = tr.count;
        if (tr.h_len < Track.HISTORY) tr.h_len++;
    }

    void motion(Track tr, long t)
    {
        // Same sim step seen twice (a slow room's idle tick, an arrival hold): keep.
        if (tr.h_len > 0 && tr.h_t[tr.h_at] == t) return;
        push(tr, t);
        // The oldest sample within the window.
        int best = -1;
        for (int k = 1; k < tr.h_len; k++)
        {
            int i = (tr.h_at - k + Track.HISTORY) % Track.HISTORY;
            if (t - tr.h_t[i] > window) break;
            best = i;
        }
        if (best < 0)
        {
            tr.vx = tr.vy = 0;
            tr.wobble = 1f;
            return;
        }
        float dt = t - tr.h_t[best];
        float vx = (tr.cx - tr.h_x[best]) / dt, vy = (tr.cy - tr.h_y[best]) / dt;
        float jump = Math.Abs(vx - tr.vx) + Math.Abs(vy - tr.vy);
        // A shape that grows or shrinks moves its centroid without moving.
        float grow = Math.Abs(tr.count - tr.h_n[best]) / (float)Math.Max(tr.count, tr.h_n[best]);
        tr.wobble = 0.8f * tr.wobble + 0.2f * Math.Min(jump * 2f + grow, 2f);
        tr.vx = Math.Clamp(vx, -12f, 12f);
        tr.vy = Math.Clamp(vy, -14f, 14f);
    }

    /// Two-pass chamfer distance to the nearest deadly cell.
    static void distances(Track tr)
    {
        var d = tr.dist;
        var hit = tr.hit;
        const float A = CELL_PX, B = CELL_PX * 1.4142f;
        // Only a box around the shape matters; the rest is FAR.
        int pad = (int)(FAR / CELL_PX) + 1;
        int c0 = Math.Max(0, tr.c0 - pad), c1 = Math.Min(COLS - 1, tr.c1 + pad);
        int r0 = Math.Max(0, tr.r0 - pad), r1 = Math.Min(ROWS - 1, tr.r1 + pad);
        Array.Fill(d, FAR);
        for (int r = r0; r <= r1; r++)
            for (int c = c0; c <= c1; c++)
            {
                int i = r * COLS + c;
                if (hit[i] != 0)
                {
                    d[i] = 0;
                    continue;
                }
                float m = FAR;
                if (c > c0) m = Math.Min(m, d[i - 1] + A);
                if (r > r0)
                {
                    m = Math.Min(m, d[i - COLS] + A);
                    if (c > c0) m = Math.Min(m, d[i - COLS - 1] + B);
                    if (c < c1) m = Math.Min(m, d[i - COLS + 1] + B);
                }
                d[i] = m;
            }
        for (int r = r1; r >= r0; r--)
            for (int c = c1; c >= c0; c--)
            {
                int i = r * COLS + c;
                float m = d[i];
                if (c < c1) m = Math.Min(m, d[i + 1] + A);
                if (r < r1)
                {
                    m = Math.Min(m, d[i + COLS] + A);
                    if (c < c1) m = Math.Min(m, d[i + COLS + 1] + B);
                    if (c > c0) m = Math.Min(m, d[i + COLS - 1] + B);
                }
                d[i] = m;
            }
    }
}
