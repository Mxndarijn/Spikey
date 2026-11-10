namespace FastSim;

/// Port of sim/rooms/room_catalog.gd.
public static class RoomCatalog
{
    static readonly string[] CALM_GROUPS = { "starter", "mid", "bonus", "seasonal" };
    static readonly string[] WILD_GROUPS = { "mid", "late", "seasonal" };

    static List<RoomDef> _all;
    static long _first = -1;

    public static List<RoomDef> all()
    {
        if (_all == null)
        {
            var list = new List<RoomDef>();
            list.AddRange(CatalogCore.defs());
            list.AddRange(CatalogMotion.defs());
            list.AddRange(CatalogMachines.defs());
            list.AddRange(CatalogSky.defs());
            list.AddRange(CatalogSeasonal.defs());
            list.AddRange(CatalogCombo.defs());
            list.AddRange(CatalogTwists.defs());
            _all = list;
        }
        return _all;
    }

    public static long first_index()
    {
        if (_first < 0) _first = index_of("open");
        return _first;
    }

    public static long index_of(string id)
    {
        var list = all();
        for (int i = 0; i < list.Count; i++)
            if (list[i].id == id) return i;
        return -1;
    }

    public static RoomDef find(string id)
    {
        long i = index_of(id);
        return i >= 0 ? all()[(int)i] : null;
    }

    public static bool allowed(RoomDef def, long score, long season)
    {
        if (def.from_score > score) return false;
        return def.season == Seasons.NONE || def.season == season;
    }

    public static long route_weight(RoomDef def, long route)
    {
        if (route == ExitKind.CALM)
        {
            if (Array.IndexOf(CALM_GROUPS, def.group) < 0) return 0;
            return def.group == "bonus" ? def.weight * 2 : def.weight;
        }
        if (route == ExitKind.WILD)
        {
            if (Array.IndexOf(WILD_GROUPS, def.group) < 0) return 0;
            return def.group == "late" ? def.weight * 2 : def.weight;
        }
        return def.weight;
    }

    public static long pick_next(SimRng rng, long current, long score, long season, long route = ExitKind.NORMAL, long arrival_y = SimConfig.WORLD_H)
    {
        var list = all();
        long start = first_index();
        var weights = new long[list.Count];
        long total = 0;
        for (int i = 0; i < list.Count; i++)
        {
            long w = 0;
            bool fits = list[i].fits_arrival(arrival_y);
            if (i != current && i != start && fits && allowed(list[i], score, season)) w = route_weight(list[i], route);
            weights[i] = w;
            total += w;
        }
        if (total == 0 && route != ExitKind.NORMAL) return pick_next(rng, current, score, season, ExitKind.NORMAL, arrival_y);
        if (total == 0) return current;
        long r = rng.next_below(total);
        for (int i = 0; i < list.Count; i++)
        {
            r -= weights[i];
            if (r < 0 && weights[i] > 0) return i;
        }
        return current;
    }
}
