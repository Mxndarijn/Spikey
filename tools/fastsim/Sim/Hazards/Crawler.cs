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
    public const long CORNER_CLEAR = 50 * SimConfig.SUB;

    public const long SWARM_SEGMENTS = 4;
    public const long SWARM_RADIUS = 7 * SimConfig.SUB;
    public const long SWARM_SPACING = 15 * SimConfig.SUB;
    public const long SWARM_GAP = 50 * SimConfig.SUB;
    public const long SPRINT_SEGMENTS = 5;
    public const long SPRINT_SPEED = 2 * SimConfig.SUB;
    public const long FREE_RUN = 3;
    public const long FAR = 1L << 30;

    public long lane = 0;
    public long start = 0;
    public long segments = SEGMENTS;
    public long seg_radius = SEG_RADIUS;
    public long spacing = SPACING;
    public long speed = SPEED;
    public long reserve = 0;
    public bool trails = false;
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

    public Hazard swarm()
    {
        segments = SWARM_SEGMENTS;
        seg_radius = SWARM_RADIUS;
        spacing = SWARM_SPACING;
        reserve = trail_offset();
        return this;
    }

    public Hazard trailing()
    {
        swarm();
        reserve = 0;
        trails = true;
        return this;
    }

    public Hazard sprinter()
    {
        segments = SPRINT_SEGMENTS;
        speed = SPRINT_SPEED;
        return this;
    }

    public long body() => (segments - 1) * spacing;

    public long trail_offset() => body() + SWARM_GAP;

    public long start_span() => W - body() - CORNER_CLEAR * speed / SPEED - reserve;

    public long near_x() => seg_radius + SimConfig.BIRD_RADIUS + 8 * SimConfig.SUB;

    public long wall_window() => (LEFT - SimConfig.BIRD_RADIUS + near_x()) / SimConfig.SPEED_X + 1;

    public long slot_clear() =>
        SimConfig.SLOT_SIZE / 2 + seg_radius + SimConfig.BIRD_RADIUS + 2 * SimConfig.SUB;

    public long exit_clear() => SimConfig.EXIT_FIT + seg_radius + SimConfig.BIRD_RADIUS + SimConfig.SUB;

    public override void setup(GameSim sim, SimRng rng)
    {
        var leader = trails ? _leader(sim) : null;
        if (leader != null) start = leader.start - trail_offset();
        else start = reserve + rng.next_below(start_span()) + lane * (W + H);
        _resize(xs, segments);
        _resize(ys, segments);
        _place();
    }

    public Crawler _leader(GameSim sim)
    {
        Crawler out_ = null;
        var hs = sim.room.hazards;
        for (int i = 0; i < hs.Count; i++)
        {
            var h = hs[i];
            if (h == this) break;
            if (h.kind == kind && h is Crawler c && c.lane == lane && !c.trails) out_ = c;
        }
        return out_;
    }

    public override void step(GameSim _sim) { _place(); }

    public void _place()
    {
        long tail = start + t * speed;
        for (long i = 0; i < segments; i++)
        {
            long s = G.posmod(tail + (segments - 1 - i) * spacing, PERIMETER);
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
        for (long i = 0; i < segments; i++)
        {
            if (sim.bird_touches_circle(xs[(int)i], ys[(int)i], seg_radius)) return true;
        }
        return false;
    }

    public override bool blocks_exit(GameSim sim, long side, long y)
    {
        var span = _in_the_way(sim, start, side, t + sim.steps_to_wall(side), 0);
        return y > span[0] - exit_clear() && y < span[1] + exit_clear();
    }

    public override long adjust_wall(GameSim sim, long side, long mask)
    {
        var s = sim.state;
        if (s.exit_open && s.exit_side == side) return mask;
        long arrive = t + sim.steps_to_wall(side);
        long covered = 0;
        bool first = true;
        var hs = sim.room.hazards;
        for (int hi = 0; hi < hs.Count; hi++)
        {
            var h = hs[hi];
            if (h.kind != kind) continue;
            if (first && h != this) return mask;
            first = false;
            var c = (Crawler)h;
            long from = c.start;
            var span = c._in_the_way(sim, from, side, arrive, c.wall_window());
            long clear = c.slot_clear();
            for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
            {
                long cy = SimConfig.slot_center_y(slot);
                if (cy > span[0] - clear && cy < span[1] + clear) covered |= 1L << (int)slot;
            }
        }
        if (covered == 0) return mask;
        return mask & ~_best_run(mask, covered, s.y);
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

    /// [lowest y, highest y] of the segments in the bird's way; [FAR, -FAR] when none is.
    public long[] _in_the_way(GameSim sim, long from, long side, long arrive, long after)
    {
        long r = SimConfig.BIRD_RADIUS;
        long wall = side == 1 ? sim.room.wall_right() - r : sim.room.wall_left() + r;
        long inward = side == 1 ? -SimConfig.SPEED_X : SimConfig.SPEED_X;
        long lo = FAR;
        long hi = -FAR;
        long near = near_x();
        for (long d = -wall_window(); d < after + 1; d++)
        {
            long bird_x = wall + inward * G.absi(d);
            long tail = from + (arrive + d) * speed;
            for (long i = 0; i < segments; i++)
            {
                long s = G.posmod(tail + i * spacing, PERIMETER);
                if (G.absi(path_x(s) - bird_x) < near)
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
        for (long i = 0; i < segments; i++) out_ = mix_all(out_, xs[(int)i], ys[(int)i]);
        if (segments != SEGMENTS || speed != SPEED || reserve != 0 || trails)
            out_ = mix_all(out_, segments, seg_radius, spacing, speed, reserve, G.B(trails));
        return out_;
    }
}
