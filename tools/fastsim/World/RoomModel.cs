namespace FastSim.Model;

/// The room as a player knows it: its rules (speed, gravity, flips, squeeze,
/// tide and blink walls, spike size) and its present state (clock, points, the
/// spikes on both walls, the exit). Read from the present sim state only; the
/// rules are the room's fixed definition (what a player learns by playing it).
/// After a predicted wall bounce the new wall's spikes are not known yet
/// (`unknown`): the sim draws them from its RNG at the bounce.
public sealed class RoomModel
{
    public string id = "", variant = "";
    public RoomDef def;
    public long speed, wall_mode, inset_max, squeeze_mode, blink_period;
    public bool squeeze, flip_flop;
    public long spike_depth, half_base, max_depth, tide_max;

    public long t, ticks, points, gravity, score;
    public bool started;
    public long hold;

    public long[] spikes = new long[2];
    public long[] tide = new long[2];
    public long tide_phase;
    public long[] blink = new long[2];
    public bool[] unknown = new bool[2];

    public bool exit_open, exit_preview, exit_locked;
    public long exit_side, exit_a_y, exit_a_kind, exit_b_y, exit_b_kind;
    /// An exit will open or show after a predicted bounce, at a height not drawn yet.
    public bool exit_unknown;

    public RoomModel Copy()
    {
        var c = (RoomModel)MemberwiseClone();
        c.spikes = (long[])spikes.Clone();
        c.tide = (long[])tide.Clone();
        c.blink = (long[])blink.Clone();
        c.unknown = (bool[])unknown.Clone();
        return c;
    }

    public static RoomModel Read(GameSim sim)
    {
        var r = sim.room;
        var s = sim.state;
        var m = new RoomModel
        {
            def = r.def,
            id = r.def.id,
            variant = r.variant_id(),
            speed = r.def.speed,
            wall_mode = r.def.wall_mode,
            inset_max = r.def.inset,
            squeeze = r.def.squeeze,
            squeeze_mode = r.def.variants.Count > 0 ? r._variant().squeeze : RoomVariant.Squeeze.POINTS,
            flip_flop = r.def.variants.Count > 0 && r._variant().flip_flop,
            blink_period = r._blink_period(),
            spike_depth = r.spike_depth(),
            half_base = r.spike_half_base(),
            max_depth = r.max_spike_depth(),
            tide_max = r.tide_max_depth(),
            t = r.t,
            ticks = r.ticks,
            points = r.points,
            gravity = r.gravity,
            score = s.score,
            started = s.started,
            hold = s.arrival_hold,
            tide_phase = r.tide_salt,
            exit_open = s.exit_open,
            exit_preview = s.exit_preview,
            exit_side = s.exit_side,
            exit_a_y = s.exit_a_y,
            exit_a_kind = s.exit_a_kind,
            exit_b_y = s.exit_b_y,
            exit_b_kind = s.exit_b_kind,
            exit_locked = sim.exit_locked(),
        };
        m.spikes[0] = s.left_spikes;
        m.spikes[1] = s.right_spikes;
        m.tide[0] = r.tide_left;
        m.tide[1] = r.tide_right;
        m.blink[0] = r.blink_left;
        m.blink[1] = r.blink_right;
        return m;
    }

    // --- Rules (the same formulas as RoomRuntime / GameSim) ---

    public long StepsAt(long tick)
    {
        if (speed == RoomDef.Speed.FAST) return tick % 4 == 0 ? 2 : 1;
        if (speed == RoomDef.Speed.SLOW) return tick % 2 == 0 ? 1 : 0;
        return 1;
    }

    /// Substeps per tick on average, times 4 (normal 4, fast 5, slow 2).
    public long SpeedQuarters => speed == RoomDef.Speed.FAST ? 5 : speed == RoomDef.Speed.SLOW ? 2 : 4;

    public long Inset(long side) => InsetAt(side, t, points);

    public long InsetAt(long side, long at, long pts)
    {
        long out_ = Math.Min(at * RoomRuntime.INSET_SPEED, inset_max);
        if (squeeze)
        {
            long squeezed = Math.Min(pts, RoomRuntime.SQUEEZE_MAX_POINTS);
            if (squeeze_mode == RoomVariant.Squeeze.LEFT)
            {
                if (side == 0) out_ += squeezed * RoomRuntime.SQUEEZE_LEFT_STEP;
            }
            else if (squeeze_mode == RoomVariant.Squeeze.BREATHE)
                out_ += SimTrig.ping_pong(at, RoomRuntime.BREATHE_PERIOD, RoomRuntime.BREATHE_IN);
            else out_ += squeezed * RoomRuntime.SQUEEZE_STEP;
        }
        return out_;
    }

    public long WallLeft => Inset(0);
    public long WallRight => SimConfig.WORLD_W - Inset(1);

    public bool BlinkSecond => wall_mode == RoomDef.WallMode.BLINK && (t / blink_period) % 2 == 1;

    public long ExitSlots()
    {
        long out_ = 0;
        long reach = SimConfig.EXIT_HALF + SimConfig.SPIKE_HALF_BASE;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            long cy = SimConfig.slot_center_y(slot);
            if (Math.Abs(cy - exit_a_y) < reach) out_ |= 1L << (int)slot;
            if (exit_b_kind != ExitKind.NORMAL && Math.Abs(cy - exit_b_y) < reach) out_ |= 1L << (int)slot;
        }
        return out_;
    }

    /// The spike slots of wall `side` now (GameSim.wall_mask). An unknown wall has none yet.
    public long Mask(long side)
    {
        if (unknown[side]) return 0;
        if (exit_open && exit_side == side) return ((1L << (int)SimConfig.SLOT_COUNT) - 1) & ~ExitSlots();
        long mask = BlinkSecond ? blink[side] : spikes[side];
        if (exit_preview && exit_side == side) mask &= ~ExitSlots();
        return mask;
    }

    /// Both patterns of a blink wall (it shows each in turn), for descriptions.
    public long MaskAt(long side, long at)
    {
        long keep = t;
        t = at;
        long m = Mask(side);
        t = keep;
        return m;
    }

    public long SlotDepth(long side, long slot)
    {
        if (wall_mode != RoomDef.WallMode.TIDE) return spike_depth;
        if (!RoomRules.has_slot(tide[side], slot)) return spike_depth;
        long phase = (slot * 29 + tide_phase) % RoomRuntime.TIDE_PERIOD;
        return SimTrig.ping_pong(t + phase, RoomRuntime.TIDE_PERIOD, tide_max);
    }

    public bool ExitAhead(long side) => exit_open && exit_side == side;
}
