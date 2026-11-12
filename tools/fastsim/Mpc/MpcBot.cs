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
    readonly Random _dice;
    int _since = 1000;
    // Motor noise: ticks until the tap being carried out lands, or -1.
    int _pending = -1;
    public long ticks, taps, doomed_ticks;

    public MpcBot(MpcParams p, Motor m = null, long seed = 1)
    {
        motor = m ?? new Motor();
        p.min_gap = Math.Max(p.min_gap, motor.min_gap);
        planner = new Planner(p) { react = motor.react, sigma = (float)motor.sigma };
        _dice = new Random(unchecked((int)(seed * 2654435761L) ^ 0x2545f491));
    }

    double gauss()
    {
        double u = 1.0 - _dice.NextDouble(), v = _dice.NextDouble();
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
        if (motor.sigma > 0) tap = hand(tap);
        if (tap && _since < motor.min_gap) tap = false;
        _since = tap ? 1 : Math.Min(_since + 1, 1000);
        if (tap) taps++;
        return tap;
    }

    /// Timing error: the hand commits to the planned tap a few ticks before
    /// it is due and lands it a Gaussian number of ticks early or late. A tap
    /// the plan wants at once (nothing was planned) can only come late.
    bool hand(bool tap_now)
    {
        if (_pending >= 0)
        {
            if (_pending > 0)
            {
                _pending--;
                return false;
            }
            _pending = -1;
            return true;
        }
        int lead = (int)Math.Ceiling(2.5 * motor.sigma);
        int first = planner.first_tap;
        if (first < 0 || first > lead) return false;
        int land = (int)Math.Round(first + gauss() * motor.sigma);
        if (land <= 0) return true;
        _pending = land - 1;
        return false;
    }
}
