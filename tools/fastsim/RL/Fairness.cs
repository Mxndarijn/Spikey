using System.Collections.Concurrent;
using System.Diagnostics;

namespace FastSim.Rl;

/// `rl review fair`: is a BlindPlanner death the bot's fault or the room's?
/// (SpikeCage-coord/research/planner-review/08-fairness.md). Tool only.
///
/// Plays the BlindPlanner on seeds first+1..first+seeds (same knobs as
/// `rl review atlas`) and, for every death, asks three judges from the
/// bot's own state `b` ticks before the death (b = 10, 20, ... up to `back`),
/// keeping the latest b each can still save ("last chance", -1 = none):
///   oracle   SurvivalSearch on the true future (sees every hidden draw).
///   honest0  a line that lives in the true world and in `k` scrambled
///            copies (BlindPlanner.blind_copy: hidden RNG and drawn-but-unshown
///            values replaced), re-planned in stages of `stage0` ticks, each
///            stage's copies made from the state at the stage's start.
///   honestR  the same with a reaction delay of `react` ticks: a stage's line
///            must live in copies scrambled `react` ticks before the stage
///            starts (what the player had seen when it decided), replayed
///            with the inputs flown since. Stages are `react` ticks long.
///   Every stage must leave each copy savable (true-future SurvivalSearch,
///   `viable` ticks), and the line must live `tail` ticks past the death.
///   Taps: any tick at least `gap` ticks after the last tap (a fast thumb).
/// Verdict: bot (honestR saves), reaction (only honest0 saves), hidden (only
/// the oracle saves), lost (not even the oracle, within `back` ticks).
/// Also counts every room entered per variant (the denominator per 1000 rooms).
public static class Fairness
{
    public sealed class Judge
    {
        public long react = 60, stage0 = 15, viable = 60, tail = 40, gap = 6;
        public int k = 6, cands = 6, budget = 24;
        public long bpx = 6, speeds = 6;
        public long stages_used;
        public bool ran_out;

        long _end;
        long _salt;
        int _left;
        List<GameSim> _hist; // true state before the input of tick base + i
        List<bool> _taps;    // input of tick base + i
        long _base;

        struct Node
        {
            public GameSim[] w;
            public int parent;
            public byte tap;
            public long since;
        }

        /// `hist`: true states of ticks base..start (inclusive) along the bot's run, `taps` its inputs
        /// for base..start-1. Whether a line from `start` lives to `end` (+ viability).
        public bool honest(List<GameSim> hist, List<bool> taps, long base_tick, long start, long end, long salt, bool delayed)
        {
            _hist = hist.Take((int)(start - base_tick + 1)).ToList();
            _taps = taps.Take((int)(start - base_tick)).ToList();
            _base = base_tick;
            _end = end;
            _salt = salt;
            _left = budget;
            ran_out = false;
            stages_used = 0;
            return stage(start, delayed);
        }

        GameSim at(long tick) => _hist[(int)(tick - _base)];

        bool stage(long s, bool delayed)
        {
            if (s >= _end) return new SurvivalSearch { max_level = 0 }.run_quick(at(s), viable);
            if (_left-- <= 0)
            {
                ran_out = true;
                return false;
            }
            stages_used++;
            long len = Math.Min(delayed ? react : stage0, _end - s);
            long info = delayed ? Math.Max(_base, s - react) : s;
            var worlds = new List<GameSim> { at(s).clone_deep() };
            for (int j = 0; j < k; j++)
            {
                var c = BlindPlanner.blind_copy(at(info), new SimRng(_salt * 7919 + s * 131 + j + 1), -1);
                for (long t = info; t < s && !c.is_over(); t++) c.step(_taps[(int)(t - _base)]);
                // A copy in which the bird would already be dead is not what the player sees.
                if (!c.is_over()) worlds.Add(c);
            }
            var found = beam(worlds.ToArray(), len);
            foreach (var (line, ends) in found)
            {
                bool ok = true;
                for (int i = 0; i < ends.Length && ok; i++)
                    if (!new SurvivalSearch { max_level = 0 }.run_quick(ends[i], viable)) ok = false;
                if (!ok) continue;
                // Fly the line in the true world, keeping its states for the next stage's copies.
                int keep_h = _hist.Count, keep_t = _taps.Count;
                var cur = at(s).clone_deep();
                for (int t = 0; t < line.Length; t++)
                {
                    cur.step(line[t] != 0);
                    _taps.Add(line[t] != 0);
                    _hist.Add(cur.clone_deep());
                }
                if (!cur.is_over() && stage(s + line.Length, delayed)) return true;
                _hist.RemoveRange(keep_h, _hist.Count - keep_h);
                _taps.RemoveRange(keep_t, _taps.Count - keep_t);
                if (ran_out) return false;
            }
            return false;
        }

