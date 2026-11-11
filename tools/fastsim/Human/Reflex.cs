namespace FastSim.Human;

/// Approach B (docs/HUMAN_BOT.md): a reflex player. No look-ahead copies of
/// the sim at all: it sees the bird, the wall ahead and where hazards are right
/// now, extrapolates only its own flight (wait or tap), and taps by a small
/// weighted rule. The ~10 weights are tuned by evolution strategies.
public sealed class ReflexBot
{
    public const int N = 10;
    /// Hand-set start point (the ES starts here).
    public static readonly double[] START = { 0.3, 1.0, 0.6, 1.5, 2.0, -0.1, 12, 0.3, 0.5, 0.0 };
    static readonly long[] PROBE = { 4, 8, 12, 16, 22, 28, 36 };

    readonly double[] w;
    readonly Skill _k;
    readonly Random _rng;
    readonly Queue<(long tick, bool want)> _seen = new();
    readonly HashSet<long> _fire = new();
    long _last = -100;

    public ReflexBot(double[] weights, Skill k, long seed)
    {
        w = weights;
        _k = k;
        _rng = new Random(unchecked((int)(seed * 40503L) ^ 0x1234567));
    }

    double gauss()
    {
        double u = 1.0 - _rng.NextDouble(), v = _rng.NextDouble();
        return Math.Sqrt(-2 * Math.Log(u)) * Math.Cos(2 * Math.PI * v);
    }

    public bool decide(GameSim sim)
    {
        var s = sim.state;
        if (!s.started) return true;
        long t = s.tick;
        // The rule fires on what the bird sees now; the tap lands `lag` ticks later.
        if (_k == null || _k.lag <= 1)
        {
            bool now = want(sim, t);
            if (now) _last = t;
            return now;
        }
        if (want(sim, t))
        {
            long a = t + (long)Math.Round(_k.lag + gauss() * _k.jitter);
            if (a <= t) a = t + 1;
            if (_rng.NextDouble() >= _k.lapse) _fire.Add(a);
            _last = t; // the intention (keeps the rhythm, the thumb is already moving)
        }
        return _fire.Remove(t);
    }

    bool want(GameSim sim, long t)
    {
        var s = sim.state;
        long g = sim.room.gravity;
        if (t - _last < HumanBot.MIN_GAP) return false;
        long side = s.vx > 0 ? 1 : 0;
        long mask = sim.wall_mask(side);
        long shift = sim.wall_shift(side);
        long hb = sim.room.spike_half_base();
        double PX = SimConfig.SUB;
        double left = sim.room.wall_left(), right = sim.room.wall_right();
        double far = s.vx > 0 ? (right - s.x) / (right - left) : (s.x - left) / (right - left);
        long goal = Rl.Observer.nearest_gap(mask, s.y).y;
        if (s.exit_open && s.exit_side == side)
        {
            goal = s.exit_a_y;
            if (s.exit_b_kind == ExitKind.WILD) goal = s.exit_b_y;
        }
        double mid = HumanBot.MID;
        double pref = goal + (mid - goal) * Math.Clamp(w[0] * far * 2, 0, 1);
        long steps = Math.Max(1, sim.steps_to_wall(side));
        long yw = Rl.Observer.fall(sim, steps, false), yt = Rl.Observer.fall(sim, steps, true);
        double hit_w = Rl.Observer.wall_hits(mask, shift, hb, yw) ? 1 : 0;
        double hit_t = Rl.Observer.wall_hits(mask, shift, hb, yt) ? 1 : 0;
        double dw = danger(sim, false), dt = danger(sim, true);
        double urg_w = Math.Exp(-dw / Math.Max(1, w[6])), urg_t = Math.Exp(-dt / Math.Max(1, w[6]));
        double below = (s.y - pref) * g / (100 * PX);
        double along = s.vy * g / (double)(-SimConfig.FLAP_VY);
        double score = w[1] * below + w[2] * along + w[3] * (hit_w - hit_t) * Math.Clamp(1.5 - far, 0, 1)
                       + w[4] * (urg_w - urg_t) + w[5] + w[7] * ((yw - pref) * g / (100 * PX))
                       + w[9] * (1 - far);
        // No tap while still shooting up (unless the wait line is deadly).
        if (along < -w[8] && urg_w < 0.5) return false;
        return score > 0;
    }

