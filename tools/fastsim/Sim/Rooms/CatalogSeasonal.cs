namespace FastSim;

/// Port of sim/rooms/catalog_seasonal.gd. Order is part of the rules.
public static class CatalogSeasonal
{
    public const long SUB = SimConfig.SUB;
    public const long WEIGHT = 12;

    /// Egg Hunt: islands built so far in the room. GDScript has one static
    /// array; here one per thread so parallel bot sims do not share it.
    [ThreadStatic] static List<Hazard> _nest_store;

    static List<Hazard> _nest => _nest_store ??= new List<Hazard>();

    public static List<RoomDef> defs()
    {
        var out_ = new List<RoomDef>();

        // Halloween
        var pumpkin = _room("pumpkin", Seasons.HALLOWEEN, 40, "pumpkin");
        pumpkin.hazards.Add(() => new Bouncer());
        out_.Add(pumpkin);

        var ghosts = _room("ghostdoors", Seasons.HALLOWEEN, 30, "ghost");
        ghosts.max_spikes = 6;
        for (long i = 0; i < 6; i++)
        {
            long gi = i;
            ghosts.hazards.Add(() => _ghost_door(gi));
        }
        out_.Add(ghosts);

        var bats = _room("bats", Seasons.HALLOWEEN, 40, "bat");
        bats.hazards.Add(() => new Mover("figure8", 3));
        out_.Add(bats);

        // Winter
        var icicles = _room("icicle", Seasons.WINTER, 50, "icicle");
        icicles.hazards.Add(() => new Drop(30, 10 * SUB, 25));
        icicles.hazards.Add(() => new Drop(70, 10 * SUB, 25));
        out_.Add(icicles);

        var gifts = _room("gifts", Seasons.WINTER, 60, "gift");
        gifts.arrival_skip = new List<long> { 0, RoomDef.CEILING_ARRIVAL };
        gifts.hazards.Add(() => new CrateDrop(true));
        out_.Add(gifts);

        // Valentine's
        var hearts = _room("hearts", Seasons.VALENTINE, 10, "heart");
        hearts.hazards.Add(() => new Bumper());
        hearts.hazards.Add(() => new Bumper(true));
        out_.Add(hearts);

        var cupid = _room("cupid", Seasons.VALENTINE, 40, "cupid");
        cupid.hazards.Add(() => new Dart(true, 0));
        cupid.hazards.Add(() => new Dart(true, 1));
        out_.Add(cupid);

        // Spring
        var eggs = _room("eggs", Seasons.SPRING, 20, "egg");
        eggs.max_spikes = 6;
        for (long band = 0; band < 4; band++)
        {
            long b = band;
            eggs.hazards.Add(() => _island(b));
            eggs.hazards.Add(() => _egg(b));
        }
        out_.Add(eggs);

        var bees = _room("bees", Seasons.SPRING, 30, "bee");
        bees.hazards.Add(() => new Mover("wave", 4));
        bees.arrival_skip = new List<long> { 295 * SUB, 405 * SUB };
        out_.Add(bees);

        // Summer
        var beach = _room("beachball", Seasons.SUMMER, 40, "beachball");
        beach.group = "bonus";
        beach.max_spikes = 3;
        beach.hazards.Add(() => new KeepyBall());
        out_.Add(beach);

        var crabs = _room("crabs", Seasons.SUMMER, 30, "crab");
        crabs.arrival_skip = new List<long> { 0, RoomDef.CEILING_ARRIVAL };
        crabs.hazards.Add(() => new Crawler(0));
        crabs.hazards.Add(() => new Crawler(1));
        out_.Add(crabs);

        // New Year
        var fireworks = _room("fireworks", Seasons.NEW_YEAR, 50, "");
        foreach (long delay in new long[] { 0, 50, 100 })
        {
            long d = delay;
            fireworks.hazards.Add(() => _firework(d));
        }
        out_.Add(fireworks);

        var countdown = _room("countdown", Seasons.NEW_YEAR, 20, "");
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

    static RoomDef _room(string id, long season, long from, string skin)
    {
        var def = new RoomDef(id, "seasonal", from);
        def.season = season;
        def.weight = WEIGHT;
        def.skin = skin;
        return def;
    }

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
        if (band == 0) _nest.Clear();
        _nest.Add(b);
        return b;
    }

    /// An egg next to the island of the same band (built just before it, so
    /// the island is already placed when this runs).
    static Hazard _egg(long band)
    {
        var island = (Block)_nest[(int)band];
        long gap = 22 * SUB;
        long x = island.x1 + gap <= 290 * SUB ? island.x1 + gap : island.x0 - gap;
        long y = (island.y0 + island.y1) / 2;
        var egg = new CoinPickup(x, y, 0);
        return egg;
    }

    static Hazard _coin(long x, long y, long appear_at) => new CoinPickup(x, y, appear_at);

    static Hazard _firework(long delay) => new Firework(delay);
}
