using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using FastSim;
using FastSim.Mpc;

static partial class Checks
{
    /// The MPC bot (docs/MPC_BOT.md) never uses the future: its code never
    /// copies or steps the GameSim (only MpcRun.cs, which plays the bot's
    /// taps on the real run, may step), and in every room variant a decision
    /// leaves the sim's checksum as it was.
    public sealed class MpcBotCheck : Check
    {
        public override string name => "mpcbot";
        public override string test => "tools/fastsim/Mpc/MpcCheck.cs";
        public const long TICKS = 400;
        /// The one file allowed to step the sim, and this check itself.
        static readonly string[] RUNNERS = { "MpcRun.cs", "MpcCheck.cs" };
        public override int count() => cases.Count;

        protected override List<object> make()
        {
            var out_ = new List<object> { (-1L, "") };
            var all = RoomCatalog.all();
            for (int i = 0; i < all.Count; i++)
            {
                if (all[i].variants.Count == 0) out_.Add(((long)i, ""));
                foreach (var v in all[i].variants) out_.Add(((long)i, v.id));
            }
            return out_;
        }

        public static string source_dir() => Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../Mpc"));

        /// Calls that would let the bot see the future, found in the bot's source.
        public static List<string> future_calls(string dir)
        {
            var bad = new List<string>();
            var banned = new Regex(@"\bclone_deep\s*\(|\.step\s*\(|\.revive\s*\(|\b_rng\b|\bSimRng\b|\bSurvivalSearch\b|new\s+GameSim\b" +
                // A boss's dice, clock and next attacks: only its drawn tells may be read.
                @"|\.seed\b|\.draw\s*\(|\blit_rows\b|\bslam_of\b|\b_next_lane\b|\bhop_to\b|\bsafe_y\b|\bclock(_in)?\s*\(" +
                @"|\b_pick_column\b|\bphase_start\b|\b_k\b|\b_lit_k\b|\bbeam_t\b|\bdart_t\b|\bfrom_y\b");
            foreach (string path in Directory.GetFiles(dir, "*.cs"))
            {
                if (RUNNERS.Contains(Path.GetFileName(path))) continue;
                string[] lines = File.ReadAllLines(path);
                for (int i = 0; i < lines.Length; i++)
                {
                    string code = lines[i];
                    int at = code.IndexOf("//");
                    if (at >= 0) code = code[..at];
                    if (banned.IsMatch(code)) bad.Add($"{Path.GetFileName(path)}:{i + 1}: {lines[i].Trim()}");
                }
            }
            return bad;
        }

        public override JsonObject run(int n)
        {
            var (room, variant) = ((long, string))cases[n];
            var fails = new List<string>();
            if (room < 0)
            {
                string dir = source_dir();
                if (!Directory.Exists(dir)) fails.Add("no MPC source at " + dir);
                else
                    foreach (string b in future_calls(dir)) fails.Add("the MPC bot may not copy or step the sim: " + b);
                return result(fails);
            }
            long seed = 1, ticks = 0;
            var sim = new GameSim(seed, Seasons.NONE, room, variant);
            var bot = new MpcBot(new MpcParams(), null, seed);
            while (ticks < TICKS && fails.Count == 0)
            {
                if (sim.is_over())
                {
                    sim = new GameSim(++seed, Seasons.NONE, room, variant);
                    bot = new MpcBot(new MpcParams(), null, seed);
                }
                long before = sim.checksum();
                bool tap = bot.decide(sim);
                if (sim.checksum() != before)
                    fails.Add($"{RoomCatalog.all()[(int)room].id}/{variant} seed {seed} tick {sim.state.tick}: deciding changed the sim");
                sim.step(tap);
                ticks++;
            }
            return result(fails);
        }

        public override string summary(List<JsonNode> results) =>
            $"no clone or step in the bot's source, {results.Count - 1} room variants decided on without changing the sim";
    }

    /// The MPC bot reads every boss tell before it strikes (Mpc/BossSight.cs):
    /// the bot plays a boss room until a tell shows, picks a spot the tell
    /// warns of that is not deadly yet, and checks that the spot, once it turns
    /// deadly, was inside a warning Sight reported when the tell first showed,
    /// due no later than it struck.
    public sealed class MpcBossSight : Check
    {
        public override string name => "mpcboss";
        public override string test => "tools/fastsim/Mpc/MpcCheck.cs:MpcBossSight";
        public const long SEEDS = 12, TICKS = 6000, WAIT = 400;
        const long SUB = SimConfig.SUB;
        public override int count() => cases.Count;

        /// (boss room, points to start the room at = its phase, tell).
        static readonly (string room, long points, string tell)[] TELLS =
        {
            ("boss_watcher", 0, "beam"), ("boss_watcher", 7, "dart"),
            ("boss_crusher", 0, "slam"), ("boss_crusher", 7, "jaw"), ("boss_crusher", 14, "crate"),
            ("boss_saw", 0, "landing"), ("boss_saw", 7, "ring"), ("boss_saw", 14, "hop"),
        };