        /// Lines (common inputs) that live `ticks` in every world: up to `cands`, one per 40 px band of
        /// the true world's end height, nearest the room's anchor first. Each with its end states.
        List<(byte[] line, GameSim[] ends)> beam(GameSim[] roots, long ticks)
        {
            var parents = new List<int>();
            var taps = new List<byte>();
            var frontier = new List<Node> { new Node { w = roots, parent = -1, since = 99 } };
            var slots = new Dictionary<long, int>();
            var next = new List<Node>();
            long bh = bpx * SimConfig.SUB, bvy = -SimConfig.FLAP_VY * 2 / speeds;
            for (long t = 0; t < ticks; t++)
            {
                slots.Clear();
                next.Clear();
                foreach (var e in frontier)
                {
                    bool can_tap = e.since >= gap;
                    for (int a = can_tap ? 1 : 0; a >= 0; a--)
                    {
                        var ws = new GameSim[e.w.Length];
                        bool dead = false;
                        long key = a == 1 ? 1 : Math.Min(e.since + 1, gap);
                        for (int i = 0; i < ws.Length && !dead; i++)
                        {
                            var s = e.w[i].clone_deep();
                            s.step(a == 1);
                            if (s.is_over()) dead = true;
                            ws[i] = s;
                            var st = s.state;
                            long along = st.vy * s.room.gravity - SimConfig.FLAP_VY;
                            long sp = G.clampi(along / bvy, 0, speeds - 1);
                            key = key * 1000003 + (st.room_index * 1000 + st.y / bh) * speeds + sp;
                        }
                        if (dead) continue;
                        var node = new Node { w = ws, parent = e.parent, tap = (byte)a, since = a == 1 ? 1 : e.since + 1 };
                        if (!slots.ContainsKey(key))
                        {
                            slots[key] = next.Count;
                            next.Add(node);
                        }
                    }
                }
                if (next.Count == 0) return new();
                frontier = new List<Node>(next.Count);
                foreach (var e in next)
                {
                    parents.Add(e.parent);
                    taps.Add(e.tap);
                    frontier.Add(new Node { w = e.w, parent = parents.Count - 1, since = e.since });
                }
            }
            long anchor = roots[0].state.exit_open || roots[0].state.exit_preview ? roots[0].state.exit_a_y : roots[0].state.anchor_y;
            var best = new Dictionary<long, Node>();
            foreach (var e in frontier)
            {
                long band = e.w[0].state.y / (40 * SimConfig.SUB);
                if (!best.ContainsKey(band)) best[band] = e;
            }
            var res = new List<(byte[], GameSim[])>();
            foreach (var e in best.Values.OrderBy(e => Math.Abs(e.w[0].state.y - anchor)).Take(cands))
            {
                var out_ = new List<byte>();
                for (int nd = e.parent; nd >= 0; nd = parents[nd]) out_.Add(taps[nd]);
                out_.Reverse();
                res.Add((out_.ToArray(), e.w));
            }
            return res;
        }
    }

    /// Ticks until the bird, flying on (x does not depend on taps), first overlaps column `c`'s
    /// crate in x (its kill range: crate edges +- the bird radius). 999 = not within 400 ticks.
    public static long crate_entry(GameSim sim, CrateDrop cd, long c)
    {
        long r = SimConfig.BIRD_RADIUS, lo = cd.col_left(c) - r, hi = cd.col_left(c) + cd.crate_w + r;
        long x = sim.state.x, vx = sim.state.vx, left = sim.room.wall_left(), right = sim.room.wall_right();
        for (long t = 0; t < 400; t++)
        {
            if (x >= lo && x <= hi) return t;
            x += vx;
            if (vx > 0 && x + r >= right) { x = 2 * (right - r) - x; vx = -vx; }
            else if (vx < 0 && x - r <= left) { x = 2 * (left + r) - x; vx = -vx; }
        }
        return 999;
    }

