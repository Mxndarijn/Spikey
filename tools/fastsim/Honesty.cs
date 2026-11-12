namespace FastSim;

/// `fastsim honesty plan|anchor`: does the BlindPlanner's plan depend on
/// things that are not on screen? (research/planner-review/01-honesty.md)
///
/// plan: a real run is played by a BlindPlanner. Every `every` ticks the
/// state is forked: one hidden value is changed in the fork (nothing drawn
/// changes), and two fresh planners with the same own seed look once, one at
/// the state and one at the fork. An honest planner makes the same plan.
///   --seeds n --cap ticks --every ticks --boss 1 (practice runs in the boss rooms) --room id (practice runs in the rooms whose id starts with it)
///   --hideboss 0 --hidekeys 0 --ownanchor 0 (the fixes off / on, to show what the test finds without them)
/// anchor: how often the anchor a player can track from the walls is the room's own.
/// seeds: the seed scan (every seed-bearing value must be replaced in a blind copy).
/// rooms: practice runs per room, deaths per 100 points (to price a fix).
public static class Honesty
{
    /// One hidden change. Returns null when it does not apply to this state.
    sealed record Change(string name, string what, Func<GameSim, BlindPlanner, SimRng, GameSim> make);

    static GameSim boss_seed(GameSim sim, BlindPlanner _, SimRng own)
    {
        if (!sim.room.hazards.Any(h => h is Boss b && b.alive && b.down_at < 0)) return null;
        var c = sim.clone_deep();
        foreach (var hz in c.room.hazards)
        {
            if (hz is not Boss boss) continue;
            // The attack being told (or under way) stays: only the crusher's slam is re-read from the seed.
            long k = -1, keep = -1;
            if (boss is BossCrusher bc && bc.phase == 1 && bc.clock() >= 0)
            {
                k = bc.clock() / BossCrusher.CYCLE;
                keep = bc.slam_of(k);
            }
            do boss.seed = own.next_u32();
            while (keep >= 0 && ((BossCrusher)boss).slam_of(k) != keep);
        }
        return c;
    }

    static GameSim rng_world(GameSim sim, BlindPlanner _, SimRng own)
    {
        var c = sim.clone_deep();
        c._rng = new SimRng(own.next_u32());
        c._spine = new SimRng(own.next_u32());
        c.room.rng_seed = own.next_u32();
        if (c.state.plan_at != 0) ExitPlanner.plan_room(c, c.state.plan_at);
        return c;
    }

    static GameSim exit_plan(GameSim sim, BlindPlanner _, SimRng own)
    {
        if (sim.state.plan_at == 0 || sim.state.exit_open || sim.state.exit_preview) return null;
        var c = sim.clone_deep();
        long seed = c.room.rng_seed;
        c.room.rng_seed = own.next_u32();
        ExitPlanner.plan_room(c, c.state.plan_at);
        c.room.rng_seed = seed;
        return c;
    }

    static GameSim anchor_shift(GameSim sim, BlindPlanner _, SimRng own)
    {
        var c = sim.clone_deep();
        long lo = SimConfig.KILL_TOP + SimConfig.ARRIVAL_EDGE, hi = SimConfig.KILL_BOTTOM - SimConfig.ARRIVAL_EDGE;
        long to = c.state.anchor_y + (own.next_below(2) == 0 ? 1 : -1) * SimConfig.SLOT_SIZE;
        if (to < lo || to > hi) to = c.state.anchor_y - (to - c.state.anchor_y);
        c.state.anchor_y = to;
        return c;
    }

    /// The anchor a player can know (tracked from the walls) in place of the room's.
    static GameSim anchor_tracked(GameSim sim, BlindPlanner driver, SimRng _)
    {
        if (driver.anchor == sim.state.anchor_y) return null;
        var c = sim.clone_deep();
        c.state.anchor_y = driver.anchor;
        return c;
    }

    static GameSim stalactite_target(GameSim sim, BlindPlanner _, SimRng own)
    {
        if (!sim.room.hazards.Any(h => h is Stalactite s && s.alive && s.gap_y != s.target_y)) return null;
        var c = sim.clone_deep();
        bool changed = false;
        foreach (var hz in c.room.hazards)
        {
            if (hz is not Stalactite st || st.gap_y == st.target_y) continue;
            long dir = st.target_y > st.gap_y ? 1 : -1;
            long to = G.clampi(st.gap_y + dir * (1 + own.next_below(Stalactite.REACH + Stalactite.MAX_STEP)), Stalactite.GAP_MIN, Stalactite.GAP_MAX);
            if (to == st.gap_y) continue;
            changed |= to != st.target_y;
            st.target_y = to;
        }
        return changed ? c : null;
    }

