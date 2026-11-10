namespace FastSim;

public sealed class RoomDef
{
    public static class WallMode { public const long STATIC = 0, TIDE = 1, BLINK = 2; }
    public static class Speed { public const long NORMAL = 0, FAST = 1, SLOW = 2; }

    public const long CEILING_ARRIVAL = 170 * SimConfig.SUB;

    public string id = "";
    public string group = "starter";
    public long from_score = 0;
    public List<long> arrival_skip = new();
    public long weight = 10;
    public long season = Seasons.NONE;
    public string skin = "";

    public bool spikes = true;
    public long extra_spikes = 0;
    public long gap = 4;
    public long max_spikes = SimConfig.MAX_SPIKES;
    public long wall_mode = WallMode.STATIC;
    public bool squeeze = false;
    public long inset = 0;
    public long reach = 0;

    public long gravity_sign = 1;
    public long speed = Speed.NORMAL;
    public bool bounce_coin = true;
    public bool bounce_coin_stacks = false;

    public List<Func<Hazard>> hazards = new();
    /// Each combo is a list of factories.
    public List<List<Func<Hazard>>> combos = new();
    public List<RoomVariant> variants = new();

    public RoomDef(string p_id, string p_group, long p_from)
    {
        id = p_id;
        group = p_group;
        from_score = p_from;
    }

    public RoomDef with(List<Func<Hazard>> p_hazards)
    {
        hazards = p_hazards;
        return this;
    }

    public bool fits_arrival(long y)
    {
        for (int i = 0; i < arrival_skip.Count; i += 2)
            if (y >= arrival_skip[i] && y < arrival_skip[i + 1]) return false;
        return true;
    }
}
