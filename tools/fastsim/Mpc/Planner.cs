namespace FastSim.Mpc;

/// The knobs of the MPC bot (docs/MPC_BOT.md). Lengths in px, times in ticks.
public sealed class MpcParams
{
    /// Sim steps planned past the next wall bounce, and at most in all.
    public int after = 78, max_steps = 170;
    /// A predicted hazard kills within this distance: m0 now, growing per step ahead.
    public float m0 = 4f, grow = 0.10f, wob = 0.5f, wob_floor = 0.08f, m_cap = 26f;
    /// Of that margin, the part that kills a plan outright: m0 plus this share of the growth.
    /// The rest is a risk band: it costs `w_risk` per step, more the deeper in.
    public float hard = 0.3f, w_risk = 8f;
    /// Touching a body that does not kill (a bumper, a bubble) costs this much per step.
    public float w_body = 15f;
    /// Use the edges' acceleration too (0: straight lines only).
    public int accel = 0;
    /// An edge moving outward may speed up: it is taken to run ahead by `lead` x the shape's
    /// observed speed changes (px per step per step), which widens the shape the way it moves.
    public float lead = 0f;
    /// Read on-screen warnings (glowing pistons, charging beams); learn which shapes follow the bird.
    public int warnings = 1, chase = 1;
    public float warn_pad = 3f, w_warn = 4f;
    public float min_accel = 0.04f;
    /// No shape is taken to move faster than this (px per step).
    public float v_max = 12f;
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
    public int window = 10;
    /// Steps a lift felt just now (an updraft) is taken to last where it has not been felt before.
    public int persist = 8;

    public void set(string key, string value)
    {
        var f = typeof(MpcParams).GetField(key) ?? throw new ArgumentException("no mpc knob " + key);
        if (f.FieldType == typeof(int)) f.SetValue(this, int.Parse(value));
        else f.SetValue(this, float.Parse(value, System.Globalization.CultureInfo.InvariantCulture));
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
    readonly long[] _lift = new long[402];
    // Lift felt per column of the room (an updraft), and the step it was felt at.
    readonly long[] _lift_at = new long[Sight.COLS];
    readonly long[] _lift_t = new long[Sight.COLS];
    long _felt_room = -1, _lift_now;
    // The bird as the last plan expected it one tick on.
    bool _have_prev;
    long _prev_vy, _prev_y, _prev_x, _prev_room, _prev_tick;
    int _bounce;
    // Frontier nodes.
    long[] _y = new long[CAP], _vy = new long[CAP], _y2 = new long[CAP], _vy2 = new long[CAP];
    float[] _c = new float[CAP], _c2 = new float[CAP];
    // Where the shape that follows the bird (if any) has got to on this line, px.
    float[] _f = new float[CAP], _f2 = new float[CAP];
    Blob _chaser;
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
        sight.window = p.window;
        sight.use_accel = p.accel != 0;
        sight.min_accel = p.min_accel;
        sight.read_warnings = p.warnings != 0;
        sight.learn_chase = p.chase != 0;
    }

