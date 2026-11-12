using System.Reflection;

namespace FastSim.Human;

/// A human motor model (Isaksen et al. 2015, measured on one-button flyers)
/// on top of a planner that only predicts visible motion (BlindPlanner,
/// scrambled copies). docs/HUMAN_BOT.md.
public sealed record Motor(
    double sigma,      // sd of each tap's timing error, ticks (early and late). The main skill knob.
    double react_mu,   // reaction to newly appearing things, ex-Gaussian: normal part mean (ticks)
    double react_sd,   //   ... and its sd
    double react_tau,  //   ... plus an exponential tail with this mean
    long min_gap,      // ticks between two presses at least (7.7 taps per second -> 8)
    long cancel,       // a planned tap can still be held back until this many ticks before it lands
    bool fine = false, // a finer search (4 px x 12 speed buckets, ~3.6x slower): more careful thinking
    Persona p = null,  // the human habits on top (preferred height, hesitation, thumb gap jitter); null = none
    int level = -1)    // search fineness (MotorTiers.LEVELS; -1 = by `fine`)
{
    /// Isaksen: reaction about 288 ms (17 ticks) to new things, at most 7.7 taps/s.
    public static Motor at(double sigma) => new(sigma, 13, 2, 4, 8, 5);

    public override string ToString() => $"tap sd {sigma:F2} t, react {react_mu + react_tau:F0} t, gap {min_gap} t";
}

/// The human habits on top of the thumb (the user's ruling, 2026-11-12: human
/// behaviour, not human timing; no lapses and no mistakes on purpose). All off by default.
public sealed record Persona(
    double pref_sd = 0,     // preferred height: offset (px) of the height the player drifts to, drawn per run
    double hes_p = 0,       // chance a press hesitates: lands an extra exponential delay late
    double hes_tau = 0,     //   ... with this mean (ticks)
    double gap_sd = 0)      // the thumb's fastest repeat varies: each next press needs min_gap + |N(0, this)| ticks
{
    public static readonly Persona NONE = new();
}

/// Plays like a person: the planner decides where taps should go; the thumb
/// lands each one N(0, sigma) ticks off (committed a little ahead, so early
/// taps happen too), never two presses closer than `min_gap`, and anything
/// that newly appears (the spikes put up at a bounce, a new hazard) is hidden
/// from the planner until a reaction time has passed. A new warning on screen
/// (Hazard.warnings: a glow, a marked column, a dashed line) that the plan in
/// hand does not survive also takes a reaction time: until then the old plan
/// is played on, with no new look.
public sealed class MotorPlayer
{
    public readonly BlindPlanner planner;
    readonly Motor _m;
    readonly Random _rng;
    readonly List<(long want, long fire)> _taps = new(); // committed presses: intended tick, landing tick
    readonly List<long> _done = new(); // intended ticks of presses already made (the plan may still show them)
    readonly HashSet<Hazard> _known = new(ReferenceEqualityComparer.Instance);
    readonly Dictionary<Hazard, long> _hidden = new(ReferenceEqualityComparer.Instance);
    long _spikes_hidden_until = -1, _score = -1, _room = -1, _last_fire = -100;
    long _window;
    long _boss_key = 0, _boss_hidden_until = -1;
    /// Boss tells get the same reaction time as new hazards (07-bosses.md); off = the planner sees them at once.
    public static bool REACT_BOSS = true;
    public long masked_ticks, presses, cancels, delayed;
    // Persona state.
    readonly Persona _p;
    long _gap_need = -1;
    public long hesitations;
    /// Every press made: (intended tick, landing tick) - the realised motor error.
    public readonly List<(long want, long fire)> made = new();
    /// Experiments: which new things get a reaction time (spikes, hazards, warnings).
    public static bool MASK_SPIKES = true, MASK_HAZARDS = true, MASK_TELLS = true;
    /// The warnings on screen last tick (hazard index, box) and the tick a new one has been taken in.
    HashSet<(int, long, long, long, long)> _warned = new(), _warned_now = new();
    readonly List<long> _warn_buf = new();
    long _tell_until = -1;
    public long tell_reactions, tell_ticks;

