namespace FastSim;

/// GDScript's integer helpers, with the exact same edge cases.
public static class G
{
    public static long mini(long a, long b) => a < b ? a : b;
    public static long maxi(long a, long b) => a > b ? a : b;
    public static long absi(long a) => a < 0 ? -a : a;
    public static long signi(long a) => a > 0 ? 1 : (a < 0 ? -1 : 0);

    /// Godot's CLAMP: below min gives min, else above max gives max.
    public static long clampi(long v, long lo, long hi) => v < lo ? lo : (v > hi ? hi : v);

    public static long posmod(long a, long b)
    {
        long v = a % b;
        if ((v < 0 && b > 0) || (v > 0 && b < 0)) v += b;
        return v;
    }

    /// int(bool).
    public static long B(bool b) => b ? 1 : 0;
}
