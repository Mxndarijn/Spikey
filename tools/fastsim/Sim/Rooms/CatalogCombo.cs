namespace FastSim;

/// Port of sim/rooms/catalog_combo.gd. Order is part of the rules.
public static class CatalogCombo
{
    public const long SUB = SimConfig.SUB;

    public static List<RoomDef> defs()
    {
        var out_ = new List<RoomDef>();

        var double_ = new RoomDef("double", "late", 120);
        double_.weight = 6;
        double_.max_spikes = 6;
        double_.combos = new List<List<Func<Hazard>>>
        {
            new List<Func<Hazard>> { () => new Rotor(), () => _piston(0, 0, 30) },
            new List<Func<Hazard>> { () => new Pendulum(), () => _drop(60) },
            new List<Func<Hazard>> { () => new Bouncer(), () => new Beam(3) },
            new List<Func<Hazard>> { () => new SawRing(), () => new Stalker() },
        };
        out_.Add(double_);

        return out_;
    }

    static Hazard _piston(long side, long half, long delay) => new Piston(side, half, delay);

    static Hazard _drop(long delay) => new Drop(delay, 10 * SUB, 25);
}
