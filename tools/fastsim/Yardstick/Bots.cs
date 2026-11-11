using FastSim.Rl;

namespace FastSim.Yard;

/// One bot the yardstick can measure (docs/YARDSTICK.md). `make(seed)` returns
/// a fresh decide function for one run: called once per tick, before
/// sim.step(), it returns whether to tap. The yardstick always calls it on the
/// live sim; a bot must not step or change that sim (clone it to look ahead).
/// `copies` says what the bot reads besides the screen: Copies.REAL (it
/// steps copies of the real sim, so it knows hidden random draws: a ceiling,
/// not a player), Copies.SCRAMBLED (copies whose RNG and hidden salts are
/// replaced: it knows the rules and visible motion, not the draws) or
/// Copies.NONE (only what it sees). The user allows predicting visible
/// motion, not RNG outcomes.
public sealed record BotSpec(string name, string about, string copies, Func<long, Func<GameSim, bool>> make)
{
    public bool peeks => copies == Copies.REAL;
}

public static class Copies
{
    public const string REAL = "real", SCRAMBLED = "scrambled", NONE = "none";
}

/// The bots the yardstick knows. A new bot plugs in from its own file, so no
/// one edits this one:
///
///     static class MyBotYardstick
///     {
///         [System.Runtime.CompilerServices.ModuleInitializer]
///         internal static void Init() => FastSim.Yard.Bots.add(new("mybot",
///             "what it is", FastSim.Yard.Copies.NONE, seed => new MyBot(seed).decide));
///     }
///
/// A family with levels adds one name per level ("human:good").
public static class Bots
{
    static readonly Dictionary<string, BotSpec> _all = new();
    static readonly object _lock = new();
    static bool _builtins;

    public static void add(BotSpec b)
    {
        lock (_lock) _all[b.name] = b;
    }

    public static IReadOnlyList<BotSpec> all()
    {
        builtins();
        lock (_lock) return _all.Values.OrderBy(b => b.name).ToList();
    }

    public static BotSpec find(string name)
    {
        builtins();
        lock (_lock) return _all.GetValueOrDefault(name);
    }

    /// `rl:all` and other `family:all` names: every bot of that family, in
    /// tier order when the names are tiers.
    public static List<BotSpec> pick(string list)
    {
        var out_ = new List<BotSpec>();
        foreach (var raw in list.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (raw.EndsWith(":all"))
            {
                string fam = raw[..^3];
                var group = all().Where(b => b.name.StartsWith(fam)).ToList();
                group.Sort((a, b) => tier_order(a.name).CompareTo(tier_order(b.name)));
                out_.AddRange(group);
                continue;
            }
            var spec = find(raw) ?? throw new ArgumentException($"no bot '{raw}' (known: {string.Join(", ", all().Select(b => b.name))})");
            out_.Add(spec);
        }
        return out_;
    }

    static int tier_order(string name)
    {
        int i = Array.IndexOf(Tiers.NAMES, name[(name.LastIndexOf(':') + 1)..]);
        return i < 0 ? 99 : i;
    }

    static void builtins()
    {
        lock (_lock)
        {
            if (_builtins) return;
            _builtins = true;
        }
        add(new("gap", "SimBots.gap_seeker: aims at the biggest gap of the wall ahead, no look-ahead", Copies.NONE,
            seed => { var rng = new SimRng(seed); return sim => SimBots.gap_seeker(sim, rng); }));
        add(new("planner", "PlannerBot: 4 random rollouts of 120 ticks on a copy of the real sim", Copies.REAL,
            seed => new PlannerBot(seed).decide));
        add(new("search", "SurvivalSearch every 30 ticks, 240 ticks ahead on a copy of the real sim (an oracle)", Copies.REAL,
            seed => new SearchBot().decide));
        add(new("honest", "review's honest planner: beam on 3 scrambled copies, 40 ticks past the next bounce, re-plan every 4 " +
            "(Bubble.next_x and Stalactite.target_y not scrambled yet)", Copies.SCRAMBLED, seed => new HonestBot(seed).decide));
        add_rl();
    }

    /// The RL policy and its calibrated tiers (tools/rlbot, docs/RL_BOT.md).
    static void add_rl()
    {
        string dir = RlMain.default_dir();
        if (!File.Exists(Path.Combine(dir, "policy.json")) || !File.Exists(Path.Combine(dir, "tiers.json"))) return;
        Policy pol = null;
        List<Tiers.Tier> tiers;
        try
        {
            tiers = Tiers.load(dir);
        }
        catch (Exception e)
        {
            Console.Error.WriteLine($"yardstick: RL tiers not loaded: {e.Message}");
            return;
        }
        Policy load()
        {
            lock (_lock) return pol ??= Policy.load(Path.Combine(dir, "policy.json"));
        }
        foreach (var t in tiers)
        {
            var hc = t.hc;
            add(new($"rl:{t.name}", $"RL policy, tier {t.name} ({hc})", Copies.NONE,
                seed => new Player(load(), hc, seed).decide));
        }
    }
}

/// SurvivalSearch as a player: searches `AHEAD` ticks on a copy of the real
/// sim and plays the first `EVERY` taps of the best line, then searches again.
/// It sees the future, so it is the ceiling a planner can reach.
public sealed class SearchBot
{
    public const long EVERY = 30;
    public const long AHEAD = 240;
    byte[] _plan = Array.Empty<byte>();
    int _at;

    public bool decide(GameSim sim)
    {
        if (!sim.state.started) return true;
        if (_at >= _plan.Length || _at >= EVERY)
        {
            var s = new SurvivalSearch();
            _plan = s.run_quick(sim, AHEAD) ? s.best_inputs : Array.Empty<byte>();
            _at = 0;
        }
        return _at < _plan.Length && _plan[_at++] == 1;
    }
}
