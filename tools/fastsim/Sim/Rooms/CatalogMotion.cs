namespace FastSim;

/// Port of sim/rooms/catalog_motion.gd. Order is part of the rules.
public static class CatalogMotion
{
    public const long SUB = SimConfig.SUB;
    public static readonly string[] PINWHEELS = { "trim", "three", "twin", "rock", "lean", "breathe" };

    public static List<RoomDef> defs()
    {
        var out_ = new List<RoomDef>();

        var cloud = new RoomDef("cloud", "starter", 10);
        cloud.hazards.Add(() => new Bumper());
        cloud.variants = new List<RoomVariant>
        {
            new RoomVariant("one"),
            new RoomVariant("two").with(new List<Func<Hazard>> { () => new Bumper(true) }),
        };
        out_.Add(cloud);

        var gates = new RoomDef("gates", "starter", 20);
        gates.max_spikes = 6;
        gates.arrival_skip = new List<long> { 0, 178 * SUB, 502 * SUB, SimConfig.WORLD_H };
        gates.hazards.Add(() => _gate(130 * SUB, 760, false));
        gates.hazards.Add(() => _gate(230 * SUB, 760, true));
        out_.Add(gates);

        var crawl = new RoomDef("crawl", "starter", 30);
        crawl.arrival_skip = new List<long> { 0, RoomDef.CEILING_ARRIVAL };
        crawl.hazards.Add(() => _crawler(0));
        crawl.hazards.Add(() => _crawler(1));
        out_.Add(crawl);

        var swing = new RoomDef("swing", "mid", 30);
        swing.variants = new List<RoomVariant>
        {
            new RoomVariant("big").with(new List<Func<Hazard>> { _big_lantern }).skipping(_px_range(362, 428)),
            new RoomVariant("twin").with(new List<Func<Hazard>> { _twin_lanterns }).skipping(_px_range(226, 380)),
            new RoomVariant("chimes").with(new List<Func<Hazard>> { () => _chime(0), () => _chime(1), () => _chime(2) }).skipping(_px_range(192, 324)),
            new RoomVariant("gusty").with(new List<Func<Hazard>> { _gusty_lantern }).skipping(_px_range(336, 392)),
            new RoomVariant("winch").with(new List<Func<Hazard>> { _winch_lantern }).skipping(_px_range(240, 310)),
        };
        out_.Add(swing);

        var stalker = new RoomDef("stalker", "mid", 40);
        stalker.max_spikes = 6;
        stalker.hazards.Add(() => new Stalker());
        out_.Add(stalker);

        var pinwheel = new RoomDef("pinwheel", "mid", 40);
        foreach (string shape in PINWHEELS)
            pinwheel.variants.Add(new RoomVariant(shape).with(new List<Func<Hazard>> { () => _pinwheel(shape) }));
        out_.Add(pinwheel);

        var sawring = new RoomDef("sawring", "late", 80);
        sawring.weight = 8;
        sawring.max_spikes = 6;
        sawring.hazards.Add(() => new SawRing());
        out_.Add(sawring);

        return out_;
    }

    static Hazard _pinwheel(string shape)
    {
        switch (shape)
        {
            case "twin":
                var pair = new Rotor(42 * SUB, 6 * SUB, 11 * SUB);
                pair.hubs = 2;
                pair.spread_x = 60 * SUB;
                pair.spread_y = 72 * SUB;
                pair.period = 300;
                return pair;
            case "lean":
                var side = new Rotor(52 * SUB, 6 * SUB, 12 * SUB);
                side.lean = 52 * SUB;
                return side;
            case "breathe":
                var lung = new Rotor(72 * SUB, 7 * SUB, 14 * SUB);
                lung.spin = Rotor.Spin.BREATHE;
                lung.blade_min = 40 * SUB;
                return lung;
        }
        var r = new Rotor(64 * SUB, 7 * SUB, 14 * SUB);
        if (shape == "three")
            r.blades = 3;
        else if (shape == "rock")
            r.spin = Rotor.Spin.ROCK;
        return r;
    }

    static Hazard _gate(long x, long period, bool follows) => new Gate(x, period, follows);

    static Hazard _crawler(long lane) => new Crawler(lane);

    static Hazard _big_lantern() => new Pendulum(180 * SUB, 330 * SUB, 28 * SUB, 56, 210);

    static Hazard _twin_lanterns() =>
        new Pendulum(130 * SUB, 200 * SUB, 20 * SUB, 45, 180).with_twin(218 * SUB, 290 * SUB);

    static Hazard _chime(int i)
    {
        long[] xs = { 95, 180, 265 };
        long[] lengths = { 150, 240, 150 };
        long[] periods = { 150, 180, 210 };
        return new Pendulum(xs[i] * SUB, lengths[i] * SUB, 15 * SUB, 40, periods[i]);
    }

    static Hazard _gusty_lantern() => new Pendulum(180 * SUB, 300 * SUB, 24 * SUB, 41, 180).gusting(18, 600);

    static Hazard _winch_lantern() =>
        new Pendulum(180 * SUB, 265 * SUB, 24 * SUB, 50, 180).winding(65 * SUB, 420);

    static List<long> _px_range(long from_px, long to_px) => new List<long> { from_px * SUB, to_px * SUB };
}
