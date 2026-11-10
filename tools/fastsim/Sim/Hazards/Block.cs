namespace FastSim;

/// Port of sim/hazards/block.gd.
public class Block : Hazard
{
    public const long BAND = 110 * SimConfig.SUB;
    public const long BAND_TOP = 96 * SimConfig.SUB;
    public const long SIDE = 80 * SimConfig.SUB;
    public const long START_MARGIN = 6 * SimConfig.SUB;
    public const long MIN_GAP = 95 * SimConfig.SUB;
    public const long PINCH_X = 48 * SimConfig.SUB;
    public const long ARRIVAL_W = 200 * SimConfig.SUB;
    public const long ARRIVAL_UP = 75 * SimConfig.SUB;
    public const long ARRIVAL_DOWN = 45 * SimConfig.SUB;
    public const long EXIT_CLEAR_X = 130 * SimConfig.SUB;
    public const long EXIT_MARGIN = 8 * SimConfig.SUB;
    public const long EXIT_ROOM = SimConfig.SLOT_SIZE;

    public long x0 = 0;
    public long y0 = 0;
    public long x1 = 0;
    public long y1 = 0;
    public long fade_period = 0;
    public long solid_ticks = 0;
    public long phase = 0;
    public long base_phase = 0;
    public long band = -1;

    public Block(long p_x0 = 0, long p_y0 = 0, long p_x1 = 0, long p_y1 = 0)
    {
        kind = "block";
        x0 = p_x0;
        y0 = p_y0;
        x1 = p_x1;
        y1 = p_y1;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        if (band < 0)
        {
            base_phase = phase;
            if (fade_period > 0 && sim.state.started) _time_faders_for_arrival(sim);
            return;
        }
        long sub = SimConfig.SUB;
        long w = (50 + rng.next_below(41)) * sub;
        long h = (24 + rng.next_below(13)) * sub;
        x0 = SIDE + rng.next_below(200 * sub - w);
        y0 = BAND_TOP + band * BAND + 10 * sub + rng.next_below(BAND - h - 20 * sub);
        long band_top = BAND_TOP + band * BAND + 10 * sub;
        long band_bottom = BAND_TOP + (band + 1) * BAND - 10 * sub - h;
        long far_x = SimConfig.WORLD_W - SIDE - w;
        long mid_x = (SimConfig.WORLD_W - w) / 2;
        long clear_y = band_top;
        long right_x = far_x;
        long left_x = SIDE;
        var above = _neighbour(sim);
        if (above.Count != 0)
        {
            clear_y = above[2] + MIN_GAP;
            right_x = above[1] + PINCH_X;
            left_x = above[0] - PINCH_X - w;
        }
        clear_y = G.clampi(G.maxi(clear_y, y0), band_top, band_bottom);
        right_x = G.clampi(right_x, SIDE, far_x);
        left_x = G.clampi(left_x, SIDE, far_x);
        bool found = false;
        // The candidate arrays are built once, before the loops (as in GDScript).
        long[] cxs = { x0, right_x, left_x, far_x, SIDE, mid_x };
        long[] cys = { y0, clear_y, band_top, band_bottom };
        foreach (long cx in cxs)
        {
            foreach (long cy in cys)
            {
                if (_in_the_way(sim, cx, cy, cx + w, cy + h)) continue;
                x0 = cx;
                y0 = cy;
                found = true;
                break;
            }
            if (found) break;
        }
        x1 = x0 + w;
        y1 = y0 + h;
        if (!found) alive = false;
    }

    void _time_faders_for_arrival(GameSim sim)
    {
        var path = sim.arrival_path();
        long margin = 4 * SimConfig.SUB;
        long reach = SimConfig.BIRD_RADIUS + margin;
        var all = new List<Block>();
        var touches = new List<List<long>>();
        for (int i = 0; i < sim.room.hazards.Count; i++)
        {
            if (sim.room.hazards[i] is not Block h || h.kind != kind || h.fade_period <= 0) continue;
            h.phase = h.base_phase;
            all.Add(h);
            var at = new List<long>();
            for (long k = 0; k < GameSim.ARRIVAL_PATH_TICKS; k++)
            {
                long px = path[(int)(2 * k)];
                long py = path[(int)(2 * k + 1)];
                long nx = G.clampi(px, h.x0, h.x1);
                long ny = G.clampi(py, h.y0, h.y1);
                if ((px - nx) * (px - nx) + (py - ny) * (py - ny) < reach * reach) at.Add(k);
            }
            touches.Add(at);
        }
        long best = 0;
        long best_hits = -1;
        for (long shift = 0; shift < fade_period; shift++)
        {
            long hits = 0;
            for (int i = 0; i < all.Count; i++)
            {
                var b = all[i];
                foreach (long k in touches[i])
                    if (G.posmod(k + 1 + b.phase + shift, b.fade_period) < b.solid_ticks)
                        hits += k < GameSim.ARRIVAL_PATH_MIN ? 1000 : 1;
            }
            if (best_hits < 0 || hits < best_hits)
            {
                best_hits = hits;
                best = shift;
            }
            if (hits == 0) break;
        }
        foreach (var b in all) b.phase = G.posmod(b.phase + best, b.fade_period);
    }

