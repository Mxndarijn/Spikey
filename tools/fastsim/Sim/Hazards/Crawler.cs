namespace FastSim;

/// Port of sim/hazards/crawler.gd.
public class Crawler : Hazard
{
    public const long SEGMENTS = 6;
    public const long SEG_RADIUS = 10 * SimConfig.SUB;
    public const long SPACING = 22 * SimConfig.SUB;
    public const long SPEED = SimConfig.SUB;
    public const long LEFT = 60 * SimConfig.SUB;
    public const long RIGHT = 300 * SimConfig.SUB;
    public const long TOP = 80 * SimConfig.SUB;
    public const long BOTTOM = 560 * SimConfig.SUB;
    public const long W = RIGHT - LEFT;
    public const long H = BOTTOM - TOP;
    public const long PERIMETER = 2 * (W + H);
    public const long START_SPAN = W - (SEGMENTS - 1) * SPACING - 50 * SimConfig.SUB;

    public const long NEAR_X = SEG_RADIUS + SimConfig.BIRD_RADIUS + 8 * SimConfig.SUB;
    public const long WALL_WINDOW = (LEFT - SimConfig.BIRD_RADIUS + NEAR_X) / SimConfig.SPEED_X + 1;
    public const long SLOT_CLEAR =
        SimConfig.SLOT_SIZE / 2 + SEG_RADIUS + SimConfig.BIRD_RADIUS + 2 * SimConfig.SUB;
    public const long EXIT_CLEAR = SimConfig.EXIT_FIT + SEG_RADIUS + SimConfig.BIRD_RADIUS + SimConfig.SUB;
    public const long FREE_RUN = 3;
    public const long REVIVE_SHIFT = 16 * SimConfig.SUB;
    public const long REVIVE_TRIES = 12;
    public const long FAR = 1L << 30;

    public long lane = 0;
    public long start = 0;
    public List<long> xs = new List<long>();
    public List<long> ys = new List<long>();

    public Crawler(long p_lane = 0)
    {
        kind = "crawler";
        lane = p_lane;
    }

    public override Hazard clone_deep()
    {
        var c = (Crawler)MemberwiseClone();
        c.xs = new List<long>(xs);
        c.ys = new List<long>(ys);
        return c;
    }

    static void _resize(List<long> l, long n)
    {
        while (l.Count < n) l.Add(0);
        if (l.Count > n) l.RemoveRange((int)n, l.Count - (int)n);
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        start = rng.next_below(START_SPAN) + lane * (W + H);
        if (sim.state.exit_open || sim.state.exit_preview)
        {
            long move = sim.state.exit_side == 1 - lane ? -REVIVE_SHIFT : REVIVE_SHIFT;
            for (long i = 0; i < REVIVE_TRIES; i++)
            {
                if (!_blocks_planned_exit(sim)) break;
                start += move;
            }
        }
        _resize(xs, SEGMENTS);
        _resize(ys, SEGMENTS);
        _place();
    }

    public override void step(GameSim _sim) { _place(); }

    public void _place()
    {
        long tail = start + t * SPEED;
        for (long i = 0; i < SEGMENTS; i++)
        {
            long s = G.posmod(tail + (SEGMENTS - 1 - i) * SPACING, PERIMETER);
            xs[(int)i] = path_x(s);
            ys[(int)i] = path_y(s);
        }
    }

    public long path_x(long s)
    {
        if (s < W) return LEFT + s;
        if (s < W + H) return RIGHT;
        if (s < 2 * W + H) return RIGHT - (s - W - H);
        return LEFT;
    }

    public long path_y(long s)
    {
        if (s < W) return TOP;
        if (s < W + H) return TOP + s - W;
        if (s < 2 * W + H) return BOTTOM;
        return BOTTOM - (s - 2 * W - H);
    }

    public override bool kills(GameSim sim)
    {
        for (long i = 0; i < SEGMENTS; i++)
        {
            if (sim.bird_touches_circle(xs[(int)i], ys[(int)i], SEG_RADIUS)) return true;
        }
        return false;
    }

