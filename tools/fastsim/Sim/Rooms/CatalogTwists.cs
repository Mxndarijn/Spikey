namespace FastSim;

/// Port of sim/rooms/catalog_twists.gd. Order is part of the rules.
public static class CatalogTwists
{
    public const long SUB = SimConfig.SUB;

    public static List<RoomDef> defs()
    {
        var out_ = new List<RoomDef>();

        var wind = new RoomDef("crosswind", "starter", 10);
        wind.hazards.Add(() => new Wind());
        wind.variants = new List<RoomVariant>
        {
            new RoomVariant("steady"), new RoomVariant("split"), new RoomVariant("gusty"),
        };
        out_.Add(wind);

        var belt = new RoomDef("belt", "starter", 20);
        belt.hazards.Add(() => new Belt());
        belt.variants = new List<RoomVariant>
        {
            new RoomVariant("up"), new RoomVariant("counter"), new RoomVariant("switchback"),
        };
        out_.Add(belt);

        var lock_ = new RoomDef("lockexit", "mid", 40);
        lock_.hazards.Add(() => new ExitKey());
        lock_.variants = new List<RoomVariant>
        {
            new RoomVariant("classic").sized(1, 1, 1),
            new RoomVariant("orbit").sized(1, 1, 1),
            new RoomVariant("trio").sized(1, 1, 1),
            new RoomVariant("quad").sized(1, 1, 1),
            new RoomVariant("chain").sized(1, 1, 1),
        };
        out_.Add(lock_);

        var lava = new RoomDef("lava", "mid", 50);
        lava.max_spikes = 6;
        lava.hazards.Add(() => new Lava());
        lava.variants = new List<RoomVariant> { new RoomVariant("lava"), new RoomVariant("crusher") };
        out_.Add(lava);

        var echo = new RoomDef("echo", "late", 80);
        echo.weight = 8;
        echo.arrival_skip = new List<long> { 280 * SUB, 360 * SUB };
        echo.hazards.Add(() => new Echo());
        echo.variants = new List<RoomVariant> { new RoomVariant("echo"), new RoomVariant("mirror") };
        out_.Add(echo);

        return out_;
    }
}
