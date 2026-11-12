namespace FastSim;

/// Port of sim/hazards/boss_crusher.gd.
public class BossCrusher : Boss
{
    public static class Crate { public const long NONE = 0, MARK = 1, FALL = 2; }

    public const long CYCLE = 240;
    public const long TELL = SimConfig.WARN_TICKS;
    public const long TEETH = 24 * SimConfig.SUB;
    public const long BITE = 20 * SimConfig.SUB;
    public const long PRESS_REST = SimConfig.KILL_TOP - TEETH;
    public const long PLATE_REST = SimConfig.KILL_BOTTOM + TEETH;
    public const long SLAM_DOWN = 12 * SimConfig.SUB;
    public const long LIFT = 6 * SimConfig.SUB;
    public const long SLAM_AT = TELL;
    public const long LIFT_AT = 170;
    public static readonly long[] SLAMS = { 250 * SimConfig.SUB, 320 * SimConfig.SUB };
    public const long SLAM_TIER = 30 * SimConfig.SUB;
    public static readonly long[] LANE_HALF = { 116 * SimConfig.SUB, 100 * SimConfig.SUB, 90 * SimConfig.SUB };
    public const long LANE_FIRST = 340 * SimConfig.SUB;
    public const long LANE_STEP_MIN = 40 * SimConfig.SUB;
    public static readonly long[] LANE_STEP_MAX = { 100 * SimConfig.SUB, 80 * SimConfig.SUB, 80 * SimConfig.SUB };
    public const long JAW_SPEED = 3 * SimConfig.SUB;
    public const long CRATE_AT = 110;
    public const long CRATE_FALL = TELL + CRATE_AT;
    public const long CRATE_HALF = 16 * SimConfig.SUB;
    public const long CRATE_SPEED = 6 * SimConfig.SUB;
    public const long COLUMNS = 7;
    public const long COLUMN_X0 = 60 * SimConfig.SUB;
    public const long COLUMN_STEP = 40 * SimConfig.SUB;
    public const long CRATE_CLEAR = 60 * SimConfig.SUB;

    public long press_y = PRESS_REST;
    public long plate_y = PLATE_REST;
    public long slam_y = 0;
    public long lane_from = LANE_FIRST;
    public long lane_to = LANE_FIRST;
    public bool telling = false;
    public long[] crate_x = { 0, 0 };
    public long[] crate_y = { 0, 0 };
    public long[] crate = { Crate.NONE, Crate.NONE };
    public bool jaw = false;
    public long _k = -1;

    public BossCrusher()
    {
        kind = "boss_crusher";
    }

    public override Hazard clone_deep()
    {
        var c = (BossCrusher)MemberwiseClone();
        c.crate_x = (long[])crate_x.Clone();
        c.crate_y = (long[])crate_y.Clone();
        c.crate = (long[])crate.Clone();
        return c;
    }

    public long lane_half() => LANE_HALF[tier - 1];

    public long slam_of(long k) => SLAMS[draw(k, 1) % SLAMS.Length] + (tier >= 2 ? SLAM_TIER : 0) - TEETH;

    public override void boss_step(GameSim sim)
    {
        telling = false;
        long c = clock();
        long press_to = jaw ? press_y : PRESS_REST;
        long plate_to = plate_y;
        if (c >= 0 && phase == 1)
        {
            long k = c / CYCLE;
            long lt = c % CYCLE;
            slam_y = slam_of(k);
            telling = lt < SLAM_AT;
            press_to = lt >= SLAM_AT && lt < LIFT_AT ? slam_y : PRESS_REST;
        }
        else if (c >= 0)
        {
            long k = c / CYCLE;
            long lt = c % CYCLE;
            if (_k != k)
            {
                _k = k;
                lane_from = jaw ? lane_to : -1;
                lane_to = jaw ? _next_lane(k) : LANE_FIRST;
                jaw = true;
            }
            telling = lt < TELL;
            long lane = lt >= TELL ? lane_to : lane_from;
            if (lane >= 0)
            {
                press_to = lane - lane_half() - TEETH;
                plate_to = lane + lane_half() + TEETH;
            }
            if (phase == 3) _crates(sim, lt);
        }
        press_y = _toward(press_y, press_to, phase == 1 ? SLAM_DOWN : JAW_SPEED, LIFT);
        plate_y = _toward(plate_y, plate_to, JAW_SPEED, JAW_SPEED);
    }

    public override void on_phase()
    {
        _k = -1;
        crate = new long[] { Crate.NONE, Crate.NONE };
    }

    public long _next_lane(long k)
    {
        long lo = PRESS_REST + TEETH + lane_half();
        long hi = PLATE_REST - TEETH - lane_half();
        long span = LANE_STEP_MAX[tier - 1] - LANE_STEP_MIN;
        long key = k + phase * 1000;
        long d = LANE_STEP_MIN + draw(key, 2) % (span / SimConfig.SUB + 1) * SimConfig.SUB;
        if (draw(key, 3) % 2 == 0) d = -d;
        long to = lane_from + d;
        if (to < lo || to > hi) to = lane_from - d;
        return G.clampi(to, lo, hi);
    }

    public static long _toward(long from, long to, long down, long up)
    {
        if (to > from) return G.mini(from + down, to);
        return G.maxi(from - up, to);
    }

