namespace FastSim;

public sealed class RoomRuntime
{
    public const long TIDE_PERIOD = 120;
    public const long INSET_SPEED = 2 * SimConfig.SUB;
    public const long BLINK_PERIOD = 60;
    public const long SQUEEZE_STEP = 6 * SimConfig.SUB;
    public const long SQUEEZE_MAX_POINTS = 10;

    public RoomDef def;
    public long index = 0;
    public long t = 0;
    public long ticks = 0;
    public long points = 0;
    public long variant = 0;
    public List<Hazard> hazards = new();
    public long tide_left = 0;
    public long tide_right = 0;
    public long tide_salt = 0;
    public long blink_left = 0;
    public long blink_right = 0;

    public RoomRuntime clone_deep()
    {
        var c = (RoomRuntime)MemberwiseClone();
        c.hazards = new List<Hazard>(hazards.Count);
        bool partners = false;
        foreach (var h in hazards)
        {
            c.hazards.Add(h.clone_deep());
            partners |= h is Gate || h is Stalactite;
        }
        if (partners)
        {
            var map = new Dictionary<Hazard, Hazard>(ReferenceEqualityComparer.Instance);
            for (int i = 0; i < hazards.Count; i++) map[hazards[i]] = c.hazards[i];
            foreach (var h in c.hazards) h.remap(map);
        }
        return c;
    }

    public void start(RoomDef p_def, long p_index, GameSim sim, SimRng rng)
    {
        def = p_def;
        index = p_index;
        t = 0;
        ticks = 0;
        points = 0;
        variant = 0;
        tide_left = 0;
        tide_right = 0;
        tide_salt = 0;
        blink_left = 0;
        blink_right = 0;
        hazards.Clear();
        var list = new List<Func<Hazard>>(def.hazards);
        var drawn = new List<long>();
        if (sim.state.started) drawn = def.arrival_variants(sim.state.y);
        if (drawn.Count == 0)
            for (int i = 0; i < def.variants.Count; i++) drawn.Add(i);
        if (drawn.Count > 1) variant = drawn[(int)rng.next_below(drawn.Count)];
        else if (drawn.Count == 1) variant = drawn[0];
        if (def.variants.Count > 0)
            foreach (var f in def.variants[(int)variant].hazards) list.Add(f);
        if (def.combos.Count > 0)
        {
            var combo = def.combos[(int)rng.next_below(def.combos.Count)];
            foreach (var f in combo) list.Add(f);
        }
        foreach (var f in list)
        {
            Hazard h = f();
            hazards.Add(h);
            h.setup(sim, rng);
        }
    }

    public long steps_this_tick() => steps_at(ticks);

    public long steps_at(long tick)
    {
        if (def.speed == RoomDef.Speed.FAST) return tick % 4 == 0 ? 2 : 1;
        if (def.speed == RoomDef.Speed.SLOW) return tick % 2 == 0 ? 1 : 0;
        return 1;
    }

    public void step(GameSim sim)
    {
        t += 1;
        // Index loop: a hazard may add hazards (none do in step today).
        for (int i = 0; i < hazards.Count; i++)
        {
            var h = hazards[i];
            if (h.alive)
            {
                h.t = t;
                h.step(sim);
            }
        }
    }

    public long inset()
    {
        long out_ = G.mini(t * INSET_SPEED, def.inset);
        if (def.squeeze) out_ += G.mini(points, SQUEEZE_MAX_POINTS) * SQUEEZE_STEP;
        return out_;
    }

    public string variant_id() => def.variants.Count == 0 ? "" : def.variants[(int)variant].id;

    public long spike_depth()
    {
        if (def.variants.Count == 0) return SimConfig.SPIKE_DEPTH;
        var v = def.variants[(int)variant];
        return SimConfig.SPIKE_DEPTH * v.spike_num / v.spike_den;
    }

    public long spike_half_base()
    {
        if (def.variants.Count == 0) return SimConfig.SPIKE_HALF_BASE;
        var v = def.variants[(int)variant];
        return G.mini(SimConfig.SPIKE_HALF_BASE * v.spike_num / v.spike_den, SimConfig.SLOT_SIZE / 2);
    }

    public long tide_max_depth() => spike_depth() * 3 / 2;

    public long max_spike_depth() => def.wall_mode == RoomDef.WallMode.TIDE ? tide_max_depth() : spike_depth();

    public long spike_bonus() => def.variants.Count == 0 ? 0 : def.variants[(int)variant].extra_spikes;

    public long wall_left() => inset();

    public long wall_right() => SimConfig.WORLD_W - inset();

    public bool blink_showing_second() => def.wall_mode == RoomDef.WallMode.BLINK && (t / BLINK_PERIOD) % 2 == 1;

    public long wall_mask(long side, long base_mask)
    {
        if (blink_showing_second()) return side == 0 ? blink_left : blink_right;
        return base_mask;
    }

    public long slot_depth(long side, long slot)
    {
        if (def.wall_mode != RoomDef.WallMode.TIDE) return spike_depth();
        long moving = side == 0 ? tide_left : tide_right;
        if (!RoomRules.has_slot(moving, slot)) return spike_depth();
        long phase = (slot * 29 + tide_salt) % TIDE_PERIOD;
        return SimTrig.ping_pong(t + phase, TIDE_PERIOD, tide_max_depth());
    }

    public void add_coin(long x, long y)
    {
        Hazard h = new CoinPickup(x, y, 0);
        h.t = t;
        hazards.Add(h);
    }

    public void on_wall_generated(long side, long mask, GameSim sim, SimRng rng)
    {
        if (def.wall_mode == RoomDef.WallMode.TIDE)
        {
            long moving = rng.next_u32() & mask;
            tide_salt = rng.next_below(TIDE_PERIOD);
            if (side == 0) tide_left = moving; else tide_right = moving;
        }
        else if (def.wall_mode == RoomDef.WallMode.BLINK)
        {
            long second = RoomRules.generate_wall(rng, sim.state.score, def);
            if (side == 0) blink_left = second; else blink_right = second;
        }
    }

    public long checksum(long h)
    {
        long out_ = Hazard.mix_all(h, index, t, ticks, points, variant, tide_left, tide_right, tide_salt, blink_left, blink_right);
        foreach (var hz in hazards)
        {
            out_ = SimHash.mix(out_, G.B(hz.alive));
            out_ = hz.checksum(out_);
        }
        return out_;
    }
}
