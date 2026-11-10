namespace FastSim;

/// Port of sim/hazards/stalactite.gd.
public class Stalactite : Hazard
{
    public const long GAP = 150 * SimConfig.SUB;
    public const long HALF_W = 22 * SimConfig.SUB;
    public const long GAP_MIN = 150 * SimConfig.SUB;
    public const long GAP_MAX = 490 * SimConfig.SUB;
    public const long REACH = 40 * SimConfig.SUB;
    public const long MAX_STEP = 60 * SimConfig.SUB;
    public const long WALL_CLEAR = 70 * SimConfig.SUB;
    public const long SLIDE = 3 * SimConfig.SUB;

    public long x = 0;
    public long gap_y = 0;
    public long target_y = 0;
    public bool follows = false;
    /// GDScript types this as Hazard; only Stalactites are ever stored in it.
    public Stalactite partner = null;

    public Stalactite(long p_x = 0, bool p_follows = false)
    {
        kind = "stalactite";
        x = p_x;
        follows = p_follows;
    }

    public override void remap(Dictionary<Hazard, Hazard> map)
    {
        if (partner != null) partner = (Stalactite)map[partner];
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        partner = null;
        if (follows)
        {
            for (int i = 0; i < sim.room.hazards.Count; i++)
            {
                var h = sim.room.hazards[i];
                if (h != this && h.kind == kind)
                {
                    var s = (Stalactite)h;
                    partner = s;
                    s.partner = this;
                }
            }
        }
        gap_y = G.clampi(FairLanes.entry_y(sim), GAP_MIN, GAP_MAX);
        target_y = gap_y;
    }

    public override void on_bounce(GameSim sim, SimRng rng)
    {
        if (follows) return;
        Stalactite near = this;
        Stalactite far = partner;
        if (partner != null && (partner.x > x) == (sim.state.vx < 0))
        {
            near = partner;
            far = this;
        }
        if (t == 0) near.target_y = near.gap_y;
        else near.target_y = _around(rng, sim.state.y, REACH);
        if (far != null) far.target_y = _around(rng, near.target_y, MAX_STEP);
        _clear_wall_ahead(sim, far != null ? far : near);
    }

    public static void _clear_wall_ahead(GameSim sim, Stalactite column)
    {
        var s = sim.state;
        long mask = s.vx > 0 ? s.right_spikes : s.left_spikes;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
            if (G.absi(SimConfig.slot_center_y(slot) - column.target_y) < WALL_CLEAR)
                mask &= ~(1L << (int)slot);
        if (s.vx > 0) s.right_spikes = mask;
        else s.left_spikes = mask;
    }

    public static long _around(SimRng rng, long center, long spread)
    {
        long lo = G.maxi(GAP_MIN, center - spread);
        long hi = G.mini(GAP_MAX, center + spread);
        if (lo > hi) return G.clampi(center, GAP_MIN, GAP_MAX);
        return lo + rng.next_below(hi - lo + 1);
    }

    public override void step(GameSim sim)
    {
        if (gap_y < target_y) gap_y = G.mini(gap_y + SLIDE, target_y);
        else if (gap_y > target_y) gap_y = G.maxi(gap_y - SLIDE, target_y);
    }

    public long top_tip() => gap_y - GAP / 2;

    public long bottom_tip() => gap_y + GAP / 2;

    public override bool kills(GameSim sim)
    {
        return sim.bird_touches_rect(x - HALF_W, 0, x + HALF_W, top_tip())
            || sim.bird_touches_rect(x - HALF_W, bottom_tip(), x + HALF_W, SimConfig.WORLD_H);
    }

    public override long checksum(long h) => mix_all(h, x, gap_y, target_y, G.B(follows));
}
