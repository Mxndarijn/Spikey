namespace FastSim.Mpc;

/// The knobs of the MPC bot (docs/MPC_BOT.md). Lengths in px, times in ticks.
public sealed class MpcParams
{
    /// Sim steps planned past the next wall bounce, and at most in all.
    public int after = 30, max_steps = 130;
    /// A predicted hazard kills within this distance: m0 now, growing per step ahead.
    public float m0 = 4f, grow = 0.10f, wob = 0.5f, m_cap = 26f;
    /// Extra distance that costs but does not kill.
    public float soft = 14f, w_soft = 3f;
    public float w_tap = 1f;
    public float edge = 40f, w_edge = 0.5f;
    public float land = 14f, w_land = 30f;
    public float w_mid = 0.02f;
    public float exit_bonus = 5f;
    /// State buckets: height (px) and speed (sub-units).
    public int by = 6, bv = 48;
    /// Taps are planned on every tick for the first ticks, then on every `coarse_step`th.
    public int fine_ticks = 8, coarse_step = 2;
    /// Fewest ticks between two taps.
    public int min_gap = 1;
    public float w_ghost = 0f;
    public int ghost_ticks = 0;
    public int window = 6;

    public void set(string key, string value)
    {
        var f = typeof(MpcParams).GetField(key) ?? throw new ArgumentException("no mpc knob " + key);
        f.SetValue(this, f.FieldType == typeof(int) ? int.Parse(value)
            : float.Parse(value, System.Globalization.CultureInfo.InvariantCulture));
    }
}

/// Plans taps over the bird's own exact movement (gravity, flap, wall
/// bounce, room speed) against what Sight saw: hazards moved on in a
/// straight line with a margin that grows over the horizon, and the spikes
/// of the wall ahead as they are now. It reads the present sim only.
public sealed class Planner
{
    const long R = SimConfig.BIRD_RADIUS;
    const long SUB = SimConfig.SUB;
    const int CAP = 8192;

    public readonly MpcParams p;
    public readonly Sight sight = new();

    // The bird's x and gravity per sim step ahead (the same for every plan).
    readonly long[] _x = new long[402];
    readonly bool[] _near = new bool[402];
    readonly long[] _grav = new long[402];
    int _bounce;
    // Frontier nodes.
    long[] _y = new long[CAP], _vy = new long[CAP], _y2 = new long[CAP], _vy2 = new long[CAP];
    float[] _c = new float[CAP], _c2 = new float[CAP];
    short[] _first = new short[CAP], _first2 = new short[CAP], _since = new short[CAP], _since2 = new short[CAP];
    int _n, _n2;
    readonly int[] _slot, _stamp;
    int _gen;
    readonly int _nvb;
    readonly long[] _depth = new long[SimConfig.SLOT_COUNT];

    // Present wall facts.
    long _left, _right, _reach, _hb, _mask, _shift, _side;
    bool _exit;
    long _exit_a, _exit_b;
    bool _exit_two;
    float _target;

    /// The tick of the first tap of the last plan (-1: none), and how it ended.
    public int first_tap;
    public bool doomed;
    public int doom_tick;
    public long expansions;

    public Planner(MpcParams prm)
    {
        p = prm;
        int nyb = (int)((SimConfig.KILL_BOTTOM - SimConfig.KILL_TOP) / (p.by * SUB)) + 2;
        _nvb = (int)(2 * SimConfig.MAX_FALL_VY / p.bv) + 2;
        _slot = new int[nyb * _nvb];
        _stamp = new int[nyb * _nvb];
        sight.ghost_ticks = p.ghost_ticks;
        sight.window = p.window;
    }