    /// Ticks until the bird's own flight (wait, or tap now) first meets a
    /// hazard where it is now, the ceiling or the floor (99 if never in sight).
    double danger(GameSim sim, bool tap)
    {
        var saved = sim.state.copy();
        var s = sim.state;
        long g = SimConfig.GRAVITY * sim.room.gravity;
        long vy = tap ? SimConfig.FLAP_VY * sim.room.gravity : s.vy;
        long y = s.y, x = s.x;
        long steps = sim.room.steps_this_tick();
        long r = SimConfig.BIRD_RADIUS;
        double hit = 99;
        long k = 0;
        int pi = 0;
        var hz = sim.room.hazards;
        for (long tick = 1; tick <= PROBE[^1] && pi < PROBE.Length; tick++)
        {
            for (long n = 0; n < Math.Max(1, steps); n++)
            {
                vy = Math.Clamp(vy + g, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY);
                y += vy;
                x += s.vx;
            }
            k++;
            if (tick != PROBE[pi]) continue;
            pi++;
            if (y - r <= SimConfig.KILL_TOP || y + r >= SimConfig.KILL_BOTTOM)
            {
                hit = tick;
                break;
            }
            if (x <= sim.room.wall_left() || x >= sim.room.wall_right()) break;
            s.x = x;
            s.y = y;
            bool bad = false;
            for (int h = 0; h < hz.Count && !bad; h++)
                if (hz[h].alive && hz[h].kills(sim)) bad = true;
            if (bad)
            {
                hit = tick;
                break;
            }
        }
        sim.state = saved;
        return hit;
    }
}

/// Tunes the reflex weights with antithetic evolution strategies (rank-based).
public static class ReflexTrainer
{
    public static double[] train(int gens, int pop, int seeds, long cap, int threads, Action<string> log)
    {
        var mean = (double[])ReflexBot.START.Clone();
        var sigma = new double[] { 0.1, 0.3, 0.3, 0.5, 0.6, 0.1, 3, 0.15, 0.2, 0.3 };
        double lr = 0.6;
        var rng = new Random(12345);
        double best_fit = -1;
        var best = (double[])mean.Clone();
        for (int gen = 0; gen < gens; gen++)
        {
            var eps = new double[pop][];
            for (int i = 0; i < pop; i++)
            {
                eps[i] = new double[ReflexBot.N];
                for (int j = 0; j < ReflexBot.N; j++) eps[i][j] = gauss(rng);
            }
            var fit = new double[pop * 2];
            long seed0 = 900_000 + gen * 1000L;
            Parallel.For(0, pop * 2, new ParallelOptions { MaxDegreeOfParallelism = threads }, c =>
            {
                var wv = new double[ReflexBot.N];
                double sign = c % 2 == 0 ? 1 : -1;
                for (int j = 0; j < ReflexBot.N; j++) wv[j] = mean[j] + sign * sigma[j] * eps[c / 2][j];
                fit[c] = evaluate(wv, seed0, seeds, cap);
            });
            // Rank-based update.
            var order = Enumerable.Range(0, pop * 2).OrderBy(i => fit[i]).ToArray();
            var rank = new double[pop * 2];
            for (int i = 0; i < order.Length; i++) rank[order[i]] = i / (double)(order.Length - 1) - 0.5;
            for (int j = 0; j < ReflexBot.N; j++)
            {
                double gsum = 0;
                for (int i = 0; i < pop; i++) gsum += (rank[2 * i] - rank[2 * i + 1]) * eps[i][j];
                mean[j] += lr * sigma[j] * gsum / pop;
            }
            double mfit = evaluate(mean, 800_000, seeds * 2, cap);
            if (mfit > best_fit)
            {
                best_fit = mfit;
                best = (double[])mean.Clone();
            }
            log($"gen {gen}: pop mean {fit.Average():F1}, best {fit.Max():F1}, mean-weights eval {mfit:F1} " +
                $"[{string.Join(", ", mean.Select(x => x.ToString("F2")))}]");
        }
        return best;
    }

    /// Mean points over full runs from the start (capped).
    public static double evaluate(double[] wv, long seed0, int seeds, long cap)
    {
        double sum = 0;
        for (int i = 0; i < seeds; i++)
        {
            var sim = new GameSim(seed0 + i);
            var bot = new ReflexBot(wv, null, seed0 + i);
            long n = 0;
            while (n < cap && !sim.is_over())
            {
                sim.step(bot.decide(sim));
                n++;
            }
            sum += sim.state.score;
        }
        return sum / seeds;
    }

    static double gauss(Random r)
    {
        double u = 1.0 - r.NextDouble(), v = r.NextDouble();
        return Math.Sqrt(-2 * Math.Log(u)) * Math.Cos(2 * Math.PI * v);
    }
}