    /// A key chain: where the keys after the one on screen will appear.
    static GameSim key_chain(GameSim sim, BlindPlanner _, SimRng own)
    {
        if (!sim.room.hazards.Any(h => h is ExitKey k && k.alive && k.mode == ExitKey.Mode.CHAIN && k.got + 1 < k.count)) return null;
        var c = sim.clone_deep();
        foreach (var hz in c.room.hazards)
        {
            if (hz is not ExitKey ek || ek.mode != ExitKey.Mode.CHAIN) continue;
            for (long i = ek.got + 1; i < ek.count; i++)
            {
                ek.chain_off[i] = ExitKey.KEY_OFF_MIN + own.next_below(ExitKey.CHAIN_OFF_MAX - ExitKey.KEY_OFF_MIN + 1);
                ek.chain_d[i] = ExitKey.CHAIN_D_MIN + own.next_below(ExitKey.CHAIN_D_MAX - ExitKey.CHAIN_D_MIN + 1);
            }
        }
        return c;
    }

    /// When an idle hunter dart next takes aim (nothing is drawn while it idles).
    static GameSim dart_idle(GameSim sim, BlindPlanner _, SimRng own)
    {
        if (!sim.room.hazards.Any(h => h is Dart d && d.alive && d.state == Dart.State.IDLE)) return null;
        var c = sim.clone_deep();
        foreach (var hz in c.room.hazards)
            if (hz is Dart d && d.state == Dart.State.IDLE) d.since += 15;
        return c;
    }

    /// A value the revive keeps (the room as entered): never read by a look.
    static GameSim entry_state(GameSim sim, BlindPlanner _, SimRng own)
    {
        if (sim._entry_rng == null) return null;
        var c = sim.clone_deep();
        c._entry_rng = new SimRng(own.next_u32());
        c._entry_spine = new SimRng(own.next_u32());
        return c;
    }

    static readonly Change[] CHANGES =
    {
        new("rng_world", "the sim's RNG, the room's wall seed, the room spine and the planned exits (control: blind_copy replaces these)", rng_world),
        new("exit_plan", "only the planned exit heights, before the ghost shows", exit_plan),
        new("entry_state", "the RNGs kept for a revive (control)", entry_state),
        new("stalactite_target", "where a sliding stalactite gap will stop (same side)", stalactite_target),
        new("boss_seed", "a boss's seed: every attack after the one being told", boss_seed),
        new("anchor_shift", "state.anchor_y moved one slot (40 px)", anchor_shift),
        new("anchor_tracked", "state.anchor_y set to what a player can track from the walls (where the two differ)", anchor_tracked),
        new("key_chain", "a key chain's later keys (each shows only when the one before is taken)", key_chain),
        new("dart_idle", "an idle dart's timer moved 15 ticks (no countdown is drawn; gray: a rhythm can be learned)", dart_idle),
    };

    static (bool first, List<bool> plan) plan_of(GameSim sim, long own_seed, Dictionary<string, string> opts, BlindPlanner driver)
    {
        var p = new BlindPlanner(own_seed);
        configure(p, opts);
        // The fresh planner gets the driver's memory (what was seen before the fork).
        p.anchor = driver.anchor;
        p.skip_observe = true;
        bool first = p.decide(sim.clone_deep());
        return (first, p.plan.ToList());
    }

    static void configure(BlindPlanner p, Dictionary<string, string> opts)
    {
        BlindPlanner.boss_blind = opts.GetValueOrDefault("hideboss", "1") != "0";
        BlindPlanner.hide_keys = opts.GetValueOrDefault("hidekeys", "1") != "0";
        p.own_anchor = opts.GetValueOrDefault("ownanchor", "1") != "0";
    }

    sealed class Tally
    {
        public long forks, differ, first_tap, early;
        public Dictionary<string, long> rooms = new();
    }

    // --- The seed scan ---------------------------------------------------

    /// Seed-bearing values that may stay as they are in a blind copy, each with the reason.
    static readonly Dictionary<string, string> SEEDS_SHOWN = new()
    {
        ["room.tide_salt"] = "the phase of the tide spikes: their motion is on screen",
    };

    const long RAW = 1L << 24;

