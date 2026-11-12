namespace FastSim;

/// Port of sim/hazards/lava.gd.
public class Lava : Hazard
{
    public static class Mode { public const long STONE = 0, COLD = 1, RAFTS = 2; }

    public const long SUB = SimConfig.SUB;
    public const long STEP = 30 * SUB;
    public const long MAX_RISES = 7;
    public const long SPEED = 80;
    public const long STONE_RADIUS = 14 * SUB;
    public const long STONE_AFTER = 3;
    public const long STONE_CLEAR = 90 * SUB;
    public const long STONE_EDGE = 80 * SUB;
    public const long EXIT_CLEAR = SimConfig.BIRD_RADIUS + 24 * SUB;
    public const long RUN = 3;
    public const long ICE_DEPTH = 12 * SUB;
    public const long ICE_AWAY = 80 * SUB;
    public const long RAFT_HALF = 32 * SUB;
    public const long RAFT_HIGH = 8 * SUB;
    public const long RAFT_SPEED = 32;
    public const long RAFT_X_MIN = 70 * SUB + RAFT_HALF;
    public const long RAFT_X_MAX = SimConfig.WORLD_W - 70 * SUB - RAFT_HALF;
    public const long RAFT_EVERY = 2;
    public const long RAFT_FROM = 2;
    public const long RAFT_TWO = 5;
    public const long MAX_RAFTS = 2;
    public const long RAFT_RISE = 60;
    public const long RAFT_SINK = 2;
    public const long RAFT_VY = SimConfig.FLAP_VY * 6 / 5;

    public long mode = Mode.STONE;
    public long line = SimConfig.KILL_BOTTOM;
    public long rises = 0;
    public long counted = 0;
    public bool stone_on = false;
    public long stone_x = 0;
    public long stone_y = 0;
    public bool ice_on = false;
    public long ice_side = 0;
    public long ice_slot = 0;
    public bool[] raft_on = { false, false };
    public long[] raft_x = { 0, 0 };
    public long[] raft_dir = { 1, 1 };
    public long[] raft_age = { 0, 0 };
    public long raft_points = 0;

    public Lava()
    {
        kind = "lava";
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        switch (sim.room.variant_id())
        {
            case "cold": mode = Mode.COLD; break;
            case "rafts": mode = Mode.RAFTS; break;
            default: mode = Mode.STONE; break;
        }
        line = rest();
        counted = sim.room.points;
        raft_points = sim.room.points;
    }

    public override Hazard clone_deep()
    {
        var c = (Lava)MemberwiseClone();
        c.raft_on = (bool[])raft_on.Clone();
        c.raft_x = (long[])raft_x.Clone();
        c.raft_dir = (long[])raft_dir.Clone();
        c.raft_age = (long[])raft_age.Clone();
        return c;
    }

    public long rest() => SimConfig.KILL_BOTTOM;

    public long line_at(long n)
    {
        return SimConfig.KILL_BOTTOM - n * STEP;
    }

    public long rises_due(GameSim sim) => G.mini(rises + sim.room.points - counted, MAX_RISES);

    public override void step(GameSim sim)
    {
        line += G.clampi(line_at(rises) - line, -SPEED, SPEED);
        for (int i = 0; i < MAX_RAFTS; i++)
        {
            if (!raft_on[i]) continue;
            raft_age[i] += 1;
            raft_x[i] += raft_dir[i] * RAFT_SPEED;
            if (raft_x[i] <= RAFT_X_MIN || raft_x[i] >= RAFT_X_MAX)
            {
                raft_x[i] = G.clampi(raft_x[i], RAFT_X_MIN, RAFT_X_MAX);
                raft_dir[i] = -raft_dir[i];
            }
        }
    }

    public override bool kills(GameSim sim)
    {
        long r = SimConfig.BIRD_RADIUS;
        if (line >= SimConfig.KILL_BOTTOM || sim.state.y + r < line) return false;
        return _raft_under(sim) < 0;
    }

    int _raft_under(GameSim sim)
    {
        for (int i = 0; i < MAX_RAFTS; i++)
        {
            if (raft_on[i] && raft_age[i] >= RAFT_RISE)
            {
                if (G.absi(sim.state.x - raft_x[i]) <= RAFT_HALF) return i;
            }
        }
        return -1;
    }

    public override void touch(GameSim sim)
    {
        if (stone_on && sim.bird_touches_circle(stone_x, stone_y, STONE_RADIUS))
        {
            stone_on = false;
            rises = 0;
        }
        if (ice_on && sim.bird_touches_rect(ice_x0(sim), ice_y0(), ice_x1(sim), ice_y1()))
        {
            ice_on = false;
            rises = 0;
        }
        long r = SimConfig.BIRD_RADIUS;
        for (int i = 0; i < MAX_RAFTS; i++)
        {
            if (!raft_on[i] || raft_age[i] < RAFT_RISE) continue;
            long x0 = raft_x[i] - RAFT_HALF;
            long x1 = raft_x[i] + RAFT_HALF;
            long top = line - RAFT_HIGH;
            bool over = _raft_under(sim) == i && sim.state.y + r >= top;
            if (over || sim.bird_touches_rect(x0, top, x1, line))
            {
                raft_on[i] = false;
                rises = G.maxi(rises - RAFT_SINK, 0);
                sim.state.y = G.mini(sim.state.y, top - r - 1);
                sim.state.vy = RAFT_VY;
                return;
            }
        }
    }

