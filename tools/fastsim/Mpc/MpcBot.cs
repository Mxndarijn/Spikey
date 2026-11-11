namespace FastSim.Mpc;

/// Human hands on top of the plan (Isaksen et al. 2015, docs/MPC_BOT.md):
/// each tap lands a Gaussian number of ticks early or late, the bot plans on
/// a world seen `react` ticks ago when something new shows up, and taps are
/// at least `min_gap` ticks apart.
public sealed class Motor
{
    /// Tap timing error, standard deviation in ticks.
    public double sigma = 0;
    /// Ticks before a new wall layout, room or hazard is acted on.
    public int react = 0;
    /// Fewest ticks between taps (8 = 7.5 taps a second).
    public int min_gap = 1;
}

/// The MPC bot: looks, plans, taps. `decide` reads the present sim and
/// leaves it as it was; it never copies or steps it.
public sealed class MpcBot
{
    public readonly Planner planner;
    public readonly Motor motor;
    readonly Random _rng;
    int _since = 1000;
    // Motor noise: the tap being carried out (ticks until it lands), or -1.
    int _pending = -1;
    int _hold = 0;
    long _seen_room = -1, _seen_mask = -1, _seen_side = -1;
    int _seen_hazards = -1;
    int _blind = 0;
    public long ticks, taps, doomed_ticks;

    public MpcBot(MpcParams p, Motor m = null, long seed = 1)
    {
        motor = m ?? new Motor();
        p.min_gap = Math.Max(p.min_gap, motor.min_gap);
        planner = new Planner(p);
        _rng = new Random(unchecked((int)(seed * 2654435761L) ^ 0x2545f491));
    }

    double gauss()
    {
        double u = 1.0 - _rng.NextDouble(), v = _rng.NextDouble();
        return Math.Sqrt(-2.0 * Math.Log(u)) * Math.Cos(2.0 * Math.PI * v);
    }

    /// The tap for this tick.
    public bool decide(GameSim sim)
    {
        ticks++;
        var s = sim.state;
        if (!s.started)
        {
            _since = 0;
            return true;
        }
        if (s.arrival_hold > 0)
        {
            // The game stands still: look, don't act.
            planner.sight.look(sim);
            return false;
        }
        bool tap = planner.plan(sim, _since);
        if (planner.doomed) doomed_ticks++;
        if (motor.sigma > 0 || motor.react > 0) tap = hands(sim, tap);
        if (tap && _since < motor.min_gap) tap = false;
        _since = tap ? 1 : Math.Min(_since + 1, 1000);
        if (tap) taps++;
        return tap;
    }

    /// Reaction time and timing error. The plan gives the ideal tick of the
    /// next tap; the hand commits to it a few ticks ahead and lands it with a
    /// Gaussian error. While something new is being taken in, no new tap starts.
    bool hands(GameSim sim, bool tap_now)
    {
        var s = sim.state;
        long side = s.vx > 0 ? 1 : 0;
        long mask = sim.wall_mask(side);
        int hazards = planner.sight.tracks.Count;
        bool fresh = s.room_index != _seen_room || side != _seen_side || mask != _seen_mask || hazards > _seen_hazards;
        if (fresh && (_seen_room != s.room_index || side != _seen_side || hazards > _seen_hazards)) _blind = motor.react;
        _seen_room = s.room_index;
        _seen_side = side;
        _seen_mask = mask;
        _seen_hazards = hazards;
        if (_pending >= 0)
        {
            if (_pending == 0)
            {
                _pending = -1;
                return true;
            }
            _pending--;
            return false;
        }
        if (_blind > 0)
        {
            _blind--;
            return false;
        }
        // Commit to the planned tap when it is `LEAD` ticks away (or due now).
        const int LEAD = 6;
        int first = planner.first_tap;
        if (first < 0 || first > LEAD) return false;
        int land = (int)Math.Round(first + gauss() * motor.sigma);
        if (land <= 0) return true;
        _pending = land - 1;
        return false;
    }
}
