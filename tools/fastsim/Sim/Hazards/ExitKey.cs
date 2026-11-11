namespace FastSim;

/// Port of sim/hazards/exit_key.gd (Locked Out).
public class ExitKey : Hazard
{
    public static class Mode { public const long CLASSIC = 0, ORBIT = 1, TRIO = 2, QUAD = 3, CHAIN = 4; }

    public const long SUB = SimConfig.SUB;
    public const long RADIUS = 12 * SUB;
    public const long COINS = 3;
    public const long MAX_KEYS = 4;
    public const long MAX_LOCKED_BOUNCES = 8;
    public const long LOCKDOWN_MAX = 4;
    public const long KEY_OFF_MIN = 62 * SUB;
    public const long KEY_OFF_MAX = 96 * SUB;
    public const long KEY_MIN_Y = 130 * SUB;
    public const long KEY_MAX_Y = 510 * SUB;
    public const long SPOT_HALF = 30 * SUB;
    public const long EXIT_NEAR = 100 * SUB;
    public const long LAYOUT_TOP = 120;
    public const long LAYOUT_SPAN = 400;
    public const long LAYOUT_MARGIN = 15;
    public static readonly long[] ZONE_LO = { 62, 160, 264 };
    public static readonly long[] ZONE_HI = { 96, 200, 298 };
    public const long KEYS_APART = 110 * SUB;
    public const long ZONE_APART = 150 * SUB;
    public const long PLACE_TRIES = 12;
    public const long CHAIN_OFF_MAX = 150 * SUB;
    public const long CHAIN_D_MIN = 160 * SUB;
    public const long CHAIN_D_MAX = 200 * SUB;
    public const long MID_Y = 320 * SUB;
    public const long ORBIT_CX = 180 * SUB;
    public const long ORBIT_CY = 330 * SUB;
    public const long ORBIT_RX = 128 * SUB;
    public const long ORBIT_RY = 165 * SUB;
    public const long ORBIT_STEPS = 540;

    public long mode = Mode.CLASSIC;
    public long count = 1;
    public long got = 0;
    public long taken_mask = 0;
    public long[] kx = new long[4];
    public long[] ky = new long[4];
    public long[] born = new long[4];
    public long[] chain_off = new long[4];
    public long[] chain_d = new long[4];
    public long phase = 0;
    public long locked_bounces = 0;
    public long walls_left = 0;
    public long walls_right = 0;
    public bool door_open = false;
    public long door_side = 0;
    public long door_a_y = 0;
    public long door_b_y = 0;

    public ExitKey(long p_mode = -1)
    {
        kind = "exit_key";
        mode = p_mode;
    }

    public override Hazard clone_deep()
    {
        var c = (ExitKey)MemberwiseClone();
        c.kx = (long[])kx.Clone();
        c.ky = (long[])ky.Clone();
        c.born = (long[])born.Clone();
        c.chain_off = (long[])chain_off.Clone();
        c.chain_d = (long[])chain_d.Clone();
        return c;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        if (mode < 0)
        {
            switch (sim.room.variant_id())
            {
                case "orbit": mode = Mode.ORBIT; break;
                case "trio": mode = Mode.TRIO; break;
                case "quad": mode = Mode.QUAD; break;
                case "chain": mode = Mode.CHAIN; break;
                default: mode = Mode.CLASSIC; break;
            }
        }
        if (mode == Mode.TRIO) count = 3;
        else if (mode == Mode.QUAD) count = 4;
        else if (mode == Mode.CHAIN) count = 3;
        else count = 1;
        if (mode == Mode.ORBIT)
        {
            phase = rng.next_below(SimTrig.TURN);
            _place_orbit();
        }
        else if (mode == Mode.TRIO || mode == Mode.QUAD)
        {
            _lay_out(rng);
        }
        else
        {
            long side = rng.next_below(2);
            long off = KEY_OFF_MIN + rng.next_below(KEY_OFF_MAX - KEY_OFF_MIN + 1);
            kx[0] = _from_wall(sim, side, off);
            ky[0] = KEY_MIN_Y + rng.next_below(KEY_MAX_Y - KEY_MIN_Y + 1);
            if (mode == Mode.CHAIN)
            {
                for (long i = 1; i < count; i++)
                {
                    chain_off[i] = KEY_OFF_MIN + rng.next_below(CHAIN_OFF_MAX - KEY_OFF_MIN + 1);
                    chain_d[i] = CHAIN_D_MIN + rng.next_below(CHAIN_D_MAX - CHAIN_D_MIN + 1);
                }
            }
        }
    }

    void _lay_out(SimRng rng)
    {
        long band = LAYOUT_SPAN / count;
        var zones = new long[4];
        for (long attempt = 0; attempt < PLACE_TRIES; attempt++)
        {
            var order = new List<long> { 0, 1, 2 };
            foreach (int i in new[] { 2, 1 })
            {
                int j = (int)rng.next_below(i + 1);
                long swap = order[i];
                order[i] = order[j];
                order[j] = swap;
            }
            while (order.Count < count) order.Add(rng.next_below(2) == 0 ? 0 : 2);
            for (int i = 0; i < count; i++)
            {
                long z = order[i];
                zones[i] = z;
                kx[i] = (ZONE_LO[z] + rng.next_below(ZONE_HI[z] - ZONE_LO[z] + 1)) * SUB;
                long top = LAYOUT_TOP + i * band + LAYOUT_MARGIN;
                ky[i] = (top + rng.next_below(band - 2 * LAYOUT_MARGIN + 1)) * SUB;
            }
            if (_layout_ok(zones)) return;
        }
        for (int i = 0; i < count; i++)
        {
            kx[i] = (i % 2 == 0 ? 80 : 280) * SUB;
            ky[i] = (LAYOUT_TOP + i * band + band / 2) * SUB;
        }
    }

