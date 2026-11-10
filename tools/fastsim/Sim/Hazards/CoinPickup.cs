namespace FastSim;

/// Port of sim/hazards/coin_pickup.gd.
public class CoinPickup : Hazard
{
    public long x = 0;
    public long y = 0;
    public long appear_at = 0;
    public const long BESIDE_GAP = 22 * SimConfig.SUB;
    public const long BESIDE_MAX_X = 290 * SimConfig.SUB;

    public long vy = 0;
    public long beside_band = -1;

    public CoinPickup(long p_x = 0, long p_y = 0, long p_appear_at = 0)
    {
        kind = "coin";
        x = p_x;
        y = p_y;
        appear_at = p_appear_at;
    }

    public override void setup(GameSim sim, SimRng _rng)
    {
        if (beside_band < 0) return;
        var hs = sim.room.hazards;
        for (int i = 0; i < hs.Count; i++)
        {
            if (hs[i] is Block island && island.band == beside_band)
            {
                x = island.x1 + BESIDE_GAP <= BESIDE_MAX_X ? island.x1 + BESIDE_GAP : island.x0 - BESIDE_GAP;
                y = (island.y0 + island.y1) / 2;
                return;
            }
        }
    }

    public virtual bool visible() => t >= appear_at;

    public override void step(GameSim _sim)
    {
        if (vy != 0 && visible())
        {
            y += vy;
            if (y > SimConfig.KILL_BOTTOM + SimConfig.COIN_RADIUS) alive = false;
        }
    }

    public override void touch(GameSim sim)
    {
        if (visible() && sim.bird_touches_circle(x, y, SimConfig.COIN_RADIUS))
        {
            alive = false;
            sim.collect_coin(x, y);
        }
    }

    public override long checksum(long h) => mix_all(h, x, y, appear_at, vy);
}
