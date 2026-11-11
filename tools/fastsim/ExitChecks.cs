using System.Text.Json.Nodes;
using FastSim;

/// `fastsim check exits`: no hazard ever kills in, or turns the bird back
/// from, the mouth of an open or ghost exit (sim/exit_zone.gd). The GDScript
/// test tests/sim/test_exit_clear.gd keeps a small sample of the same rule.
static partial class Checks
{
    /// Probes: is anything in an exit's mouth now? Bird circles from touching
    /// the wall to one bird radius back, within EXIT_HALF of the exit's height.
    public static class ExitMouth
    {
        public const long STEP = 2 * SimConfig.SUB;

        /// The kinds of hazard that kill a bird somewhere in an open or ghost
        /// exit's mouth right now, or that turn back a bird flying into it.
        public static List<string> blockers(GameSim sim)
        {
            var hits = new List<string>();
            var s = sim.state;
            if (!s.exit_open && !s.exit_preview) return hits;
            long r = SimConfig.BIRD_RADIUS;
            long keep_x = s.x, keep_y = s.y, keep_vx = s.vx, keep_vy = s.vy;
            var ys = new List<long> { s.exit_a_y };
            if (s.exit_b_kind != ExitKind.NORMAL) ys.Add(s.exit_b_y);
            long wall = s.exit_side == 1 ? sim.room.wall_right() - r : sim.room.wall_left() + r;
            long dir = s.exit_side == 1 ? -1 : 1;
            foreach (long ey in ys)
                for (long dx = 0; dx <= r; dx += STEP)
                    for (long dy = -SimConfig.EXIT_HALF; dy <= SimConfig.EXIT_HALF; dy += STEP)
                    {
                        s.x = wall + dir * dx;
                        s.y = ey + dy;
                        foreach (var h in sim.room.hazards)
                            if (h.alive && h.kills(sim) && !hits.Contains(h.kind)) hits.Add(h.kind);
                    }
            s.x = keep_x;
            s.y = keep_y;
            // Solid things (Bumper Cloud, bubbles, balls): one that turns a
            // bird in the mouth back from the wall blocks the exit too.
            foreach (long ey in ys)
                foreach (long dy in new[] { -SimConfig.EXIT_HALF / 2, 0, SimConfig.EXIT_HALF / 2 })
                {
                    var c = sim.clone_deep();
                    c.state.x = wall;
                    c.state.y = ey + dy;
                    c.state.vx = -dir * SimConfig.SPEED_X;
                    c.state.vy = 0;
                    for (int i = 0; i < c.room.hazards.Count; i++)
                    {
                        var h = c.room.hazards[i];
                        if (!h.alive) continue;
                        h.touch(c);
                        if (c.state.vx * -dir <= 0 && !hits.Contains(h.kind + " (turns back)"))
                        {
                            hits.Add(h.kind + " (turns back)");
                            c.state.vx = -dir * SimConfig.SPEED_X;
                        }
                    }
                }
            s.vx = keep_vx;
            s.vy = keep_vy;
            return hits;
        }

        /// Plays `inputs` on `sim` and returns the first time a hazard is in an
        /// exit's mouth, or "". A mouth counts from the first hazard step after
        /// it appeared or moved (hazards step before the bird, so they keep out
        /// of a new mouth from the next step on).
        public static string watch(GameSim sim, byte[] inputs, out int exits)
        {
            exits = 0;
            long key = -1, since = -1;
            foreach (byte tap in inputs)
            {
                sim.step(tap == 1);
                if (!sim.state.alive) break;
                var st = sim.state;
                long now = st.exit_open || st.exit_preview
                    ? SimHash.mix(SimHash.mix(SimHash.mix(st.exit_side, st.exit_a_y), st.exit_b_y), st.room_index)
                    : -1;
                if (now != key)
                {
                    key = now;
                    since = sim.room.t;
                    if (now != -1) exits++;
                    continue;
                }
                if (now == -1 || sim.room.t <= since) continue;
                var b = blockers(sim);
                if (b.Count > 0)
                    return $"tick {st.tick} score {st.score} {RoomCatalog.all()[(int)st.room_kind].id}/{sim.room.variant_id()}"
                        + $" {(st.exit_open ? "open" : "ghost")} exit y {st.exit_a_y / SimConfig.SUB}"
                        + (st.exit_b_kind != ExitKind.NORMAL ? $"/{st.exit_b_y / SimConfig.SUB}" : "")
                        + $" side {st.exit_side}: {string.Join(", ", b)}";
            }
            return "";
        }
    }

    /// Every variant of every room (practice, SurvivalSearch through the first
    /// portal) and full runs through the portals in every season, seed
    /// 4206176851 among them (a hazard sat on its exit in version 21): nothing
    /// is ever in an open or ghost exit's mouth.
    public sealed class Exits : Check
    {
        public override string name => "exits";
        public override string test => "tests/sim/test_exit_clear.gd:test_no_hazard_in_an_exit_mouth";
        public const int SEEDS_EACH = 8;
        public const long ROOM_TICKS = 1700;
        public static readonly long[] RUN_SEEDS = { 4206176851, 3392377610, 1, 77, 5000, 9131 };
        public const long RUN_TICKS = 12000;

        public override int count() => cases.Count;

        /// [kind, room index or season, variant, seed].
        protected override List<object> make()
        {
            var out_ = new List<object>();
            var all = RoomCatalog.all();
            for (int i = 0; i < all.Count; i++)
            {
                var ids = all[i].variants.Count == 0 ? new List<string> { "" } : all[i].variants.Select(v => v.id).ToList();
                foreach (var v in ids)
                    for (int k = 0; k < SEEDS_EACH; k++)
                        out_.Add(("room", (long)i, v, 1000L + k * 77));
            }
            foreach (long seed in RUN_SEEDS)
                for (long season = Seasons.NONE; season < Seasons.COUNT; season++)
                    out_.Add(("run", season, "", seed));
            return out_;
        }

        public override JsonObject run(int n)
        {
            var (kind, a, v, seed) = ((string, long, string, long))cases[n];
            GameSim start() => kind == "room"
                ? new GameSim(seed, RoomCatalog.all()[(int)a].season, a, v)
                : new GameSim(seed, a);
            string what = kind == "room"
                ? $"{RoomCatalog.all()[(int)a].id}/{v} seed {seed}"
                : $"run seed {seed} season {a}";
            var search = new SurvivalSearch();
            search.run_quick(start(), kind == "room" ? ROOM_TICKS : RUN_TICKS);
            string bad = ExitMouth.watch(start(), search.best_inputs, out int exits);
            var fails = new List<string>();
            if (bad != "") fails.Add($"{what}: {bad}");
            return result(fails, new JsonObject { ["exits"] = exits });
        }

        public override string summary(List<JsonNode> results) =>
            $"{results.Sum(r => (int)r["exits"])} exits watched in {results.Count} plays "
            + $"({SEEDS_EACH} practice seeds per variant, {RUN_SEEDS.Length} run seeds x {Seasons.COUNT + 1} seasons)";
    }
}
