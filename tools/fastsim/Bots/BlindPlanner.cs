namespace FastSim;

/// A planner that knows the rules but not the hidden future. It looks ahead
/// on a copy of the sim whose RNG (and the hidden values already drawn, see
/// `blind_copy`) are replaced by its own random numbers: the copy moves
/// everything visible exactly as the game does, and every random outcome in
/// it is a guess. Beam search over tap / wait, re-planned every `replan`
/// ticks. Tool only (playtest bots).
public sealed class BlindPlanner
{
    /// Ticks looked ahead at most, and at most `past` ticks past the next bounce.
    public long horizon = 200, past = 110;
    /// Ticks between looks when the last look was calm, and when it was not
    /// (no line in some guessed future, or only a fine / shorter line).
    public int replan = 4, replan_danger = 1;
    /// Guessed futures per look, lines compared per look, and the tap timing
    /// error (ticks early and late) a line is tried with. The line played is
    /// the one that lives in the most (future, timing) trials; then the cheapest.
    public int copies = 1, lines = 1, wobble = 0;
    /// Lines differ when they part within this many ticks.
    public int part = 16;
    /// Cost per tick of each px away from the middle height, and per tap (px).
    public long mid_cost = 1, tap_cost = 0;
    /// Extra cost per tick while a bird `margin` px higher or lower would die (0 = not checked).
    public long margin = 16, margin_cost = 2000;
    /// The margin also counts the spikes of the wall ahead, the ceiling and the floor.
    public bool spike_margin = true;
    /// The taps planned for the next ticks (read only; the human layer lands them with timing noise).
    public IReadOnlyCollection<bool> plan => _plan;
    /// Lines never tap twice within `min_gap` ticks (a thumb's limit; 0 = off). `last_press`: the
    /// tick of the player's last real press, set by the caller (the human layer) before decide.
    public long min_gap = 0, last_press = -1000;
    /// Human layer: `frozen` = no new looks (an attention lapse; the old plan runs out),
    /// `mid_offset` = px added to the height the cost pulls to (a player's preferred height).
    public bool frozen;
    /// Noise-aware line choice: each candidate line is replayed `mc_samples` times with every tap
    /// moved by its own N(0, mc_sigma) ticks (a person's thumb), instead of all taps shifted by
    /// `wobble`. The line that lives in most samples is played. 0 = off.
    public int mc_samples;
    public double mc_sigma;
    public long mc_trials;
    public long mid_offset;
    /// One-sided stalactite fangs re-aim at every bounce. In an imagined bounce
    /// the planner takes the worst case: 1 = the column met first comes out as
    /// far as the rule allows, 2 = both columns do. 0 = whatever the copy draws.
    public int worst_fangs = 2;
    /// Rules from the death traces (research/families/*.md), each with a switch:
    /// no_pingpong: a line may not bounce twice on the same wall so that the
    ///   exit opens there, unless its preview was on screen when the look began
    ///   (its height is a guess until then; the wall fills with spikes around it).
    /// keep_plan: when no line lives the whole look, the rest of the old plan
    ///   stays if it still lives in the new copy.
    /// bounce_look: a new look at every change of direction.
    /// wide_key: the bucket also holds the flight direction and x (bumpers and
    ///   wind send lines to different places at the same height).
    /// aim_exit: the height cost pulls to an exit that is on screen instead of the middle.
    /// wall_look: when no line lives the whole look, search to just past the
    ///   wall ahead (the part with nothing to guess) with coarse, fine and
    ///   very fine buckets before trying shorter looks.
    /// full_speeds: the speed buckets span the whole range of fall speeds
    ///   (before, every fall above 3.3 px a tick shared one bucket).
    /// aim_anchor: with no exit on screen the height cost pulls to the room's
    ///   anchor (the next gaps are drawn around it) instead of the middle.
    public bool wall_look = true, full_speeds = false, aim_anchor = false;
    /// aim_wall: with no exit on screen the height cost pulls to the middle of
    ///   the free part of the wall ahead (its nearest free point), for each
    ///   line anew after every bounce. The next wall's sure gap is drawn within
    ///   reach of the middle of what was free on the wall just hit (GameSim.
    ///   _new_wall, a rule a player learns), so from there every next gap is
    ///   nearest. Read from the wall drawn on screen only. Wins over aim_anchor.
    public bool aim_wall = false;
    /// mid_visible: the middle the height cost pulls to (when no exit, wall or
    ///   anchor aim applies) is the middle of the open height on screen: under
    ///   the Crusher's press and over its plate, over the lava line. Without it
    ///   the middle is the cage's (y 320), whatever fills the cage.
    public bool mid_visible = false;

    /// The middle of the open height on screen in `s` (ceiling and floor lines, moved by what covers them).
    public static long visible_mid(GameSim s)
    {
        long top = SimConfig.KILL_TOP, bottom = SimConfig.KILL_BOTTOM;
        foreach (var hz in s.room.hazards)
        {
            if (!hz.alive) continue;
            if (hz is BossCrusher bc && bc.down_at < 0)
            {
                top = Math.Max(top, bc.press_y + BossCrusher.BITE);
                bottom = Math.Min(bottom, bc.plate_y - BossCrusher.BITE);
            }
            else if (hz is Lava lv) bottom = Math.Min(bottom, lv.line);
        }
        return bottom > top ? (top + bottom) / 2 : (SimConfig.KILL_TOP + SimConfig.KILL_BOTTOM) / 2;
    }