        protected override List<object> make() => TELLS.Select(x => (object)x).ToList();

        /// The spot the tell now on screen warns of, if a tell shows.
        static (long x, long y)? spot(Boss h, string tell)
        {
            const long MID = SimConfig.WORLD_W / 2;
            switch (h)
            {
                case BossWatcher w when tell == "beam" && w.beam == BossWatcher.Beam.WARN:
                    for (int i = 0; i < BossWatcher.ROWS.Length; i++)
                        if (((w.lit >> i) & 1) == 1) return (MID, BossWatcher.ROWS[i]);
                    return null;
                case BossWatcher w when tell == "dart" && w.dart == BossWatcher.Dart.MARK:
                    return (MID, w.dart_lane);
                case BossCrusher c when tell == "slam" && c.telling && c.phase == 1:
                    return (MID, c.slam_y + BossCrusher.BITE);
                case BossCrusher c when tell == "jaw" && c.telling && c.jaw && c.phase == 2:
                {
                    long top = c.lane_to - c.lane_half() - BossCrusher.TEETH + BossCrusher.BITE;
                    long bottom = c.lane_to + c.lane_half() + BossCrusher.TEETH - BossCrusher.BITE;
                    if (top > c.press_y + BossCrusher.BITE + 8 * SUB) return (MID, top);
                    if (bottom < c.plate_y - BossCrusher.BITE - 8 * SUB) return (MID, bottom);
                    return null;
                }
                case BossCrusher c when tell == "crate" && c.crate[0] == BossCrusher.Crate.MARK:
                    return (c.crate_x[0], (c.press_y + c.plate_y) / 2);
                case BossSaw s when tell == "landing" && s.telling && s.phase == 1:
                    return (BossSaw.KING_X, s.to_y);
                case BossSaw s when tell == "ring" && s.telling && s.phase == 2:
                    return (BossSaw.KING_X, s.to_y - s.ring_max());
                case BossSaw s when tell == "hop" && s.telling && s.phase == 3:
                    return (BossSaw.KING_X, s.to_y + BossSaw.RING_HOP);
            }
            return null;
        }

        static bool deadly(GameSim sim, Hazard h, (long x, long y) p)
        {
            long x = sim.state.x, y = sim.state.y;
            sim.state.x = p.x;
            sim.state.y = p.y;
            bool k = h.kills(sim);
            sim.state.x = x;
            sim.state.y = y;
            return k;
        }

        static bool inside(Sight.Warn w, float x, float y, long steps) =>
            x >= w.x0 && x <= w.x1 && y >= w.y0 && y <= w.y1 && steps >= w.eta - 1 && steps <= w.eta + w.dur;

        public override JsonObject run(int n)
        {
            var (room_id, points, tell) = TELLS[n];
            var fails = new List<string>();
            long room = RoomCatalog.index_of(room_id);
            int seen = 0;
            for (long seed = 1; seed <= SEEDS && seen < 3 && fails.Count == 0; seed++)
            {
                var sim = new GameSim(seed, Seasons.NONE, room);
                var bot = new MpcBot(new MpcParams(), null, seed);
                var boss = sim.room.hazards.OfType<Boss>().First();
                (long x, long y)? at = null;
                List<Sight.Warn> warned = null;
                long t0 = 0;
                for (long i = 0; i < TICKS && !sim.is_over(); i++)
                {
                    // Start the room in the tell's phase.
                    if (sim.room.points < points) sim.room.points = points;
                    bool tap = bot.decide(sim);
                    if (at == null && boss.down_at < 0)
                    {
                        var p = spot(boss, tell);
                        if (p != null && !deadly(sim, boss, p.Value))
                        {
                            at = p;
                            warned = new List<Sight.Warn>(bot.planner.sight.warns);
                            t0 = sim.room.t;
                        }
                    }
                    sim.step(tap);
                    if (at == null || sim.is_over()) continue;
                    long d = sim.room.t - t0;
                    if (deadly(sim, boss, at.Value))
                    {
                        float x = (float)at.Value.x / SUB, y = (float)at.Value.y / SUB;
                        if (!warned.Any(w => inside(w, x, y, d)))
                        {
                            var near = warned.Where(w => x >= w.x0 && x <= w.x1 && y >= w.y0 && y <= w.y1)
                                .Select(w => $"eta {w.eta} dur {w.dur}");
                            fails.Add($"{room_id} {tell} seed {seed}: ({x:F0}, {y:F0}) turned deadly {d} steps after the tell showed, " +
                                $"not warned then (warnings there: {string.Join("; ", near.DefaultIfEmpty("none"))})");
                        }
                        seen++;
                        break;
                    }
                    if (d > WAIT) break;
                }
            }
            if (fails.Count == 0 && seen == 0) fails.Add($"{room_id} {tell}: the tell never showed and struck in {SEEDS} seeds");
            return result(fails);
        }

        public override string summary(List<JsonNode> results) =>
            $"{results.Count} boss tells warned before they strike";
    }
}