    /// Looks at the present sim and plans. Returns whether the plan taps now.
    /// `since`: ticks since the bot's last tap.
    public bool plan(GameSim sim, int since)
    {
        sight.look(sim);
        var s = sim.state;
        var room = sim.room;
        _side = s.vx > 0 ? 1 : 0;
        _left = room.wall_left();
        _right = room.wall_right();
        _reach = room.max_spike_depth();
        _hb = room.spike_half_base();
        _mask = sim.wall_mask(_side);
        _shift = sim.wall_shift(_side);
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++) _depth[slot] = room.slot_depth(_side, slot);
        _exit = s.exit_open && s.exit_side == _side && !sim.exit_locked();
        _exit_a = s.exit_a_y;
        _exit_b = s.exit_b_y;
        _exit_two = s.exit_b_kind != ExitKind.NORMAL;
        bool flip = room.def.variants.Count > 0 && room._variant().flip_flop;
        // Where to be after the bounce: the middle, or the exit shown for the wall after.
        _target = (SimConfig.KILL_TOP + SimConfig.KILL_BOTTOM) / 2f / SUB;
        if (s.exit_preview || (s.exit_open && s.exit_side != _side))
        {
            _target = (float)s.exit_a_y / SUB;
            if (_exit_two && Math.Abs(s.exit_b_y - s.y) < Math.Abs(s.exit_a_y - s.y)) _target = (float)s.exit_b_y / SUB;
        }

        // The bird's x per step: it does not depend on the taps. _grav[j] is
        // the gravity during step j (a flip-flop room flips after the bounce step).
        long x = s.x, vx = s.vx, g = room.gravity;
        _bounce = -1;
        int steps = 0;
        for (int j = 1; j <= p.max_steps; j++)
        {
            x += vx;
            _x[j] = x;
            _near[j] = _bounce < 0 && (vx < 0 ? x - R <= _left + _reach : x + R >= _right - _reach);
            _grav[j] = g;
            bool wall = vx > 0 ? x + R >= _right : x - R <= _left;
            if (wall)
            {
                if (_bounce >= 0) break;
                _bounce = j;
                x = vx > 0 ? 2 * (_right - R) - x : 2 * (_left + R) - x;
                vx = -vx;
                if (flip) g = -g;
            }
            steps = j;
            _grav[j + 1] = g;
            if (_bounce >= 0 && j >= _bounce + p.after) break;
        }
        _grav[1] = room.gravity;

