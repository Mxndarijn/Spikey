using System.Text.Json.Nodes;
using FastSim;

/// The rest of `fastsim check` (Checks.cs): the sims the checks start from,
/// and the room searches and bot runs that were GDScript tests.
static partial class Checks
{
    /// Port of tests/support/bot_setups.gd (BotSetups): the sims the checks
    /// start from. Parity records runs from each, so they must stay equal.
    public static class Setups
    {
        public static readonly long[] ENTRY_YS = { 140 * SimConfig.SUB, 300 * SimConfig.SUB, 480 * SimConfig.SUB };

        public static void came_in(GameSim sim, long index, long toward, long y)
        {
            sim.state.y = y;
            sim.state.anchor_y = y;
            long skip = sim._arrival_retries(toward, index);
            for (long i = 0; i < skip; i++) sim._rng.next_u32();
            sim._arrive_in(toward, index);
        }

        public static GameSim revived(int index, long seed_value, string exit, long side, long toward, long y)
        {
            var def = RoomCatalog.all()[index];
            var sim = new GameSim(seed_value, def.season);
            sim.step(true);
            long every = SimConfig.POINTS_PER_ROOM;
            long base_ = G.maxi(every, (def.from_score + every - 1) / every * every);
            sim.state.score = base_ + 3;
            came_in(sim, index, toward, y);
            switch (exit)
            {
                case "open":
                    sim.state.score = base_;
                    ExitPlanner.plan(sim, sim._rng, side, base_);
                    sim.state.exit_open = true;
                    break;
                case "ghost":
                    sim.state.score = base_ + every - 1;
                    ExitPlanner.plan(sim, sim._rng, side, base_ + every);
                    sim.state.exit_preview = true;
                    break;
            }
            sim.kill(DeathCause.FLOOR);
            sim.revive();
            return sim;
        }

        public static GameSim crawl_revived(int index, long seed_value, string exit, long side, long y)
        {
            var def = RoomCatalog.all()[index];
            var sim = new GameSim(seed_value, def.season);
            sim.step(true);
            // Not a fork score, so there is one exit.
            long base_ = 60;
            sim.state.score = base_ + 3;
            came_in(sim, index, seed_value % 2, sim.state.y);
            if (exit == "open")
            {
                sim.state.score = base_;
                ExitPlanner.plan(sim, sim._rng, side, base_);
                sim.state.exit_open = true;
            }
            else
            {
                sim.state.score = base_ + SimConfig.POINTS_PER_ROOM - 1;
                ExitPlanner.plan(sim, sim._rng, side, base_ + SimConfig.POINTS_PER_ROOM);
                sim.state.exit_preview = true;
            }
            sim.state.exit_a_y = y;
            sim.kill(DeathCause.FLOOR);
            sim.revive();
            return sim;
        }

        public static GameSim gates_revived(long seed_value, bool open, long side, long exit_y, string variant = "classic")
        {
            int index = (int)RoomCatalog.index_of("gates");
            var def = RoomCatalog.all()[index];
            long every = SimConfig.POINTS_PER_ROOM;
            long base_ = G.maxi(every, (def.from_score + every - 1) / every * every);
            var sim = new GameSim(seed_value, def.season, -1, variant);
            sim.step(true);
            sim.state.score = open ? base_ : base_ + every - 1;
            came_in(sim, index, seed_value % 2, sim.state.y);
            ExitPlanner.plan(sim, sim._rng, side, open ? base_ : base_ + every);
            sim.state.exit_a_y = exit_y;
            sim.state.exit_open = open;
            sim.state.exit_preview = !open;
            sim.kill(DeathCause.HAZARD);
            sim.revive();
            return sim;
        }

        public static GameSim practice(string id, long seed_value, string variant = "classic")
        {
            int index = (int)RoomCatalog.index_of(id);
            return new GameSim(seed_value, RoomCatalog.all()[index].season, index, variant);
        }

        public static GameSim isles_revived(string id, long seed_value, string exit, long side, string variant = "classic")
        {
            int index = (int)RoomCatalog.index_of(id);
            var def = RoomCatalog.all()[index];
            var sim = new GameSim(seed_value, def.season, -1, variant);
            sim.step(true);
            long every = SimConfig.POINTS_PER_ROOM;
            long base_ = G.maxi(every, (def.from_score + every - 1) / every * every);
            if (exit == "open")
            {
                sim.state.score = base_;
                came_in(sim, index, seed_value % 2, sim.state.y);
                ExitPlanner.plan(sim, sim._rng, side, base_);
                sim.state.exit_open = true;
            }
            else
            {
                sim.state.score = base_ + every - 1;
                came_in(sim, index, seed_value % 2, sim.state.y);
                ExitPlanner.plan(sim, sim._rng, side, base_ + every);
                sim.state.exit_preview = true;
            }
            sim.kill(DeathCause.HAZARD);
            sim.revive();
            return sim;
        }
    }

