namespace FastSim;

/// Port of sim/rooms/catalog_sky.gd. Order is part of the rules.
public static class CatalogSky
{
    public const long SUB = SimConfig.SUB;

    public static List<RoomDef> defs()
    {
        var out_ = new List<RoomDef>();

        var updraft = new RoomDef("updraft", "mid", 60);
        updraft.hazards.Add(() => new Updraft());
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
        keepy.hazards.Add(() => new KeepyBall());
        out_.Add(keepy);

        return out_;
    }

    static Hazard _bubble(long lane) => new Bubble(lane);

    static Hazard _drop(long delay, long speed, long gap) => new Drop(delay, speed, gap);

    static Hazard _rain(long delay, long speed, long gap, long warn, long radius, long style)
        => new Drop(delay, speed, gap, warn, radius, style);

    static Hazard _sweep(long delay, long column)
        => new Drop(delay, 10 * SUB, 60, Drop.WARN, Drop.RADIUS, Drop.Style.PLAIN, column);
}