        _n = 1;
        _y[0] = s.y;
        _vy[0] = s.vy;
        _c[0] = 0;
        _first[0] = -1;
        _since[0] = (short)Math.Min(since, 1000);
        float best_done = float.MaxValue;
        int best_done_first = -1;
        doomed = false;
        int done = 0;
        long ticks0 = room.ticks;
        for (int k = 0; done < steps; k++)
        {
            int n_steps = (int)room.steps_at(ticks0 + k);
            if (done + n_steps > steps) n_steps = steps - done;
            bool may_tap = k < p.fine_ticks || k % p.coarse_step == 0;
            _n2 = 0;
            _gen++;
            for (int i = 0; i < _n; i++)
            {
                for (int tap = 0; tap < 2; tap++)
                {
                    if (tap == 1 && (!may_tap || _since[i] < p.min_gap)) break;
                    expansions++;
                    long y = _y[i], vy = _vy[i];
                    float c = _c[i];
                    int first = _first[i];
                    int snc = _since[i] + 1;
                    if (tap == 1)
                    {
                        vy = SimConfig.FLAP_VY * _grav[done + 1];
                        c += p.w_tap;
                        if (first < 0) first = k;
                        snc = 1;
                    }
                    int res = 0;
                    for (int q = 1; q <= n_steps && res == 0; q++) res = move(done + q, ref y, ref vy, ref c);
                    if (res == 1) continue;
                    if (res == 2)
                    {
                        c -= p.exit_bonus;
                        if (c < best_done)
                        {
                            best_done = c;
                            best_done_first = first;
                        }
                        continue;
                    }
                    int yb = (int)((y - SimConfig.KILL_TOP) / (p.by * SUB));
                    int vb = (int)((vy + SimConfig.MAX_FALL_VY) / p.bv);
                    int key = yb * _nvb + vb;
                    int at;
                    if (_stamp[key] == _gen)
                    {
                        at = _slot[key];
                        if (c >= _c2[at]) continue;
                    }
                    else
                    {
                        if (_n2 >= CAP) continue;
                        _stamp[key] = _gen;
                        at = _n2++;
                        _slot[key] = at;
                    }
                    _y2[at] = y;
                    _vy2[at] = vy;
                    _c2[at] = c;
                    _first2[at] = (short)first;
                    _since2[at] = (short)Math.Min(snc, 1000);
                }
            }
            done += n_steps;
            if (_n2 == 0)
            {
                // Every line dies by here (or left through the exit): keep the last living ones.
                if (best_done == float.MaxValue)
                {
                    doomed = true;
                    doom_tick = k;
                }
                break;
            }
            (_y, _y2) = (_y2, _y);
            (_vy, _vy2) = (_vy2, _vy);
            (_c, _c2) = (_c2, _c);
            (_first, _first2) = (_first2, _first);
            (_since, _since2) = (_since2, _since);
            _n = _n2;
        }
        float best = best_done;
        int best_first = best_done_first;
        bool reached = done >= steps && _n2 > 0;
        if (best_done == float.MaxValue || reached)
            for (int i = 0; i < _n; i++)
            {
                float c = _c[i];
                if (reached) c += p.w_mid * Math.Abs((float)_y[i] / SUB - _target);
                if (c < best)
                {
                    best = c;
                    best_first = _first[i];
                }
            }
        first_tap = best_first;
        return best_first == 0;
    }

    /// One sim step of the bird at step `j` ahead. 0: alive, 1: dead, 2: left through the exit.
    int move(int j, ref long y, ref long vy, ref float c)
    {
        vy = G.clampi(vy + SimConfig.GRAVITY * _grav[j], -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY);
        y += vy;
        long x = _x[j];
        if (_near[j] && hits_wall(x, y)) return 1;
        // Hazards, where they will be if they keep moving as seen.
        float xp = (float)x / SUB, yp = (float)y / SUB;
        var tracks = sight.tracks;
        for (int t = 0; t < tracks.Count; t++)
        {
            var tr = tracks[t];
            if (p.w_ghost > 0) c += ghost(tr, xp, yp);
            if (tr.count == 0) continue;
            int col = (int)MathF.Floor((xp - tr.vx * j) / Sight.CELL_PX);
            int row = (int)MathF.Floor((yp - tr.vy * j) / Sight.CELL_PX);
            if (col < 0 || col >= Sight.COLS || row < 0 || row >= Sight.ROWS) continue;
            float d = tr.dist[row * Sight.COLS + col];
            float m = Math.Min(p.m0 + (p.grow + p.wob * tr.wobble) * j, p.m_cap);
            if (d <= m) return 1;
            if (d < m + p.soft) c += p.w_soft * (1f - (d - m) / p.soft);
        }
        if (j == _bounce)
        {
            if (_exit)
            {
                long fit = SimConfig.EXIT_FIT;
                if (G.absi(y - _exit_a) <= fit || (_exit_two && G.absi(y - _exit_b) <= fit)) return 2;
            }
            // Landing close to a spike costs.
            long clear = long.MaxValue;
            for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
            {
                if (!RoomRules.has_slot(_mask, slot)) continue;
                long d = G.absi(y - SimConfig.slot_center_y(slot) - _shift) - (_hb + R);
                if (d < clear) clear = d;
            }
            float cl = (float)clear / SUB;
            if (cl < p.land) c += p.w_land * (1f - Math.Max(cl, 0f) / p.land);
        }
        if (y - R <= SimConfig.KILL_TOP || y + R >= SimConfig.KILL_BOTTOM) return 1;
        float top = (float)(y - R - SimConfig.KILL_TOP) / SUB, bottom = (float)(SimConfig.KILL_BOTTOM - y - R) / SUB;
        float e = Math.Min(top, bottom);
        if (e < p.edge) c += p.w_edge * (1f - e / p.edge);
        return 0;
    }

    float ghost(Track tr, float xp, float yp)
    {
        int col = (int)(xp / Sight.CELL_PX), row = (int)(yp / Sight.CELL_PX);
        if (col < 0 || col >= Sight.COLS || row < 0 || row >= Sight.ROWS) return 0;
        return tr.ghost[row * Sight.COLS + col] > 0 ? p.w_ghost : 0;
    }

    /// The sim's spike test on the wall ahead, with the spikes as they are now.
    bool hits_wall(long x, long y)
    {
        if (_mask == 0) return false;
        long base_x = _side == 0 ? _left : _right;
        long dir = _side == 0 ? 1 : -1;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            if (!RoomRules.has_slot(_mask, slot)) continue;
            long depth = _depth[slot];
            if (depth <= 0) continue;
            long cy = SimConfig.slot_center_y(slot) + _shift;
            if (G.absi(y - cy) > _hb + R) continue;
            if (SimMath.circle_hits_triangle(x, y, R, base_x, cy - _hb, base_x, cy + _hb, base_x + dir * depth, cy))
                return true;
        }
        return false;
    }
}