    /// Where `aim_wall` pulls a bird flying to the wall ahead of it in `s`.
    public static long wall_aim(GameSim s)
    {
        long mask = drawn(s.state, s.state.vx > 0 ? 1 : 0);
        long lo = -1, hi = -1;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            if (RoomRules.has_slot(mask, slot)) continue;
            if (lo < 0) lo = slot;
            hi = slot;
        }
        if (lo < 0) return (SimConfig.KILL_TOP + SimConfig.KILL_BOTTOM) / 2;
        return anchor_after(mask, (SimConfig.slot_center_y(lo) + SimConfig.slot_center_y(hi)) / 2);
    }
    public long wall_looks;
    public bool no_pingpong = true, keep_plan = true, bounce_look = true, wide_key = false, aim_exit = true;
    public long kept_plans;
    /// Buckets: one survivor per height (px) and speed bucket; the finer set is tried when the first finds no line.
    public long bucket_px = 8, speed_buckets = 6, fine_px = 3, fine_speeds = 12;

    /// Honesty switches (research/planner-review/01-honesty.md), all on. The boss
    /// seed is `boss_blind` (BossBlind).
    /// own_anchor: the copy's anchor_y is the planner's own, tracked from the
    ///   walls it bounced off and the exit it took, never the room's state.anchor_y
    ///   (the user's ruling: the anchor comes only from walls already seen).
    /// hide_keys: a key chain's later keys (shown one at a time) are placed anew.
    public static bool hide_keys = true;
    public bool own_anchor = true;
    public long anchor = SimConfig.BIRD_START_Y;
    long _seen_room = 0, _last_y;
    /// Tests: the memory was set by hand, don't update it from this tick's events.
    public bool skip_observe = false;
    bool _last_open;
    long _last_a, _last_b, _last_b_kind;
    readonly long[] _last_drawn = new long[2];

    static long drawn(SimState s, long side)
    {
        long slots = ExitPlanner.slots(s);
        if (s.exit_open && s.exit_side == side) return ((1L << (int)SimConfig.SLOT_COUNT) - 1) & ~slots;
        long mask = side == 0 ? s.left_spikes : s.right_spikes;
        if (s.exit_preview && s.exit_side == side) mask &= ~slots;
        return mask;
    }

    /// GameSim._anchor_at_wall without the pull to the planned exit.
    public static long anchor_after(long mask, long anchor)
    {
        long best = anchor, best_d = -1, slot = 0;
        while (slot < SimConfig.SLOT_COUNT)
        {
            if (RoomRules.has_slot(mask, slot)) { slot++; continue; }
            long lo = slot;
            while (slot + 1 < SimConfig.SLOT_COUNT && !RoomRules.has_slot(mask, slot + 1)) slot++;
            long y = Math.Clamp(anchor, SimConfig.slot_center_y(lo), SimConfig.slot_center_y(slot));
            long d = Math.Abs(y - anchor);
            if (best_d < 0 || d < best_d) { best = y; best_d = d; }
            slot++;
        }
        return best;
    }

    /// Called once per tick before the tap: what the player saw happen in the last tick.
    public void observe(GameSim sim)
    {
        var s = sim.state;
        if (s.room_index != _seen_room)
        {
            _seen_room = s.room_index;
            if (_last_open)
            {
                bool a = Math.Abs(_last_y - _last_a) <= SimConfig.EXIT_FIT || _last_b_kind == ExitKind.NORMAL;
                long door = _last_b_kind != ExitKind.NORMAL ? SimConfig.FORK_DOOR_Y : (a ? _last_a : _last_b);
                anchor = GameSim._arrival_y(door);
            }
        }
        else if (sim.events.Contains(Event.BOUNCE))
            anchor = anchor_after(_last_drawn[s.vx > 0 ? 0 : 1], anchor);
        _last_y = s.y;
        _last_drawn[0] = drawn(s, 0);
        _last_drawn[1] = drawn(s, 1);
        _last_open = s.exit_open;
        _last_a = s.exit_a_y;
        _last_b = s.exit_b_y;
        _last_b_kind = s.exit_b_kind;
    }

    /// Plan reuse (0 = off): after a calm look the plan is followed for up to
    /// `follow` ticks without a new look, as long as it still lives on a copy
    /// made with the same guesses as that look (checked every `replan` ticks,
    /// at the cost of one line instead of a whole search). Something new on
    /// screen that the guess had wrong kills the line in the copy: then it looks.
    public int follow = 0;
    /// Lines may tap whenever the bird's upward speed is under this (the default
    /// keeps taps about 12 ticks apart, so a line can't climb faster than 3.75 px a tick).
    public long tap_below = SurvivalSearch.TAP_BELOW_VY;
    /// Free tap timing that the buckets can hold: a line may tap again as soon
    /// as it has left the speed bucket of a fresh tap (upward speed under
    /// FLAP_VY + one bucket). Any sooner, a line that taps and its twin that
    /// does not share a bucket, the cheaper one (the tap, below the aimed
    /// height) wins every tick, and no line can ever start to fall: with
    /// `tap_below` at "always" the whole search climbs into the ceiling
    /// (measured: 3.1 deaths per 100 points against 0.05). With 12 speed
    /// buckets this is a tap every 5 ticks (4.5 px a tick up, against 3.75).
    public bool tap_free = false;
    /// When no line lives the whole look: play the line that lived longest in
    /// that same search (it is already there) instead of searching again
    /// to the wall and with 3/4, 9/16, ... of the look.
    /// Measured harmful (seeds 1..200, cap 20,000: 43 deaths against 31, ceiling
    /// deaths 16 against 6): the longest line of a failed look often ends at the
    /// ceiling, and the search to the wall it skips is the part with nothing to
    /// guess. Kept off; for measuring only.
    public bool longest = false;
    byte[] _deep;
    long _deep_len, _deep_cost;
    /// Measurement only: look ahead on true copies (the hidden future as it will be).
    /// Shows what the same search does with nothing to guess.
    public bool peek = false;
    public long follows, follow_fails;
    long _guess;
    int _since_look;
    bool _calm;

    readonly SimRng _own;
    readonly Queue<bool> _plan = new();
    int _since = int.MaxValue;
    int _wait = 1;
    long _bounce_y = -1, _vx;
    readonly List<(byte[] taps, long cost, GameSim sim)> _found = new();
    /// How the last look ended: 0 = a line for the whole look, 1 = only with fine buckets, 2 = only a shorter look, 3 = none.
    public int last_look;
    /// In how many of the guessed futures the played line lived (of `copies`).
    public int last_agree;
    public long looks, fine_looks, short_looks, no_looks, split_looks;
    /// The last look's first guessed-future seed (blind_copy(sim, new SimRng(it)) is its copy)
    /// and the plan it left (read by the autopsy).
    public long last_seed0;
    /// The anchor the last look's copies used (-1 = the room's own).
    public long last_anchor = -1;
    public bool[] last_plan = Array.Empty<bool>();
    /// Sim steps spent looking ahead (the planner's CPU cost; the game's own ticks are not counted).
    public long steps;

    public BlindPlanner(long seed) => _own = new SimRng(977 * seed + 5);

    /// Whether the rest of the plan in hand lives in a fresh copy of what is on
    /// screen now (false with no plan), guessed the same way as the look that made
    /// it, so only something new on screen can kill it. The human layer asks when a
    /// new warning shows.
    public bool plan_lives(GameSim sim)
    {
        if (_plan.Count == 0) return false;
        var rest = _plan.Select(b => (byte)(b ? 1 : 0)).ToArray();
        return lives(blind_copy(sim, new SimRng(_guess), _bounce_y, reveal, own_anchor ? anchor : -1, boss_unseen, boss_leak), rest, 0);
    }

    public bool decide(GameSim sim)
    {
        if (!skip_observe) observe(sim);
        if (!sim.state.started) return true;
        // The height at the last bounce: a player remembers it (stalactite gaps slide to it).
        if (sim.state.vx != _vx)
        {
            if (_vx != 0) _bounce_y = sim.state.y;
            if (_vx != 0 && bounce_look) _since = int.MaxValue;
            _vx = sim.state.vx;
        }
#if PROF
        long p0 = Prof.now();
#endif
        if (!frozen && (_since >= _wait || _plan.Count == 0))
        {
            bool kept = false;
            if (follow > 0 && _since != int.MaxValue && _calm && _plan.Count >= 24 && _since_look + _since < follow)
            {
                var rest = _plan.Select(b => (byte)(b ? 1 : 0)).ToArray();
                kept = lives(peek ? sim.clone_deep() : blind_copy(sim, new SimRng(_guess), _bounce_y, reveal, own_anchor ? anchor : -1, boss_unseen, boss_leak), rest, 0);
                if (kept)
                {
                    follows++;
                    _since_look += _since;
                    _since = 0;
                }
                else follow_fails++;
            }
            if (!kept)
            {
                look(sim);
                _since_look = 0;
                last_plan = _plan.ToArray();
            }
        }
#if PROF
        Prof.add(Prof.LOOK, p0);
#endif
        _since++;
        bool tap = _plan.Count > 0 && _plan.Dequeue();
        // The sim ignores taps during the wait out of a portal: don't make them.
        return tap && sim.state.arrival_hold == 0;
    }

    void look(GameSim sim)
    {
        long want = Math.Min(horizon, sim.steps_to_wall(sim.state.vx > 0 ? 1 : 0) + past);
        looks++;
        last_look = 0;
        int n = Math.Max(1, copies);
        var seeds = new long[n];
        for (int j = 0; j < n; j++) seeds[j] = _own.next_u32();
        last_seed0 = seeds[0];
        last_anchor = own_anchor ? anchor : -1;
        _guess = seeds[0];
        _calm = false;
        GameSim copy(int j) => peek ? sim.clone_deep() : blind_copy(sim, new SimRng(seeds[j]), _bounce_y, reveal, own_anchor ? anchor : -1, boss_unseen, boss_leak);
        long to_wall = sim.steps_to_wall(sim.state.vx > 0 ? 1 : 0);
        // Lines from the first guessed future (fine buckets when the coarse ones find none).
        _deep = null;
        _deep_len = 0;
        beam(copy(0), want, bucket_px, speed_buckets);
        if (_found.Count == 0 && fine_px > 0)
        {
            last_look = 1;
            fine_looks++;
            beam(copy(0), want, fine_px, fine_speeds);
        }
        byte[] found = null;
        last_agree = 0;
        _noise_base = _noise.next_u32();
        int trials = mc_samples > 0 ? n * mc_samples : n * (1 + 2 * (wobble > 0 ? 1 : 0));
        if (_found.Count > 0 && trials == 1)
        {
            found = _found[0].taps;
            last_agree = 1;
        }
        else if (_found.Count > 0)
        {
            long best_cost = 0;
            foreach (var (taps, cost, _) in _found.ToList())
            {
                int ok = 0;
                for (int j = 0; j < n; j++)
                    if (mc_samples > 0)
                        for (int k = 0; k < mc_samples; k++)
                        {
                            mc_trials++;
                            if (lives(copy(j), jitter(taps, k), 0)) ok++;
                        }
                    else
                        for (int w = -1; w <= 1; w++)
                        {
                            if (w != 0 && wobble == 0) continue;
                            if (lives(copy(j), taps, w * wobble)) ok++;
                        }
                if (found == null || ok > last_agree || (ok == last_agree && cost < best_cost))
                {
                    found = taps;
                    last_agree = ok;
                    best_cost = cost;
                }
            }
        }
        if (found == null && keep_plan && _plan.Count >= 8)
        {
            var rest = _plan.Select(b => (byte)(b ? 1 : 0)).ToArray();
            if (lives(copy(0), rest, 0))
            {
                kept_plans++;
                last_look = 2;
                short_looks++;
                _wait = replan_danger;
                _since = 0;
                return;
            }
        }
        if (found == null && longest && _deep != null)
        {
            found = _deep;
            last_look = 2;
        }
        if (found == null && wall_look && to_wall + 26 < want)
        {
            foreach (var (px, sp) in new[] { (bucket_px, speed_buckets), (fine_px, fine_speeds), (2L, 40L) })
            {
                beam(copy(0), to_wall + 26, px, sp);
                if (_found.Count == 0) continue;
                found = _found[0].taps;
                last_look = 2;
                wall_looks++;
                break;
            }
        }
        for (long t = want * 3 / 4; t >= 2 && found == null; t = t * 3 / 4)
        {
            last_look = 2;
            beam(copy(0), t, bucket_px, speed_buckets);
            if (_found.Count == 0 && fine_px > 0 && keep_plan) beam(copy(0), t, fine_px, fine_speeds);
            if (_found.Count > 0) found = _found[0].taps;
        }
        if (last_look == 2) short_looks++;
        if (found == null)
        {
            last_look = 3;
            no_looks++;
        }
        bool danger = last_look != 0 || last_agree < trials;
        if (last_look == 0 && last_agree < trials) split_looks++;
        _wait = danger ? replan_danger : replan;
        _calm = !danger;
        _plan.Clear();
        if (found != null)
            foreach (byte b in found) _plan.Enqueue(b != 0);
        _since = 0;
    }

    /// After a bounce in a copy: one-sided fangs aim as far out as their rule
    /// allows (within REACH of the anchor for the column met first, MAX_STEP
    /// past that for the other when `both`).
    static void fangs_out(GameSim c, bool both)
    {
        List<Stalactite> cols = null;
        foreach (var hz in c.room.hazards)
            if (hz is Stalactite st && st.fixed_lo < 0 && st.top != st.bottom) (cols ??= new()).Add(st);
        if (cols == null) return;
        cols.Sort((p, q) => c.state.vx > 0 ? p.x.CompareTo(q.x) : q.x.CompareTo(p.x));
        long center = c.state.anchor_y, spread = Stalactite.REACH;
        for (int i = 0; i < cols.Count; i++)
        {
            var st = cols[i];
            if (i == 0 || both)
                st.target_y = st.bottom ? Math.Max(Stalactite.GAP_MIN, center - spread) : Math.Min(Stalactite.GAP_MAX, center + spread);
            center = st.target_y;
            spread = Stalactite.MAX_STEP;
        }
    }

    readonly SimRng _noise = new(424242);
    /// `taps` with every tap after the first few ticks moved by its own N(0, mc_sigma) ticks
    /// (sample k of a look; the same k gives each candidate the same noise draws).
    byte[] jitter(byte[] taps, int k)
    {
        var r = new SimRng(_noise_base + 7919L * k);
        var o = new byte[taps.Length];
        for (int t = 0; t < taps.Length; t++)
        {
            if (taps[t] == 0) continue;
            double u1 = (r.next_u32() + 1.0) / 4294967297.0, u2 = r.next_u32() / 4294967296.0;
            int d = (int)Math.Round(Math.Sqrt(-2 * Math.Log(u1)) * Math.Cos(2 * Math.PI * u2) * mc_sigma);
            int at = Math.Clamp(t + d, 0, taps.Length - 1);
            o[at] = 1;
        }
        return o;
    }
    long _noise_base;

    /// Whether the bird lives through `taps` on `c`, with every tap `shift` ticks late (early if negative).
    bool lives(GameSim c, byte[] taps, int shift)
    {
#if PROF
        long p0 = Prof.now();
        try { return lives_(c, taps, shift); } finally { Prof.add(Prof.LIVES, p0); }
    }

    static bool lives_(GameSim c, byte[] taps, int shift)
    {
#endif
        for (int t = 0; t < taps.Length; t++)
        {
            steps++;
            int from = t - shift;
            c.step(from >= 0 && from < taps.Length && taps[from] != 0);
            if (c.is_over()) return false;
        }
        return true;
    }

    /// A copy of `sim` with every hidden random value replaced by `own`'s.
    /// Measurement only: copies keep the room's true planned exits (hazards
    /// treat those mouths as walls from the room's start, ExitZone, before
    /// they are drawn). True = the planner knows where the exits will be.
    public static bool know_exits = false;
    /// Measurement only: the copy keeps the room's true wall seed (knows every next wall),
    /// or is a plain copy (knows everything).
    public static bool know_walls = false, know_all = false;

    /// Boss rooms: every attack is drawn from the boss's hidden seed, so the
    /// copy gets its own seed too (the attack being told stays: BossBlind).
    /// False = the planner knows every future attack (a leak; measuring only).
    public static bool boss_blind = true;

    /// `bounce_y`: the bird's height at its last bounce if the player saw it (-1 = not).
    /// Measuring only (Human/Atlas.cs): bits of `Reveal` that leave one kind of
    /// hidden value as it truly is in the copy. 0 = everything hidden (play).
    public int reveal = 0;
    /// Boss rooms (research/planner-review/07-bosses.md): `boss_unseen`: the
    /// tell now on screen has not been taken in yet (set by the human layer
    /// for a reaction time), so it is a guess as well (with `boss_blind`).
    /// `boss_leak` (measuring only): this planner's copies keep the true boss seed.
    public bool boss_unseen = false, boss_leak = false;

    public static class Reveal
    {
        public const int RNG = 1, WALLSEED = 2, SPINE = 4, EXITS = 8, STALAC = 16, SALTS = 32, PRIVRNG = 64,
            BUBBLE = 128, KEEPY = 256, BEAM = 512, UPDRAFT = 1024, BOSS = 2048, ALL = 4095;
        public static readonly (string name, int bit)[] KINDS =
        {
            ("rng", RNG), ("wallseed", WALLSEED), ("spine", SPINE), ("exits", EXITS), ("stalac", STALAC), ("salts", SALTS),
            ("privrng", PRIVRNG), ("bubble", BUBBLE), ("keepy", KEEPY), ("beam", BEAM), ("updraft", UPDRAFT), ("boss", BOSS),
        };
    }

    /// `own_anchor`: the planner's own room anchor, tracked from walls it saw (-1 = keep the copy's).
    /// `boss_unseen`: the boss tell on screen is not taken in yet (a guess too).
    public static GameSim blind_copy(GameSim sim, SimRng own, long bounce_y = -1, int reveal = 0, long own_anchor = -1, bool boss_unseen = false, bool boss_leak = false)
    {
#if PROF
        long p0 = Prof.now();
        var c = blind_copy_(sim, own, bounce_y, reveal, own_anchor, boss_unseen, boss_leak);
        Prof.add(Prof.BLIND, p0);
        return c;
    }

    static GameSim blind_copy_(GameSim sim, SimRng own, long bounce_y, int reveal, long own_anchor, bool boss_unseen, bool boss_leak)
    {
#endif
        var c = sim.clone_deep();
        c.memo_arrivals = true;
        if (know_all) return c;
        bool R(int bit) => (reveal & bit) != 0;
        if (own_anchor >= 0) c.state.anchor_y = own_anchor;
        // The run's seed and the room as entered (kept for a revive, with both RNGs) hold the
        // true draws. A look never revives: the copy does not carry them.
        c.seed_value = 0;
        c._entry_room = null;
        c._entry_state = null;
        c._entry_rng = null;
        c._entry_spine = null;
        long true_seed = c.room.rng_seed;
        { var x = own.next_u32(); if (!R(Reveal.RNG)) c._rng = new SimRng(x); }
        // Seed-only generation: each wall reseeds from the room's seed, the
        // spine picks the next rooms, and the exits are planned from the room's
        // seed at room start. All three are hidden: replace them and plan again
        // (plan_room keeps an exit already on screen as it is).
        { var x = own.next_u32(); if (!R(Reveal.WALLSEED)) c.room.rng_seed = x; }
        { var x = own.next_u32(); if (!R(Reveal.SPINE)) c._spine = new SimRng(x); }
        if (know_walls) c.room.rng_seed = true_seed;
        // Each wall's draws come from the room's seed and how many walls the room
        // has drawn. With a seed of its own the count tells the copy nothing, but
        // its guesses would still change with it: keep only what the rules ask of
        // it (none yet, the first, later ones), so no look depends on a count the
        // screen does not show.
        if (!know_walls && !R(Reveal.WALLSEED)) c.room.walls = Math.Min(c.room.walls, 2);
        if (c.state.plan_at != 0 && !know_exits && !R(Reveal.EXITS)) ExitPlanner.plan_room(c, c.state.plan_at);
        // Sliding stalactite gaps: the column the bird met first slides to
        // within REACH of the height it bounced at, the other to within
        // MAX_STEP of that (the room's rule, which a player learns).
        // On seed-only generation the room slides them to state.anchor_y (the
        // exit taken or the open run on the last wall: on screen), so that is used.
        bounce_y = c.state.anchor_y;
        if (bounce_y >= 0 && !R(Reveal.STALAC))
        {
            var cols = c.room.hazards.OfType<Stalactite>().Where(st => st.fixed_lo < 0).ToList();
            cols.Sort((p, q) => c.state.vx > 0 ? p.x.CompareTo(q.x) : q.x.CompareTo(p.x));
            long center = bounce_y, spread = Stalactite.REACH;
            foreach (var st in cols)
            {
                if (st.gap_y != st.target_y)
                {
                    long lo = Math.Max(Stalactite.GAP_MIN, center - spread), hi = Math.Min(Stalactite.GAP_MAX, center + spread);
                    // Only the side it is seen sliding to.
                    if (st.target_y > st.gap_y) lo = Math.Max(lo, st.gap_y + 1);
                    else hi = Math.Min(hi, st.gap_y - 1);
                    // A fang from one side only: the worst case (its tip as far out as it may go).
                    if (lo > hi) st.target_y = st.gap_y + (st.target_y > st.gap_y ? 1 : -1) * own.next_below(Stalactite.SLIDE * 8 + 1);
                    else if (st.bottom && !st.top) st.target_y = lo;
                    else if (st.top && !st.bottom) st.target_y = hi;
                    else st.target_y = lo + own.next_below(hi - lo + 1);
                }
                center = st.target_y;
                spread = Stalactite.MAX_STEP;
            }
        }
        // Values the sim has already drawn but not yet shown. A value that is
        // on screen (a warning, a marked column, a moving thing) stays.
        foreach (var hz in c.room.hazards)
        {
            int kind = hz switch
            {
                CrateDrop or Dart => Reveal.SALTS, Drop or Firework or OrchardSpawner => Reveal.PRIVRNG,
                Bubble => Reveal.BUBBLE, Stalactite => Reveal.STALAC, KeepyBall => Reveal.KEEPY,
                Beam => Reveal.BEAM, Updraft => Reveal.UPDRAFT, Boss => Reveal.BOSS, _ => 0,
            };
            if (kind != 0 && R(kind)) continue;
            if (hz is Boss bs && boss_blind && !boss_leak) BossBlind.scramble(bs, own, boss_unseen);
            switch (hz)
            {
                // Hash salts and private RNGs: where every later crate, dart, drop, rocket and coin goes.
                case CrateDrop cd: cd.salt = own.next_u32(); break;
                case Dart d: d.salt = own.next_u32(); break;
                case Drop dr: dr._rng.reseed(own.next_u32()); break;
                case Firework fw: fw._rng.reseed(own.next_u32()); break;
                case OrchardSpawner os: os._rng.reseed(own.next_u32()); break;
                // Where the bubble comes back after its next pop.
                case Bubble b:
                    b.next_x = Bubble.MIN_X + own.next_below(Bubble.MAX_X - Bubble.MIN_X + 1);
                    // A late spiky bubble under the floor: its glow (bubble_painter.gd) is
                    // under half size until 3 * WARN ticks before it rises.
                    if (b.spiked && b.wait > 3 * Bubble.WARN) b.x = Bubble.MIN_X + own.next_below(Bubble.MAX_X - Bubble.MIN_X + 1);
                    break;
                // Where a sliding gap stops: the side it slides to is visible, how far is not.
                case Stalactite st when st.gap_y != st.target_y && (bounce_y < 0 || st.fixed_lo >= 0):
                {
                    long far = own.next_below(Stalactite.REACH + Stalactite.MAX_STEP + 1);
                    long to = st.gap_y + (st.target_y > st.gap_y ? far : -far);
                    st.target_y = G.clampi(to, Stalactite.GAP_MIN, Stalactite.GAP_MAX);
                    break;
                }
                // A key chain: where each later key appears is drawn at the room's start.
                case ExitKey ek when hide_keys && ek.mode == ExitKey.Mode.CHAIN:
                    for (long i = ek.got + 1; i < ek.count; i++)
                    {
                        ek.chain_off[i] = ExitKey.KEY_OFF_MIN + own.next_below(ExitKey.CHAIN_OFF_MAX - ExitKey.KEY_OFF_MIN + 1);
                        ek.chain_d[i] = ExitKey.CHAIN_D_MIN + own.next_below(ExitKey.CHAIN_D_MAX - ExitKey.CHAIN_D_MIN + 1);
                    }
                    break;
                // The second ball's column before it drops in.
                case KeepyBall kb when kb.waiting > 0 && c.room.t < KeepyBall.SECOND_DROP:
                    kb.x = KeepyBall.MIN_X + own.next_below(KeepyBall.MAX_X - KeepyBall.MIN_X + 1);
                    break;
                // The order rows fire in, among rows that have not warned yet.
                case Beam bm:
                {
                    var idle = new List<int>();
                    for (int i = 0; i < bm.delays.Count; i++)
                        if (bm.t < bm.delays[i]) idle.Add(i);
                    // Sorted first, so the result does not depend on the true order.
                    var waits = idle.Select(i => bm.delays[i]).OrderBy(x => x).ToList();
                    for (int i = 0; i < idle.Count; i++) bm.delays[idle[i]] = waits[i];
                    for (int i = idle.Count - 1; i > 0; i--)
                    {
                        int j = (int)own.next_below(i + 1);
                        (bm.delays[idle[i]], bm.delays[idle[j]]) = (bm.delays[idle[j]], bm.delays[idle[i]]);
                    }
                    break;
                }
                // A gusty updraft's first gust: no countdown is shown.
                case Updraft up when up.drift_span == 0 && up.gust != Updraft.Gust.NONE && up.t + up.phase < Updraft.GUST_OFF:
                    up.phase = own.next_below(Updraft.GUST_OFF - up.t);
                    break;
            }
        }
        return c;
    }

    /// Reuse the sims of lines that died or lost their bucket (Bots/SimPool.cs); off = allocate every copy.
    public static bool pool = true;
    readonly Stack<GameSim> _pool = new();

    GameSim clone(GameSim s) => pool && _pool.Count > 0 ? SimPool.copy(s, _pool.Pop()) : s.clone_deep();

    void drop(GameSim s)
    {
        if (pool && _pool.Count < 4096) _pool.Push(s);
    }

    struct Node
    {
        public GameSim sim;
        public int parent;
        public byte tap;
        public long cost;
        public long since; // ticks since this line's last tap
        public long aim; // the height its cost pulls to
    }

    /// Fills `_found` with up to `lines` lines that live `ticks` ticks,
    /// cheapest first: the cheapest of each family of lines that share their first `part` ticks.
    void beam(GameSim root, long ticks, long bpx, long speeds)
    {
#if PROF
        long p0 = Prof.now();
        try { beam_(root, ticks, bpx, speeds); } finally { Prof.add(Prof.BEAM, p0); }
    }

    void beam_(GameSim root, long ticks, long bpx, long speeds)
    {
#endif
        _found.Clear();
        var layer = new List<int>();
        long bh = bpx * SimConfig.SUB;
        long bvy = full_speeds ? (SimConfig.MAX_FALL_VY - SimConfig.FLAP_VY) / speeds + 1 : -SimConfig.FLAP_VY * 2 / speeds;
        long tap_from = tap_free ? SimConfig.FLAP_VY + bvy : tap_below;
        long mid = mid_visible ? visible_mid(root) : (SimConfig.KILL_TOP + SimConfig.KILL_BOTTOM) / 2;
        bool exit_shown = root.state.exit_open || root.state.exit_preview;
        if (aim_exit && exit_shown) mid = root.state.exit_a_y;
        else if (aim_wall) mid = wall_aim(root);
        else if (aim_anchor) mid = root.state.anchor_y;
        if (!(aim_exit && exit_shown)) mid += mid_offset * SimConfig.SUB;
        bool re_aim = aim_wall && !(aim_exit && exit_shown);
        var parents = new List<int>();
        var taps = new List<byte>();
        var frontier = new List<Node> { new Node { sim = root, parent = -1, since = root.state.tick - last_press, aim = mid } };
        var slots = new Dictionary<long, int>();
        var next = new List<Node>();
        for (long t = 0; t < ticks; t++)
        {
            slots.Clear();
            next.Clear();
            foreach (var e in frontier)
            {
                bool can_tap = e.sim.state.vy * e.sim.room.gravity > tap_from
                               && (min_gap <= 0 || e.since >= min_gap);
                long vx0 = e.sim.state.vx, room0 = e.sim.state.room_index;
                bool e_open = e.sim.state.exit_open;
                for (int a = can_tap ? 1 : 0; a >= 0; a--)
                {
#if PROF
                    long q0 = Prof.now();
                    var s = a == 1 ? clone(e.sim) : e.sim;
                    if (a == 1) Prof.add(Prof.CLONE, q0);
                    q0 = Prof.now();
                    s.step(a == 1);
                    Prof.add(Prof.STEP, q0);
#else
                    var s = a == 1 ? clone(e.sim) : e.sim;
                    s.step(a == 1);
#endif
                    steps++;
                    if (s.is_over())
                    {
                        drop(s);
                        continue;
                    }
                    // The exit opened on the wall the bird just bounced off, at a height nobody has seen.
                    if (no_pingpong && !exit_shown && s.state.exit_open && !e_open && s.state.exit_side == (s.state.vx > 0 ? 0 : 1))
                    {
                        drop(s);
                        continue;
                    }
                    if (worst_fangs > 0 && (s.state.vx != vx0 || s.state.room_index != room0)) fangs_out(s, worst_fangs > 1);
                    var st = s.state;
                    long aim = e.aim;
                    if (re_aim && (st.vx != vx0 || st.room_index != room0))
                        aim = aim_exit && (st.exit_open || st.exit_preview) ? st.exit_a_y : wall_aim(s) + mid_offset * SimConfig.SUB;
                    long cost = e.cost + Math.Abs(st.y - aim) / SimConfig.SUB * mid_cost + a * tap_cost;
#if PROF
                    long q1 = Prof.now();
                    if (margin > 0 && near_death(s)) cost += margin_cost;
                    Prof.add(Prof.NEAR, q1);
#else
                    if (margin > 0 && near_death(s)) cost += margin_cost;
#endif
                    long along = st.vy * s.room.gravity - SimConfig.FLAP_VY;
                    long speed = G.clampi(along / bvy, 0, speeds - 1);
                    long key = (st.room_index * 1000 + st.y / bh) * speeds + speed;
                    if (wide_key) key = (key * 64 + st.x / (16 * SimConfig.SUB)) * 2 + (st.vx > 0 ? 1 : 0);
                    var node = new Node { sim = s, parent = e.parent, tap = (byte)a, cost = cost, since = a == 1 ? 1 : e.since + 1, aim = aim };
                    if (slots.TryGetValue(key, out int at))
                    {
                        if (cost < next[at].cost)
                        {
                            drop(next[at].sim);
                            next[at] = node;
                        }
                        else drop(s);
                    }
                    else
                    {
                        slots[key] = next.Count;
                        next.Add(node);
                    }
                }
            }
            if (next.Count == 0)
            {
                if (longest && t > 0)
                {
                    var top = frontier[0];
                    foreach (var e in frontier)
                        if (e.cost < top.cost) top = e;
                    if (t > _deep_len || (t == _deep_len && top.cost < _deep_cost))
                    {
                        var line = new List<byte>();
                        for (int nd = top.parent; nd >= 0; nd = parents[nd]) line.Add(taps[nd]);
                        line.Reverse();
                        _deep = line.ToArray();
                        _deep_len = t;
                        _deep_cost = top.cost;
                    }
                }
                return;
            }
            layer.Add(parents.Count);
            frontier = new List<Node>(next.Count);
            foreach (var e in next)
            {
                parents.Add(e.parent);
                taps.Add(e.tap);
                frontier.Add(new Node { sim = e.sim, parent = parents.Count - 1, cost = e.cost, since = e.since, aim = e.aim });
            }
        }
        // The family of a line: its node `part` ticks in.
        long depth = Math.Min(part, ticks) - 1;
        int family_end = depth + 1 < layer.Count ? layer[(int)depth + 1] : parents.Count;
        long room = frontier.Max(e => e.sim.state.room_index);
        var best = new Dictionary<int, Node>();
        foreach (var e in frontier)
        {
            if (e.sim.state.room_index != room) continue;
            int f = e.parent;
            while (f >= family_end) f = parents[f];
            if (!best.TryGetValue(f, out var have) || e.cost < have.cost) best[f] = e;
        }
        foreach (var e in best.Values.OrderBy(e => e.cost).Take(Math.Max(1, lines)))
        {
            var out_ = new List<byte>();
            for (int nd = e.parent; nd >= 0; nd = parents[nd]) out_.Add(taps[nd]);
            out_.Reverse();
            _found.Add((out_.ToArray(), e.cost, e.sim));
        }
    }

    static bool near_spikes(GameSim s, long y, long m)
    {
        var st = s.state;
        long r = SimConfig.BIRD_RADIUS;
        if (y - m - r <= SimConfig.KILL_TOP || y + m + r >= SimConfig.KILL_BOTTOM) return true;
        long side = st.vx > 0 ? 1 : 0;
        long dist = (side == 1 ? s.room.wall_right() - st.x : st.x - s.room.wall_left()) - r;
        if (dist > s.room.max_spike_depth()) return false;
        long mask = s.wall_mask(side);
        if (mask == 0) return false;
        long shift = s.wall_shift(side), hb = s.room.spike_half_base();
        return Rl.Observer.wall_hits(mask, shift, hb, y - m) || Rl.Observer.wall_hits(mask, shift, hb, y + m);
    }

    /// Whether a bird `margin` px above or below this one would be killed by a hazard now
    /// (or, with `spike_margin`, by the spikes of the wall ahead, the ceiling or the floor).
    bool near_death(GameSim s)
    {
        var hz = s.room.hazards;
        long y = s.state.y;
        if (spike_margin && near_spikes(s, y, margin * SimConfig.SUB)) return true;
        if (hz.Count == 0) return false;
        bool bad = false;
        for (int d = -1; d <= 1 && !bad; d += 2)
        {
            s.state.y = y + d * margin * SimConfig.SUB;
            for (int h = 0; h < hz.Count && !bad; h++)
                if (hz[h].alive && hz[h].kills(s)) bad = true;
        }
        s.state.y = y;
        return bad;
    }
}
