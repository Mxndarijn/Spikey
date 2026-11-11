namespace FastSim.Human;

/// What one run looked like, for the "looks human" score: the bird's height
/// each tick, the taps and the bounces (new spikes appear at a bounce).
public sealed class Trace
{
    public long seed;
    public long points;
    public long ticks;
    public bool dead;
    public string room = "";
    public string cause = "";
    public List<long> taps = new();
    public List<long> bounces = new();
    public List<long> rooms = new();
    /// Heights as a share of the playfield, 0 = ceiling kill line, 1 = floor
    /// (flipped in reversed gravity, so 1 is always "where you fall to").
    public List<float> h = new();
    /// Spike deaths: height at the last bounce, at death, and of the nearest gap ahead (px).
    public long bounce_y = -1, death_y = -1, gap_y = -1, since_bounce = -1;

    /// Plays one run with `decide`, recording it. `cap` ticks at most.
    public static Trace play(GameSim sim, Func<GameSim, bool> decide, long cap, bool keep_heights = true)
    {
        var tr = new Trace { seed = sim.seed_value };
        long start = sim.state.score;
        long n = 0;
        double top = SimConfig.KILL_TOP, span = SimConfig.KILL_BOTTOM - SimConfig.KILL_TOP;
        while (n < cap && !sim.is_over())
        {
            long t = sim.state.tick;
            bool tap = decide(sim);
            long sc = sim.state.score, ri = sim.state.room_index;
            sim.step(tap);
            if (tap && sim.state.started) tr.taps.Add(t);
            if (sim.state.score != sc)
            {
                tr.bounces.Add(t);
                tr.bounce_y = sim.state.y / SimConfig.SUB;
            }
            if (sim.state.room_index != ri) tr.rooms.Add(t);
            if (keep_heights && sim.state.started && sim.state.arrival_hold == 0)
            {
                double f = (sim.state.y - top) / span;
                if (sim.room.gravity < 0) f = 1 - f;
                tr.h.Add((float)f);
            }
            n++;
        }
        if (sim.is_over())
        {
            tr.death_y = sim.state.y / SimConfig.SUB;
            long side = sim.state.vx > 0 ? 1 : 0;
            tr.gap_y = PlannerBot.gap_center_y(sim.wall_mask(side)) / SimConfig.SUB;
            tr.since_bounce = tr.bounces.Count > 0 ? sim.state.tick - tr.bounces[^1] : -1;
        }
        tr.points = sim.state.score - start;
        tr.ticks = n;
        tr.dead = sim.is_over();
        tr.room = sim.room.def.id + (sim.room.variant_id() != "" ? "/" + sim.room.variant_id() : "");
        tr.cause = tr.dead ? DeathCause.NAMES[sim.state.death_cause] : "";
        return tr;
    }
}

/// The "looks human" score (0..100) of many runs, from parts that each
/// compare one habit with how people play a one-button flyer. No real
/// Flapjaw replays were on this PC, so the bands are priors from human
/// motor and reaction data (docs/HUMAN_BOT.md); swap in measured bands once
/// real replays are allowed.
public static class Humanness
{
    public sealed record Report(
        double floor, double ceiling, double h_mean, double h_sd,
        double gap_med, double gap_cv, double fast_taps, double repeat,
        double react_fast, double react_med, double score)
    {
        public override string ToString() =>
            $"looks-human {score:F0}/100 | height mean {h_mean:F2} sd {h_sd:F2}, floor {floor:P0}, ceiling {ceiling:P0} | " +
            $"tap gap med {gap_med:F0}t cv {gap_cv:F2}, <6t {fast_taps:P1}, same-gap {repeat:P0} | " +
            $"first tap after bounce <8t {react_fast:P0}, med {react_med:F0}t";
    }

