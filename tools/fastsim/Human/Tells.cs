namespace FastSim.Human;

/// `fastsim human tells --tier t [--persona k=v,...] [--sigma s] [--react r]`:
/// the things a viewer would notice that a person never does (06-humanlike.md):
/// realised tap error, rhythm, where in the gap the bird crosses the wall,
/// panic bursts, how two attempts at the same seed differ, and how runs end.
public static class Tells
{
    sealed class Run
    {
        public long seed, points, ticks;
        public bool dead;
        public string cause = "", room = "";
        public long since_bounce = -1;
        public List<long> taps = new();
        public List<double> offs = new();     // crossing height in the gap: -1 top edge .. +1 bottom edge
        public List<double> errs = new();     // landing - intended, ticks
        public long clean_death;              // 1: the planner had a full line for the last 45 ticks
        public long lapses, lapse_ticks, panics, hes;
        public double h_sum, h_sq;
        public long h_n;
    }

    public static Persona parse(string s)
    {
        var p = new Persona();
        foreach (var kv in s.Split(',', StringSplitOptions.RemoveEmptyEntries))
        {
            var a = kv.Split('=');
            double v = double.Parse(a[1], System.Globalization.CultureInfo.InvariantCulture);
            p = a[0] switch
            {
                "perr" => p with { perr = v }, "lapse_min" => p with { lapse_min = v }, "lapse_len" => p with { lapse_len = v },
                "panic" => p with { panic = v }, "fatigue" => p with { fatigue = v }, "pref_sd" => p with { pref_sd = v },
                "hes_p" => p with { hes_p = v }, "hes_tau" => p with { hes_tau = v }, "margin" => p with { margin = (long)v },
                "sigma_run" => p with { sigma_run = v }, "mc" => p with { mc = (int)v }, "gap_sd" => p with { gap_sd = v },
                _ => throw new ArgumentException($"unknown persona field '{a[0]}'"),
            };
        }
        return p;
    }

    /// The Kaplan-Meier median score (runs alive at the cap are censored there) and a
    /// 95% interval from 400 resamples of the runs. Infinity = more than half live past the cap.
    public static (double med, double lo, double hi) km_median(List<(long points, bool dead)> runs)
    {
        static double km(List<(long points, bool dead)> rs)
        {
            double surv = 1;
            int at_risk = rs.Count;
            foreach (var g in rs.GroupBy(r => r.points).OrderBy(g => g.Key))
            {
                int died = g.Count(r => r.dead);
                if (at_risk > 0) surv *= 1.0 - (double)died / at_risk;
                if (surv <= 0.5) return g.Key;
                at_risk -= g.Count();
            }
            return double.PositiveInfinity;
        }
        var rng = new Random(12345);
        var meds = new List<double>();
        for (int b = 0; b < 400; b++)
        {
            var pick = new List<(long, bool)>(runs.Count);
            for (int i = 0; i < runs.Count; i++) pick.Add(runs[rng.Next(runs.Count)]);
            meds.Add(km(pick));
        }
        meds.Sort();
        return (km(runs), meds[(int)(0.025 * meds.Count)], meds[(int)(0.975 * meds.Count) - 1]);
    }

    public static Motor motor(Func<string, string, string> opt)
    {
        string tier = opt("tier", "good");
        var m = MotorTiers.of(tier);
        if (opt("sigma", "") != "") m = m with { sigma = double.Parse(opt("sigma", "0")) };
        if (opt("react", "") != "") m = m with { react_mu = double.Parse(opt("react", "13")) };
        if (opt("fine", "") != "") m = m with { fine = opt("fine", "0") == "1" };
        string ps = opt("persona", "");
        if (opt("human", "0") == "1" && MotorTiers.HUMAN.TryGetValue(tier, out var hm)) m = hm;
        if (ps != "") m = m with { p = parse(ps) };
        return m;
    }

