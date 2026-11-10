namespace FastSim;

/// Port of sim/hazards/orbit_coin.gd.
public sealed class OrbitCoin : CoinPickup
{
    public const long PERIOD = 640;

    public long cx = 0;
    public long cy = 0;
    public long radius = 0;
    public long phase = 0;

    public OrbitCoin(long p_cx = 0, long p_cy = 0, long p_radius = 0, long p_phase = 0) : base(p_cx, p_cy, 0)
    {
        cx = p_cx;
        cy = p_cy;
        radius = p_radius;
        phase = p_phase;
        _place();
    }

    public override void setup(GameSim _sim, SimRng _rng)
    {
        _place();
    }

    public override void step(GameSim _sim)
    {
        _place();
    }

    public void _place()
    {
        long a = phase + t * SimTrig.TURN / PERIOD;
        x = cx + radius * SimTrig.cos_t(a) / SimTrig.ONE;
        y = cy + radius * SimTrig.sin_t(a) / SimTrig.ONE;
    }

    public override long checksum(long h) => mix_all(h, x, y, cx, cy, radius, phase);
}