    public static Report of(IList<Trace> runs)
    {
        var hs = new List<float>();
        var gaps = new List<long>();
        var react = new List<long>();
        long same = 0, pairs = 0;
        foreach (var r in runs)
        {
            hs.AddRange(r.h);
            for (int i = 1; i < r.taps.Count; i++)
            {
                long g = r.taps[i] - r.taps[i - 1];
                if (g > 120) continue; // a hold, not a rhythm
                gaps.Add(g);
                if (i > 1)
                {
                    pairs++;
                    if (g == r.taps[i - 1] - r.taps[i - 2]) same++;
                }
            }
            int j = 0;
            foreach (long b in r.bounces)
            {
                while (j < r.taps.Count && r.taps[j] <= b) j++;
                if (j < r.taps.Count && r.taps[j] - b <= 90) react.Add(r.taps[j] - b);
            }
        }
        if (hs.Count == 0) hs.Add(0.5f);
        double floor = hs.Count(x => x > 0.85) / (double)hs.Count;
        double ceil = hs.Count(x => x < 0.12) / (double)hs.Count;
        double mean = hs.Average();
        double sd = Math.Sqrt(hs.Average(x => (x - mean) * (x - mean)));
        double gmed = gaps.Count > 0 ? med(gaps) : 0;
        double gmean = gaps.Count > 0 ? gaps.Average() : 1;
        double gcv = gaps.Count > 1 ? Math.Sqrt(gaps.Average(x => (x - gmean) * (x - gmean))) / gmean : 0;
        double fast = gaps.Count > 0 ? gaps.Count(x => x < 6) / (double)gaps.Count : 0;
        double rep = pairs > 0 ? same / (double)pairs : 0;
        double rfast = react.Count > 0 ? react.Count(x => x < 8) / (double)react.Count : 0;
        double rmed = react.Count > 0 ? med(react) : 0;

        // Each part: 1 inside the human band, falling off linearly outside it.
        double s = 0;
        s += 20 * band(floor, 0, 0.12, 0.35);        // little time hugging the floor
        s += 10 * band(ceil, 0, 0.06, 0.25);         // or the ceiling
        s += 10 * band2(mean, 0.35, 0.65, 0.2);      // mostly mid screen
        s += 10 * band2(sd, 0.10, 0.25, 0.08);       // but not frozen at one height
        s += 10 * band2(gmed, 14, 36, 10);           // a calm tap rhythm (about 2-4 taps a second)
        s += 10 * band2(gcv, 0.25, 0.75, 0.2);       // neither metronome nor random
        s += 10 * band(fast, 0, 0.02, 0.10);         // almost never faster than 10 taps a second
        s += 10 * band(rep, 0, 0.20, 0.50);          // tick-exact repeats are robotic
        s += 10 * band(rfast, 0, 0.08, 0.30);        // no reaction to new spikes under ~130 ms
        return new Report(floor, ceil, mean, sd, gmed, gcv, fast, rep, rfast, rmed, s);
    }

    /// 1 when x <= ok, 0 when x >= bad (x >= lo assumed).
    static double band(double x, double lo, double ok, double bad) =>
        x <= ok ? 1 : x >= bad ? 0 : (bad - x) / (bad - ok);

    /// 1 inside [lo, hi], falling to 0 at `fall` outside.
    static double band2(double x, double lo, double hi, double fall) =>
        x < lo ? Math.Max(0, 1 - (lo - x) / fall) : x > hi ? Math.Max(0, 1 - (x - hi) / fall) : 1;

    public static double med(IEnumerable<long> xs)
    {
        var a = xs.OrderBy(x => x).ToArray();
        if (a.Length == 0) return 0;
        return a.Length % 2 == 1 ? a[a.Length / 2] : (a[a.Length / 2 - 1] + a[a.Length / 2]) / 2.0;
    }

    public static double pct(IEnumerable<long> xs, double p)
    {
        var a = xs.OrderBy(x => x).ToArray();
        if (a.Length == 0) return 0;
        return a[(int)Math.Clamp(Math.Round(p * (a.Length - 1)), 0, a.Length - 1)];
    }
}
