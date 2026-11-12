namespace FastSim;

/// Port of sim/rooms/hazard.gd. Subclasses keep the GDScript names
/// (snake_case) so each line can be checked against the original.
public abstract class Hazard
{
    public string kind = "";
    public bool alive = true;
    public long t = 0;

    public virtual void setup(GameSim sim, SimRng rng) { }
    public virtual void step(GameSim sim) { }
    public virtual bool kills(GameSim sim) => false;
    public virtual void touch(GameSim sim) { }
    public virtual long adjust_wall(GameSim sim, long side, long mask) => mask;
    public virtual void on_bounce(GameSim sim, SimRng rng) { }
    public virtual void on_flap(GameSim sim) { }
    public virtual bool blocks_exit(GameSim sim, long side, long y) => false;
    public virtual bool guards_edge(GameSim sim, bool top) => false;
    public virtual long band_top() => -1;
    public virtual long band_bottom() => -1;
    public virtual bool near_row(GameSim sim, long _y, long _half, long _from, long _to) => false;
    public virtual long wall_shift(GameSim sim, long side) => 0;
    public virtual bool locks_exit(GameSim sim) => false;
    public const int WARN_SIZE = 7;
    public const long WARN_KILL = 0, WARN_PUSH = 1;

    /// The warnings (tells) on screen now, WARN_SIZE numbers each added to `out_`:
    /// x0, y0, x1, y1, eta, dur, kind (see sim/rooms/hazard.gd). Reads only.
    public virtual void warnings(GameSim sim, List<long> out_) { }

    public static void add_warning(List<long> out_, long x0, long y0, long x1, long y1, long eta, long dur, long p_kind)
    {
        out_.Add(G.mini(x0, x1));
        out_.Add(G.mini(y0, y1));
        out_.Add(G.maxi(x0, x1));
        out_.Add(G.maxi(y0, y1));
        out_.Add(eta);
        out_.Add(dur);
        out_.Add(p_kind);
    }

    public virtual long checksum(long h) => h;

    /// A deep copy. The default copies every plain field; a subclass with
    /// lists or an RNG overrides this to copy those too.
    public virtual Hazard clone_deep() => (Hazard)MemberwiseClone();

    /// After a room copy: point references to other hazards at their copies.
    public virtual void remap(Dictionary<Hazard, Hazard> map) { }

    public static long mix_all(long h, params long[] values)
    {
        long out_ = h;
        foreach (long v in values) out_ = SimHash.mix(out_, v);
        return out_;
    }

    public static long mix_all(long h, List<long> values)
    {
        long out_ = h;
        foreach (long v in values) out_ = SimHash.mix(out_, v);
        return out_;
    }
}
