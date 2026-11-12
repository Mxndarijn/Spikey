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
    bool fine = false) // a finer search (4 px x 12 speed buckets, ~3.6x slower): more careful thinking
{
    /// Isaksen: reaction about 288 ms (17 ticks) to new things, at most 7.7 taps/s.
    public static Motor at(double sigma) => new(sigma, 13, 2, 4, 8, 5);

    public override string ToString() => $"tap sd {sigma:F2} t, react {react_mu + react_tau:F0} t, gap {min_gap} t";
}

/// Plays like a person: the planner decides where taps should go; the thumb
/// lands each one N(0, sigma) ticks off (committed a little ahead, so early
/// taps happen too), never two presses closer than `min_gap`, and anything
/// that newly appears (the spikes put up at a bounce, a new hazard) is hidden
/// from the planner until a reaction time has passed.
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
    /// Experiments: which new things get a reaction time (spikes, hazards).
    public static bool MASK_SPIKES = true, MASK_HAZARDS = true;

    public MotorPlayer(Motor m, long seed, BlindPlanner planner = null)
    {
        _m = m;
        _rng = new Random(unchecked((int)(seed * 2246822519L) ^ 0x3c6ef372));
        this.planner = planner ?? make_planner(seed, m);
        _window = Math.Max(1, (long)Math.Ceiling(2.5 * m.sigma));
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
        return bp;
    }

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
            long f = w + (long)Math.Round(gauss() * _m.sigma);
            _taps.Add((w, Math.Max(f, t)));
        }
        // Press now?
        int due = -1;
        for (int i = 0; i < _taps.Count; i++)
            if (_taps[i].fire <= t && (due < 0 || _taps[i].fire < _taps[due].fire)) due = i;
        if (due < 0) return false;
        if (t - _last_fire < _m.min_gap)
        {
            delayed++;
            return false; // the thumb is still on its way back: the press lands a little later
        }
        _done.Add(_taps[due].want);
        _done.RemoveAll(d => d < t - 16);
        _taps.RemoveAt(due);
        _last_fire = t;
        presses++;
        return true;
    }

    /// Starts a reaction time for everything that appeared since the last tick.
    void notice(GameSim sim, long t)
    {
        var s = sim.state;
        if (s.room_index != _room)
        {
            // A new room: it shows during the arrival hold, so it is seen by the time the bird moves.
            _room = s.room_index;
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
        var (sg, re, fine) = (BlindPlanner.know_exits ? TIER_KNOWN_EXITS : TIER)[tier];
        return Motor.at(sg) with { react_mu = re, react_tau = re < 0 ? 0 : 4, fine = fine };
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
