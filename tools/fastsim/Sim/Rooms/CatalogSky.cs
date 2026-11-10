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
        rain.hazards.Add(() => _drop(30, 10 * SUB, 25));
        rain.hazards.Add(() => _drop(70, 10 * SUB, 25));
        out_.Add(rain);

        var orchard = new RoomDef("orchard", "bonus", 30);
        orchard.weight = 4;
        orchard.max_spikes = 2;
        orchard.bounce_coin = false;
        orchard.skin = "pinecone";
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
}
