namespace FastSim.Mpc;

/// The boss tells and bodies the game draws (game/run/painters/boss_*_painter.gd),
/// read as warnings. Only what is on screen: the rows that flicker, the dart's
/// dashed lane and glowing wall, the slam line, the jaw lane, a crate's dashed
/// column, the saw's landing ring, and the bodies themselves. When a tell
/// strikes is counted from the step it was first seen (each tell shows for the
/// boss's TELL steps, a rule a player learns); a tell first seen mid-way is
/// taken as due any time from the next step to a full TELL on. The bot never
/// reads a boss's seed, its clock or its next attack (MpcCheck bans them).
public sealed partial class Sight
{
    /// A boss tell seen on screen: the step it first showed, the last step it
    /// showed, and what it showed then (a target height, the phase).
    sealed class Tell
    {
        public long start, last, a, b, c;
        public bool known;
    }

    readonly Dictionary<int, Tell> _tells = new();
    long _first_t = -1;

    const float S = SimConfig.SUB;
    const float RP = SimConfig.BIRD_RADIUS / S;
    const float W_PX = SimConfig.WORLD_W / S, H_PX = SimConfig.WORLD_H / S;

    /// The tell `key` (hazard place * 8 + which tell) for this look: started
    /// now if it was off at the last step. Null while it is off.
    Tell tell(int key, bool on, long t)
    {
        _tells.TryGetValue(key, out var k);
        if (!on) return null;
        if (k == null)
        {
            k = new Tell();
            _tells[key] = k;
            k.start = t;
            k.known = t > _first_t;
        }
        else if (k.last < t - 1)
        {
            k.start = t;
            k.known = true;
        }
        k.last = t;
        return k;
    }

    Tell recall(int key) => _tells.GetValueOrDefault(key);

    /// Steps from now until a tell of `len` steps strikes: the earliest and latest.
    static (int lo, int hi) due(Tell k, long t, long len)
    {
        int el = (int)(t - k.start);
        int hi = (int)len - el;
        return (k.known ? hi : Math.Min(hi, 1), hi);
    }

    void boss_warnings(GameSim sim, Boss boss, int at)
    {
        if (boss.down_at >= 0) return;
        long t = sim.room.t;
        if (boss is BossWatcher w) watcher(sim, w, at * 8, t);
        else if (boss is BossCrusher c) crusher(c, at * 8, t);
        else if (boss is BossSaw s) saw(s, at * 8, t);
    }

    /// A disc of bird centres to be out of, as nested boxes around it.
    void disc(float cx, float cy, float r, int eta, int dur)
    {
        r += RP;
        const int N = 4;
        for (int q = 0; q < N; q++)
        {
            float y = r * q / N;
            float hx = MathF.Sqrt(r * r - y * y), hy = r * (q + 1) / N;
            warns.Add(new Warn(cx - hx, cy - hy, cx + hx, cy + hy, eta, dur));
        }
    }

    // ---- The Watcher: flickering rows, then beams; a dashed lane, then the dart.

    void watcher(GameSim sim, BossWatcher w, int key, long t)
    {
        float x0 = sim.room.wall_left() / S - RP, x1 = sim.room.wall_right() / S + RP;
        // The beams: lit rows flicker for TELL steps, then burn for BEAM_ON.
        tell(key, w.beam == BossWatcher.Beam.WARN, t);
        var k = recall(key);
        if (w.beam != BossWatcher.Beam.OFF && k != null && t - k.last <= BossWatcher.TELL + BossWatcher.BEAM_ON)
        {
            var (lo, hi) = due(k, t, BossWatcher.TELL);
            int eta = w.beam == BossWatcher.Beam.ON ? Math.Min(lo, 0) : lo;
            int dur = hi - eta + (int)BossWatcher.BEAM_ON;
            float half = BossWatcher.HALF_H / S + RP;
            for (int i = 0; i < BossWatcher.ROWS.Length; i++)
            {
                if (((w.lit >> i) & 1) == 0) continue;
                float y = BossWatcher.ROWS[i] / S;
                warns.Add(new Warn(x0, y - half, x1, y + half, eta, dur));
            }
        }
        // The dart: its lane is marked and its wall glows for TELL steps, then it flies across.
        var d = tell(key + 1, w.dart == BossWatcher.Dart.MARK, t);
        if (w.dart == BossWatcher.Dart.MARK && d != null)
        {
            var (lo, hi) = due(d, t, BossWatcher.TELL);
            long wall = w.dart_side == 1 ? sim.room.wall_right() : sim.room.wall_left();
            dart(w, wall / S, lo, hi);
        }
        else if (w.dart == BossWatcher.Dart.FLY) dart(w, w.dart_x / S, 0, 0);
    }