    public record Death(long seed, long score, long tick, string room, string cause, string verdict,
        long oracle, long honest0, long honest_r, bool undecided, long since_bounce, long since_entry,
        long x, long y, long crate_shown, long crate_e, double secs);

    public static int run(Dictionary<string, string> opts, int seeds, long cap, int threads)
    {
        long L(string key, long d) => long.Parse(opts.GetValueOrDefault(key, d.ToString()));
        long first = L("first", 0), back = L("back", 240), step = L("step", 10);
        string out_path = opts.GetValueOrDefault("out", "");
        Judge make() => new Judge
        {
            react = L("react", 60), stage0 = L("stage0", 15), viable = L("viable", 60), tail = L("tail", 40),
            gap = L("gap", 6), k = (int)L("k", 6), cands = (int)L("cands", 6), budget = (int)L("budget", 24),
        };
        var clock = Stopwatch.StartNew();
        var rooms = new ConcurrentDictionary<string, long>();
        var deaths = new ConcurrentBag<Death>();
        var marks = new ConcurrentDictionary<string, long>();
        long points = 0, alive = 0;
        string setup = "";
        int done = 0;
        Parallel.For(0, seeds, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            var t0 = Stopwatch.StartNew();
            long seed = first + i + 1;
            var sim = new GameSim(seed);
            var bot = new BlindPlanner(seed);
            string cfg = Review.configure(bot, opts);
            if (i == 0) setup = cfg;
            var taps = new List<bool>();
            long bounce_tick = 0, entry_tick = 0, drops = -1, drop_tick = 0;
            long ri0 = -1, last_e = -1;
            while (!sim.is_over() && taps.Count < cap)
            {
                if (sim.state.room_index != ri0)
                {
                    ri0 = sim.state.room_index;
                    rooms.AddOrUpdate(sim.room.def.id + "/" + sim.room.variant_id(), 1, (_, v) => v + 1);
                }
                bool tap = bot.decide(sim);
                taps.Add(tap);
                long vx = sim.state.vx, ri = sim.state.room_index;
                sim.step(tap);
                if (sim.state.vx != vx) bounce_tick = taps.Count;
                if (sim.state.room_index != ri) entry_tick = taps.Count;
                var cd = sim.room.hazards.OfType<CrateDrop>().FirstOrDefault();
                long dn = cd == null ? -1 : cd.drops;
                if (dn != drops)
                {
                    drops = dn;
                    drop_tick = taps.Count;
                    if (cd != null && cd.col >= 0)
                        foreach (long cc in new[] { cd.col, cd.col_b })
                        {
                            if (cc < 0) continue;
                            long e = crate_entry(sim, cd, cc);
                            last_e = e;
                            bool outer = cc == 0 || cc == cd.cols - 1;
                            string v = sim.room.def.id + "/" + sim.room.variant_id();
                            marks.AddOrUpdate($"{v}	{(outer ? "outer" : "inner")}	{Math.Min(e, 200) / 5 * 5}", 1, (_, x) => x + 1);
                        }
                }
            }
            Interlocked.Add(ref points, sim.state.score);
            if (!sim.is_over())
            {
                Interlocked.Increment(ref alive);
                Console.Error.WriteLine($"[{Interlocked.Increment(ref done)}/{seeds}] seed {seed} alive at {sim.state.score}");
                return;
            }
            long died = taps.Count;
            string room = sim.room.def.id + "/" + sim.room.variant_id();
            string cause = DeathCause.NAMES[sim.state.death_cause];
            long shown = sim.room.hazards.OfType<CrateDrop>().Any() ? died - drop_tick : -1;
            // True states of the last back + react + 1 ticks before the death.
            long lead = back + L("react", 60) + 1;
            long base_tick = Math.Max(0, died - lead);
            var c = new GameSim(seed);
            for (long t = 0; t < base_tick; t++) c.step(taps[(int)t]);
            var hist = new List<GameSim>();
            for (long t = base_tick; t <= died; t++)
            {
                hist.Add(c.clone_deep());
                if (t < died) c.step(taps[(int)t]);
            }
            long end = died + L("tail", 40);
            var judge = make();
            bool undecided = false;
            long last(Func<long, bool> saves)
            {
                for (long b = step; b <= back && died - b >= base_tick; b += step)
                    if (saves(b)) return b;
                return -1;
            }
            long oracle = last(b => new SurvivalSearch().run_quick(hist[(int)(died - b - base_tick)], b + judge.tail + judge.viable));
            long honest_r = -1, honest0 = -1;
            if (oracle >= 0)
            {
                honest_r = last(b =>
                {
                    bool ok = judge.honest(hist, taps.Skip((int)base_tick).ToList(), base_tick, died - b, end, seed, true);
                    undecided |= judge.ran_out;
                    return ok;
                });
                if (honest_r < 0)
                    honest0 = last(b => judge.honest(hist, taps.Skip((int)base_tick).ToList(), base_tick, died - b, end, seed, false));
                else honest0 = honest_r;
            }
            string verdict = honest_r >= 0 ? "bot" : honest0 >= 0 ? "reaction" : oracle >= 0 ? "hidden" : "lost";
            deaths.Add(new Death(seed, sim.state.score, died, room, cause, verdict, oracle, honest0, honest_r, undecided,
                died - bounce_tick, died - entry_tick, sim.state.x / SimConfig.SUB, sim.state.y / SimConfig.SUB, shown, shown >= 0 ? last_e : -1,
                t0.Elapsed.TotalSeconds));
            Console.Error.WriteLine($"[{Interlocked.Increment(ref done)}/{seeds}] seed {seed} {room} {cause} {verdict} o{oracle} h0 {honest0} hR {honest_r}{(undecided ? " (budget)" : "")} {t0.Elapsed.TotalSeconds:F0}s");
        });
        var sb = new System.Text.StringBuilder();
        var j = make();
        sb.AppendLine($"fairness of BlindPlanner deaths [{setup}], seeds {first + 1}..{first + seeds}, cap {cap}, gameplay {SimConfig.GAMEPLAY_VERSION}");
        sb.AppendLine($"judges: back {back} step {step}, react {j.react}, stage0 {j.stage0}, copies {j.k}, cands {j.cands}, budget {j.budget}, viable {j.viable}, tail {j.tail}, tap gap {j.gap}");
        var ds = deaths.OrderBy(d => d.seed).ToList();
        sb.AppendLine($"{ds.Count} deaths in {points} points = {100.0 * ds.Count / Math.Max(1, points):F3} per 100; {alive} of {seeds} alive at the cap; {clock.Elapsed.TotalSeconds:F0} s");
        sb.AppendLine("verdicts: " + string.Join(", ", ds.GroupBy(d => d.verdict).OrderByDescending(g => g.Count()).Select(g => $"{g.Key} {g.Count()}")));
        sb.AppendLine("rooms\tvariant\tentered\tdeaths\tbot\treaction\thidden\tlost");
        foreach (var kv in rooms.OrderByDescending(kv => ds.Count(d => d.room == kv.Key)).ThenBy(kv => kv.Key))
        {
            var g = ds.Where(d => d.room == kv.Key).ToList();
            sb.AppendLine($"room\t{kv.Key}\t{kv.Value}\t{g.Count}\t{g.Count(d => d.verdict == "bot")}\t{g.Count(d => d.verdict == "reaction")}\t{g.Count(d => d.verdict == "hidden")}\t{g.Count(d => d.verdict == "lost")}");
        }
        sb.AppendLine("seed\tscore\ttick\troom\tcause\tverdict\toracle\thonest0\thonestR\tundecided\tsince_bounce\tsince_entry\tx\ty\tcrate_shown\tsecs");
        foreach (var d in ds)
            sb.AppendLine($"{d.seed}\t{d.score}\t{d.tick}\t{d.room}\t{d.cause}\t{d.verdict}\t{d.oracle}\t{d.honest0}\t{d.honest_r}\t{(d.undecided ? 1 : 0)}\t{d.since_bounce}\t{d.since_entry}\t{d.x}\t{d.y}\t{d.crate_shown}\t{d.secs:F0}");
        sb.AppendLine("crate marks: variant, column, ticks from the mark until the bird enters the column's kill range (5-tick bins), count");
        foreach (var kv in marks.OrderBy(kv => kv.Key)) sb.AppendLine($"mark	{kv.Key}	{kv.Value}");
        string text = sb.ToString();
        if (out_path != "") File.WriteAllText(out_path, text);
        Console.Write(text);
        return 0;
    }
}