    public MotorPlayer(Motor m, long seed, BlindPlanner planner = null)
    {
        _m = m;
        _rng = new Random(unchecked((int)(seed * 2246822519L) ^ 0x3c6ef372));
        this.planner = planner ?? make_planner(seed, m);
        _p = m.p ?? Persona.NONE;
        _window = Math.Max(1, (long)Math.Ceiling(2.5 * m.sigma));
        if (_p.pref_sd > 0) this.planner.mid_offset = (long)Math.Round(gauss() * _p.pref_sd);
    }

    /// The planner a person with tap sd `sigma` plays with: it keeps its line
    /// clear of spikes, ceiling and floor too (a narrow gap costs more than a
    /// detour), and tries its lines with taps `wobble` ticks early and late.
    public static BlindPlanner make_planner(long seed, Motor m)
    {
        var bp = new BlindPlanner(seed);
        if (m.sigma > 0)
        {
            bp.lines = 8;
            bp.wobble = Math.Max(1, (int)Math.Round(m.sigma));
        }
        if (m.fine)
        {
            bp.bucket_px = 4;
            bp.speed_buckets = 12;
        }
        if (m.level >= 0)
        {
            var (px, speeds, tap_free) = MotorTiers.LEVELS[m.level];
            bp.bucket_px = px;
            bp.speed_buckets = speeds;
            bp.tap_free = tap_free;
        }
        bp.follow = FOLLOW;
        return bp;
    }

    /// Plan reuse for every tier's planner (BlindPlanner.follow; 0 = a new look every 4 ticks).
    /// Seeds 1..600, cap 20,000 on the bare planner: no more deaths, a seventh of the search.
    public static int FOLLOW = 48;

    double gauss()
    {
        double u = 1.0 - _rng.NextDouble(), v = _rng.NextDouble();
        return Math.Sqrt(-2 * Math.Log(u)) * Math.Cos(2 * Math.PI * v);
    }

    long reaction()
    {
        double r = _m.react_mu + _m.react_sd * gauss() - _m.react_tau * Math.Log(1.0 - _rng.NextDouble());
        return Math.Max(1, (long)Math.Round(r));
    }

    /// Debug: a line per tick (set by `human motortrace`).
    public Action<string> log;

    public bool decide(GameSim sim)
    {
        bool r = decide_inner(sim);
        if (log != null && sim.state.started)
        {
            var plan = planner.plan;
            string ps = plan == null ? "" : string.Concat(plan.Take(30).Select(b => b ? '|' : '.'));
            log($"t {sim.state.tick} y {sim.state.y / SimConfig.SUB} vy {sim.state.vy} look {planner.last_look} " +
                $"press {(r ? 1 : 0)} committed [{string.Join(" ", _taps.Select(x => $"{x.want}->{x.fire}"))}] plan {ps}");
        }
        return r;
    }

