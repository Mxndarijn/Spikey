using System.Text.Json.Nodes;
using FastSim;
using FastSim.Rl;

static partial class Checks
{
    /// What the RL bot's danger grid holds in each boss room, during each
    /// tell and each attack (docs/RL_BOT.md, "Boss tells"). A survival search
    /// plays through the fight; every tick the grid is taken with the tells
    /// on and off. Warned cells (deadly only with the tells on) must show
    /// during every tell kind the painters draw and never outside a tell, and
    /// observing must leave the sim as it was.
    public sealed class RlBossTells : Check
    {
        public override string name => "rlboss";
        public override string test => "tools/fastsim/RL/BossTellCheck.cs";
        public static readonly string[] BOSSES = { "boss_watcher", "boss_crusher", "boss_saw" };
        public const long SEEDS = 2;
        public const long MAX_TICKS = 2400;

        public static readonly Dictionary<string, string[]> KINDS = new()
        {
            ["boss_watcher"] = new[] { "beam tell", "beam", "dart tell", "dart" },
            ["boss_crusher"] = new[] { "slam tell", "slam", "jaw tell", "jaw", "crate tell", "crate" },
            ["boss_saw"] = new[] { "hop tell", "hop", "ring tell", "ring" },
        };

        public override int count() => cases.Count;

        protected override List<object> make()
        {
            var out_ = new List<object>();
            foreach (var b in BOSSES)
                for (long s = 1; s <= SEEDS; s++) out_.Add((b, s));
            return out_;
        }

        /// The tells and attacks under way, from the boss's visible state.
        public static List<string> kinds(Boss b)
        {
            var k = new List<string>();
            if (b.down_at >= 0) return k;
            switch (b)
            {
                case BossWatcher w:
                    if (w.beam == BossWatcher.Beam.WARN) k.Add("beam tell");
                    if (w.beam == BossWatcher.Beam.ON) k.Add("beam");
                    if (w.dart == BossWatcher.Dart.MARK) k.Add("dart tell");
                    if (w.dart == BossWatcher.Dart.FLY) k.Add("dart");
                    break;
                case BossCrusher c:
                    if (c.telling && c.phase == 1) k.Add("slam tell");
                    if (!c.telling && c.phase == 1 && c.press_y > BossCrusher.PRESS_REST) k.Add("slam");
                    if (c.telling && c.phase != 1 && c.jaw) k.Add("jaw tell");
                    if (!c.telling && c.phase != 1 && c.jaw) k.Add("jaw");
                    if (c.crate[0] == BossCrusher.Crate.MARK || c.crate[1] == BossCrusher.Crate.MARK) k.Add("crate tell");
                    if (c.crate[0] == BossCrusher.Crate.FALL || c.crate[1] == BossCrusher.Crate.FALL) k.Add("crate");
                    break;
                case BossSaw s:
                    if (s.telling && s.phase != 2) k.Add("hop tell");
                    if (!s.telling && s.phase != 2 && s.clock() >= 0) k.Add("hop");
                    if (s.telling && s.phase == 2) k.Add("ring tell");
                    if (s.ring >= BossSaw.RING_SHOW) k.Add("ring");
                    break;
            }
            return k;
        }

        public override JsonObject run(int n)
        {
            var (id, seed) = ((string, long))cases[n];
            var fails = new List<string>();
            var sim = new GameSim(seed, Seasons.NONE, RoomCatalog.index_of(id));
            var boss = (Boss)sim.room.hazards.First(h => h is Boss);
            var on = new float[Observer.FRAME];
            var off = new float[Observer.FRAME];
            var ticks = new Dictionary<string, long>();
            var warned = new Dictionary<string, long>();
            var danger = new Dictionary<string, long>();
            var rnd = new Random((int)seed);
            long done = 0;
            bool keep = Observer.tells;
            try
            {
                while (done < MAX_TICKS && sim.state.room_index == 0 && fails.Count < 5)
                {
                    var search = new SurvivalSearch { pick = rnd };
                    if (!search.run(sim, 360))
                    {
                        fails.Add($"{id} seed {seed}: the search found no way on at tick {sim.state.tick}");
                        break;
                    }
                    int m = Math.Min(120, search.best_inputs.Length);
                    for (int i = 0; i < m && sim.state.room_index == 0; i++, done++)
                    {
                        long sum = sim.checksum();
                        Observer.tells = true;
                        Observer.grid(sim, on, 0);
                        Observer.tells = false;
                        Observer.grid(sim, off, 0);
                        if (sim.checksum() != sum) fails.Add($"{id} seed {seed} tick {sim.state.tick}: observing changed the sim");
                        long w = 0, d = 0;
                        for (int c = 0; c < Observer.GRID; c++)
                        {
                            if (off[c] > 0) d++;
                            else if (on[c] > 0) w++;
                        }
                        var ks = kinds(boss);
                        bool tell = ks.Any(k => k.EndsWith("tell"));
                        if (!tell && w > 0) fails.Add($"{id} seed {seed} tick {sim.state.tick}: {w} warned cells with no tell");
                        foreach (var k in ks)
                        {
                            ticks[k] = ticks.GetValueOrDefault(k) + 1;
                            warned[k] = warned.GetValueOrDefault(k) + w;
                            danger[k] = danger.GetValueOrDefault(k) + d;
                        }
                        sim.step(search.best_inputs[i] == 1);
                    }
                }
            }
            finally
            {
                Observer.tells = keep;
            }
            var o = new JsonObject { ["boss"] = id };
            foreach (var k in ticks.Keys)
                o[k] = new JsonArray(ticks[k], warned[k], danger[k]);
            return result(fails, o);
        }

        public override List<string> combine(List<JsonNode> results)
        {
            var fails = new List<string>();
            foreach (var b in BOSSES)
                foreach (var k in KINDS[b])
                {
                    var (t, w, _) = sum(results, b, k);
                    if (t == 0) fails.Add($"{b}: no '{k}' seen: the fight wasn't covered");
                    else if (k.EndsWith("tell") && w == 0) fails.Add($"{b}: '{k}' for {t} ticks but no warned cell");
                }
            return fails;
        }

        static (long t, long w, long d) sum(List<JsonNode> results, string b, string k)
        {
            long t = 0, w = 0, d = 0;
            foreach (var r in results)
            {
                if ((string)r["boss"] != b || r[k] is not JsonArray a) continue;
                t += (long)a[0];
                w += (long)a[1];
                d += (long)a[2];
            }
            return (t, w, d);
        }

        /// Per boss and kind: ticks seen, mean warned cells, mean deadly cells (of 150).
        public override string summary(List<JsonNode> results)
        {
            var parts = new List<string>();
            foreach (var b in BOSSES)
            {
                var ks = KINDS[b].Select(k =>
                {
                    var (t, w, d) = sum(results, b, k);
                    return t == 0 ? $"{k} -" : $"{k} {t}t w{(double)w / t:F1} d{(double)d / t:F1}";
                });
                parts.Add(b.Replace("boss_", "") + ": " + string.Join(", ", ks));
            }
            return "boss grids (ticks, mean warned / deadly cells): " + string.Join("; ", parts);
        }
    }
}
