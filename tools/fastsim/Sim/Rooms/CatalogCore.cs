namespace FastSim;

/// Port of sim/rooms/catalog_core.gd. Order is part of the rules.
public static class CatalogCore
{
    public const long SUB = SimConfig.SUB;

    public static List<RoomDef> defs()
    {
        var out_ = new List<RoomDef>();

        out_.Add(new RoomDef("open", "starter", 0));

        var crowded = new RoomDef("crowded", "starter", 10);
        crowded.extra_spikes = 1;
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
        foreach (long[] p in new[] { new long[] { 180, 220 }, new long[] { 120, 320 }, new long[] { 240, 320 }, new long[] { 180, 420 } })
        {
            long cx = p[0] * SUB;
            long cy = p[1] * SUB;
            garden.hazards.Add(() => _coin(cx, cy, 0));
        }
        out_.Add(garden);

        var bramble = new RoomDef("bramble", "mid", 40);
        bramble.hazards.Add(() => new Bouncer());
        out_.Add(bramble);

        var squeeze = new RoomDef("squeeze", "mid", 50);
        squeeze.squeeze = true;
        out_.Add(squeeze);

        var slowmo = new RoomDef("slowmo", "bonus", 60);
        slowmo.weight = 4;
        slowmo.speed = RoomDef.Speed.SLOW;
        slowmo.max_spikes = 2;
        long[] arc = { 0, 60, 80, 60, 0 };
        for (long i = 0; i < 5; i++)
        {
            long x = (90 + i * 45) * SUB;
            long y = (330 - arc[i]) * SUB;
            slowmo.hazards.Add(() => _coin(x, y, 0));
        }
        out_.Add(slowmo);

        var blink = new RoomDef("blink", "late", 80);
        blink.weight = 8;
        blink.wall_mode = RoomDef.WallMode.BLINK;
        out_.Add(blink);

        var flip = new RoomDef("flip", "late", 90);
        flip.weight = 8;
        flip.gravity_sign = -1;
        out_.Add(flip);

        var midnight = new RoomDef("midnight", "late", 100);
        midnight.weight = 8;
        midnight.speed = RoomDef.Speed.FAST;
        midnight.extra_spikes = 2;
        midnight.skin = "midnight";
        out_.Add(midnight);

        return out_;
    }

    static Hazard _island(long band)
    {
        var b = new Block();
        b.band = band;
        return b;
    }

    static Hazard _coin(long x, long y, long appear_at) => new CoinPickup(x, y, appear_at);
}
