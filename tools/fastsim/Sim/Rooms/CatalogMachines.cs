namespace FastSim;

/// Port of sim/rooms/catalog_machines.gd. Order is part of the rules.
public static class CatalogMachines
{
    public const long SUB = SimConfig.SUB;

    public const long SLAM_REACH = 150 * SUB;
    public const long SLAM_GLOW = 60;
    public static readonly long[] LADDER_Y = { 170 * SUB, 300 * SUB, 430 * SUB };
    public const long LADDER_REACH = 140 * SUB;
    public const long LADDER_BEAT = 36;
    public const long WIDE_COLS = 4;
    public const long WIDE_COL_W = 70 * SUB;
    public const long WIDE_W = 64 * SUB;
    public const long WIDE_H = 48 * SUB;
    public const long WIDE_MAX = 3;
    public const long FANG_GAP = 100 * SUB;
    public static readonly long[] TRIO_X = { 75, 180, 285 };
    public const long ALT_GAP = 150 * SUB;
    public const long ALT_LO = 260 * SUB;
    public const long ALT_HI = 380 * SUB;
    public const long ALT_ARRIVAL_LO = 270 * SUB;
    public const long ALT_ARRIVAL_HI = 430 * SUB;
    public const long SHORT_GAP = 300 * SUB;
    public const long SHORT_Y = 320 * SUB;
    public const long SHORT_HALF_W = 18 * SUB;
    public const long SHORT_ARRIVAL_LO = 256 * SUB;
    public const long SHORT_ARRIVAL_HI = 448 * SUB;

    public static List<RoomDef> defs()
    {
        var out_ = new List<RoomDef>();

        var piston = new RoomDef("piston", "mid", 30);
        piston.max_spikes = 6;
        piston.variants = new List<RoomVariant>
        {
            new RoomVariant("classic").with(new List<Func<Hazard>> { () => _piston(0, 0, 30), () => _piston(1, 1, 30 + Piston.PERIOD / 2) }),
            new RoomVariant("double-slam").with(new List<Func<Hazard>> { () => _slam(0), () => _slam(1) }),
            new RoomVariant("ladder").with(new List<Func<Hazard>> { () => _rung(0), () => _rung(1), () => _rung(2) }),
        };
        out_.Add(piston);

        var court = new RoomDef("court", "mid", 40);
        court.hazards.Add(() => _pad(true, 300));
        court.hazards.Add(() => _pad(false, 240));
        court.variants = new List<RoomVariant>
        {
            new RoomVariant("classic"),
            new RoomVariant("goal-pad").with(new List<Func<Hazard>> { () => new PadCoin(false) }),
        };
        out_.Add(court);

        var crates = new RoomDef("crates", "mid", 60);
        crates.max_spikes = 6;
        crates.variants = crate_variants(false);
        out_.Add(crates);

        var beams = new RoomDef("beams", "mid", 50);
        beams.max_spikes = 5;
        beams.hazards.Add(() => new Beam());
        out_.Add(beams);

        var stalac = new RoomDef("stalac", "mid", 30);
        stalac.max_spikes = 4;
        stalac.arrival_skip = new List<long> { 0, RoomDef.CEILING_ARRIVAL };
        stalac.variants = new List<RoomVariant>
        {
            new RoomVariant("classic").with(new List<Func<Hazard>> { () => _stalactite(130 * SUB, false), () => _stalactite(230 * SUB, true) }),
            new RoomVariant("floor").with(new List<Func<Hazard>> { () => _fang(130, false, false), () => _fang(230, true, false) }),
            new RoomVariant("ceiling-only").with(new List<Func<Hazard>> { () => _fang(130, false, true), () => _fang(230, true, true) }),
            new RoomVariant("alternating").with(new List<Func<Hazard>> { () => _finger(0), () => _finger(1), () => _finger(2) })
                .skipping(new List<long> { 0, ALT_ARRIVAL_LO, ALT_ARRIVAL_HI, SimConfig.WORLD_H }),
            new RoomVariant("short-fangs").with(new List<Func<Hazard>> { () => _short(0), () => _short(1), () => _short(2) })
                .skipping(new List<long> { 0, SHORT_ARRIVAL_LO, SHORT_ARRIVAL_HI, SimConfig.WORLD_H }),
        };
        out_.Add(stalac);

        var hunter = new RoomDef("hunter", "late", 80);
        hunter.weight = 8;
        hunter.variants = new List<RoomVariant>
        {
            new RoomVariant("classic").with(new List<Func<Hazard>> { () => new Dart() }),
            new RoomVariant("twin").with(new List<Func<Hazard>> { () => _hunter(0, 1), () => _hunter(1, 0) }),
        };
        out_.Add(hunter);

        return out_;
    }

    public static List<RoomVariant> crate_variants(bool gifts)
    {
        return new List<RoomVariant>
        {
            new RoomVariant("classic").with(new List<Func<Hazard>> { () => _crates(gifts, false, false) }),
            new RoomVariant("wide").with(new List<Func<Hazard>> { () => _crates(gifts, true, false) }),
            new RoomVariant("pairs").with(new List<Func<Hazard>> { () => _crates(gifts, false, true) }),
        };
    }

    static Hazard _crates(bool gifts, bool wide, bool pair)
    {
        if (wide) return new CrateDrop(gifts, WIDE_COLS, WIDE_COL_W, WIDE_W, WIDE_H, WIDE_MAX, pair);
        return new CrateDrop(gifts, CrateDrop.COLS, CrateDrop.COL_W, CrateDrop.CRATE, CrateDrop.CRATE, CrateDrop.MAX_HEIGHT, pair);
    }

    static Hazard _piston(long side, long half, long delay) => new Piston(side, half, delay);

    static Hazard _hunter(long slot, long home) => new Dart(false, slot, home);

    static Hazard _slam(long side)
    {
        var p = new Piston(side, Piston.HALF_ALL, 30, SLAM_GLOW);
        p.reach = SLAM_REACH;
        p.follows = side == 1;
        return p;
    }

    static Hazard _rung(long i)
    {
        var p = new Piston(1, 0, 30 + i * LADDER_BEAT);
        p.reach = LADDER_REACH;
        p.fixed_y = LADDER_Y[i];
        return p;
    }

    static Hazard _pad(bool top, long period) => new EdgePad(top, period);

    static Hazard _stalactite(long x, bool follows) => new Stalactite(x, follows);

    static Hazard _fang(long x_px, bool follows, bool ceiling)
    {
        var s = new Stalactite(x_px * SUB, follows);
        s.top = ceiling;
        s.bottom = !ceiling;
        s.gap = ceiling ? Stalactite.GAP : FANG_GAP;
        return s;
    }

    static Hazard _finger(long i)
    {
        var s = new Stalactite(TRIO_X[i] * SUB, i > 0);
        s.top = i % 2 == 0;
        s.bottom = i % 2 == 1;
        s.gap = ALT_GAP;
        s.fixed_lo = ALT_LO;
        s.fixed_hi = ALT_HI;
        return s;
    }

    static Hazard _short(long i)
    {
        var s = new Stalactite(TRIO_X[i] * SUB, i > 0);
        s.gap = SHORT_GAP;
        s.half_w = SHORT_HALF_W;
        s.fixed_lo = SHORT_Y;
        s.fixed_hi = SHORT_Y;
        return s;
    }
}
