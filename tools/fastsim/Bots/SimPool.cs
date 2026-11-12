using System.Reflection;
using System.Reflection.Emit;

namespace FastSim;

/// Planner searches only: copies a sim into one the search threw away (a line
/// that died or lost its bucket) instead of allocating a new one. The result is
/// the same as `GameSim.clone_deep`: every field copied, the objects a sim owns
/// (state, room, hazards, RNGs, event list) copied into the old sim's own ones.
/// Hazards with lists or an RNG of their own (they override clone_deep) are still
/// cloned. Shared objects (the entry room and state, kept for a revive) stay
/// shared, as in clone_deep. Tool only; the game never calls this.
public static class SimPool
{
    static readonly Dictionary<Type, Action<object, object>> _copiers = new();
    static readonly Dictionary<Type, bool> _plain = new();

    /// Copies every instance field (the type's and its base classes') from `src` to `dst`.
    static Action<object, object> copier(Type t)
    {
        lock (_copiers)
        {
            if (_copiers.TryGetValue(t, out var f)) return f;
            var dm = new DynamicMethod("copy_" + t.Name, null, new[] { typeof(object), typeof(object) }, t, true);
            var il = dm.GetILGenerator();
            for (var at = t; at != null && at != typeof(object); at = at.BaseType)
                foreach (var fi in at.GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly))
                {
                    il.Emit(OpCodes.Ldarg_1);
                    il.Emit(OpCodes.Castclass, t);
                    il.Emit(OpCodes.Ldarg_0);
                    il.Emit(OpCodes.Castclass, t);
                    il.Emit(OpCodes.Ldfld, fi);
                    il.Emit(OpCodes.Stfld, fi);
                }
            il.Emit(OpCodes.Ret);
            f = (Action<object, object>)dm.CreateDelegate(typeof(Action<object, object>));
            _copiers[t] = f;
            return f;
        }
    }

    /// True when the hazard type copies with MemberwiseClone (no lists or RNGs of its own).
    static bool plain(Type t)
    {
        lock (_plain)
        {
            if (_plain.TryGetValue(t, out bool p)) return p;
            p = t.GetMethod(nameof(Hazard.clone_deep))!.DeclaringType == typeof(Hazard);
            _plain[t] = p;
            return p;
        }
    }

    [ThreadStatic] static Dictionary<Hazard, Hazard> _map;
    [ThreadStatic] static Dictionary<Type, Action<object, object>> _local;

    static Action<object, object> local(Type t)
    {
        _local ??= new();
        if (!_local.TryGetValue(t, out var f)) _local[t] = f = copier(t);
        return f;
    }

    /// `dst` becomes a deep copy of `src` (as `src.clone_deep()` would be). `dst`
    /// must be a sim nobody else uses (a copy the caller owns), never the game's.
    public static GameSim copy(GameSim src, GameSim dst)
    {
        var st = dst.state;
        var rm = dst.room;
        var hz = rm.hazards;
        var ev = dst.events;
        var r1 = dst._rng;
        var r2 = dst._spine;
        local(typeof(GameSim))(src, dst);
        local(typeof(SimState))(src.state, st);
        dst.state = st;
        ev.Clear();
        ev.AddRange(src.events);
        dst.events = ev;
        local(typeof(SimRng))(src._rng, r1);
        dst._rng = r1;
        local(typeof(SimRng))(src._spine, r2);
        dst._spine = r2;
        var from = src.room;
        local(typeof(RoomRuntime))(from, rm);
        rm.hazards = hz;
        dst.room = rm;
        int n = from.hazards.Count;
        bool partners = false;
        for (int i = 0; i < n; i++)
        {
            var h = from.hazards[i];
            var t = h.GetType();
            Hazard d = i < hz.Count ? hz[i] : null;
            if (d != null && d.GetType() == t && plain(t)) local(t)(h, d);
            else d = h.clone_deep();
            if (i < hz.Count) hz[i] = d;
            else hz.Add(d);
            partners |= h is Gate || h is Stalactite || h is Piston;
        }
        if (hz.Count > n) hz.RemoveRange(n, hz.Count - n);
        if (partners)
        {
            var map = _map ??= new Dictionary<Hazard, Hazard>(ReferenceEqualityComparer.Instance);
            map.Clear();
            for (int i = 0; i < n; i++) map[from.hazards[i]] = hz[i];
            foreach (var h in hz) h.remap(map);
            map.Clear();
        }
        return dst;
    }
}
