namespace FastSim;

/// Port of sim/rooms/catalog_machines.gd. Order is part of the rules.
public static class CatalogMachines
{
    public const long SUB = SimConfig.SUB;

    public static List<RoomDef> defs()
    {
        var out_ = new List<RoomDef>();

        var piston = new RoomDef("piston", "mid", 30);
        piston.max_spikes = 6;
        piston.hazards.Add(() => _piston(0, 0, 30));
        piston.hazards.Add(() => _piston(1, 1, 30 + Piston.PERIOD / 2));
        out_.Add(piston);

        var court = new RoomDef("court", "mid", 40);
        court.hazards.Add(() => _pad(true, 300));
        court.hazards.Add(() => _pad(false, 240));
        court.variants = new List<RoomVariant>
        {
            new RoomVariant("classic"),
            new RoomVariant("goal-pad").with(new List<Func<Hazard>> { () => new PadCoin(false) }),
        };
        out_.Add(court);

        var crates = new RoomDef("crates", "mid", 60);
        crates.max_spikes = 6;
        crates.hazards.Add(() => new CrateDrop());
        out_.Add(crates);

        var beams = new RoomDef("beams", "mid", 50);
        beams.max_spikes = 5;
        beams.hazards.Add(() => new Beam());
        out_.Add(beams);

        var stalac = new RoomDef("stalac", "mid", 30);
        stalac.max_spikes = 4;
        stalac.arrival_skip = new List<long> { 0, RoomDef.CEILING_ARRIVAL };
        stalac.hazards.Add(() => _stalactite(130 * SUB, false));
        stalac.hazards.Add(() => _stalactite(230 * SUB, true));
        out_.Add(stalac);

        var hunter = new RoomDef("hunter", "late", 80);
        hunter.weight = 8;
        hunter.hazards.Add(() => new Dart());
        out_.Add(hunter);

        return out_;
    }

    static Hazard _piston(long side, long half, long delay) => new Piston(side, half, delay);

    static Hazard _pad(bool top, long period) => new EdgePad(top, period);

    static Hazard _stalactite(long x, bool follows) => new Stalactite(x, follows);
}
