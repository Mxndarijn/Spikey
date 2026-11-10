namespace FastSim;

/// Port of sim/sim_rng.gd (xoshiro128** on 32-bit values in 64-bit ints).
public sealed class SimRng
{
    public const long MASK = 0xFFFFFFFF;
    public long _s0, _s1, _s2, _s3;

    public SimRng(long seed_value = 0) { reseed(seed_value); }

    public SimRng Clone() => (SimRng)MemberwiseClone();

    public void reseed(long seed_value)
    {
        long x = (seed_value ^ 0x9E3779B9) & MASK;
        x ^= (seed_value >> 32) & MASK;
        if (x == 0) x = 0x6D2B79F5;
        x = _xorshift32(x); _s0 = x;
        x = _xorshift32(x); _s1 = x;
        x = _xorshift32(x); _s2 = x;
        x = _xorshift32(x); _s3 = x;
    }

    public long next_u32()
    {
        long result = (_rotl((_s1 * 5) & MASK, 7) * 9) & MASK;
        long t = (_s1 << 9) & MASK;
        _s2 ^= _s0;
        _s3 ^= _s1;
        _s1 ^= _s2;
        _s0 ^= _s3;
        _s2 ^= t;
        _s3 = _rotl(_s3, 11);
        return result;
    }

    public long next_below(long n) => next_u32() % n;

    public long state_checksum()
        => SimHash.mix(SimHash.mix(SimHash.mix(SimHash.mix(SimHash.SEED, _s0), _s1), _s2), _s3);

    static long _xorshift32(long v)
    {
        long x = v;
        x ^= (x << 13) & MASK;
        x ^= x >> 17;
        x ^= (x << 5) & MASK;
        return x;
    }

    static long _rotl(long x, int k) => ((x << k) | (x >> (32 - k))) & MASK;
}
