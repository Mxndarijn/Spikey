using System.Text.Json;
using System.Text.Json.Nodes;
using FastSim;

/// `fastsim sameseed <seed> [season] [ticks] --out file.json`: plays one seed
/// several ways (different taps, and one play with a revive) and lists what
/// differs between the plays: rooms, variants, room seeds, exits (planned,
/// ghost, open, taken), wall spikes, anchors, hazard states at each bounce and
/// coin spawns. A research tool: it never changes the sim.
public static class SameSeed
{
    public sealed class Wall
    {
        public long tick, in_room, score, side, mask, anchor, bird_y, life;
        public string hazards = "";
        public string coin = "";
    }

    public sealed class Room
    {
        public long index, life, arrive_tick, hold, route, bird_y, anchor;
        public string kind = "", variant = "", seed = "", plan = "", hazards = "", spikes = "";
        public string ghost = "", open = "", taken = "";
        public long ghost_tick = -1, open_tick = -1, taken_tick = -1;
    }

    public sealed class Play
    {
        public string name = "";
        public long start_tick = -1, revive_tick = -1, death_tick = -1;
        public string death = "";
        public List<Room> rooms = new();
        public Dictionary<string, Wall> walls = new();
    }

    static string Hz(GameSim sim)
    {
        var parts = new List<string>();
        foreach (var h in sim.room.hazards)
            parts.Add($"{h.kind}:{(h.alive ? h.checksum(0) & 0xffff : -1):x}");
        return string.Join(",", parts);
    }

    static Play Record(string name, GameSim sim, Func<GameSim, bool?> decide, bool revive, long max_ticks)
    {
        var p = new Play { name = name };
        long life = 0;
        Room cur = null;
        void NewRoom(long tick)
        {
            var st = sim.state;
            cur = new Room
            {
                index = st.room_index, life = life, arrive_tick = tick, hold = st.arrival_hold,
                route = st.route, bird_y = st.y / SimConfig.SUB, anchor = st.anchor_y / SimConfig.SUB,
                kind = RoomCatalog.all()[(int)st.room_kind].id, variant = sim.room.variant_id(),
                seed = $"{sim.room.rng_seed:x}",
                plan = $"L {st.plan_a_y_left / SimConfig.SUB}/{st.plan_b_y_left / SimConfig.SUB} R {st.plan_a_y_right / SimConfig.SUB}/{st.plan_b_y_right / SimConfig.SUB}",
                hazards = Hz(sim), spikes = $"{st.left_spikes:x}|{st.right_spikes:x}",
            };
            p.rooms.Add(cur);
        }
        long rel(long t) => p.start_tick < 0 ? 0 : t - p.start_tick;
        NewRoom(0);
        long steps = 0;
        while (steps < max_ticks)
        {
            bool? d = decide(sim);
            if (!d.HasValue) break;
            steps++;
            sim.step(d.Value);
            var st = sim.state;
            foreach (int e in sim.events)
            {
                if (e == Event.START) p.start_tick = st.tick - 1;
                if (e == Event.ROOM_CHANGE)
                {
                    if (cur != null) { cur.taken_tick = rel(st.tick); cur.taken = $"{st.anchor_y / SimConfig.SUB}"; }
                    NewRoom(rel(st.tick));
                }
                if (e == Event.EXIT_PREVIEW && cur != null && cur.ghost_tick < 0)
                {
                    cur.ghost_tick = rel(st.tick);
                    cur.ghost = $"side {st.exit_side} y {st.exit_a_y / SimConfig.SUB}" + (st.exit_b_kind != ExitKind.NORMAL ? $"/{st.exit_b_y / SimConfig.SUB}" : "");
                }
                if (e == Event.EXIT_OPEN && cur != null && cur.open_tick < 0)
                {
                    cur.open_tick = rel(st.tick);
                    cur.open = $"side {st.exit_side} y {st.exit_a_y / SimConfig.SUB}" + (st.exit_b_kind != ExitKind.NORMAL ? $"/{st.exit_b_y / SimConfig.SUB}" : "");
                }
                if (e == Event.BOUNCE || e == Event.ROOM_CHANGE)
                {
                    long side = st.vx > 0 ? 1 : 0;
                    var w = new Wall
                    {
                        tick = rel(st.tick), in_room = rel(st.tick) - cur.arrive_tick, score = st.score, side = side,
                        mask = side == 0 ? st.left_spikes : st.right_spikes,
                        anchor = st.anchor_y / SimConfig.SUB, bird_y = st.y / SimConfig.SUB, life = life,
                        hazards = Hz(sim),
                    };
                    p.walls[$"{st.room_index}:{sim.room.walls}"] = w;
                }
                if (e == Event.COIN_SPAWN)
                {
                    string k = $"{st.room_index}:{sim.room.walls}";
                    if (p.walls.TryGetValue(k, out var w)) w.coin = $"{st.coin_x / SimConfig.SUB},{st.coin_y / SimConfig.SUB}";
                }
            }
            if (!st.alive)
            {
                p.death_tick = rel(st.tick);
                p.death = $"{st.death_cause} room {st.room_index} score {st.score}";
                if (sim.can_revive() && revive)
                {
                    sim.revive();
                    life++;
                    p.revive_tick = rel(st.tick);
                    NewRoom(rel(st.tick));
                    continue;
                }
                break;
            }
        }
        return p;
    }

