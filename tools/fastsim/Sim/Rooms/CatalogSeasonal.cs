namespace FastSim;

/// Port of sim/rooms/catalog_seasonal.gd. Order is part of the rules.
public static class CatalogSeasonal
{
    public const long SUB = SimConfig.SUB;
    public const long WEIGHT = 12;

    public static List<RoomDef> defs()
    {
        var out_ = new List<RoomDef>();

        // Halloween
        var pumpkin = _room("pumpkin", Seasons.HALLOWEEN, 40);
        pumpkin.variants = new List<RoomVariant>
        {
            new RoomVariant("classic").with(new List<Func<Hazard>> { () => new Bouncer() }),
            new RoomVariant("twin").with(new List<Func<Hazard>>
            {
                () => _twin(Bouncer.Lane.UPPER),
                () => _twin(Bouncer.Lane.LOWER),
            }),
            new RoomVariant("splitting").with(new List<Func<Hazard>> { () => new SplittingBouncer() }),
        };
        out_.Add(pumpkin);

        var ghosts = _room("ghostdoors", Seasons.HALLOWEEN, 30);
        ghosts.max_spikes = 6;
        for (long i = 0; i < 6; i++)
        {
            long gi = i;
            ghosts.hazards.Add(() => _ghost_door(gi));
        }
        out_.Add(ghosts);

        var bats = _room("bats", Seasons.HALLOWEEN, 40);
        foreach (string shape in new[] { "classic", "wide", "pair" })
            bats.variants.Add(new RoomVariant(shape).with(new List<Func<Hazard>> { () => _bats(shape) }));
        out_.Add(bats);

        // Winter
        var icicles = _room("icicle", Seasons.WINTER, 50);
        icicles.hazards.Add(() => new Drop(30, 10 * SUB, 25));
        icicles.hazards.Add(() => new Drop(70, 10 * SUB, 25));
        out_.Add(icicles);

        var gifts = _room("gifts", Seasons.WINTER, 60);
        gifts.arrival_skip = new List<long> { 0, RoomDef.CEILING_ARRIVAL };
        gifts.hazards.Add(() => new CrateDrop(true));
        out_.Add(gifts);

        // Valentine's
        var hearts = _room("hearts", Seasons.VALENTINE, 10);
        hearts.variants = new List<RoomVariant>
        {
            new RoomVariant("classic").with(new List<Func<Hazard>> { () => new Bumper(), () => new Bumper(true) }),
            new RoomVariant("one-big").with(new List<Func<Hazard>> { () => new Bumper().big() }),
            new RoomVariant("orbit").with(new List<Func<Hazard>>
            {
                () => new Bumper().orbit(),
                () => new Bumper(true).orbit(),
            }),
        };
        out_.Add(hearts);

        var cupid = _room("cupid", Seasons.VALENTINE, 40);
        foreach (string shape in new[] { "classic", "double", "slow-volley" })
            cupid.variants.Add(new RoomVariant(shape).with(new List<Func<Hazard>> { () => _cupid(shape, 0), () => _cupid(shape, 1) }));
        out_.Add(cupid);

        // Spring
        var eggs = _room("eggs", Seasons.SPRING, 20);
        eggs.max_spikes = 6;
        for (long band = 0; band < 4; band++)
        {
            long b = band;
            eggs.hazards.Add(() => _island(b));
            eggs.hazards.Add(() => _egg(b));
        }
        out_.Add(eggs);

        var bees = _room("bees", Seasons.SPRING, 30);
        bees.hazards.Add(() => new Mover("wave", 4));
        bees.arrival_skip = new List<long> { 295 * SUB, 405 * SUB };
        out_.Add(bees);

        // Summer
        var beach = _room("beachball", Seasons.SUMMER, 40);
        beach.group = "bonus";
        beach.max_spikes = 3;
        beach.variants = new List<RoomVariant>
        {
            new RoomVariant("classic").with(new List<Func<Hazard>> { () => new KeepyBall() }),
            new RoomVariant("two").with(new List<Func<Hazard>>
            {
                () => new KeepyBall().dropping(0),
                () => new KeepyBall().dropping(KeepyBall.SECOND_DROP),
            }),
            new RoomVariant("heavy").with(new List<Func<Hazard>> { () => new KeepyBall().heavy() }),
        };
        out_.Add(beach);

        var crabs = _room("crabs", Seasons.SUMMER, 30);
        crabs.arrival_skip = new List<long> { 0, RoomDef.CEILING_ARRIVAL };
        crabs.variants = CatalogMotion.crawl_variants();
        out_.Add(crabs);

        // New Year
        var fireworks = _room("fireworks", Seasons.NEW_YEAR, 50);
        var styles = new (string, long)[]
        {
            ("classic", Firework.Style.RING),
            ("double", Firework.Style.DOUBLE),
            ("cross", Firework.Style.CROSS),
        };
        foreach (var (shape, style) in styles)
        {
            var rockets = new List<Func<Hazard>>();
            foreach (long delay in style == Firework.Style.DOUBLE ? new long[] { 0, 75 } : new long[] { 0, 50, 100 })
            {
                long d = delay;
                long st = style;
                rockets.Add(() => _firework(d, st));
            }
            fireworks.variants.Add(new RoomVariant(shape).with(rockets));
        }
        out_.Add(fireworks);

        var countdown = _room("countdown", Seasons.NEW_YEAR, 20);
        countdown.group = "bonus";
        countdown.max_spikes = 2;
        for (long i = 0; i < 10; i++)
        {
            long angle = i * SimTrig.TURN / 10;
            long x = 180 * SUB + 100 * SUB * SimTrig.cos_t(angle) / SimTrig.ONE;
            long y = 320 * SUB + 130 * SUB * SimTrig.sin_t(angle) / SimTrig.ONE;
            long appear_at = i * SimConfig.TICKS_PER_SECOND;
            countdown.hazards.Add(() => _coin(x, y, appear_at));
        }
        out_.Add(countdown);

        return out_;
    }