    static string deaths(SurvivalSearch search) =>
        "{" + string.Join(", ", search.last_deaths.Select(kv => $"{kv.Key}: {kv.Value}")) + "}";

    /// How far the best line of a search must get.
    public enum Through { Alive, PortalTaken, ExactlyOnePortal, PastStart }

    /// A list of SurvivalSearch cases.
    public abstract class Searches : Check
    {
        protected record S(string label, Func<GameSim> make, long ticks, Through through, bool quick = false);
        public override int count() => cases.Count;

        public override JsonObject run(int n)
        {
            var c = (S)cases[n];
            var sim = c.make();
            var search = new SurvivalSearch();
            bool ok = c.quick ? search.run_quick(sim, c.ticks) : search.run(sim, c.ticks);
            var fails = new List<string>();
            if (!ok)
            {
                fails.Add($"{c.label}: all died at tick {search.ticks_survived} ({deaths(search)})");
                return result(fails);
            }
            long got = search.best.state.room_index;
            bool through = c.through switch
            {
                Through.PortalTaken => got >= 1,
                Through.ExactlyOnePortal => got == 1,
                Through.PastStart => got > sim.state.room_index,
                _ => true,
            };
            if (!through) fails.Add($"{c.label}: nobody got through the portal (room {got})");
            return result(fails);
        }

        public override string summary(List<JsonNode> results) => $"{results.Count} searches";
    }

    /// The searches of tests/sim/test_crawl_passable.gd: through the first
    /// portal on the seeds where a crawler once covered the way, and from a
    /// revive through the hard exits (the GD test searched seed 7 only).
    public sealed class Crawl : Searches
    {
        public override string name => "crawl";
        public override string test => "tests/sim/test_crawl_passable.gd:test_search_gets_past_the_first_portal";
        public const long SEARCH_TICKS = 1000;
        public static readonly (string id, long seed)[] SEARCH_CASES = { ("crawl", 22), ("crawl", 64), ("crabs", 89) };
        public const long REVIVE_SEEDS = 8;

        protected override List<object> make()
        {
            var out_ = new List<object>();
            foreach (var (id, seed) in SEARCH_CASES)
            {
                int index = (int)RoomCatalog.index_of(id);
                out_.Add(new S($"{id} seed {seed}", () => new GameSim(seed, RoomCatalog.all()[index].season, index),
                    SEARCH_TICKS, Through.PortalTaken));
            }
            int crawl = (int)RoomCatalog.index_of("crawl");
            long top = SimConfig.slot_center_y(1);
            long bottom = SimConfig.slot_center_y(SimConfig.SLOT_COUNT - 2);
            var hard = new (string exit, long side, long y)[] { ("ghost", 1, top), ("ghost", 0, bottom), ("open", 1, top), ("open", 0, bottom) };
            for (long k = 0; k < REVIVE_SEEDS; k++)
                foreach (var (exit, side, y) in hard)
                {
                    long seed = 7 + k;
                    out_.Add(new S($"seed {seed}: {exit} exit on wall {side} at {y / SimConfig.SUB} px, after the revive",
                        () => Setups.crawl_revived(crawl, seed, exit, side, y), SimConfig.ARRIVAL_HOLD + 240, Through.ExactlyOnePortal));
                }
            return out_;
        }
    }

    /// The searches of tests/sim/test_gates_passable.gd: the once unreachable
    /// portals, the quick runs from just before an exit is planned, and after
    /// a revive at every exit height on both walls (more seeds here).
    public sealed class Gates : Searches
    {
        public override string name => "gates";
        public override string test => "tests/sim/test_gates_passable.gd:test_the_portal_is_reachable";
        public static readonly (long seed, long ticks)[] ONCE_IMPOSSIBLE = { (141, 960), (144, 960) };
        public const long SEEDS = 14;
        public const long QUICK_TICKS = 290;
        /// More quick-run seeds per variant, and revive rounds (the GD test played 1).
        public const long MORE_SEEDS = 42;
        public const long REVIVE_ROUNDS = 3;