    public void _crates(GameSim sim, long lt)
    {
        if (lt == CRATE_AT)
        {
            long count = tier >= 2 ? 2 : 1;
            long used = -1;
            for (long i = 0; i < count; i++)
            {
                long col = _pick_column(sim, used, i);
                used = col;
                crate[i] = Crate.MARK;
                crate_x[i] = COLUMN_X0 + col * COLUMN_STEP;
            }
            for (long i = count; i < 2; i++) crate[i] = Crate.NONE;
        }
        for (long i = 0; i < 2; i++)
        {
            if (crate[i] == Crate.NONE) continue;
            if (crate[i] == Crate.MARK)
            {
                crate_y[i] = press_y + TEETH + CRATE_HALF;
                if (lt >= CRATE_FALL) crate[i] = Crate.FALL;
            }
            else
            {
                crate_y[i] += CRATE_SPEED;
                if (crate_y[i] + CRATE_HALF >= plate_y - TEETH) crate[i] = Crate.NONE;
            }
        }
    }

    public long _pick_column(GameSim sim, long used, long i)
    {
        long fall = (2 * lane_half()) / CRATE_SPEED + 2;
        var ok = new List<long>();
        long far = 0;
        long far_d = -1;
        for (long col = 0; col < COLUMNS; col++)
        {
            if (col == used) continue;
            long x = COLUMN_X0 + col * COLUMN_STEP;
            long near = SimConfig.WORLD_W;
            for (long s = CRATE_FALL - CRATE_AT; s < CRATE_FALL - CRATE_AT + fall + 1; s += 2)
                near = G.mini(near, G.absi(x_after(sim, s) - x));
            if (near >= CRATE_CLEAR) ok.Add(col);
            if (near > far_d)
            {
                far_d = near;
                far = col;
            }
        }
        if (ok.Count == 0) return far;
        return ok[(int)(draw(_k + phase * 1000, 10 + i) % ok.Count)];
    }

    public override void boss_down_step(GameSim _sim)
    {
        telling = false;
        crate = new long[] { Crate.NONE, Crate.NONE };
        press_y = _toward(press_y, PRESS_REST, LIFT, LIFT);
        plate_y = _toward(plate_y, PLATE_REST, LIFT, LIFT);
    }

    public override bool boss_kills(GameSim sim)
    {
        if (sim.state.y - SimConfig.BIRD_RADIUS <= press_y + BITE) return true;
        if (sim.state.y + SimConfig.BIRD_RADIUS >= plate_y - BITE) return true;
        for (long i = 0; i < 2; i++)
        {
            if (crate[i] == Crate.FALL)
            {
                long x = crate_x[i];
                long y = crate_y[i];
                if (sim.bird_touches_rect(x - CRATE_HALF, y - CRATE_HALF, x + CRATE_HALF, y + CRATE_HALF))
                    return true;
            }
        }
        return false;
    }

    public override bool safe_y(long y, long steps)
    {
        long top = press_y;
        long bottom = plate_y;
        long c = clock_in(steps);
        if (c >= 0 && phase == 1)
        {
            long lt = c % CYCLE;
            if (lt >= SLAM_AT && lt < LIFT_AT) top = G.maxi(top, slam_of(c / CYCLE));
        }
        else if (c >= 0)
        {
            long k = c / CYCLE;
            long lt = c % CYCLE;
            long lane = jaw ? lane_to : LANE_FIRST;
            long spread = 0;
            if (k > _k && jaw && lt >= TELL)
                spread = G.mini((lt - TELL) * JAW_SPEED, LANE_STEP_MAX[tier - 1]);
            top = G.maxi(top, lane - lane_half() - TEETH + spread);
            bottom = G.mini(bottom, lane + lane_half() + TEETH - spread);
        }
        long r = SimConfig.BIRD_RADIUS + MARGIN;
        return y - r > top + BITE && y + r < bottom - BITE;
    }

    public override long checksum(long h) =>
        mix_all(
            base.checksum(h),
            press_y,
            plate_y,
            slam_y,
            lane_from,
            lane_to,
            G.B(telling),
            G.B(jaw),
            crate_x[0],
            crate_y[0],
            crate[0],
            crate_x[1],
            crate_y[1],
            crate[1],
            _k);

    public override void warnings(GameSim sim, List<long> out_)
    {
        if (down_at >= 0 || clock() < 0) return;
        long lt = clock() % CYCLE;
        long x0 = sim.room.wall_left();
        long x1 = sim.room.wall_right();
        if (telling && phase == 1)
        {
            long dur = LIFT_AT - SLAM_AT + (slam_y - PRESS_REST) / LIFT + 1;
            add_warning(out_, x0, SimConfig.KILL_TOP, x1, slam_y + BITE, SLAM_AT - lt, dur, WARN_KILL);
        }
        else if (telling)
        {
            long top = lane_to - lane_half() - TEETH + BITE;
            long bottom = lane_to + lane_half() + TEETH - BITE;
            add_warning(out_, x0, SimConfig.KILL_TOP, x1, top, TELL - lt, CYCLE, WARN_KILL);
            add_warning(out_, x0, bottom, x1, SimConfig.KILL_BOTTOM, TELL - lt, CYCLE, WARN_KILL);
        }
        for (int i = 0; i < 2; i++)
            if (crate[i] == Crate.MARK)
                add_warning(out_, crate_x[i] - CRATE_HALF, lane_to - lane_half(), crate_x[i] + CRATE_HALF, lane_to + lane_half(),
                    CRATE_FALL - lt, (2 * lane_half()) / CRATE_SPEED + 2, WARN_KILL);
    }
}
