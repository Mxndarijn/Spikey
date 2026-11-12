using System.Text.Json.Nodes;
using FastSim.Yard;

namespace FastSim.Measure;

/// Tier verdicts from a holdout run set (docs/BOT_TESTING.md, "Report").
///   beginner..expert: the KM median and its interval. A bot fits its tier
///     when the median is within +-15% of the target and the whole interval
///     lies inside the tier's band (edges: geometric middles of the targets).
///   beast: the KM median is missing (half the runs reach the cap) or above
///     354. Reported by its plateau rate (deaths per 100 points from 40 on).
///   infinite: every run that can be finished is finished. Which runs can be
///     finished comes from the fairness judge (`rl review fair`): a death it
///     calls `bot` had an honest, visible-only line (a 1 s reaction); deaths it
///     calls reaction, hidden or lost had none, so those runs do not count.
///     finished share = alive at the cap / (alive + bot deaths), Wilson CI.
public static class Tier
{
    public const double FIT = 0.15;
    public static readonly string[] FINISHABLE = { "bot" };

    public static (double lo, double hi) band(string tier)
    {
        var t = Stats.TIERS;
        int i = Array.FindIndex(t, x => x.name == tier);
        if (i < 0) return (double.NaN, double.NaN);
        double lo = i == 0 ? Math.Sqrt(t[0].target * t[0].target / 2) : Math.Sqrt(t[i - 1].target * t[i].target);
        double hi = i == t.Length - 1 ? double.PositiveInfinity : Math.Sqrt(t[i].target * t[i + 1].target);
        return (lo, hi);
    }

    /// Fairness file of `rl review fair`: the death rows (seed, ..., verdict).
    public static Dictionary<long, string> load_fair(string path)
    {
        var res = new Dictionary<long, string>();
        var lines = File.ReadAllLines(path);
        int head = Array.FindIndex(lines, l => l.StartsWith("seed\tscore\ttick\troom\tcause\tverdict"));
        if (head < 0) throw new InvalidDataException($"{path}: no death rows of `rl review fair`");
        for (int i = head + 1; i < lines.Length; i++)
        {
            var c = lines[i].Split('\t');
            if (c.Length < 6 || !long.TryParse(c[0], out long seed)) break;
            res[seed] = c[5];
        }
        return res;
    }

    public static JsonObject verdict(Survival.Set set, string claimed, Dictionary<long, string> fair, int reps = 2000)
    {
        var d = Survival.describe(set, reps);
        var km = d["km_median"]!.AsObject();
        double med = (double?)km["value"] ?? double.NaN, lo = (double?)km["lo"] ?? double.NaN, hi = (double?)km["hi"] ?? double.NaN;
        var o = new JsonObject
        {
            ["runs"] = set.runs.Count, ["deaths"] = set.deaths, ["cap_ticks"] = set.cap,
            ["km_median"] = km.DeepClone(), ["per_100_plateau"] = d["per_100_plateau"]!.DeepClone(),
            ["alive_share"] = d["alive_share"]!.DeepClone(),
        };
        double beast_edge = band("beast").lo;
        bool beast = double.IsNaN(med) || med >= beast_edge;
        string tier = beast ? "beast" : Stats.tier_of(med);
        o["tier"] = tier;
        if (claimed != "" && claimed != "beast" && claimed != "infinite")
        {
            var (blo, bhi) = band(claimed);
            double target = Stats.TIERS.First(t => t.name == claimed).target;
            bool near = !double.IsNaN(med) && Math.Abs(med / target - 1) <= FIT;
            bool inside = !double.IsNaN(lo) && !double.IsNaN(hi) && lo >= blo && hi < bhi;
            o["claimed"] = claimed;
            o["target"] = target;
            o["band"] = new JsonArray(Math.Round(blo, 1), Math.Round(bhi, 1));
            o["off_target"] = double.IsNaN(med) ? null : Math.Round(med / target - 1, 3);
            o["fits"] = near && inside;
            o["why"] = near && inside ? "median within 15% of the target and its CI inside the band"
                : !near ? $"median {med:F0} is more than 15% from {target}" : $"CI [{lo:F0}, {hi:F0}] leaves the band [{blo:F0}, {bhi:F0})";
        }
        if (beast || claimed is "beast" or "infinite")
        {
            o["claimed"] = claimed == "" ? null : claimed;
            o["fits_beast"] = beast && (double.IsNaN(lo) || lo >= beast_edge);
            if (fair != null)
            {
                int alive = set.alive, finishable_deaths = 0, unfinishable = 0, unjudged = 0;
                foreach (var r in set.runs.Where(r => r.dead))
                {
                    if (!fair.TryGetValue(r.seed, out var v)) unjudged++;
                    else if (FINISHABLE.Contains(v)) finishable_deaths++;
                    else unfinishable++;
                }
                int n = alive + finishable_deaths;
                var (wlo, whi) = Survival.wilson(alive, n);
                o["finishable"] = new JsonObject
                {
                    ["runs"] = n, ["finished"] = alive, ["share"] = n == 0 ? null : Math.Round(alive / (double)n, 4),
                    ["lo"] = Math.Round(wlo, 4), ["hi"] = Math.Round(whi, 4),
                    ["deaths_with_an_honest_line"] = finishable_deaths, ["deaths_without"] = unfinishable, ["deaths_not_judged"] = unjudged,
                };
                o["infinite"] = unjudged == 0 && finishable_deaths == 0 && n > 0;
                o["infinite_rule"] = "every run that can be finished (fairness judge: an honest line existed) reached the cap";
            }
            else o["infinite"] = "needs --fair (rl review fair on the same seeds)";
        }
        return o;
    }
}