        protected override List<object> make()
        {
            var out_ = new List<object>();
            foreach (var (seed, ticks) in ONCE_IMPOSSIBLE)
                out_.Add(new S($"seed {seed}", () => Setups.practice("gates", seed), ticks, Through.PortalTaken));
            long every = SimConfig.POINTS_PER_ROOM;
            void quick(long seed_value, string variant, bool ghost) =>
                out_.Add(new S($"{variant} seed {seed_value} ({(ghost ? "ghost" : "open")})", () =>
                {
                    var sim = Setups.practice("gates", seed_value, variant);
                    sim.state.score += every - (ghost ? 2 : 1);
                    return sim;
                }, QUICK_TICKS, Through.PastStart));
            for (long i = 0; i < SEEDS * 2; i++) quick(500 + i * 37, i < SEEDS ? "classic" : "single-small", i % 4 != 3);
            foreach (var variant in new[] { "classic", "single-small" })
                for (long k = 0; k < MORE_SEEDS; k++) quick(3000 + k * 41, variant, k % 4 != 3);
            long crossing = SimConfig.WORLD_W / SimConfig.SPEED_X;
            for (long round = 0; round < REVIVE_ROUNDS; round++)
            {
                long n = 0;
                foreach (var variant in new[] { "classic", "single-small" })
                    for (long slot = 1; slot < SimConfig.SLOT_COUNT - 1; slot += 2)
                    {
                        // A small gate plans no exit that low (Gate.SMALL_EXIT_MAX_Y).
                        if (variant != "classic" && SimConfig.slot_center_y(slot) > Gate.SMALL_EXIT_MAX_Y) continue;
                        for (long side = 0; side < 2; side++)
                        {
                            // Alternate, so every height gets both cases across the two walls.
                            bool open = n % 2 == 0;
                            n += 1;
                            long seed = 100 + n + round * 1000, y = SimConfig.slot_center_y(slot), sd = side;
                            // Open or a ghost, the exit is behind the revived bird: two crossings.
                            long ticks = SimConfig.ARRIVAL_HOLD + crossing * 2 + 20;
                            string v = variant;
                            out_.Add(new S($"{variant} seed {seed}: {(open ? "open" : "ghost")} exit at slot {slot} on wall {side}",
                                () => Setups.gates_revived(seed, open, sd, y, v), ticks, Through.PastStart));
                        }
                    }
            }
            return out_;
        }
    }

    /// The searches of tests/sim/test_isles_passable.gd: Floating Isles and
    /// Egg Hunt in every variant through the portal from just before an exit
    /// is planned, and a revived bird through the open exit (more seeds here).
    public sealed class Isles : Searches
    {
        public override string name => "isles";
        public override string test => "tests/sim/test_isles_passable.gd:test_isles_lead_through_the_portal";
        public static readonly long[] ISLES_SEEDS = { 1, 322, 7, 2024, 31337 };
        public static readonly long[] EGGS_SEEDS = { 3, 58 };
        public static readonly long[] REVIVE_SEEDS = { 15, 127, 183 };
        public const long NEAR_EXIT = 28;
        public const long PORTAL_TICKS = 450;
        /// The open exit is behind the revived bird: two crossings, and a bit.
        public static readonly long REVIVE_TICKS = SimConfig.ARRIVAL_HOLD + 2 * (SimConfig.WORLD_W / SimConfig.SPEED_X) + 30;
        public static readonly string[] ISLES_VARIANTS = { "classic", "drifting", "one-big" };
        public static readonly string[] EGGS_VARIANTS = { "classic", "drifting", "golden" };
        /// More seeds for every room variant and the revive.
        public const long MORE_SEEDS = 12;

        protected override List<object> make()
        {
            var out_ = new List<object>();
            void portal(string id, long seed, string v) => out_.Add(new S($"{id} {v} seed {seed}", () =>
            {
                var sim = Setups.practice(id, seed, v);
                sim.state.score = NEAR_EXIT;
                return sim;
            }, PORTAL_TICKS, Through.PortalTaken, quick: true));
            var more = Enumerable.Range(0, (int)MORE_SEEDS).Select(k => 400 + k * 53L).ToList();
            foreach (var v in ISLES_VARIANTS)
                foreach (var s in ISLES_SEEDS.Concat(more)) portal("isles", s, v);
            foreach (var v in EGGS_VARIANTS)
                foreach (var s in EGGS_SEEDS.Concat(more)) portal("eggs", s, v);
            foreach (var v in ISLES_VARIANTS)
                foreach (var s in REVIVE_SEEDS.Concat(more))
                    out_.Add(new S($"isles {v} seed {s}, after the revive", () => Setups.isles_revived("isles", s, "open", s % 2, v),
                        REVIVE_TICKS, Through.PastStart, quick: true));
            return out_;
        }
    }

    /// tests/sim/test_rooms_survivable.gd: rooms SurvivalSearch once proved
    /// impossible stay survivable, and the search finds no way for a dead bird.
    public sealed class Rescued : Searches
    {
        public override string name => "rescued";
        public override string test => "tests/sim/test_rooms_survivable.gd";
        public static readonly (string id, long seed, long ticks)[] CASES =
        {
            // Gravity Flip (the search itself used to mix up flipped speeds).
            ("flip", 1000, 300),
            // Saw Ring: wide rings left no way to the wall gap.
            ("sawring", 1000, 600), ("sawring", 1154, 900),
            // Double Trouble: four full-width beams plus the bouncing ball.
            ("double", 1077, 520),
        };