    bool _layout_ok(long[] zones)
    {
        for (int i = 0; i < count; i++)
        {
            for (int j = i + 1; j < count; j++)
            {
                long dx = kx[i] - kx[j];
                long dy = ky[i] - ky[j];
                if (dx * dx + dy * dy < KEYS_APART * KEYS_APART) return false;
                if (zones[i] == zones[j] && G.absi(dy) < ZONE_APART) return false;
            }
        }
        return true;
    }

    static long _from_wall(GameSim sim, long side, long off) =>
        side == 0 ? sim.room.wall_left() + off : sim.room.wall_right() - off;

    public override void step(GameSim sim)
    {
        if (mode == Mode.ORBIT && !done()) _place_orbit();
        var s = sim.state;
        door_open = s.exit_open;
        door_side = s.exit_side;
        door_a_y = s.exit_a_y;
        door_b_y = s.exit_b_kind != ExitKind.NORMAL ? s.exit_b_y : 0;
    }

    void _place_orbit()
    {
        long a = phase + t * SimTrig.TURN / ORBIT_STEPS;
        kx[0] = ORBIT_CX + ORBIT_RX * SimTrig.cos_t(a) / SimTrig.ONE;
        ky[0] = ORBIT_CY + ORBIT_RY * SimTrig.sin_t(a) / SimTrig.ONE;
    }

    public bool done() => got >= count;

    public bool shown(long i)
    {
        if (i >= count || ((taken_mask >> (int)i) & 1) == 1) return false;
        return mode != Mode.CHAIN || i == got;
    }

    public override void touch(GameSim sim)
    {
        for (long i = 0; i < count; i++)
        {
            if (!shown(i) || !sim.bird_touches_circle(kx[i], ky[i], RADIUS)) continue;
            taken_mask |= 1L << (int)i;
            got += 1;
            if (count == 1)
            {
                for (long c = 0; c < COINS; c++) sim.collect_coin(kx[i], ky[i]);
            }
            else
            {
                sim.collect_coin(kx[i], ky[i]);
                if (done()) sim.collect_coin(kx[i], ky[i], count);
            }
            if (mode == Mode.CHAIN && !done()) _show_next(sim, got);
            return;
        }
    }

    void _show_next(GameSim sim, long i)
    {
        var s = sim.state;
        kx[i] = _from_wall(sim, s.vx > 0 ? 0 : 1, chain_off[i]);
        long y = s.y > MID_Y ? s.y - chain_d[i] : s.y + chain_d[i];
        ky[i] = G.clampi(y, KEY_MIN_Y, KEY_MAX_Y);
        born[i] = t;
    }

    public long band_key(long side)
    {
        if (mode == Mode.ORBIT) return -1;
        for (long i = 0; i < count; i++)
        {
            if (!shown(i)) continue;
            long off = side == 0 ? kx[i] : SimConfig.WORLD_W - kx[i];
            if (off <= CHAIN_OFF_MAX) return i;
        }
        return -1;
    }

    public override long adjust_wall(GameSim sim, long side, long mask)
    {
        long walls;
        if (side == 0)
        {
            walls_left += 1;
            walls = walls_left;
        }
        else
        {
            walls_right += 1;
            walls = walls_right;
        }
        long out_ = mask;
        long spot = 0;
        long k = band_key(side);
        if (k >= 0 && walls % 2 == 0)
        {
            for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
            {
                if (G.absi(SimConfig.slot_center_y(slot) - ky[k]) <= SPOT_HALF) spot |= 1L << (int)slot;
            }
            out_ &= ~spot;
        }
        if (sim.state.exit_open && locked())
            out_ = _add_spikes(out_, G.mini(LOCKDOWN_MAX, locked_bounces + 1), spot);
        return out_;
    }

    static long _add_spikes(long mask, long n, long keep)
    {
        long run = RoomRules.longest_gap_mask(mask);
        if (run == 0) return mask;
        int lo = 0;
        while (((run >> lo) & 1) == 0) lo += 1;
        int hi = lo;
        while (hi + 1 < SimConfig.SLOT_COUNT && ((run >> (hi + 1)) & 1) == 1) hi += 1;
        long out_ = mask;
        long added = 0;
        for (int d = 1; d < SimConfig.SLOT_COUNT; d++)
        {
            foreach (int slot in new[] { lo - d, hi + d })
            {
                if (added >= n) return out_;
                if (slot < 0 || slot >= SimConfig.SLOT_COUNT) continue;
                if (((out_ >> slot) & 1) == 1 || ((keep >> slot) & 1) == 1) continue;
                out_ |= 1L << slot;
                added += 1;
            }
        }
        return out_;
    }

    public override bool blocks_exit(GameSim sim, long side, long y)
    {
        long k = band_key(side);
        return k >= 0 && G.absi(y - ky[k]) > EXIT_NEAR;
    }

    public override bool locks_exit(GameSim sim) => locked();

    public bool locked() => !done() && locked_bounces < MAX_LOCKED_BOUNCES;

    public override void on_bounce(GameSim sim, SimRng rng)
    {
        if (sim.state.exit_open && !done()) locked_bounces += 1;
    }

    public override long checksum(long h)
    {
        long out_ = mix_all(h, mode, count, got, taken_mask, phase, locked_bounces, walls_left, walls_right,
            G.B(door_open), door_side, door_a_y, door_b_y);
        for (int i = 0; i < MAX_KEYS; i++) out_ = mix_all(out_, kx[i], ky[i], born[i], chain_off[i], chain_d[i]);
        return out_;
    }
}