    /// The dart's lane in pieces, each due when the dart's tip (at `tip` px
    /// now, or when it starts) gets there and clear once its back has passed.
    void dart(BossWatcher w, float tip, int lo, int hi)
    {
        const float SEG = 40f;
        float speed = BossWatcher.DART_SPEED / S, len = BossWatcher.DART_LEN / S;
        float dir = w.dart_side == 1 ? -1f : 1f;
        float y = w.dart_lane / S, half = BossWatcher.DART_HALF / S + RP;
        for (float u = -len; u < W_PX; u += SEG)
        {
            float a = tip + dir * u, b = tip + dir * (u + SEG);
            if (Math.Max(a, b) < -RP || Math.Min(a, b) > W_PX + RP) continue;
            int s_in = Math.Max(0, (int)MathF.Floor((u - RP) / speed));
            int s_out = (int)MathF.Ceiling((u + SEG + RP + len) / speed);
            warns.Add(new Warn(Math.Min(a, b) - RP, y - half, Math.Max(a, b) + RP, y + half,
                lo + s_in, hi - lo + s_out - s_in + 1));
        }
    }

    // ---- The Crusher: a slam line, the jaw lane, crates' columns.

    void crusher(BossCrusher c, int key, long t)
    {
        float bite = BossCrusher.BITE / S, teeth = BossCrusher.TEETH / S;
        var k = tell(key, c.telling, t);
        if (k != null)
        {
            // What the dashes show: the slam line (phase 1) or the jaw lane.
            k.a = c.phase == 1 ? c.slam_y : c.jaw ? c.lane_to : -1;
            k.b = c.phase;
        }
        k = recall(key);
        // A slam line is spent once the press lifts; a jaw lane holds until the next one shows.
        long spent = c.phase == 1 ? BossCrusher.LIFT_AT : BossCrusher.CYCLE;
        if (k != null && k.b == c.phase && k.a >= 0 && t - k.start < spent)
        {
            var (lo, hi) = due(k, t, BossCrusher.TELL);
            float press = c.press_y / S + bite, plate = c.plate_y / S - bite;
            if (c.phase == 1)
            {
                // The press slams down to the line, holds, then lifts.
                float to = k.a / S + bite;
                int hold = (int)(BossCrusher.LIFT_AT - BossCrusher.SLAM_AT);
                jaw(true, press, to, BossCrusher.SLAM_DOWN / S, lo, hi, hold, BossCrusher.LIFT / S);
            }
            else
            {
                float half = c.lane_half() / S;
                float lane = k.a / S;
                int stay = (int)BossCrusher.CYCLE;
                jaw(true, press, lane - half - teeth + bite, BossCrusher.JAW_SPEED / S, lo, hi, stay, 0);
                jaw(false, plate, lane + half + teeth - bite, BossCrusher.JAW_SPEED / S, lo, hi, stay, 0);
            }
        }
        for (int i = 0; i < 2; i++)
        {
            var m = tell(key + 2 + i, c.crate[i] == BossCrusher.Crate.MARK, t);
            if (c.crate[i] == BossCrusher.Crate.MARK && m != null)
            {
                var (lo, hi) = due(m, t, BossCrusher.TELL);
                // It hangs under the press, which may still be moving to the jaw lane shown.
                float now = (c.press_y + BossCrusher.TEETH) / S, then = now;
                var j = recall(key);
                if (j != null && j.b == c.phase && j.a >= 0) then = (j.a - c.lane_half()) / S;
                crate(c, i, Math.Max(now, then), Math.Min(now, then), lo, hi);
            }
            else if (c.crate[i] == BossCrusher.Crate.FALL)
            {
                float top = (c.crate_y[i] - BossCrusher.CRATE_HALF) / S;
                crate(c, i, top, top, 0, 0);
            }
        }
    }

