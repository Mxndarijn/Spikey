using System.Text.Json.Nodes;
using FastSim;

/// `fastsim check exits`: no hazard ever kills in, or turns the bird back
/// from, an exit's mouth (sim/exit_zone.gd); from an exit's ghost until it
/// closes no wall spike reaches into it; two plays of a seed that fly
/// differently meet each exit at the same place. The GDScript test
/// tests/sim/test_exit_clear.gd keeps a small sample of the first rule.
static partial class Checks
{
    /// Probes: is anything in an exit's mouth now? Bird circles from touching
    /// the wall to one bird radius back, within EXIT_HALF of the exit's height.
    public static class ExitMouth
    {
        public const long STEP = 2 * SimConfig.SUB;

        /// The kinds of hazard that kill a bird somewhere in an exit's mouth
        /// (ExitZone's boxes) right now, or that turn back a bird flying into it.
        public static List<string> blockers(GameSim sim)
        {
            var hits = new List<string>();
            long n = ExitZone.count(sim);
            if (n == 0) return hits;
            var s = sim.state;
            long r = SimConfig.BIRD_RADIUS;
            long keep_x = s.x, keep_y = s.y;
            for (long i = 0; i < n; i++)
            {
                long side = ExitZone.box_side(sim, i), ey = ExitZone.box_y(sim, i);
                long wall = side == 1 ? sim.room.wall_right() - r : sim.room.wall_left() + r;
                long dir = side == 1 ? -1 : 1;
                for (long dx = 0; dx <= r; dx += STEP)
                    for (long dy = -SimConfig.EXIT_HALF; dy <= SimConfig.EXIT_HALF; dy += STEP)
                    {
                        s.x = wall + dir * dx;
                        s.y = ey + dy;
                        foreach (var h in sim.room.hazards)
                            if (h.alive && h.kills(sim) && !hits.Contains(h.kind)) hits.Add(h.kind);
                    }
            }
            s.x = keep_x;
            s.y = keep_y;
            // Solid things (Bumper Cloud, bubbles, balls): one that turns a
            // bird in the mouth back from the wall blocks the exit too.
            for (long i = 0; i < n; i++)
            {
                long side = ExitZone.box_side(sim, i), ey = ExitZone.box_y(sim, i);
                long wall = side == 1 ? sim.room.wall_right() - r : sim.room.wall_left() + r;
                long dir = side == 1 ? -1 : 1;
                foreach (long dy in new[] { -SimConfig.EXIT_HALF / 2, 0, SimConfig.EXIT_HALF / 2 })
                {
                    var c = sim.clone_deep();
                    c.state.x = wall;
                    c.state.y = ey + dy;
                    c.state.vx = -dir * SimConfig.SPEED_X;
                    c.state.vy = 0;
                    for (int k = 0; k < c.room.hazards.Count; k++)
                    {
                        var h = c.room.hazards[k];
                        if (!h.alive) continue;
                        h.touch(c);
                        if (c.state.vx * -dir <= 0)
                        {
                            if (!hits.Contains(h.kind + " (turns back)")) hits.Add(h.kind + " (turns back)");
                            c.state.vx = -dir * SimConfig.SPEED_X;
                        }
                    }
                }
            }
            return hits;
        }

        /// From an exit's ghost until it closes, no wall spike (slid by a belt
        /// or not) reaches into its mouth (the opening and a bird radius).
        public static string spike_in_mouth(GameSim sim)
        {
            var st = sim.state;
            if (!st.exit_open && !st.exit_preview) return "";
            long side = st.exit_side;
            long mask = sim.wall_mask(side);
            long shift = sim.wall_shift(side);
            var ys = new List<long> { st.exit_a_y };
            if (st.exit_b_kind != ExitKind.NORMAL) ys.Add(st.exit_b_y);
            for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
            {
                if ((mask & (1L << (int)slot)) == 0) continue;
                long cy = SimConfig.slot_center_y(slot) + shift;
                foreach (long ey in ys)
                    if (G.absi(cy - ey) <= ExitZone.HALF + SimConfig.SPIKE_HALF_BASE)
                        return $"wall spike at {cy / SimConfig.SUB} px";
            }
            return "";
        }

        /// What a play met: the first failure, and its exits by
        /// (room number, room, wall, exit score) -> heights.
        public sealed class Play
        {
            public string bad = "";
            public int exits;
            public Dictionary<string, string> seen = new();
        }