    /// At an open fork on the wall ahead: flap to hold the Calm exit's height.
    static bool? Calm(GameSim sim)
    {
        var s = sim.state;
        long heading = s.vx > 0 ? 1 : 0;
        if (!s.exit_open || s.exit_side != heading || s.exit_b_kind == ExitKind.NORMAL) return null;
        long target = s.exit_a_kind == ExitKind.CALM ? s.exit_a_y : s.exit_b_y;
        long margin = 6 * SimConfig.SUB;
        if (sim.room.gravity < 0) return s.y < target - margin && s.vy <= 0;
        return s.y > target + margin && s.vy >= 0;
    }

    public static int run(List<string> pos, Dictionary<string, string> opts)
    {
        long seed = long.Parse(pos.Count > 1 ? pos[1] : "3392377610");
        long season = long.Parse(pos.Count > 2 ? pos[2] : "-1");
        long ticks = long.Parse(pos.Count > 3 ? pos[3] : "20000");
        GameSim start() => new GameSim(seed, season);

        long die = long.Parse(opts.GetValueOrDefault("die", "4"));
        bool only_r = opts.ContainsKey("onlyrevive");
        var plays = new List<Play>();
        // A, B: PlannerBot with two bot seeds (it aims for the Wild exit at a fork).
        foreach (var (nm, bs) in only_r ? new[] { ("A", 1L) } : new[] { ("A", 1L), ("B", 2L) })
        {
            var bot = new PlannerBot(bs);
            plays.Add(Record(nm, start(), s => bot.decide(s), false, ticks));
        }
        // C: bot seed 3, and it takes the Calm exit at every fork.
        if (!only_r)
        {
            var bot = new PlannerBot(3);
            plays.Add(Record("C (calm)", start(), s => Calm(s) ?? bot.decide(s), false, ticks));
        }
        // R: bot seed 1 until the middle of room 2 (score ends in 4), then no
        // taps until the bird dies, a revive, and on with the bot (more revives
        // allowed).
        {
            var bot = new PlannerBot(1);
            bool dying = false, done = false;
            plays.Add(Record("R (revive)", start(), s =>
            {
                if (!done && !dying && s.state.room_index >= 2 && s.state.score % 10 == die && !s.state.exit_preview && s.state.arrival_hold == 0) dying = true;
                if (dying && s.state.revives == 0) return false;
                if (dying) { dying = false; done = true; }
                return bot.decide(s);
            }, true, ticks + 600));
        }
        var outj = new JsonObject { ["seed"] = seed, ["season"] = season };
        var arr = new JsonArray();
        foreach (var p in plays)
        {
            Console.WriteLine($"== play {p.name}: {p.rooms.Count} rooms, {p.walls.Count} walls, death {p.death} at {p.death_tick}, revive at {p.revive_tick}");
            foreach (var r in p.rooms)
                Console.WriteLine($"  room {r.index} life {r.life} {r.kind}/{r.variant} seed {r.seed} in@{r.arrive_tick} hold {r.hold} route {r.route} anchor {r.anchor} bird {r.bird_y} plan [{r.plan}] ghost@{r.ghost_tick} {r.ghost} open@{r.open_tick} {r.open} taken@{r.taken_tick}");
            arr.Add(JsonSerializer.SerializeToNode(p, new JsonSerializerOptions { IncludeFields = true }));
        }
        outj["plays"] = arr;

        // Diffs against play A.
        var diffs = new JsonArray();
        var A = plays[0];
        foreach (var p in plays.Skip(1))
        {
            Console.WriteLine($"-- A vs {p.name}");
            int same_walls = 0, diff_walls = 0, cmp_walls = 0;
            foreach (var ra in A.rooms)
            {
                var rb = p.rooms.LastOrDefault(r => r.index == ra.index);
                if (rb == null) continue;
                var fields = new List<string>();
                if (ra.kind != rb.kind) fields.Add($"room kind {ra.kind} vs {rb.kind}");
                if (ra.variant != rb.variant) fields.Add($"variant {ra.variant} vs {rb.variant}");
                if (ra.seed != rb.seed) fields.Add($"room seed {ra.seed} vs {rb.seed}");
                if (ra.plan != rb.plan) fields.Add($"plan {ra.plan} vs {rb.plan}");
                if (ra.arrive_tick != rb.arrive_tick) fields.Add($"arrive tick {ra.arrive_tick} vs {rb.arrive_tick}");
                if (rb.life != ra.life) fields.Add($"after a revive");
                if (ra.hold != rb.hold) fields.Add($"hold {ra.hold} vs {rb.hold}");
                if (ra.hazards != rb.hazards) fields.Add($"hazards at arrival differ");
                if (ra.spikes != rb.spikes) fields.Add($"arrival spikes {ra.spikes} vs {rb.spikes}");
                if (ra.bird_y != rb.bird_y) fields.Add($"bird y at portal {ra.bird_y} vs {rb.bird_y}");
                if (ra.ghost != rb.ghost && ra.ghost != "" && rb.ghost != "") fields.Add($"ghost {ra.ghost} vs {rb.ghost}");
                if (ra.ghost_tick >= 0 && rb.ghost_tick >= 0 && ra.ghost_tick - ra.arrive_tick != rb.ghost_tick - rb.arrive_tick) fields.Add($"ghost tick in room {ra.ghost_tick - ra.arrive_tick} vs {rb.ghost_tick - rb.arrive_tick}");
                if (ra.open != rb.open && ra.open != "" && rb.open != "") fields.Add($"open {ra.open} vs {rb.open}");
                if (ra.open_tick >= 0 && rb.open_tick >= 0 && ra.open_tick - ra.arrive_tick != rb.open_tick - rb.arrive_tick) fields.Add($"open tick in room {ra.open_tick - ra.arrive_tick} vs {rb.open_tick - rb.arrive_tick}");
                var wd = new List<string>();
                foreach (var (k, wa) in A.walls)
                {
                    if (!k.StartsWith($"{ra.index}:")) continue;
                    if (!p.walls.TryGetValue(k, out var wb)) continue;
                    cmp_walls++;
                    var f = new List<string>();
                    if (wa.mask != wb.mask) f.Add($"spikes {wa.mask:x} vs {wb.mask:x}");
                    if (wa.in_room != wb.in_room) f.Add($"tick in room {wa.in_room} vs {wb.in_room}");
                    if (wa.score != wb.score) f.Add($"score {wa.score} vs {wb.score}");
                    if (wa.side != wb.side) f.Add($"side {wa.side} vs {wb.side}");
                    if (wa.anchor != wb.anchor) f.Add($"anchor {wa.anchor} vs {wb.anchor}");
                    if (wa.coin != wb.coin) f.Add($"coin {wa.coin} vs {wb.coin}");
                    if (wa.hazards != wb.hazards)
                    {
                        var ha = wa.hazards.Split(','); var hb = wb.hazards.Split(',');
                        var kinds = new List<string>();
                        for (int q = 0; q < Math.Min(ha.Length, hb.Length); q++) if (ha[q] != hb[q]) kinds.Add(ha[q].Split(':')[0]);
                        f.Add($"hazard state differs: {string.Join("+", kinds.Distinct())}");
                    }
                    if (f.Count == 0) same_walls++;
                    else { diff_walls++; wd.Add($"wall {k.Split(':')[1]} (score {wa.score}): {string.Join("; ", f)}"); }
                }
                string head = $"room {ra.index} {ra.kind}/{ra.variant}";
                Console.WriteLine($"  {head}: {(fields.Count == 0 ? "same" : string.Join("; ", fields))}");
                foreach (var w in wd) Console.WriteLine($"    {w}");
                diffs.Add(new JsonObject
                {
                    ["vs"] = p.name, ["room"] = ra.index, ["kind"] = ra.kind, ["variant"] = ra.variant,
                    ["room_diffs"] = new JsonArray(fields.Select(x => (JsonNode)x).ToArray()),
                    ["wall_diffs"] = new JsonArray(wd.Select(x => (JsonNode)x).ToArray()),
                });
            }
            Console.WriteLine($"  walls compared {cmp_walls}: same {same_walls}, differ {diff_walls}");
        }
        outj["diffs"] = diffs;
        if (opts.TryGetValue("out", out var file))
            File.WriteAllText(file, outj.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        return 0;
    }
}
