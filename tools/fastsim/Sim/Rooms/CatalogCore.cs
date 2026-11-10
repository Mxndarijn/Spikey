namespace FastSim;

/// Port of sim/rooms/catalog_core.gd. Order is part of the rules.
public static class CatalogCore
{
    public const long SUB = SimConfig.SUB;
    public const long GARDEN_CX = 180 * SUB;
    public const long GARDEN_CY = 320 * SUB;
    public const long ORBIT_RADIUS = 95 * SUB;

    public static List<RoomDef> defs()
    {
        var out_ = new List<RoomDef>();

        out_.Add(new RoomDef("open", "starter", 0));

        var crowded = new RoomDef("crowded", "starter", 10);
        crowded.extra_spikes = 1;
        crowded.variants = new List<RoomVariant>
        {
            new RoomVariant("classic"),
            new RoomVariant("lopsided").leaning(2),
            new RoomVariant("storm").sized(1, 1, 2),
        };
        out_.Add(crowded);

        var narrow = new RoomDef("narrow", "starter", 10);
        narrow.inset = 50 * SUB;
        narrow.reach = 100 * SUB;
        out_.Add(narrow);

        var tide = new RoomDef("tide", "starter", 10);
        tide.wall_mode = RoomDef.WallMode.TIDE;
        tide.variants = new List<RoomVariant>
        {
            new RoomVariant("normal"),
            new RoomVariant("big").sized(3, 2, -1),
            new RoomVariant("small").sized(2, 3, 3),
        };
        out_.Add(tide);

        var isles = new RoomDef("isles", "starter", 10);
        isles.max_spikes = 6;
        for (long i = 0; i < 4; i++)
        {
            long bi = i;
            isles.hazards.Add(() => _island(bi));
        }
        out_.Add(isles);

        var garden = new RoomDef("garden", "bonus", 20);
        garden.weight = 4;
        garden.max_spikes = 3;
        garden.bounce_coin_stacks = true;
        var diamond = new[] { new long[] { 180, 220 }, new long[] { 120, 320 }, new long[] { 240, 320 }, new long[] { 180, 420 } };
        var still = new List<Func<Hazard>>();
        var spots = new List<long>();
        foreach (long[] p in diamond)
        {
            long cx = p[0] * SUB;
            long cy = p[1] * SUB;
            still.Add(() => _coin(cx, cy, 0));
            spots.Add(p[0] * SUB);
            spots.Add(p[1] * SUB);
        }
        var orbit = new List<Func<Hazard>>();
        for (long i = 0; i < 4; i++)
        {
            long ph = i * SimTrig.TURN / 4;
            orbit.Add(() => _orbit_coin(ph));
        }
        var decoy = new List<Func<Hazard>>(still);
        decoy.Add(() => _decoy(spots));
        garden.variants = new List<RoomVariant>
        {
            new RoomVariant("classic").with(still),
            new RoomVariant("orbit").with(orbit),
            new RoomVariant("decoy").with(decoy),
        };
        out_.Add(garden);

        var bramble = new RoomDef("bramble", "mid", 40);
        bramble.variants = new List<RoomVariant>
        {
            new RoomVariant("classic").with(new List<Func<Hazard>> { () => new Bouncer() }),
            new RoomVariant("twin").with(new List<Func<Hazard>>
            {
                () => _twin(Bouncer.Lane.UPPER),
                () => _twin(Bouncer.Lane.LOWER),
            }),
            new RoomVariant("split").with(new List<Func<Hazard>> { () => new SplittingBouncer() }),
            new RoomVariant("revup").with(new List<Func<Hazard>> { () => new RevvingBouncer() }),
            new RoomVariant("curious").with(new List<Func<Hazard>> { () => new CuriousBouncer() }),
            new RoomVariant("heavy").with(new List<Func<Hazard>> { () => new HeavyBouncer() }),
        };
        out_.Add(bramble);

        var squeeze = new RoomDef("squeeze", "mid", 50);
        squeeze.squeeze = true;
        squeeze.variants = new List<RoomVariant>
        {
            new RoomVariant("classic"),
            new RoomVariant("left-only").squeezing(RoomVariant.Squeeze.LEFT),
            new RoomVariant("breathing").squeezing(RoomVariant.Squeeze.BREATHE),
        };
        out_.Add(squeeze);

        var slowmo = new RoomDef("slowmo", "bonus", 60);
        slowmo.weight = 4;
        slowmo.speed = RoomDef.Speed.SLOW;
        slowmo.max_spikes = 2;
        long[] arc = { 0, 60, 80, 60, 0 };
        var arc_coins = new List<Func<Hazard>>();
        var zigzag = new List<Func<Hazard>>();
        for (long i = 0; i < 5; i++)
        {
            long x = (90 + i * 45) * SUB;
            long y = (330 - arc[i]) * SUB;
            long zy = (i % 2 == 1 ? 380 : 280) * SUB;
            arc_coins.Add(() => _coin(x, y, 0));
            zigzag.Add(() => _coin(x, zy, 0));
        }
        slowmo.variants = new List<RoomVariant>
        {
            new RoomVariant("classic").with(arc_coins),
            new RoomVariant("zigzag").with(zigzag),
        };
        out_.Add(slowmo);

        var blink = new RoomDef("blink", "late", 80);
        blink.weight = 8;
        blink.wall_mode = RoomDef.WallMode.BLINK;
        blink.variants = new List<RoomVariant>
        {
            new RoomVariant("classic"),
            new RoomVariant("fast").blinking(RoomRuntime.BLINK_PERIOD / 2),
        };
        out_.Add(blink);

        var flip = new RoomDef("flip", "late", 90);
        flip.weight = 8;
        flip.gravity_sign = -1;
        flip.variants = new List<RoomVariant> { new RoomVariant("classic"), new RoomVariant("flip-flop").flipping() };
        out_.Add(flip);

        var midnight = new RoomDef("midnight", "late", 100);
        midnight.weight = 8;
        midnight.speed = RoomDef.Speed.FAST;
        midnight.extra_spikes = 2;
        midnight.variants = new List<RoomVariant>
        {
            new RoomVariant("classic"), new RoomVariant("lantern"), new RoomVariant("flicker")
        };
        out_.Add(midnight);

        return out_;
    }

    static Hazard _island(long band)
    {
        var b = new Block();
        b.band = band;
        return b;
    }

    static Hazard _twin(long lane) => new Bouncer(Bouncer.TWIN_RADIUS, lane);

    static Hazard _coin(long x, long y, long appear_at) => new CoinPickup(x, y, appear_at);

    static Hazard _orbit_coin(long phase) => new OrbitCoin(GARDEN_CX, GARDEN_CY, ORBIT_RADIUS, phase);

    static Hazard _decoy(List<long> spots) => new SpikeBall(spots);
}
