namespace FastSim;

/// Port of sim/hazards/pad_coin.gd.
public sealed class PadCoin : CoinPickup
{
    public const long RESPAWN = 60;

    public bool on_top = false;
    public long wait = 0;

    public PadCoin(bool p_on_top = false) : base(0, 0, 0)
    {
        on_top = p_on_top;
    }

    public override void setup(GameSim sim, SimRng _rng)
    {
        _follow(sim);
    }

    public override bool visible() => wait == 0;

    public override void step(GameSim sim)
    {
        if (wait > 0) wait -= 1;
        _follow(sim);
    }

    public void _follow(GameSim sim)
    {
        var hs = sim.room.hazards;
        for (int i = 0; i < hs.Count; i++)
        {
            if (hs[i] is EdgePad pad && pad.top == on_top)
            {
                x = G.clampi((pad.x0() + pad.x1()) / 2, SimConfig.COIN_MIN_X, SimConfig.COIN_MAX_X);
                y = on_top ? SimConfig.COIN_MIN_Y : SimConfig.COIN_MAX_Y;
                return;
            }
        }
    }

    public override void touch(GameSim sim)
    {
        if (visible() && sim.bird_touches_circle(x, y, SimConfig.COIN_RADIUS))
        {
            sim.collect_coin(x, y);
            on_top = !on_top;
            wait = RESPAWN;
            _follow(sim);
        }
    }

    public override long checksum(long h) => mix_all(h, x, y, G.B(on_top), wait);
}
