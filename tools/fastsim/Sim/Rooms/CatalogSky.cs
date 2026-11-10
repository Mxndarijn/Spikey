namespace FastSim;

/// Port of sim/rooms/catalog_sky.gd. Order is part of the rules.
public static class CatalogSky
{
    public const long SUB = SimConfig.SUB;

    public static List<RoomDef> defs()
    {
        var out_ = new List<RoomDef>();

        var updraft = new RoomDef("updraft", "mid", 60);
        updraft.variants = new List<RoomVariant>
        {
            new RoomVariant("chimney").with(new List<Func<Hazard>> { () => _air(180, 50, Updraft.CHIMNEY) }),
            new RoomVariant("twin").with(new List<Func<Hazard>>
            {
                () => _air(100, 40, Updraft.HOVER), () => _air(260, 40, Updraft.HOVER),
            }),
            new RoomVariant("drift").with(new List<Func<Hazard>> { () => _drift(70, 220, 50) }),
            new RoomVariant("gust").with(new List<Func<Hazard>> { () => _gust() }),
            new RoomVariant("updown").with(new List<Func<Hazard>>
            {
                () => _air(120, 50, Updraft.HOVER), () => _air(240, 50, -Updraft.HOVER),
            }),
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
        for (long lane = 0; lane < 3; lane++)
        {
            long l = lane;
            bubbles.hazards.Add(() => _bubble(l));
        }
        out_.Add(bubbles);

        var rain = new RoomDef("rain", "late", 70);
        rain.weight = 8;
        rain.hazards.Add(() => _drop(30, 10 * SUB, 25));
        rain.hazards.Add(() => _drop(70, 10 * SUB, 25));
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
        keepy.hazards.Add(() => new KeepyBall());
        out_.Add(keepy);

        return out_;
    }

    static Hazard _air(long x_px, long half_px, long lift) => new Updraft(x_px * SUB, half_px * SUB, lift);

    static Hazard _drift(long min_px, long span_px, long half_px) =>
        new Updraft(min_px * SUB, half_px * SUB, Updraft.HOVER).drifting(min_px * SUB, span_px * SUB);

    static Hazard _gust() => new Updraft(SimConfig.WORLD_W / 2, Updraft.HALF_W, Updraft.STRONG).gusty();

    static Hazard _coin(long x_px, long y_px) => new CoinPickup(x_px * SUB, y_px * SUB);

    static Hazard _bubble(long lane) => new Bubble(lane);

    static Hazard _drop(long delay, long speed, long gap) => new Drop(delay, speed, gap);
}
