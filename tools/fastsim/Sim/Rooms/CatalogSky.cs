namespace FastSim;

/// Port of sim/rooms/catalog_sky.gd. Order is part of the rules.
public static class CatalogSky
{
    public const long SUB = SimConfig.SUB;
    public const long SPIKY_SPREAD = 230;

    public static List<RoomDef> defs()
    {
        var out_ = new List<RoomDef>();

        var updraft = new RoomDef("updraft", "mid", 60);
        var high = new List<long> { 0, 172 * SUB };
        updraft.variants = new List<RoomVariant>
        {
            new RoomVariant("chimney").with(new List<Func<Hazard>> { () => _air(180, 50, Updraft.CHIMNEY) }),
            new RoomVariant("twin").with(new List<Func<Hazard>>
            {
                () => _air(100, 40, Updraft.HOVER), () => _air(260, 40, Updraft.HOVER),
            }).skipping(high),
            new RoomVariant("drift").with(new List<Func<Hazard>> { () => _drift(70, 220, 50) }),
            new RoomVariant("gust").with(new List<Func<Hazard>> { () => _gust() }),
            new RoomVariant("updown").with(new List<Func<Hazard>>
            {
                () => _air(120, 50, Updraft.HOVER), () => _air(240, 50, -Updraft.HOVER),
            }).skipping(high),
            new RoomVariant("coins").with(new List<Func<Hazard>>
            {
                () => _air(180, 60, Updraft.LIFT),
                () => _coin(180, 220),
                () => _coin(180, 270),
                () => _coin(180, 320),
            }),
        };
        out_.Add(updraft);

        var bubbles = new RoomDef("bubbles", "mid", 50);
        bubbles.arrival_skip = new List<long> { 0, RoomDef.CEILING_ARRIVAL };
        var classic = new List<Func<Hazard>>();
        var giants = new List<Func<Hazard>>();
        var coin_bubbles = new List<Func<Hazard>>();
        for (long lane = 0; lane < 3; lane++)
        {
            long l = lane;
            classic.Add(() => _bubble(l));
            giants.Add(() => _giant(l));
            coin_bubbles.Add(l % 2 == 0 ? (Func<Hazard>)(() => _coin_bubble(l)) : () => _bubble(l));
        }
        bubbles.variants = new List<RoomVariant>
        {
            new RoomVariant("classic").with(classic),
            new RoomVariant("giants").with(giants),
            new RoomVariant("spiky").with(new List<Func<Hazard>>
            {
                () => _bubble(0),
                () => _spiky_bubble(1, 0),
                () => _bubble(2),
                () => _spiky_bubble(3, SPIKY_SPREAD),
            }),
            new RoomVariant("coin-bubbles").with(coin_bubbles),
        };
        out_.Add(bubbles);

        var rain = new RoomDef("rain", "late", 70);
        rain.weight = 8;
        var hail = new List<Func<Hazard>>();
        foreach (long d in new long[] { 30, 55, 80, 105 })
        {
            long dd = d;
            hail.Add(() => _rain(dd, 10 * SUB, 45, Drop.WARN, 6 * SUB, Drop.Style.PLAIN));
        }
        var sweep = new List<Func<Hazard>>();
        for (long i = 0; i < 4; i++)
        {
            long ii = i;
            sweep.Add(() => _sweep(30 + 12 * ii, (45 + 90 * ii) * SUB));
        }
        rain.variants = new List<RoomVariant>
        {
            new RoomVariant("classic").with(new List<Func<Hazard>>
            {
                () => _drop(30, 10 * SUB, 25), () => _drop(70, 10 * SUB, 25),
            }),
            new RoomVariant("drizzle").with(new List<Func<Hazard>>
            {
                () => _rain(30, 6 * SUB, 30, 75, Drop.RADIUS, Drop.Style.PLAIN),
                () => _rain(135, 6 * SUB, 30, 75, Drop.RADIUS, Drop.Style.PLAIN),
            }),
            new RoomVariant("hail").with(hail),
            new RoomVariant("sweep").with(sweep),
            new RoomVariant("shatter").with(new List<Func<Hazard>>
            {
                () => _rain(30, 10 * SUB, 40, 50, Drop.RADIUS, Drop.Style.SHATTER),
                () => _rain(85, 10 * SUB, 40, 50, Drop.RADIUS, Drop.Style.SHATTER),
            }),
            new RoomVariant("wobble").with(new List<Func<Hazard>>
            {
                () => _rain(30, 7 * SUB, 30, 55, Drop.RADIUS, Drop.Style.WOBBLE),
                () => _rain(90, 7 * SUB, 30, 55, Drop.RADIUS, Drop.Style.WOBBLE),
            }),
            new RoomVariant("stake").with(new List<Func<Hazard>>
            {
                () => _rain(30, 8 * SUB, 30, 60, 13 * SUB, Drop.Style.STAKE),
                () => _rain(140, 8 * SUB, 30, 60, 13 * SUB, Drop.Style.STAKE),
            }),
        };
        out_.Add(rain);

        var orchard = new RoomDef("orchard", "bonus", 30);
        orchard.weight = 4;
        orchard.max_spikes = 2;
        orchard.bounce_coin = false;
        orchard.hazards.Add(() => new OrchardSpawner());
        orchard.hazards.Add(() => _drop(90, 6 * SUB, 140));
        out_.Add(orchard);

        var keepy = new RoomDef("keepy", "bonus", 40);
        keepy.weight = 4;
        keepy.max_spikes = 3;
        keepy.variants = new List<RoomVariant>
        {
            new RoomVariant("classic").with(new List<Func<Hazard>> { () => new KeepyBall() }),
            new RoomVariant("two-balls").with(new List<Func<Hazard>>
            {
                () => new KeepyBall().dropping(0),
                () => new KeepyBall().dropping(KeepyBall.SECOND_DROP),
            }),
        };
        out_.Add(keepy);

        return out_;
    }

    static Hazard _air(long x_px, long half_px, long lift) => new Updraft(x_px * SUB, half_px * SUB, lift);

    static Hazard _drift(long min_px, long span_px, long half_px) =>
        new Updraft(min_px * SUB, half_px * SUB, Updraft.HOVER).drifting(min_px * SUB, span_px * SUB);

    static Hazard _gust() => new Updraft(SimConfig.WORLD_W / 2, Updraft.HALF_W, Updraft.STRONG).gusty();

    static Hazard _coin(long x_px, long y_px) => new CoinPickup(x_px * SUB, y_px * SUB);

    static Hazard _bubble(long lane) => new Bubble(lane);

    static Hazard _giant(long lane) => new Bubble(lane, Bubble.GIANT_RADIUS, Bubble.GIANT_RISE);

    static Hazard _spiky_bubble(long lane, long delay) => new Bubble(lane).spiky(delay);

    static Hazard _coin_bubble(long lane) => new Bubble(lane).with_coin();

    static Hazard _drop(long delay, long speed, long gap) => new Drop(delay, speed, gap);

    static Hazard _rain(long delay, long speed, long gap, long warn, long radius, long style)
        => new Drop(delay, speed, gap, warn, radius, style);

    static Hazard _sweep(long delay, long column)
        => new Drop(delay, 10 * SUB, 60, Drop.WARN, Drop.RADIUS, Drop.Style.PLAIN, column);
}