    public bool _in_the_way(GameSim sim, long bx0, long by0, long bx1, long by1)
    {
        return sim.start_path_hits_rect(bx0, by0, bx1, by1, START_MARGIN)
            || sim.blocks_start_lane(bx0, by0, bx1, by1)
            || _blocks_arrival(sim, bx0, by0, bx1, by1)
            || _crowds_neighbour(sim, bx0, by0, bx1)
            || _covers_exit(sim, bx0, by0, bx1, by1);
    }

    public bool _covers_exit(GameSim sim, long bx0, long by0, long bx1, long by1)
    {
        var st = sim.state;
        if (!st.exit_open && !st.exit_preview) return false;
        if (_fronts_exit(sim, st.exit_side, st.exit_a_y, EXIT_ROOM, bx0, by0, bx1, by1)) return true;
        return st.exit_b_kind != ExitKind.NORMAL
            && _fronts_exit(sim, st.exit_side, st.exit_b_y, EXIT_ROOM, bx0, by0, bx1, by1);
    }

    public bool _blocks_arrival(GameSim sim, long bx0, long by0, long bx1, long by1)
    {
        var st = sim.state;
        if (!st.started) return false;
        long up = st.y - ARRIVAL_UP * sim.room.def.gravity_sign;
        long down = st.y + ARRIVAL_DOWN * sim.room.def.gravity_sign;
        long top = G.mini(up, down);
        long bottom = G.maxi(up, down);
        if (by1 > top && by0 < bottom)
        {
            if (st.vx > 0 && bx0 < sim.room.wall_left() + ARRIVAL_W) return true;
            if (st.vx < 0 && bx1 > sim.room.wall_right() - ARRIVAL_W) return true;
        }
        if (!st.exit_open) return false;
        top = G.mini(top, st.exit_a_y - ARRIVAL_UP);
        bottom = G.maxi(bottom, st.exit_a_y + ARRIVAL_UP);
        if (st.exit_b_kind != ExitKind.NORMAL)
        {
            top = G.mini(top, st.exit_b_y - ARRIVAL_UP);
            bottom = G.maxi(bottom, st.exit_b_y + ARRIVAL_UP);
        }
        return by1 > top && by0 < bottom;
    }

    /// The island of the band above, as [x0, x1, y1]; empty if there is none.
    public List<long> _neighbour(GameSim sim)
    {
        var hs = sim.room.hazards;
        for (int i = 0; i < hs.Count; i++)
        {
            var other = hs[i];
            if (other != this && other.kind == kind && other.alive && ((Block)other).band == band - 1)
            {
                var o = (Block)other;
                return new List<long> { o.x0, o.x1, o.y1 };
            }
        }
        return new List<long>();
    }

    public bool _crowds_neighbour(GameSim sim, long bx0, long by0, long bx1)
    {
        var other = _neighbour(sim);
        if (other.Count == 0) return false;
        bool beside = bx0 - other[1] >= PINCH_X || other[0] - bx1 >= PINCH_X;
        return !beside && by0 - other[2] < MIN_GAP;
    }

    public bool _fronts_exit(
        GameSim sim, long side, long y, long margin, long bx0, long by0, long bx1, long by1)
    {
        long away = side == 0 ? bx0 - sim.room.wall_left() : sim.room.wall_right() - bx1;
        if (away >= EXIT_CLEAR_X) return false;
        long reach = SimConfig.BIRD_RADIUS + margin;
        return by1 + reach > y && by0 - reach < y;
    }

    public override bool blocks_exit(GameSim sim, long side, long y)
    {
        if (band < 0) return false;
        return _fronts_exit(sim, side, y, EXIT_MARGIN, x0, y0, x1, y1);
    }

    public bool solid()
    {
        if (fade_period <= 0) return true;
        return G.posmod(t + phase, fade_period) < solid_ticks;
    }

    public long opacity()
    {
        if (fade_period <= 0) return SimTrig.ONE;
        long p = G.posmod(t + phase, fade_period);
        if (p < solid_ticks) return SimTrig.ONE;
        long fade = fade_period - solid_ticks;
        long into = p - solid_ticks;
        long third = G.maxi(fade / 3, 1);
        if (into < third) return SimTrig.ONE - SimTrig.ONE * into / third;
        if (into > fade - third) return SimTrig.ONE * (into - (fade - third)) / third;
        return 0;
    }

    public override bool kills(GameSim sim) => solid() && sim.bird_touches_rect(x0, y0, x1, y1);

    public override long checksum(long h)
        => mix_all(h, x0, y0, x1, y1, fade_period, solid_ticks, phase);
}