    bool decide_inner(GameSim sim)
    {
        var s = sim.state;
        if (!s.started)
        {
            _score = s.score;
            _room = s.room_index;
            foreach (var h in sim.room.hazards) _known.Add(h);
            return true;
        }
        long t = s.tick;
        notice(sim, t);
        var view = sim;
        if (t < _spikes_hidden_until || _hidden.Count > 0)
        {
            view = masked(sim, t);
            masked_ticks++;
        }
        planner.boss_unseen = t < _boss_hidden_until;
        // Reacting to a tell: the old plan is played on while it lasts (never an empty thumb).
        bool reacting = t < _tell_until && planner.plan.Count > 0;
        if (reacting) tell_ticks++;
        planner.frozen = reacting;
        planner.min_gap = _m.min_gap > 1 ? _m.min_gap : 0;
        planner.last_press = _last_fire;
        bool now = planner.decide(view);
        // Where the planner wants taps from now to `_window` ticks on.
        var want = new List<long>();
        if (now) want.Add(t);
        if (_window > 0 && planner.plan is IReadOnlyCollection<bool> plan)
        {
            long u = t + 1;
            foreach (bool b in plan)
            {
                if (u > t + _window) break;
                if (b) want.Add(u);
                u++;
            }
        }
        // Hold back presses the plan dropped, while there is still time.
        for (int i = _taps.Count - 1; i >= 0; i--)
        {
            var (w, f) = _taps[i];
            if (w <= t + _window && f - t > _m.cancel && !want.Any(x => Math.Abs(x - w) <= 4))
            {
                _taps.RemoveAt(i);
                cancels++;
            }
        }
        // Commit new presses (each one lands with its own timing error).
        foreach (long w in want)
        {
            if (_taps.Any(x => Math.Abs(x.want - w) <= 4) || _done.Any(d => Math.Abs(d - w) <= 4)) continue;
            double e = gauss() * _m.sigma;
            if (_p.hes_p > 0 && _rng.NextDouble() < _p.hes_p)
            {
                e -= _p.hes_tau * Math.Log(1.0 - _rng.NextDouble());
                hesitations++;
            }
            long f = w + (long)Math.Round(e);
            _taps.Add((w, Math.Max(f, t)));
        }
        // Press now?
        int due = -1;
        for (int i = 0; i < _taps.Count; i++)
            if (_taps[i].fire <= t && (due < 0 || _taps[i].fire < _taps[due].fire)) due = i;
        if (due < 0) return false;
        if (t - _last_fire < Math.Max(_m.min_gap, _gap_need))
        {
            delayed++;
            return false; // the thumb is still on its way back: the press lands a little later
        }
        made.Add(_taps[due]);
        _done.Add(_taps[due].want);
        _done.RemoveAll(d => d < t - 16);
        _taps.RemoveAt(due);
        _last_fire = t;
        if (_p.gap_sd > 0) _gap_need = _m.min_gap + (long)Math.Round(Math.Abs(gauss()) * _p.gap_sd);
        presses++;
        return true;
    }

    /// Starts a reaction time for everything that appeared since the last tick.
    void notice(GameSim sim, long t)
    {
        var s = sim.state;
        bool new_room = s.room_index != _room;
        if (new_room)
        {
            // A new room: it shows during the arrival hold, so it is seen by the time the bird moves.
            _room = s.room_index;
            _tell_until = -1;
            _known.Clear();
            _hidden.Clear();
            foreach (var h in sim.room.hazards) _known.Add(h);
            _spikes_hidden_until = -1;
        }
        else if (s.score != _score)
            _spikes_hidden_until = MASK_SPIKES && _m.react_mu >= 0 ? t + reaction() : -1; // new spikes on the wall ahead
        _score = s.score;
        foreach (var h in sim.room.hazards)
            if (h is Boss b)
            {
                long key = BossBlind.tell_key(b);
                if (key != _boss_key && REACT_BOSS && _m.react_mu >= 0) _boss_hidden_until = t + reaction();
                _boss_key = key;
            }
        foreach (var h in sim.room.hazards)
            if (h.alive && _known.Add(h) && MASK_HAZARDS && _m.react_mu >= 0) _hidden[h] = t + reaction();
        foreach (var h in _hidden.Where(kv => kv.Value <= t).Select(kv => kv.Key).ToList()) _hidden.Remove(h);
        // New warnings (tells). One that the plan in hand lives through needs no
        // change of plan; one that kills it is acted on a reaction time later.
        _warned_now.Clear();
        bool fresh = false;
        for (int i = 0; i < sim.room.hazards.Count; i++)
        {
            var h = sim.room.hazards[i];
            if (!h.alive) continue;
            _warn_buf.Clear();
            h.warnings(sim, _warn_buf);
            for (int k = 0; k + Hazard.WARN_SIZE <= _warn_buf.Count; k += Hazard.WARN_SIZE)
            {
                var key = (i, _warn_buf[k], _warn_buf[k + 1], _warn_buf[k + 2], _warn_buf[k + 3]);
                _warned_now.Add(key);
                if (!_warned.Contains(key)) fresh = true;
            }
        }
        (_warned, _warned_now) = (_warned_now, _warned);
        // Only a plan that was whole before the warning showed: a planner already
        // in trouble (no full line at its last look) keeps looking every tick.
        if (fresh && !new_room && MASK_TELLS && _m.react_mu >= 0 && t >= _tell_until && planner.last_look == 0
            && planner.plan.Count > 0 && !planner.plan_lives(sim))
        {
            _tell_until = t + reaction();
            tell_reactions++;
        }
    }

