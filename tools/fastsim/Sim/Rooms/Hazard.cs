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
