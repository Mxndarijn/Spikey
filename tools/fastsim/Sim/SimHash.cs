namespace FastSim;

public static class SimHash
{
    public const long SEED = 0x811C9DC5;
    public const long PRIME = 16777619;
    public const long MASK = 0xFFFFFFFF;

    public static long mix(long h, long value) => ((h ^ (value & MASK)) * PRIME) & MASK;
}