    static Run play(long seed, long bot_seed, Motor m, long cap)
    {
        var mp = new MotorPlayer(m, bot_seed, MotorPlayer.make_planner(bot_seed, m));
        var sim = new GameSim(seed);
        var r = new Run { seed = seed };
        long start = sim.state.score, n = 0, last_bounce = -1, last_bad = -1000;
        double top = SimConfig.KILL_TOP, span = SimConfig.KILL_BOTTOM - SimConfig.KILL_TOP;
        while (n < cap && !sim.is_over())
        {
            long t = sim.state.tick;
            bool tap = mp.decide(sim);
            if (sim.state.started && mp.planner.last_look >= 2) last_bad = t;
            long sc = sim.state.score, vx = sim.state.vx, y = sim.state.y;
            long mask = sim.wall_mask(vx > 0 ? 1 : 0);
            sim.step(tap);
            if (tap && sim.state.started) r.taps.Add(t);
            if (sim.state.score != sc && !sim.is_over())
            {
                last_bounce = t;
                double o = gap_offset(mask, y);
                if (!double.IsNaN(o)) r.offs.Add(o);
            }
            if (sim.state.started && sim.state.arrival_hold == 0)
            {
                double f = (sim.state.y - top) / span;
                r.h_sum += f;
                r.h_sq += f * f;
                r.h_n++;
            }
            n++;
        }
        r.points = sim.state.score - start;
        r.ticks = n;
        r.dead = sim.is_over();
        if (r.dead)
        {
            r.cause = DeathCause.NAMES[sim.state.death_cause];
            r.room = sim.room.def.id + (sim.room.variant_id() != "" ? "/" + sim.room.variant_id() : "");
            r.since_bounce = last_bounce < 0 ? -1 : sim.state.tick - last_bounce;
            r.clean_death = sim.state.tick - last_bad > 45 ? 1 : 0;
        }
        foreach (var (w, f) in mp.made) r.errs.Add(f - w);
        r.lapses = mp.lapses;
        r.lapse_ticks = mp.lapse_ticks;
        r.panics = mp.panics;
        r.hes = mp.hesitations;
        return r;
    }

    /// Where y sits in the free run of slots that holds it: -1 top edge, 0 middle, +1 bottom edge.
    static double gap_offset(long mask, long y)
    {
        long slot = (y - SimConfig.SLOT_TOP) / SimConfig.SLOT_SIZE;
        if (slot < 0 || slot >= SimConfig.SLOT_COUNT || RoomRules.has_slot(mask, slot)) return double.NaN;
        long a = slot, b = slot;
        while (a > 0 && !RoomRules.has_slot(mask, a - 1)) a--;
        while (b < SimConfig.SLOT_COUNT - 1 && !RoomRules.has_slot(mask, b + 1)) b++;
        if (a == 0 && b == SimConfig.SLOT_COUNT - 1) return double.NaN; // no spikes on that wall
        double top = SimConfig.SLOT_TOP + a * SimConfig.SLOT_SIZE, bot = SimConfig.SLOT_TOP + (b + 1) * SimConfig.SLOT_SIZE;
        return (y - (top + bot) / 2) / ((bot - top) / 2);
    }

    static double sd(IList<double> x)
    {
        if (x.Count < 2) return 0;
        double m = x.Average();
        return Math.Sqrt(x.Sum(v => (v - m) * (v - m)) / (x.Count - 1));
    }