        /// Plays `inputs` on `sim`, checking every step: nothing in a mouth
        /// (from the first hazard step after the boxes appeared or moved:
        /// hazards step before the bird, so they keep out of a new box from
        /// the next step on), no spike in a shown exit's mouth, and the exits
        /// met.
        public static Play watch(GameSim sim, IEnumerable<byte> inputs)
        {
            var play = new Play();
            long key = -1, since = -1;
            foreach (byte tap in inputs)
            {
                sim.step(tap == 1);
                if (!sim.state.alive) break;
                var st = sim.state;
                string room = $"{RoomCatalog.all()[(int)st.room_kind].id}/{sim.room.variant_id()}";
                string where = $"tick {st.tick} score {st.score} {room}";
                if (st.exit_open || st.exit_preview)
                {
                    long at = (st.score + 1) / SimConfig.POINTS_PER_ROOM;
                    string k = $"room {st.room_index} {room} side {st.exit_side} exit {at}";
                    string v = $"{st.exit_a_y / SimConfig.SUB}"
                        + (st.exit_b_kind != ExitKind.NORMAL ? $"/{st.exit_b_y / SimConfig.SUB}" : "");
                    if (!play.seen.ContainsKey(k))
                    {
                        play.seen[k] = v;
                        play.exits++;
                    }
                    else if (play.seen[k] != v && play.bad == "")
                        play.bad = $"{where}: exit moved from {play.seen[k]} to {v} px on wall {st.exit_side}";
                    string sp = spike_in_mouth(sim);
                    if (sp != "" && play.bad == "")
                        play.bad = $"{where}: {(st.exit_open ? "open" : "ghost")} exit {v} px side {st.exit_side}: {sp}";
                }
                long now = -1;
                long n = ExitZone.count(sim);
                if (n > 0)
                {
                    now = SimHash.mix(st.room_index, n);
                    for (long i = 0; i < n; i++)
                        now = SimHash.mix(SimHash.mix(now, ExitZone.box_side(sim, i)), ExitZone.box_y(sim, i));
                }
                if (now != key)
                {
                    key = now;
                    since = sim.room.t;
                    continue;
                }
                if (now == -1 || sim.room.t <= since || play.bad != "") continue;
                var b = blockers(sim);
                if (b.Count > 0)
                {
                    var boxes = new List<string>();
                    for (long i = 0; i < n; i++)
                        boxes.Add($"{ExitZone.box_y(sim, i) / SimConfig.SUB} px side {ExitZone.box_side(sim, i)}");
                    play.bad = $"{where}, exit mouth {string.Join(", ", boxes)}: {string.Join(", ", b)}";
                }
            }
            return play;
        }
    }

    /// Every variant of every room (practice, SurvivalSearch through the first
    /// portal) and full runs through the portals in every season, seed
    /// 4206176851 among them (a hazard sat on its exit in version 21), each
    /// played twice with different taps: nothing is ever in an exit's mouth,
    /// no spike in a shown exit's mouth, and both plays meet the same exits.
    public sealed class Exits : Check
    {
        public override string name => "exits";
        public override string test => "tests/sim/test_exit_clear.gd:test_no_hazard_in_an_exit_mouth";
        public const int SEEDS_EACH = 8;
        public const long ROOM_TICKS = 1700;
        public static readonly long[] RUN_SEEDS = { 4206176851, 3392377610, 1, 77, 5000, 9131 };
        public const long RUN_TICKS = 12000;
        /// Taps for the first steps of the second play, so it flies another
        /// way into the same seed.
        public static readonly byte[] OTHER_START =
            { 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 };

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
            long ticks = kind == "room" ? ROOM_TICKS : RUN_TICKS;
            var fails = new List<string>();
            var search = new SurvivalSearch();
            search.run_quick(start(), ticks);
            var one = ExitMouth.watch(start(), search.best_inputs);
            if (one.bad != "") fails.Add($"{what}: {one.bad}");
            var lead = start();
            foreach (byte tap in OTHER_START) lead.step(tap == 1);
            var other = new SurvivalSearch();
            other.run_quick(lead, ticks);
            var two = ExitMouth.watch(start(), OTHER_START.Concat(other.best_inputs));
            if (two.bad != "") fails.Add($"{what} (other taps): {two.bad}");
            int same = 0;
            foreach (var (k, y) in one.seen)
            {
                if (!two.seen.TryGetValue(k, out var y2)) continue;
                same++;
                if (y != y2) fails.Add($"{what}: {k}: at {y} px in one play, {y2} px in the other");
            }
            return result(fails, new JsonObject { ["exits"] = one.exits + two.exits, ["same"] = same });
        }

        public override string summary(List<JsonNode> results) =>
            $"{results.Sum(r => (int)r["exits"])} exits in {2 * results.Count} plays, "
            + $"{results.Sum(r => (int)r["same"])} met by both plays of a seed "
            + $"({SEEDS_EACH} practice seeds per variant, {RUN_SEEDS.Length} run seeds x {Seasons.COUNT + 1} seasons)";
    }
}
