using System.Collections.Concurrent;
using System.Diagnostics;
using System.Globalization;

namespace FastSim.Diff;

/// fastsim difficulty list|measure|score (docs/ROOM_DIFFICULTY.md).
///   list                       every room and variant it can score
///   measure --what tube,react,bots [--rooms a,b/v] [--trials 16] [--first 0]
///           [--bots beginner,...,honest] [--jobs 8] --out m.tsv
///                              one TSV row per (measure, room, entry, bot); rows already
///                              in --out are kept and not played again (resume)
///   score --in m.tsv[,more.tsv] [--out report]  the ranked table (report.md, report.json)
public static class DiffMain
{
    public static readonly CultureInfo INV = CultureInfo.InvariantCulture;

    public static int run(List<string> pos, Dictionary<string, string> opts)
    {
        string what = pos.Count > 1 ? pos[1] : "list";
        switch (what)
        {
            case "list":
                foreach (var t in Cases.all(opts.GetValueOrDefault("rooms", "*")))
                    Console.WriteLine($"{t.label,-26} {t.def.group,-9} from {t.def.from_score,4}  cap {t.cap}");
                return 0;
            case "measure": return measure(opts);
            case "score": return Score.run(opts);
            case "show":
            {
                // One entry's tube, tick by tick: --rooms <label> --first <entry>.
                var t = Cases.all(opts["rooms"])[0];
                var tube = new Tube { log = Console.WriteLine };
                var r = tube.run(Cases.arrive(t, long.Parse(opts.GetValueOrDefault("first", "0"))), t.cap);
                Console.WriteLine($"way {r.way} first_exit {r.first_exit} band min {r.band_min} p10 {r.band_p10} window {r.line_window} med {r.line_window_med}");
                // A second opinion on the way through: SurvivalSearch (finer buckets, escalating), to the exit.
                var at = Cases.arrive(t, long.Parse(opts.GetValueOrDefault("first", "0")));
                var ss = new SurvivalSearch();
                bool lived = ss.run(at, t.cap);
                bool out_ = lived && Cases.cleared(ss.best, at.state.room_index);
                Console.WriteLine($"survival search: {(out_ ? "gets through" : lived ? "lives to the cap but is still in the room" : $"all die by tick {ss.ticks_survived} ({string.Join(", ", ss.last_deaths.Select(kv => kv.Key + " " + kv.Value))})")}");
                return 0;
            }
        }
        Console.Error.WriteLine("fastsim difficulty list|measure|score");
        return 2;
    }