    /// The sim as the player has taken it in: new spikes not yet seen are not
    /// there, nor are hazards that appeared less than a reaction time ago.
    GameSim masked(GameSim sim, long t)
    {
        var c = sim.clone_deep();
        if (t < _spikes_hidden_until)
        {
            if (c.state.vx > 0) c.state.right_spikes = 0;
            else c.state.left_spikes = 0;
        }
        if (_hidden.Count > 0)
            for (int i = c.room.hazards.Count - 1; i >= 0; i--)
                if (_hidden.ContainsKey(sim.room.hazards[i])) c.room.hazards[i].alive = false; // kept in the list: other hazards may link to it
        return c;
    }
}

/// The tiers: tap timing sd (the main knob) and the reaction to new things
/// per tier, fitted on the rate median (docs/HUMAN_BOT.md). Expert reacts faster
/// than the measured human ~17 ticks (about 6), beast not at all; both think with
/// the finer search. Beast has no human limit but the 8-tick thumb gap (which costs
/// nothing once the planner plans with it).
public static class MotorTiers
{
    public static readonly Dictionary<string, (double sigma, double react, bool fine)> TIER = new()
    {
        ["beginner"] = (1.4, 13, false), ["normal"] = (0.6, 13, false), ["good"] = (0.0, 8, false),
        ["expert"] = (0.2, 2, true), ["beast"] = (0.0, -100, true),
    };
    /// The tiers on the shared human rules (MotorTiers.shared) at the calibration's start
    /// points (tools/calibrate_tiers.ps1): `human tells --human 1` plays these. Not fitted.
    public static Dictionary<string, Motor> HUMAN => new()
    {
        ["beginner"] = shared(24, 1), ["normal"] = shared(20, 2), ["good"] = shared(15, 3), ["expert"] = shared(12, 5),
    };
    public static readonly Dictionary<string, double> SIGMA = TIER.ToDictionary(kv => kv.Key, kv => kv.Value.sigma);

    /// The tiers when the planner knows the planned exit mouths (BlindPlanner.know_exits):
    /// hazards bounce off them from room start, so a hidden-exit copy mispredicts them.
    /// Seeds 1..100, full cap: rate medians 33 / 59 / 119 / 257 / 724.
    public static readonly Dictionary<string, (double sigma, double react, bool fine)> TIER_KNOWN_EXITS = new()
    {
        ["beginner"] = (1.4, 13, false), ["normal"] = (0.6, 13, false), ["good"] = (0.3, 13, false),
        ["expert"] = (0.0, 8, false), ["beast"] = (0.0, -100, true),
    };

    public static Motor of(string tier)
    {
        if (!BlindPlanner.know_exits && CALIBRATED.TryGetValue(tier, out var c)) return shared(c.react, c.level);
        var (sg, re, fine) = (BlindPlanner.know_exits ? TIER_KNOWN_EXITS : TIER)[tier];
        return Motor.at(sg) with { react_mu = re, react_tau = re < 0 ? 0 : 4, fine = fine };
    }

    // ---------------------------------------------------- calibrated tiers

    /// The human rules every calibrated tier shares (the user's ruling, 2026-11-12): only what
    /// is on screen, the 8-tick thumb gap with jitter (no metronome), a little hesitation, the
    /// cage middle when nothing forces otherwise, a loosely varying preferred height, and the
    /// same small tap scatter. No lapses, no mistakes on purpose. A tier differs from the next
    /// only by its two knobs: the reaction to new things and the search fineness.
    public const double SHARED_SIGMA = 0.4;
    public static readonly Persona SHARED = new(hes_p: 0.03, hes_tau: 4, pref_sd: 20, gap_sd: 1.5);