    /// Every value under `root` that holds raw random state: a SimRng, a number whose field is
    /// named *seed* / *salt*, or any number too big to be a position, a time or a count (a raw draw).
    /// Found by reflection, so a new hazard with its own seed is found without being listed.
    static void seed_fields(object root, string path, Dictionary<string, long> out_, HashSet<object> seen)
    {
        if (root == null || !seen.Add(root)) return;
        var flags = System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic
            | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.DeclaredOnly;
        for (var type = root.GetType(); type != null && type != typeof(object); type = type.BaseType)
            foreach (var f in type.GetFields(flags))
            {
                object v = f.GetValue(root);
                string at = path == "" ? f.Name : path + "." + f.Name;
                void number(string where, long n)
                {
                    string name = f.Name.ToLowerInvariant();
                    if (name.Contains("seed") || name.Contains("salt") || Math.Abs(n) >= RAW) out_[where] = n;
                }
                switch (v)
                {
                    case null: break;
                    case SimRng rng: out_[at] = rng.state_checksum(); break;
                    case long n: number(at, n); break;
                    case long[] arr:
                        for (int i = 0; i < arr.Length; i++) number($"{at}[{i}]", arr[i]);
                        break;
                    case List<long> list:
                        for (int i = 0; i < list.Count; i++) number($"{at}[{i}]", list[i]);
                        break;
                    case List<Hazard> hz:
                        for (int i = 0; i < hz.Count; i++) seed_fields(hz[i], $"{at}[{i}:{hz[i].GetType().Name}]", out_, seen);
                        break;
                    // The catalog (rules, the same for every run) and links between hazards (reached through the list).
                    case RoomDef or RoomVariant or Hazard or string or bool or int or Delegate: break;
                    default:
                        if (v.GetType().IsClass && v.GetType().Namespace == "FastSim") seed_fields(v, at, out_, seen);
                        break;
                }
            }
    }

    static Dictionary<string, long> seed_fields(GameSim sim)
    {
        var out_ = new Dictionary<string, long>();
        seed_fields(sim, "", out_, new HashSet<object>(ReferenceEqualityComparer.Instance));
        return out_;
    }

    /// "room.hazards[3:Dart].salt" -> "room.hazards[Dart].salt", "x.delays[2]" -> "x.delays[i]".
    static string seed_name(string path)
    {
        var sb = new System.Text.StringBuilder();
        for (int i = 0; i < path.Length; i++)
        {
            sb.Append(path[i]);
            if (path[i] != '[') continue;
            int j = i + 1;
            while (j < path.Length && char.IsDigit(path[j])) j++;
            if (j < path.Length && path[j] == ':') i = j;
            else if (j < path.Length && path[j] == ']')
            {
                sb.Append('i');
                i = j - 1;
            }
        }
        return sb.ToString();
    }

    /// The seed scan: every room and variant is played for `cap` ticks (and full runs for 8 x
    /// `cap`); every 50 ticks the state gets a blind copy, and every seed-bearing value found in
    /// the state must be gone or replaced in the copy. Returns how many kinds came through unchanged.
    public static int seedscan(int seeds, long cap, List<string> lines)
    {
        var bad = new SortedDictionary<string, (long n, string where)>();
        var all = new SortedSet<string>();
        long states = 0;
        var defs = RoomCatalog.all();
        var runs = new List<(long seed, long room, string variant)>();
        for (long seed = 1; seed <= seeds; seed++)
        {
            runs.Add((seed, -1, ""));
            for (int r = 0; r < defs.Count; r++)
            {
                if (defs[r].variants.Count == 0) runs.Add((seed, r, ""));
                foreach (var v in defs[r].variants) runs.Add((seed, r, v.id));
            }
        }
        foreach (var (seed, room, variant) in runs)
        {
            var sim = new GameSim(seed, Seasons.NONE, room, variant);
            var rng = new SimRng(seed);
            var own = new SimRng(seed * 131 + 7);
            long ticks = room < 0 ? cap * 8 : cap;
            for (long t = 0; t < ticks; t++)
            {
                if (sim.is_over())
                {
                    // Practice runs cannot revive: start the room again with another seed.
                    if (sim.can_revive()) sim.revive();
                    else if (room >= 0) sim = new GameSim(seed * 1000 + t, Seasons.NONE, room, variant);
                    else break;
                }
                if (t % 50 == 7)
                {
                    states++;
                    var before = seed_fields(sim);
                    var after = seed_fields(BlindPlanner.blind_copy(sim, own));
                    foreach (var (path, value) in before)
                    {
                        string name = seed_name(path);
                        all.Add(name);
                        if (value == 0 || SEEDS_SHOWN.ContainsKey(name)) continue;
                        if (!after.TryGetValue(path, out long now) || now != value) continue;
                        string where = sim.room.def.id + "/" + sim.room.variant_id();
                        bad[name] = (bad.TryGetValue(name, out var had) ? had.n + 1 : 1, where);
                    }
                }
                sim.step(SimBots.gap_seeker(sim, rng));
            }
        }
        lines.Add($"seed scan: {states} states over {defs.Count} rooms and their variants, {all.Count} kinds of seed-bearing value:");
        lines.Add("  " + string.Join(", ", all));
        foreach (var (name, why) in SEEDS_SHOWN) lines.Add($"  allowed to stay: {name} ({why})");
        foreach (var (name, (n, where)) in bad) lines.Add($"  UNCHANGED in the blind copy: {name}, {n} states (for example in {where})");
        if (bad.Count == 0) lines.Add("  every one is replaced or dropped by blind_copy");
        return bad.Count;
    }