    static int measure(Dictionary<string, string> opts)
    {
        var whats = opts.GetValueOrDefault("what", "tube").Split(',', StringSplitOptions.RemoveEmptyEntries);
        var targets = Cases.all(opts.GetValueOrDefault("rooms", "*"));
        int trials = int.Parse(opts.GetValueOrDefault("trials", "16"));
        long first = long.Parse(opts.GetValueOrDefault("first", "0"));
        int jobs = int.Parse(opts.GetValueOrDefault("jobs", "4"));
        var bots = opts.GetValueOrDefault("bots", string.Join(",", BotPlay.BOTS)).Split(',', StringSplitOptions.RemoveEmptyEntries);
        string path = opts.GetValueOrDefault("out", "difficulty.tsv");
        var done = new HashSet<string>();
        if (File.Exists(path))
            foreach (var line in Score.lines(path))
            {
                var f = line.Split('\t');
                if (f.Length > 4) done.Add($"{f[0]}\t{f[1]}\t{f[2]}\t{f[3]}");
            }
        var work = new List<(string m, Target t, long i, string bot)>();
        foreach (var m in whats)
            foreach (var t in targets)
                for (long i = first; i < first + trials; i++)
                {
                    if (m == "bots")
                    {
                        foreach (var b in bots)
                            if (!done.Contains($"bots\t{t.label}\t{i}\t{b}")) work.Add((m, t, i, b));
                    }
                    else if (!done.Contains($"{m}\t{t.label}\t{i}\t-")) work.Add((m, t, i, "-"));
                }
        // Heavy and light rooms mixed, the same order every time.
        var rnd = new Random(7);
        work = work.OrderBy(_ => rnd.Next()).ToList();
        Console.WriteLine($"difficulty measure: {work.Count} items ({done.Count} already in {path}), {jobs} threads");
        var clock = Stopwatch.StartNew();
        using var w = new StreamWriter(new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.Read));
        var gate = new object();
        int n = 0;
        Parallel.ForEach(work, new ParallelOptions { MaxDegreeOfParallelism = jobs }, item =>
        {
            string row;
            var sw = Stopwatch.StartNew();
            try { row = one(item.m, item.t, item.i, item.bot); }
            catch (Exception e) { row = $"error\t{e.GetType().Name}: {e.Message.Replace('\t', ' ').Replace('\n', ' ')}"; }
            lock (gate)
            {
                w.WriteLine($"{item.m}\t{item.t.label}\t{item.i}\t{item.bot}\t{row}\t{sw.ElapsedMilliseconds}");
                w.Flush();
                n++;
                if (n % 50 == 0 || n == work.Count)
                    Console.WriteLine($"  {n}/{work.Count}  {clock.Elapsed.TotalMinutes:F1} min");
            }
        });
        Console.WriteLine($"difficulty measure: done in {clock.Elapsed.TotalMinutes:F1} min");
        return 0;
    }

    static string F(double x) => x.ToString("0.###", INV);

    static string one(string m, Target t, long i, string bot)
    {
        switch (m)
        {
            case "tube":
            {
                var r = new Tube().run(Cases.arrive(t, i), t.cap);
                // The tube merges near-equal states, so it can miss a way: a "no way" is
                // checked with SurvivalSearch (finer, escalating). 1 confirmed, 0 it got through, - not needed.
                string confirmed = "-";
                if (!r.way)
                {
                    var at = Cases.arrive(t, i);
                    var ss = new SurvivalSearch();
                    confirmed = ss.run(at, t.cap) && Cases.cleared(ss.best, at.state.room_index) ? "0" : "1";
                }
                return string.Join("\t", r.way ? 1 : 0, r.ticks, r.first_exit, r.peak, r.band_min, r.band_p10, r.band_med,
                    F(r.tight_s), F(r.paths_bits), F(r.bits_per_s), r.line_window, r.line_window_med, r.line_taps,
                    r.line_tight, F(r.line_s), F(r.choice_s), F(r.viable_frac), confirmed);
            }
            case "react":
            {
                var rows = ReactSweep.run(t, i);
                // Per R: shown, no way, died within R; and the same for the shown things with a way at R = 0.
                var cells = new List<string> { rows.Count.ToString() };
                for (int j = 0; j < ReactSweep.REACTS.Length; j++)
                {
                    cells.Add(rows.Count(r => r.verdict[j] == 0).ToString());
                    cells.Add(rows.Count(r => r.verdict[j] < 0).ToString());
                    cells.Add(rows.Count(r => r.verdict[0] == 1 && r.verdict[j] != 1).ToString());
                }
                cells.Add(string.Join(",", rows.Where(r => r.verdict.Any(v => v != 1))
                    .Select(r => $"{r.kind}@{r.tick}:{string.Join("", r.verdict.Select(v => v == 1 ? 'o' : v == 0 ? 'x' : 'd'))}")));
                if (cells[^1] == "") cells[^1] = "-";
                return string.Join("\t", cells);
            }
            case "bots":
            {
                var (ok, ticks, why) = BotPlay.play(t, i, bot);
                return $"{(ok ? 1 : 0)}\t{ticks}\t{(why == "" ? "-" : why)}";
            }
        }
        throw new Exception("unknown measure " + m);
    }
}