    /// Search fineness, coarse to fine: (bucket px, speed buckets, free tap timing). Level 2
    /// is BlindPlanner's default; level 5 is the strongest measured search (4 px x 12 with
    /// tap_free: about half the deaths of level 2 on short screens, 1.4x its CPU).
    public static readonly (long px, long speeds, bool tap_free)[] LEVELS =
    {
        (16, 3, false), (12, 4, false), (8, 6, false), (6, 8, false), (4, 12, false), (4, 12, true),
    };
    public const int DEFAULT_LEVEL = 2;

    public static string level_text(int l) => $"{LEVELS[l].px} px x {LEVELS[l].speeds}{(LEVELS[l].tap_free ? ", free taps" : "")}";

    /// A tier at these knobs: `react` the mean reaction to new things (ticks, ex-Gaussian with
    /// sd 2 and a tail of 4), `level` the search fineness (LEVELS).
    public static Motor shared(double react, int level)
    {
        if (level < 0 || level >= LEVELS.Length) throw new ArgumentException($"search level {level}: 0..{LEVELS.Length - 1}");
        return new Motor(SHARED_SIGMA, Math.Max(0, react - 4), 2, 4, 8, 5, false, SHARED, level);
    }

    /// The fitted knobs per tier (tools/fastsim/Human/tiers.json, written by
    /// tools/calibrate_tiers.ps1). Empty when there is no file: the old TIER table plays.
    public static readonly Dictionary<string, (double react, int level)> CALIBRATED = load_calibrated();

    public static string calibrated_file
    {
        get
        {
            for (var d = new DirectoryInfo(AppContext.BaseDirectory); d != null; d = d.Parent)
            {
                string p = Path.Combine(d.FullName, "Human", "tiers.json");
                if (File.Exists(p)) return p;
                if (File.Exists(Path.Combine(d.FullName, "FastSim.csproj"))) return p;
            }
            return Path.Combine(AppContext.BaseDirectory, "tiers.json");
        }
    }

    static Dictionary<string, (double, int)> load_calibrated()
    {
        var res = new Dictionary<string, (double, int)>();
        string f = calibrated_file;
        if (!File.Exists(f)) return res;
        var j = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(f))!["tiers"]!.AsObject();
        foreach (var (tier, v) in j) res[tier] = ((double)v!["react"]!, (int)v["level"]!);
        return res;
    }

    [System.Runtime.CompilerServices.ModuleInitializer]
    internal static void Register()
    {
        foreach (var name in TIER.Keys.ToList())
        {
            string tier = name;
            var m = of(tier);
            FastSim.Yard.Bots.add(new($"human:{tier}",
                $"MotorPlayer: BlindPlanner (class defaults{(m.fine ? ", 4 px x 12 speed buckets" : "")}; 8 lines tried with tap shifts when sd > 0) + motor model: " +
                $"tap sd {m.sigma} ticks, reaction {(m.react_mu < 0 ? "none" : $"~{m.react_mu + m.react_tau:F0} ticks")} to new spikes/hazards, " +
                "8 ticks between presses",
                FastSim.Yard.Copies.SCRAMBLED, seed => new MotorPlayer(of(tier), seed).decide));
            // The same tier on the known-exits table, with the planner told the planned exit
            // mouths (only honest if the game shows them from room start). Process-wide switch:
            // run these bots in their own yardstick call.
            FastSim.Yard.Bots.add(new($"human-ke:{tier}",
                $"human:{tier} on the known-exits table, BlindPlanner.know_exits = true",
                FastSim.Yard.Copies.SCRAMBLED, seed => { BlindPlanner.know_exits = true; return new MotorPlayer(of(tier), seed).decide; }));
        }
    }
}