        protected override List<object> make()
        {
            var out_ = new List<object>();
            foreach (var (id, seed, ticks) in CASES)
            {
                int index = (int)RoomCatalog.index_of(id);
                out_.Add(new S($"{id} seed {seed}", () => new GameSim(seed, RoomCatalog.all()[index].season, index), ticks, Through.Alive));
            }
            out_.Add("dead");
            return out_;
        }

        public override JsonObject run(int n)
        {
            if (cases[n] is S) return base.run(n);
            // A sim that is already over has no way to survive.
            var sim = new GameSim(1);
            sim.step(true);
            sim.kill(DeathCause.CEILING);
            bool found = new SurvivalSearch().run(sim, 10);
            return result(found ? new() { "a dead bird cannot survive, but the search found a way" } : new());
        }

        public override string summary(List<JsonNode> results) => $"{results.Count - 1} searches and a dead bird";
    }

    /// tests/sim/test_bot_runs.gd: random tappers keep the sim's invariants and
    /// every run ends; gap seekers clear several rooms (more runs here: the GD
    /// test played 150 and 40).
    public sealed class Runs : Check
    {
        public override string name => "runs";
        public override string test => "tests/sim/test_bot_runs.gd";
        public const long RANDOM_RUNS = 600;
        public const long SEEKER_RUNS = 160;
        public const long RANDOM_TICKS = 20000;
        public override int count() => cases.Count;

        protected override List<object> make()
        {
            var out_ = new List<object>();
            var seeds = new SimRng(1001);
            for (long run = 0; run < RANDOM_RUNS; run++) out_.Add(("random", run, seeds.next_u32()));
            seeds = new SimRng(2002);
            for (long run = 0; run < SEEKER_RUNS; run++) out_.Add(("seeker", run, seeds.next_u32()));
            return out_;
        }

        public override JsonObject run(int n)
        {
            var (kind, run, seed_value) = ((string, long, long))cases[n];
            var fails = new List<string>();
            if (kind == "seeker")
                return result(fails, new JsonObject { ["score"] = SimBots.play_gap(seed_value, run + 1).state.score });
            var sim = new GameSim(seed_value);
            var bot = new SimRng(run + 1);
            long last_score = 0;
            while (!sim.is_over() && sim.state.tick < RANDOM_TICKS)
            {
                sim.step(SimBots.random_tapper(sim, bot));
                var s = sim.state;
                long r = SimConfig.BIRD_RADIUS;
                if (s.x - r < -SimConfig.SPEED_X || s.x + r > SimConfig.WORLD_W + SimConfig.SPEED_X)
                    fails.Add($"run {run} tick {s.tick}: bird outside side walls (x={s.x})");
                if (s.score < last_score || s.score > last_score + 1)
                    fails.Add($"run {run} tick {s.tick}: score jumped {last_score} -> {s.score}");
                // Rooms change through exits, which open every POINTS_PER_ROOM points.
                if (s.room_index > s.score / SimConfig.POINTS_PER_ROOM)
                    fails.Add($"run {run} tick {s.tick}: room {s.room_index} at score {s.score}");
                if (s.left_spikes != 0 && s.right_spikes != 0)
                    fails.Add($"run {run} tick {s.tick}: both walls have spikes");
                if (fails.Count > 0) return result(fails);
                last_score = s.score;
            }
            if (!sim.is_over()) fails.Add($"run {run} never ended");
            return result(fails);
        }

        static List<long> scores(List<JsonNode> results) =>
            results.Where(r => r["score"] != null).Select(r => (long)r["score"]).ToList();

        public override List<string> combine(List<JsonNode> results)
        {
            var got = scores(results);
            var fails = new List<string>();
            long best = got.Count == 0 ? 0 : got.Max();
            if (best < 3 * SimConfig.POINTS_PER_ROOM) fails.Add($"best bot run reaches room 4 (got {best})");
            long changes = got.Count(x => x >= SimConfig.POINTS_PER_ROOM);
            if (changes < SEEKER_RUNS / 2) fails.Add($"most bot runs change room at least once ({changes} of {SEEKER_RUNS})");
            return fails;
        }

        public override string summary(List<JsonNode> results)
        {
            var got = scores(results);
            long best = got.Count > 0 ? got.Max() : 0, avg = got.Count > 0 ? got.Sum() / got.Count : 0;
            return $"{RANDOM_RUNS} random tapper runs, {SEEKER_RUNS} gap seeker runs (best {best}, average {avg})";
        }
    }
}
