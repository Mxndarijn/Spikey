namespace FastSim;

/// Port of sim/rooms/catalog_combo.gd. Order is part of the rules.
public static class CatalogCombo
{
    public const long SUB = SimConfig.SUB;
    public const long COMBO_WARN = SimConfig.ARRIVAL_BLIND;

    public static List<RoomDef> defs()
    {
        var out_ = new List<RoomDef>();

        var double_ = new RoomDef("double", "late", 120);
        double_.weight = 6;
        double_.max_spikes = 6;
        double_.variants = new List<RoomVariant>
        {
            new RoomVariant("pinwheel_piston").with(new List<Func<Hazard>> { () => new Rotor(), () => _piston(0, 0, 30) }),
            new RoomVariant("swing_rain").with(new List<Func<Hazard>> { () => new Pendulum(), () => _drop(60) })
                .skipping(new List<long> { 318 * SUB, 368 * SUB }),
            new RoomVariant("bramble_beams").with(new List<Func<Hazard>> { () => new Bouncer(), () => new Beam(3, SimConfig.WARN_TICKS, true) }),
            new RoomVariant("saw_rain").with(new List<Func<Hazard>> { () => new SawRing(), () => _drop(60) }),
        };
        out_.Add(double_);

        return out_;
    }

    static Hazard _piston(long side, long half, long delay) => new Piston(side, half, delay, COMBO_WARN, true);

    static Hazard _drop(long delay) => new Drop(delay, 10 * SUB, 25, COMBO_WARN);
}