    /// A jaw moving its kill line from `now` to `to` at `speed` px per step
    /// once the tell is due, staying `stay` steps, then going back at `back`
    /// px per step (0: until the next tell shows): a band per 12 px.
    void jaw(bool top, float now, float to, float speed, int lo, int hi, int stay, float back)
    {
        float gap = top ? to - now : now - to;
        if (gap <= 0) return;
        const float BAND = 12f;
        int start = Math.Max(lo, 1);
        for (float d = Math.Min(BAND, gap); ; d = Math.Min(d + BAND, gap))
        {
            float line = top ? now + d : now - d;
            int s = (int)MathF.Ceiling(d / speed) - 1;
            int dur = hi - lo + stay - s + (back > 0 ? (int)MathF.Ceiling((gap - d) / back) + 1 : 0);
            if (top) warns.Add(new Warn(-RP, -RP, W_PX + RP, line + RP, start + s, dur));
            else warns.Add(new Warn(-RP, line - RP, W_PX + RP, H_PX + RP, start + s, dur));
            if (d >= gap) break;
        }
    }

    /// A crate's column below it in pieces, each due when the falling crate
    /// (its top between `high` and `low` px when it starts) gets there.
    void crate(BossCrusher c, int i, float low, float high, int lo, int hi)
    {
        const float BAND = 24f;
        float half = BossCrusher.CRATE_HALF / S, speed = BossCrusher.CRATE_SPEED / S;
        float x = c.crate_x[i] / S, floor = (c.plate_y - BossCrusher.TEETH) / S;
        for (float ya = high; ya < floor; ya += BAND)
        {
            float yb = Math.Min(ya + BAND, floor);
            int s_in = Math.Max(0, (int)MathF.Floor((ya - RP - low - 2 * half) / speed));
            int s_out = (int)MathF.Ceiling((yb + RP - high) / speed);
            warns.Add(new Warn(x - half - RP, ya - RP, x + half + RP, yb + RP, Math.Max(lo, 0) + s_in,
                hi - lo + s_out - s_in + 1));
        }
    }

    // ---- Saw King: its blade ring, the dashed landing ring, the ring of blades it throws out.

    void saw(BossSaw s, int key, long t)
    {
        float kx = BossSaw.KING_X / S, ky = s.king_y / S;
        float king = BossSaw.KING_R / S;
        float blades = s.ring >= BossSaw.RING_SHOW ? (s.ring + BossSaw.BLADE_R) / S : 0f;
        var k = tell(key, s.telling, t);
        if (k != null && k.start == t)
        {
            // The dashed ring shows where it lands; it jumps from where it sits now.
            k.a = s.to_y;
            k.b = s.phase;
            k.c = s.king_y;
        }
        // The spinning blades around it now: as a whole disc while they spin.
        if (blades > 0) disc(kx, ky, blades, 0, s.telling ? (int)BossSaw.TELL : 30);
        k = recall(key);
        if (k == null || k.b != s.phase) return;
        long cycle = s.cycle();
        if (t - k.start > cycle) return;
        var (lo, hi) = due(k, t, BossSaw.TELL);
        int jump = (int)BossSaw.JUMP;
        float from = k.c / S, to = k.a / S;
        float r = Math.Max(king, s.phase == 3 ? (BossSaw.RING_HOP + BossSaw.BLADE_R) / S : 0f);
        // The jump, from the tell's end over JUMP steps, then sitting where it landed.
        if (hi + jump >= 0)
        {
            for (int q = 0; q <= jump; q += 6)
            {
                float y = from + (to - from) * q / jump;
                disc(kx, y, r, lo + q - 3, hi - lo + 7);
            }
            disc(kx, to, r, lo + jump, hi - lo + (int)cycle);
        }
        if (s.phase == 2)
        {
            // The blades fly out to the dashed ring once it has landed, stay, and come back.
            float reach = (s.ring_max() + BossSaw.BLADE_R) / S;
            int show = (int)(BossSaw.RING_SHOW / BossSaw.RING_SPEED);
            int out_ = (int)((s.ring_max() - BossSaw.RING_SHOW) / BossSaw.RING_SPEED);
            int at = lo + jump + show - 1;
            int dur = hi - lo + (int)(BossSaw.RING_IN - BossSaw.RING_OUT) - show + out_ + 2;
            if (at + dur >= 0) disc(kx, to, reach, at, dur);
        }
    }
}
