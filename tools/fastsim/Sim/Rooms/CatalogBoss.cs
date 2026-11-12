namespace FastSim;

/// Port of sim/rooms/catalog_boss.gd. Order is part of the rules.
public static class CatalogBoss
{
    public const long SPIKES = 3;

    public static List<RoomDef> defs()
    {
        var out_ = new List<RoomDef>();
        out_.Add(_boss("boss_watcher", () => new BossWatcher()));
        out_.Add(_boss("boss_crusher", () => new BossCrusher()));
        out_.Add(_boss("boss_saw", () => new BossSaw()));
        return out_;
    }

    public static RoomDef _boss(string id, Func<Hazard> make)
    {
        var def = new RoomDef(id, "boss", SimConfig.BOSS_EVERY);
        def.boss = true;
        def.max_spikes = SPIKES;
        def.hazards.Add(make);
        return def;
    }
}