    public static int run(Func<string, string, string> opt, int threads)
    {
        var m = motor(opt);
        int seeds = int.Parse(opt("seeds", "100"));
        long first = long.Parse(opt("first", "0"));
        long cap = long.Parse(opt("cap", SimConfig.MAX_TICKS.ToString()));
        bool repeat = opt("repeat", "1") == "1";
        var runs = new Run[seeds];
        var twin = new Run[seeds];
        var sw = System.Diagnostics.Stopwatch.StartNew();
        Parallel.For(0, seeds, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            long seed = first + 1 + i;
            runs[i] = play(seed, seed, m, cap);
            if (repeat && i < 40) twin[i] = play(seed, seed + 7919, m, Math.Min(cap, 3600));
        });
        var pts = runs.Select(r => r.points).ToArray();
        double d = runs.Count(r => r.dead) / (double)Math.Max(1, pts.Sum());
        double rate = d <= 0 ? double.PositiveInfinity : Math.Log(0.5) / Math.Log(1 - d);
        var errs = runs.SelectMany(r => r.errs).ToList();
        var offs = runs.SelectMany(r => r.offs).ToList();
        var gaps = new List<double>();
        long bursts = 0, minutes_ticks = runs.Sum(r => r.ticks);
        var max_rate = new List<double>();
        foreach (var r in runs)
        {
            int run3 = 0, best = 0;
            for (int i = 1; i < r.taps.Count; i++)
            {
                long g = r.taps[i] - r.taps[i - 1];
                if (g <= 120) gaps.Add(g);
                if (g <= 11) { run3++; if (run3 == 2) bursts++; } else run3 = 0;
            }
            // Most taps in any 1 s window.
            int j = 0;
            for (int i = 0; i < r.taps.Count; i++)
            {
                while (r.taps[i] - r.taps[j] >= 60) j++;
                best = Math.Max(best, i - j + 1);
            }
            max_rate.Add(best);
        }
        double gm = gaps.Count > 0 ? gaps.Average() : 0;
        // Same seed, another bot seed: ticks until the first different press, and share of same presses.
        var div = new List<double>();
        var same = new List<double>();
        for (int i = 0; i < seeds; i++)
        {
            if (twin[i] == null) continue;
            var a = runs[i].taps.Where(x => x < 3600).ToList();
            var b = twin[i].taps;
            int k = 0;
            while (k < a.Count && k < b.Count && a[k] == b[k]) k++;
            div.Add(k < a.Count && k < b.Count ? Math.Min(a[k], b[k]) : Math.Min(a.Count > 0 ? a[^1] : 0, b.Count > 0 ? b[^1] : 0));
            var sb = new HashSet<long>(b);
            same.Add(a.Count == 0 ? 0 : a.Count(x => sb.Contains(x)) / (double)a.Count);
        }
        var dead = runs.Where(r => r.dead).ToList();
        var causes = dead.GroupBy(r => r.cause).OrderByDescending(g => g.Count()).ToList();
        double ent = 0;
        foreach (var g in causes) { double p = g.Count() / (double)dead.Count; ent -= p * Math.Log(p); }
        double hm = runs.Sum(r => r.h_sum) / Math.Max(1, runs.Sum(r => r.h_n));
        double hsd = Math.Sqrt(Math.Max(0, runs.Sum(r => r.h_sq) / Math.Max(1, runs.Sum(r => r.h_n)) - hm * hm));
        double mins = minutes_ticks / 3600.0;
        var sb2 = dead.Select(r => (double)r.since_bounce).Where(x => x >= 0).OrderBy(x => x).ToList();
        var (km, km_lo, km_hi) = km_median(runs.Select(r => (r.points, r.dead)).ToList());
        string F(double v) => double.IsPositiveInfinity(v) ? "past the cap" : v.ToString("F0");
        Console.WriteLine($"{opt("tier", "good")} {m} persona [{(m.p == null ? "" : m.p.ToString())}] seeds {seeds} cap {cap}: " +
                          $"KM median {F(km)} [{F(km_lo)}, {F(km_hi)}], median of the runs {Humanness.med(pts)}, rate median {rate:F1}, deaths/100pt {100 * d:F3}, alive {runs.Count(r => !r.dead)}, {sw.Elapsed.TotalSeconds:F0}s");
        Console.WriteLine($"  tap error: sd {sd(errs):F2} t, |err|>=4t {errs.Count(e => Math.Abs(e) >= 4) / (double)Math.Max(1, errs.Count):P1}, " +
                          $"rhythm: gap mean {gm:F1} t cv {(gm > 0 ? sd(gaps) / gm : 0):F2}, gaps<=11t {gaps.Count(g => g <= 11) / (double)Math.Max(1, gaps.Count):P1} (=8t {gaps.Count(g => g == 8) / (double)Math.Max(1, gaps.Count):P1}), " +
                          $"bursts(3+ taps <=11t) {bursts / Math.Max(0.01, mins):F2}/min, max taps in 1 s: med {Humanness.med(max_rate.Select(x => (long)x))} max {max_rate.DefaultIfEmpty(0).Max()}");
        Console.WriteLine($"  gap crossing: mean {(offs.Count > 0 ? offs.Average() : 0):F2} sd {sd(offs):F2}, |off|<0.2 {offs.Count(o => Math.Abs(o) < 0.2) / (double)Math.Max(1, offs.Count):P0}, " +
                          $"|off|>0.6 {offs.Count(o => Math.Abs(o) > 0.6) / (double)Math.Max(1, offs.Count):P0} | height mean {hm:F2} sd {hsd:F2}");
        Console.WriteLine($"  same seed, other bot seed (40 seeds, first 60 s): first different press at tick med {Humanness.med(div.Select(x => (long)x))}, " +
                          $"presses on the same tick {(same.Count > 0 ? same.Average() : 0):P0}");
        Console.WriteLine($"  deaths {dead.Count}: clean (planner had a full line for 45 t) {dead.Count(r => r.clean_death == 1) / (double)Math.Max(1, dead.Count):P0}, " +
                          $"cause entropy {ent / Math.Log(Math.Max(2, causes.Count)):F2} [{string.Join(", ", causes.Take(5).Select(g => $"{g.Key} {g.Count()}"))}], " +
                          $"ticks after bounce p25/50/75 {pq(sb2, 0.25)}/{pq(sb2, 0.5)}/{pq(sb2, 0.75)}");
        Console.WriteLine($"  rooms: {string.Join(", ", dead.GroupBy(r => r.room).OrderByDescending(g => g.Count()).Take(6).Select(g => $"{g.Key} {g.Count()}"))}");
        Console.WriteLine($"  persona: lapses {runs.Sum(r => r.lapses) / Math.Max(0.01, mins):F2}/min ({runs.Sum(r => r.lapse_ticks) / (double)Math.Max(1, minutes_ticks):P1} of time), " +
                          $"panic presses {runs.Sum(r => r.panics) / Math.Max(0.01, mins):F2}/min, hesitations {runs.Sum(r => r.hes) / Math.Max(0.01, mins):F2}/min");
        return 0;
    }

    static string pq(List<double> s, double p) => s.Count == 0 ? "-" : s[(int)Math.Round(p * (s.Count - 1))].ToString("F0");
}