    public override bool blocks_exit(GameSim sim, long side, long y)
    {
        var span = _in_the_way(sim, start, side, t + sim.steps_to_wall(side), 0);
        return y > span[0] - EXIT_CLEAR && y < span[1] + EXIT_CLEAR;
    }

    public override void on_bounce(GameSim sim, SimRng _rng)
    {
        var s = sim.state;
        long side = s.vx > 0 ? 1 : 0;
        if (s.exit_open && s.exit_side == side) return;
        long arrive = t + sim.steps_to_wall(side);
        long covered = 0;
        bool first = true;
        var hs = sim.room.hazards;
        for (int hi = 0; hi < hs.Count; hi++)
        {
            var h = hs[hi];
            if (h.kind != kind) continue;
            if (first && h != this) return;
            first = false;
            long from = ((Crawler)h).start;
            var span = _in_the_way(sim, from, side, arrive, WALL_WINDOW);
            for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
            {
                long cy = SimConfig.slot_center_y(slot);
                if (cy > span[0] - SLOT_CLEAR && cy < span[1] + SLOT_CLEAR) covered |= 1L << (int)slot;
            }
        }
        if (covered == 0) return;
        long mask = side == 1 ? s.right_spikes : s.left_spikes;
        long run = _best_run(mask, covered, s.y);
        if ((run & mask) == 0) return;
        if (side == 1) s.right_spikes = mask & ~run;
        else s.left_spikes = mask & ~run;
    }

    public long _best_run(long mask, long covered, long bird_y)
    {
        for (long want = FREE_RUN; want > 0; want--)
        {
            long best = 0;
            long best_rank = -1;
            for (long slot = 0; slot < SimConfig.SLOT_COUNT - want + 1; slot++)
            {
                long run = ((1L << (int)want) - 1) << (int)slot;
                if ((covered & run) != 0) continue;
                long centre = SimConfig.slot_center_y(slot) + (want - 1) * SimConfig.SLOT_SIZE / 2;
                long away = G.absi(centre - bird_y);
                long spikes = 0;
                for (long i = 0; i < want; i++)
                {
                    if (RoomRules.has_slot(mask, slot + i)) spikes += 1;
                }
                long rank = away + spikes * SimConfig.WORLD_H;
                if (away > RoomRules.GAP_REACH) rank += SimConfig.SLOT_COUNT * SimConfig.WORLD_H;
                if (best_rank < 0 || rank < best_rank)
                {
                    best_rank = rank;
                    best = run;
                }
            }
            if (best != 0) return best;
        }
        return 0;
    }

    public bool _blocks_planned_exit(GameSim sim)
    {
        var s = sim.state;
        if (blocks_exit(sim, s.exit_side, s.exit_a_y)) return true;
        return s.exit_b_kind != ExitKind.NORMAL && blocks_exit(sim, s.exit_side, s.exit_b_y);
    }

    /// [lowest y, highest y] of the segments in the bird's way; [FAR, -FAR] when none is.
    public long[] _in_the_way(GameSim sim, long from, long side, long arrive, long after)
    {
        long r = SimConfig.BIRD_RADIUS;
        long wall = side == 1 ? sim.room.wall_right() - r : sim.room.wall_left() + r;
        long inward = side == 1 ? -SimConfig.SPEED_X : SimConfig.SPEED_X;
        long lo = FAR;
        long hi = -FAR;
        for (long d = -WALL_WINDOW; d < after + 1; d++)
        {
            long bird_x = wall + inward * G.absi(d);
            long tail = from + (arrive + d) * SPEED;
            for (long i = 0; i < SEGMENTS; i++)
            {
                long s = G.posmod(tail + i * SPACING, PERIMETER);
                if (G.absi(path_x(s) - bird_x) < NEAR_X)
                {
                    long y = path_y(s);
                    lo = G.mini(lo, y);
                    hi = G.maxi(hi, y);
                }
            }
        }
        return new long[] { lo, hi };
    }

    public override long checksum(long h)
    {
        long out_ = mix_all(h, lane, start);
        for (long i = 0; i < SEGMENTS; i++) out_ = mix_all(out_, xs[(int)i], ys[(int)i]);
        return out_;
    }
}