    public long ice_x0(GameSim sim) => ice_side == 0 ? sim.room.wall_left() : sim.room.wall_right() - ICE_DEPTH;

    public long ice_x1(GameSim sim) => ice_side == 0 ? sim.room.wall_left() + ICE_DEPTH : sim.room.wall_right();

    public long ice_y0() => SimConfig.slot_center_y(ice_slot) - SimConfig.SLOT_SIZE / 2;

    public long ice_y1() => SimConfig.slot_center_y(ice_slot) + SimConfig.SLOT_SIZE / 2;

    bool _slot_clear(long slot, long edge)
    {
        long cy = SimConfig.slot_center_y(slot);
        long half = SimConfig.SLOT_SIZE / 2;
        return cy + half <= edge - SimConfig.BIRD_RADIUS;
    }

    public override long adjust_wall(GameSim sim, long side, long mask)
    {
        if (ice_on && side == ice_side)
        {
            for (long slot = G.maxi(ice_slot - 1, 0); slot < G.mini(ice_slot + 2, SimConfig.SLOT_COUNT); slot++)
                mask &= ~(1L << (int)slot);
        }
        if (mask == 0) return mask;
        long edge = line_at(rises_due(sim));
        long run = 0;
        long first_ok = -1;
        long last_ok = -1;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            if (!_slot_clear(slot, edge))
            {
                run = 0;
                continue;
            }
            if (first_ok < 0) first_ok = slot;
            last_ok = slot;
            run = RoomRules.has_slot(mask, slot) ? 0 : run + 1;
            if (run >= RUN) return mask;
        }
        if (first_ok < 0 || last_ok - first_ok + 1 < RUN) return mask;
        long c0 = SimConfig.slot_center_y(0);
        long near = (sim.state.anchor_y - c0 + SimConfig.SLOT_SIZE / 2) / SimConfig.SLOT_SIZE;
        long mid = G.clampi(near, first_ok + 1, last_ok - 1);
        for (long slot = mid - 1; slot < mid + 2; slot++) mask &= ~(1L << (int)slot);
        return mask;
    }

    public override void on_bounce(GameSim sim, SimRng rng)
    {
        rises = rises_due(sim);
        counted = sim.room.points;
        if (mode == Mode.COLD)
        {
            _place_ice(sim, rng);
            return;
        }
        if (mode == Mode.RAFTS)
        {
            _place_raft(sim, rng);
            return;
        }
        if (stone_on || rises < STONE_AFTER) return;
        long heading = line_at(rises);
        long lo = SimConfig.KILL_TOP + STONE_EDGE;
        long hi = heading - STONE_CLEAR;
        stone_x = (110 + rng.next_below(141)) * SUB;
        stone_y = lo + rng.next_below(G.maxi(hi - lo, 0) + 1);
        stone_on = true;
    }

    void _place_ice(GameSim sim, SimRng rng)
    {
        if (ice_on || rises < STONE_AFTER) return;
        long heading = line_at(rises);
        long lo = SimConfig.KILL_TOP + STONE_EDGE;
        long hi = heading - STONE_CLEAR;
        long count = 0;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            if (_ice_fits(sim, slot, lo, hi)) count += 1;
        }
        if (count == 0) return;
        long pick = rng.next_below(count);
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            if (!_ice_fits(sim, slot, lo, hi)) continue;
            if (pick == 0)
            {
                ice_slot = slot;
                break;
            }
            pick -= 1;
        }
        ice_side = sim.state.vx > 0 ? 0 : 1;
        ice_on = true;
    }

    bool _ice_fits(GameSim sim, long slot, long lo, long hi)
    {
        long cy = SimConfig.slot_center_y(slot);
        return cy >= lo && cy <= hi && G.absi(cy - sim.state.y) >= ICE_AWAY;
    }

    void _place_raft(GameSim sim, SimRng rng)
    {
        if (rises < RAFT_FROM || sim.room.points - raft_points < RAFT_EVERY) return;
        long allowed = rises >= RAFT_TWO ? MAX_RAFTS : 1;
        long out_ = 0;
        int free = -1;
        for (int i = 0; i < MAX_RAFTS; i++)
        {
            if (raft_on[i]) out_ += 1;
            else if (free < 0) free = i;
        }
        if (out_ >= allowed || free < 0) return;
        raft_x[free] = RAFT_X_MIN + rng.next_below(RAFT_X_MAX - RAFT_X_MIN + 1);
        raft_dir[free] = rng.next_below(2) == 0 ? 1 : -1;
        raft_age[free] = 0;
        raft_on[free] = true;
        raft_points = sim.room.points;
    }

    public override bool blocks_exit(GameSim sim, long side, long y)
    {
        long worst = line_at(G.mini(rises_due(sim) + sim.points_to_exit(), MAX_RISES));
        return y > worst - EXIT_CLEAR;
    }

    public override long checksum(long h)
    {
        long out_ = mix_all(h, mode, line, rises, counted, G.B(stone_on), stone_x, stone_y);
        if (mode == Mode.COLD)
        {
            out_ = mix_all(out_, G.B(ice_on), ice_side, ice_slot);
        }
        else if (mode == Mode.RAFTS)
        {
            out_ = mix_all(out_, raft_points);
            for (int i = 0; i < MAX_RAFTS; i++)
                out_ = mix_all(out_, G.B(raft_on[i]), raft_x[i], raft_dir[i], raft_age[i]);
        }
        return out_;
    }
}