    /// Looks at the present sim and plans. Returns whether the plan taps now.
    /// `since`: ticks since the bot's last tap.
    public bool plan(GameSim sim, int since)
    {
        sight.look(sim);
        var s = sim.state;
        var room = sim.room;
        feel(sim);
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
            int lc = (int)Math.Clamp(x / Sight.CELL, 0, Sight.COLS - 1);
            _lift[j] = _lift_t[lc] >= 0 && room.t - _lift_t[lc] < 1500 ? _lift_at[lc] : (j <= p.persist ? _lift_now : 0);
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

        _chaser = null;
        foreach (var b in sight.blobs)
            if (b.chase > 0f)
            {
                _chaser = b;
                break;
            }
        _f[0] = _chaser == null ? 0f : (_chaser.e[2] + _chaser.e[3]) / 2f;
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
                    float c = _c[i], f = _f[i];
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
                    for (int q = 1; q <= n_steps && res == 0; q++) res = move(done + q, ref y, ref vy, ref c, ref f);
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
                    _f2[at] = f;
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
            (_f, _f2) = (_f2, _f);
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

    /// Tells the planner the tap that was really made this tick, so the next
    /// look can compare where the bird is with where its own movement puts it.
    public void expect(GameSim sim, bool tap)
    {
        var s = sim.state;
        var room = sim.room;
        _have_prev = room.steps_at(room.ticks) == 1 && s.arrival_hold == 0;
        long vy = tap ? SimConfig.FLAP_VY * room.gravity : s.vy;
        vy = G.clampi(vy + SimConfig.GRAVITY * room.gravity, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY);
        _prev_vy = vy;
        _prev_y = s.y + vy;
        _prev_x = s.x + s.vx;
        _prev_room = s.room_index;
        _prev_tick = s.tick + 1;
    }

    /// What pushed the bird beyond its own movement since the last tick: a
    /// steady lift (an updraft) is remembered per column of the room.
    void feel(GameSim sim)
    {
        var s = sim.state;
        if (s.room_index != _felt_room)
        {
            _felt_room = s.room_index;
            Array.Fill(_lift_t, -1);
            _lift_now = 0;
            _have_prev = false;
        }
        if (!_have_prev || s.room_index != _prev_room || s.tick != _prev_tick) return;
        _have_prev = false;
        // Past a wall bounce the x differs: nothing to learn that tick.
        if (s.x != _prev_x) return;
        long lift = s.vy - _prev_vy;
        // A bump or a carry is not a steady push.
        if (Math.Abs(lift) > 2 * SimConfig.GRAVITY || s.y != _prev_y + lift) lift = 0;
        _lift_now = lift;
        int c = (int)Math.Clamp(s.x / Sight.CELL, 0, Sight.COLS - 1);
        _lift_at[c] = lift;
        _lift_t[c] = sim.room.t;
    }

    /// One sim step of the bird at step `j` ahead. 0: alive, 1: dead, 2: left through the exit.
    int move(int j, ref long y, ref long vy, ref float c, ref float f)
    {
        // The follower steps toward where the bird was, then the bird moves.
        if (_chaser != null) f += Math.Clamp((float)y / SUB - f, -_chaser.chase, _chaser.chase);
        vy = G.clampi(vy + SimConfig.GRAVITY * _grav[j], -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY);
        if (_lift[j] != 0) vy = G.clampi(vy + _lift[j], -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY);
        y += vy;
        long x = _x[j];
        if (_near[j] && hits_wall(x, y)) return 1;
        // Shapes, where they will be if their edges keep moving as seen.
        float xp = (float)x / SUB, yp = (float)y / SUB;
        var blobs = sight.blobs;
        for (int t = 0; t < blobs.Count; t++)
        {
            var b = blobs[t];
            float jj = 0.5f * j * j;
            float x0 = ahead(b, 0, j), x1 = ahead(b, 1, j), y0, y1;
            if (b == _chaser)
            {
                float half = (b.e[3] - b.e[2]) / 2f;
                y0 = f - half;
                y1 = f + half;
            }
            else
            {
                y0 = ahead(b, 2, j);
                y1 = ahead(b, 3, j);
            }
            if (x1 - x0 < 2f || y1 - y0 < 2f) continue;
            float m = Math.Min(p.m0 + p.grow * j + p.wob * Math.Max(b.wobble - p.wob_floor, 0f) * jj, p.m_cap);
            float far = m + p.soft;
            if (xp < x0 - far || xp > x1 + far || yp < y0 - far || yp > y1 + far) continue;
            float ox = xp < x0 ? x0 - xp : xp > x1 ? xp - x1 : 0f;
            float oy = yp < y0 ? y0 - yp : yp > y1 ? yp - y1 : 0f;
            // The same place in the shape as it is now.
            float sx = b.e[0] + (Math.Clamp(xp, x0, x1) - x0) * (b.e[1] - b.e[0]) / (x1 - x0);
            float sy = b.e[2] + (Math.Clamp(yp, y0, y1) - y0) * (b.e[3] - b.e[2]) / (y1 - y0);
            int col = Math.Clamp((int)(sx / Sight.CELL_PX) - b.wc0, 0, b.ww - 1);
            int row = Math.Clamp((int)(sy / Sight.CELL_PX) - b.wr0, 0, b.wh - 1);
            float d = b.dist[row * b.ww + col];
            if (ox > 0 || oy > 0) d += MathF.Sqrt(ox * ox + oy * oy);
            if (d <= m)
            {
                if (b.body) c += p.w_body;
                else if (d <= p.m0 + (m - p.m0) * p.hard) return 1;
                else c += p.w_risk * (1.5f - (d - p.m0) / Math.Max(m - p.m0, 0.01f));
            }
            else if (d < far) c += (b.body ? 0.3f : 1f) * p.w_soft * (1f - (d - m) / p.soft);
        }
        var warns = sight.warns;
        for (int t = 0; t < warns.Count; t++)
        {
            var w = warns[t];
            if (j < w.eta - 1 || j > w.eta + w.dur) continue;
            float pad = p.warn_pad;
            if (xp < w.x0 - pad - p.soft || xp > w.x1 + pad + p.soft || yp < w.y0 - pad - p.soft || yp > w.y1 + pad + p.soft) continue;
            float ox = xp < w.x0 ? w.x0 - xp : xp > w.x1 ? xp - w.x1 : 0f;
            float oy = yp < w.y0 ? w.y0 - yp : yp > w.y1 ? yp - w.y1 : 0f;
            float d = Math.Max(ox, oy);
            if (d <= pad) return 1;
            if (d < pad + p.soft) c += p.w_warn * (1f - (d - pad) / p.soft);
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

    /// Where edge `k` of a shape is `j` steps on: its speed and acceleration
    /// carried on, the speed never past `v_max`.
    float ahead(Blob b, int k, int j)
    {
        float v = b.v[k], a = b.a[k];
        // Outward: left and top edges moving to smaller values, right and bottom to larger.
        float outward = (k & 1) == 1 ? 1f : -1f;
        if (a == 0f && p.lead > 0f && v * outward > 0.3f) a = outward * p.lead * Math.Min(b.wobble, 0.4f);
        if (a == 0f) return b.e[k] + v * j;
        // Steps until the speed limit.
        float lim = a > 0 ? (p.v_max - v) / a : (-p.v_max - v) / a;
        if (lim < 0) lim = 0;
        if (j <= lim) return b.e[k] + v * j + 0.5f * a * j * j;
        float at = b.e[k] + v * lim + 0.5f * a * lim * lim;
        return at + (v + a * lim) * (j - lim);
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
