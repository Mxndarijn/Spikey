namespace FastSim;

/// Port of sim/hazards/boss_watcher.gd.
public class BossWatcher : Boss
{
    public static class Beam { public const long OFF = 0, WARN = 1, ON = 2; }
    public static class Dart { public const long NONE = 0, MARK = 1, FLY = 2; }

    public static readonly long[] ROWS =
    {
        200 * SimConfig.SUB,
        260 * SimConfig.SUB,
        320 * SimConfig.SUB,
        380 * SimConfig.SUB,
        440 * SimConfig.SUB,
        500 * SimConfig.SUB,
        560 * SimConfig.SUB,
    };
    public const long CYCLE = 240;
    public const long BEAM_TELL = SimConfig.WARN_TICKS;
    public const long GAZE_TELL = 60;
    public const long BEAM_ON = 70;
    public const long HALF_H = 6 * SimConfig.SUB;
    public const long MAX_RUN = 3;
    public const long GAZE = 120;
    public const long GAZE_FAST = 100;
    public const long GAZE_AT = 130;
    public const long DART_SPEED = 10 * SimConfig.SUB;
    public const long DART_LEN = 34 * SimConfig.SUB;
    public const long DART_HALF = 10 * SimConfig.SUB;
    public const long LANE_MIN = 110 * SimConfig.SUB;
    public const long LANE_MAX = 530 * SimConfig.SUB;

    public long lit = 0;
    public long beam = Beam.OFF;
    public long beam_t = 0;
    public long dart = Dart.NONE;
    public long dart_lane = 0;
    public long dart_side = 0;
    public long dart_x = 0;
    public long dart_t = 0;
    public long _lit_k = -1;

    public BossWatcher()
    {
        kind = "boss_watcher";
    }

    public long lit_rows(long p, long k)
    {
        long count = (p == 1 ? 3 : 2) + (tier >= 2 ? 1 : 0);
        var rng = new SimRng(draw(k, p));
        for (long _try = 0; _try < 20; _try++)
        {
            long mask = 0;
            long n = 0;
            while (n < count)
            {
                long r = rng.next_below(ROWS.Length);
                if (((mask >> (int)r) & 1) == 0)
                {
                    mask |= 1L << (int)r;
                    n += 1;
                }
            }
            if (_longest_run(mask) <= MAX_RUN) return mask;
        }
        return 0b1010101 & ((1L << ROWS.Length) - 1);
    }

    public static long _longest_run(long mask)
    {
        long best = 0;
        long run = 0;
        for (long i = 0; i < ROWS.Length; i++)
        {
            run = ((mask >> (int)i) & 1) == 1 ? run + 1 : 0;
            best = G.maxi(best, run);
        }
        return best;
    }

    public long gaze_every() => tier >= 3 ? GAZE_FAST : GAZE;

    public override void boss_step(GameSim sim)
    {
        beam = Beam.OFF;
        long c = clock();
        if (c < 0)
        {
            dart = Dart.NONE;
            return;
        }
        if (phase != 2)
        {
            long k = c / CYCLE;
            beam_t = c % CYCLE;
            if (_lit_k != k)
            {
                _lit_k = k;
                lit = lit_rows(phase, k);
            }
            if (beam_t < BEAM_TELL) beam = Beam.WARN;
            else if (beam_t < BEAM_TELL + BEAM_ON) beam = Beam.ON;
        }
        long g = phase == 2 ? c % gaze_every() : (c % CYCLE) - GAZE_AT;
        if (phase != 1) _gaze(sim, g);
    }

    public void _gaze(GameSim sim, long g)
    {
        if (g == 0)
        {
            dart = Dart.MARK;
            dart_lane = G.clampi(sim.state.y, LANE_MIN, LANE_MAX);
            dart_side = sim.state.vx > 0 ? 1 : 0;
        }
        if (dart == Dart.MARK)
        {
            dart_t = g;
            if (g >= GAZE_TELL)
            {
                dart = Dart.FLY;
                dart_x = dart_side == 1 ? sim.room.wall_right() : sim.room.wall_left();
            }
        }
        else if (dart == Dart.FLY)
        {
            dart_x += dart_side == 1 ? -DART_SPEED : DART_SPEED;
            if (dart_x < -DART_LEN || dart_x > SimConfig.WORLD_W + DART_LEN) dart = Dart.NONE;
        }
    }

    public override void boss_down_step(GameSim _sim)
    {
        beam = Beam.OFF;
        dart = Dart.NONE;
    }

    public override bool boss_kills(GameSim sim)
    {
        if (beam == Beam.ON)
        {
            for (long i = 0; i < ROWS.Length; i++)
            {
                if (((lit >> (int)i) & 1) == 1)
                {
                    long y = ROWS[i];
                    if (sim.bird_touches_rect(sim.room.wall_left(), y - HALF_H, sim.room.wall_right(), y + HALF_H))
                        return true;
                }
            }
        }
        if (dart == Dart.FLY)
        {
            long back = dart_side == 1 ? dart_x + DART_LEN : dart_x - DART_LEN;
            if (sim.bird_touches_rect(dart_x, dart_lane - DART_HALF, back, dart_lane + DART_HALF)) return true;
        }
        return false;
    }

    public override bool safe_y(long y, long steps)
    {
        if (phase == 2) return true;
        long c = clock_in(steps);
        if (c < 0) return true;
        long lt = c % CYCLE;
        if (lt < BEAM_TELL || lt >= BEAM_TELL + BEAM_ON) return true;
        long mask = lit_rows(phase, c / CYCLE);
        for (long i = 0; i < ROWS.Length; i++)
            if (((mask >> (int)i) & 1) == 1 && G.absi(y - ROWS[i]) < HALF_H + SimConfig.BIRD_RADIUS + MARGIN)
                return false;
        return true;
    }

    public override long checksum(long h) =>
        mix_all(base.checksum(h), lit, beam, beam_t, dart, dart_lane, dart_side, dart_x, dart_t, _lit_k);
}