    static RoomDef _room(string id, long season, long from)
    {
        var def = new RoomDef(id, "seasonal", from);
        def.season = season;
        def.weight = WEIGHT;
        return def;
    }

    static Hazard _twin(long lane) => new Bouncer(Bouncer.TWIN_RADIUS, lane);

    static Hazard _ghost_door(long i)
    {
        long col = i % 2;
        long row = i / 2;
        long x0 = (90 + col * 120) * SUB;
        long y0 = (190 + row * 130) * SUB;
        var b = new Block(x0, y0, x0 + 60 * SUB, y0 + 34 * SUB);
        b.fade_period = 240;
        b.solid_ticks = 140;
        b.phase = i * 40;
        return b;
    }

    static Hazard _island(long band)
    {
        var b = new Block();
        b.band = band;
        return b;
    }

    /// An egg next to the island of the same band (CoinPickup.beside_band: it
    /// finds the island, built and placed just before it, in setup()).
    static Hazard _egg(long band)
    {
        var egg = new CoinPickup();
        egg.beside_band = band;
        return egg;
    }

    static Hazard _coin(long x, long y, long appear_at) => new CoinPickup(x, y, appear_at);

    static Hazard _firework(long delay, long style) => new Firework(delay, style);

    static Hazard _bats(string shape)
    {
        switch (shape)
        {
            case "wide":
                var wide = new Mover("figure8", 3);
                wide.loop_w = 104 * SUB;
                wide.loop_h = 112 * SUB;
                wide.loop_period = 380;
                return wide;
            case "pair":
                var pair = new Mover("figure8", 2);
                pair.loop_period = 400;
                pair.chase = true;
                return pair;
        }
        return new Mover("figure8", 3);
    }

    static Hazard _cupid(string shape, long slot)
    {
        var d = new Dart(true, slot);
        switch (shape)
        {
            case "double":
                d.lane_count = 5;
                d.lane_min = 110 * SUB;
                d.lane_max = 470 * SUB;
                d.pair = true;
                break;
            case "slow-volley":
                d.lanes_speed = 3 * SUB;
                d.lanes_flash = 84;
                break;
        }
        return d;
    }
}