    static int seeds_check(Dictionary<string, string> opts, int seeds, long cap)
    {
        configure(new BlindPlanner(1), opts);
        var lines = new List<string>();
        int bad = seedscan(seeds, cap, lines);
        foreach (string l in lines) Console.WriteLine(l);
        return bad == 0 ? 0 : 1;
    }

    /// `honesty rooms --boss 1 | --room id`: practice runs, 20 points each: how many die, per room.
    static int rooms(List<(long seed, long room)> runs, Dictionary<string, string> opts, int threads, long cap)
    {
        var res = new (string room, bool dead, long points)[runs.Count];
        Parallel.For(0, runs.Count, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            var (seed, room) = runs[i];
            var sim = new GameSim(seed, Seasons.NONE, room);
            var bot = new BlindPlanner(seed);
            configure(bot, opts);
            for (long t = 0; t < cap && !sim.is_over() && sim.room.points < SimConfig.BOSS_POINTS; t++) sim.step(bot.decide(sim));
            res[i] = (sim.room.def.id, sim.is_over(), sim.room.points);
        });
        Console.WriteLine($"honesty rooms [hideboss {(BlindPlanner.boss_blind ? 1 : 0)} ownanchor {opts.GetValueOrDefault("ownanchor", "1")} hidekeys {(BlindPlanner.hide_keys ? 1 : 0)}], {SimConfig.BOSS_POINTS} points per run:");
        foreach (var g in res.GroupBy(r => r.room).OrderBy(g => g.Key))
            Console.WriteLine($"  {g.Key,-16} {g.Count(r => r.dead),4} deaths in {g.Count(),4} runs, {g.Sum(r => r.points),6} points = {100.0 * g.Count(r => r.dead) / Math.Max(1, g.Sum(r => r.points)):F3} per 100");
        Console.WriteLine($"  all              {res.Count(r => r.dead),4} deaths in {res.Length,4} runs, {res.Sum(r => r.points),6} points = {100.0 * res.Count(r => r.dead) / Math.Max(1, res.Sum(r => r.points)):F3} per 100");
        return 0;
    }

    public static int run(List<string> pos, Dictionary<string, string> opts)
    {
        string what = pos.Count > 1 ? pos[1] : "plan";
        long L(string k, long d) => long.Parse(opts.GetValueOrDefault(k, d.ToString()));
        int seeds = (int)L("seeds", 16), threads = (int)L("threads", 4);
        long cap = L("cap", 6000), every = L("every", 23), first = L("first", 0);
        bool boss = L("boss", 0) != 0;
        string room_id = opts.GetValueOrDefault("room", "");
        var runs = new List<(long seed, long room)>();
        for (int i = 1; i <= seeds; i++)
        {
            if (boss)
                foreach (long b in RoomCatalog.bosses()) runs.Add((first + i, b));
            else if (room_id != "")
            {
                for (int r = 0; r < RoomCatalog.all().Count; r++)
                    if (RoomCatalog.all()[r].id.StartsWith(room_id)) runs.Add((first + i, r));
            }
            else runs.Add((first + i, -1));
        }
        if (what == "seeds") return seeds_check(opts, (int)L("seeds", 3), L("cap", 900));
        if (what == "rooms") return rooms(runs, opts, threads, cap);
        var tally = CHANGES.ToDictionary(c => c.name, _ => new Tally());
        long bounces = 0, same = 0, near_bounces = 0, near_same = 0, off_px = 0;
        var gate = new object();
        Parallel.For(0, runs.Count, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            var (seed, room) = runs[i];
            var sim = room >= 0 ? new GameSim(seed, Seasons.NONE, room) : new GameSim(seed);
            var driver = new BlindPlanner(seed);
            configure(driver, opts);
            var own = new SimRng(seed * 7919 + 13);
            var local = CHANGES.ToDictionary(c => c.name, _ => new Tally());
            long lb = 0, ls = 0, lnb = 0, lns = 0, loff = 0;
            for (long t = 0; t < cap && !sim.is_over(); t++)
            {
                bool tap = driver.decide(sim);
                if (sim.events.Contains(Event.BOUNCE) && sim.state.started)
                {
                    bool near = !sim.state.exit_open && sim.points_to_exit() <= GameSim.EXIT_STEER;
                    lb++;
                    if (near) lnb++;
                    if (driver.anchor == sim.state.anchor_y)
                    {
                        ls++;
                        if (near) lns++;
                    }
                    else loff += Math.Abs(driver.anchor - sim.state.anchor_y) / SimConfig.SUB;
                }
                if (what == "plan" && sim.state.started && sim.state.arrival_hold == 0 && t % every == 0)
                {
                    long ps = seed * 31 + t;
                    (bool first, List<bool> plan)? base_plan = null;
                    foreach (var ch in CHANGES)
                    {
                        var fork = ch.make(sim, driver, own);
                        if (fork == null) continue;
                        base_plan ??= plan_of(sim, ps, opts, driver);
                        var b = plan_of(fork, ps, opts, driver);
                        var a = base_plan.Value;
                        var tl = local[ch.name];
                        tl.forks++;
                        int at = -1;
                        if (a.first != b.first) at = 0;
                        else
                        {
                            int n = Math.Max(a.plan.Count, b.plan.Count);
                            for (int j = 0; j < n && at < 0; j++)
                                if ((j < a.plan.Count && a.plan[j]) != (j < b.plan.Count && b.plan[j])) at = j + 1;
                        }
                        if (at < 0) continue;
                        tl.differ++;
                        if (at == 0) tl.first_tap++;
                        if (at < 4) tl.early++;
                        string id = sim.room.def.id + "/" + sim.room.variant_id();
                        tl.rooms[id] = tl.rooms.GetValueOrDefault(id) + 1;
                    }
                }
                sim.step(tap);
            }
            lock (gate)
            {
                bounces += lb;
                same += ls;
                near_bounces += lnb;
                near_same += lns;
                off_px += loff;
                foreach (var (name, tl) in local)
                {
                    var g = tally[name];
                    g.forks += tl.forks;
                    g.differ += tl.differ;
                    g.first_tap += tl.first_tap;
                    g.early += tl.early;
                    foreach (var (id, n) in tl.rooms) g.rooms[id] = g.rooms.GetValueOrDefault(id) + n;
                }
            }
        });
        string setup = $"hideboss {(BlindPlanner.boss_blind ? 1 : 0)} ownanchor {opts.GetValueOrDefault("ownanchor", "1")} hidekeys {(BlindPlanner.hide_keys ? 1 : 0)}";
        Console.WriteLine($"honesty {what}: {runs.Count} runs ({(boss ? "practice, boss rooms" : room_id != "" ? "practice, rooms " + room_id + "*" : "full runs")}), seeds {first + 1}..{first + seeds}, cap {cap}, a fork every {every} ticks [{setup}]");
        Console.WriteLine($"  anchor: tracked == the room's at {same}/{bounces} bounces ({100.0 * same / Math.Max(1, bounces):F1}%); " +
            $"within {GameSim.EXIT_STEER} points of an exit {near_same}/{near_bounces} ({100.0 * near_same / Math.Max(1, near_bounces):F1}%), " +
            $"elsewhere {same - near_same}/{bounces - near_bounces}; mean gap when off {off_px / Math.Max(1, bounces - same)} px");
        if (what != "plan") return 0;
        Console.WriteLine("  change             forks   plan differs   first tap   in 4 ticks   rooms");
        foreach (var ch in CHANGES)
        {
            var g = tally[ch.name];
            string rooms = string.Join(", ", g.rooms.OrderByDescending(kv => kv.Value).Take(6).Select(kv => $"{kv.Key} {kv.Value}"));
            Console.WriteLine($"  {ch.name,-18} {g.forks,5}   {g.differ,5} {100.0 * g.differ / Math.Max(1, g.forks),5:F1}%   {g.first_tap,5}       {g.early,5}        {rooms}");
        }
        foreach (var ch in CHANGES) Console.WriteLine($"  {ch.name}: {ch.what}");
        return 0;
    }
}
