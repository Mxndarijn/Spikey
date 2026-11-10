namespace FastSim;

/// Port of sim/hazards/coin_pickup.gd.
public class CoinPickup : Hazard
{
    public long x = 0;
    public long y = 0;
    public long appear_at = 0;
    public long vy = 0;

    public CoinPickup(long p_x = 0, long p_y = 0, long p_appear_at = 0)
    {
        kind = "coin";
        x = p_x;
        y = p_y;
        appear_at = p_appear_at;
    }

    public bool visible() => t >= appear_at;

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
