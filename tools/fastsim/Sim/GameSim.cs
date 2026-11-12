namespace FastSim;

public static class Event
{
    public const int START = 0, FLAP = 1, BOUNCE = 2, SCORE = 3, ROOM_CHANGE = 4, DEATH = 5,
        COIN_SPAWN = 6, COIN = 7, EXIT_OPEN = 8, EXIT_PREVIEW = 9, REVIVE = 10, BOSS_DOWN = 11;
}

/// Port of sim/game_sim.gd. Same names, same order of everything.
/// Loops over room.hazards use indexes and re-read Count, like GDScript's
/// array iteration, so a hazard added during a loop is visited too.
public sealed class GameSim
{
    public const long BUMP_VY = -SimConfig.FLAP_VY * 6 / 5;
    public const long ARRIVAL_WALL_SPARE = 30;
    public const long PRACTICE_START_GAP = 40 * SimConfig.SUB;
    public static readonly long[] ARRIVAL_HEIGHTS = { 0, -SimConfig.EXIT_FIT, SimConfig.EXIT_FIT, -SimConfig.EXIT_FIT / 2, SimConfig.EXIT_FIT / 2 };

    public long seed_value;
    public long season;
    public long practice_room = -1;
    /// Bots only: the variant id to play in place of the drawn one ("" = the drawn one).
    public string forced_variant = "";
    public SimState state = new SimState();
    public RoomRuntime room = new RoomRuntime();
    public List<int> events = new List<int>(8);
    public SimRng _rng;
    public SimRng _spine;
    public bool _checking = false;
    /// Bots only, never in the game: a planner copy remembers arrival checks (Bots/ArrivalMemo.cs).
    public bool memo_arrivals = false;
    /// The room, the whole state and both RNGs as the bird came in, for a revive. Never changed after
    /// it is taken, so clones share it (GDScript's SimCopy copies it).
    public long _arrival_wait = SimConfig.PORTAL_HOLD;
    public long _free_lo = -1;
    public long _free_hi = -1;
    public RoomRuntime _entry_room = null;
    public SimState _entry_state = null;
    public SimRng _entry_rng = null;
    public SimRng _entry_spine = null;

    GameSim() { }

    public GameSim(long p_seed, long p_season = Seasons.NONE, long p_practice_room = -1, string p_variant = "")
    {
        seed_value = p_seed;
        season = p_season;
        forced_variant = p_variant;
        _spine = new SimRng(p_seed);
        _rng = new SimRng(0);
        _seed_room();
        if (p_practice_room >= 0 && p_practice_room < RoomCatalog.all().Count)
        {
            practice_room = p_practice_room;
            state.score = RoomCatalog.all()[(int)practice_room].from_score;
            state.x = PRACTICE_START_GAP;
            _enter_room(practice_room);
            ExitPlanner.plan_room(this, next_exit_score());
        }
        else
        {
            _enter_room(RoomCatalog.first_index());
            ExitPlanner.plan_room(this, next_exit_score());
            _keep_entry();
        }
    }

    /// Deep copy (what SimClone.copy does in GDScript).
    public GameSim clone_deep()
    {
        var c = new GameSim();
        c.seed_value = seed_value;
        c.season = season;
        c.practice_room = practice_room;
        c.forced_variant = forced_variant;
        c.state = state.copy();
        c.room = room.clone_deep();
        c.events = new List<int>(events);
        c._rng = _rng.Clone();
        c._spine = _spine.Clone();
        c._arrival_wait = _arrival_wait;
        c._checking = _checking;
        c.memo_arrivals = memo_arrivals;
        c._entry_room = _entry_room;
        c._entry_state = _entry_state;
        c._entry_rng = _entry_rng;
        c._entry_spine = _entry_spine;
        return c;
    }

    public bool is_practice() => practice_room >= 0;

    public bool is_over() => !state.alive;

    public void step(bool tap)
    {
        events.Clear();
        if (!state.alive) return;
        if (state.arrival_hold > 0)
        {
            state.arrival_hold -= 1;
            state.tick += 1;
            return;
        }
        if (tap)
        {
            if (!state.started)
            {
                state.started = true;
                events.Add(Event.START);
            }
            state.vy = SimConfig.FLAP_VY * room.gravity;
            state.flaps += 1;
            for (int i = 0; i < room.hazards.Count; i++)
                if (room.hazards[i].alive) room.hazards[i].on_flap(this);
            events.Add(Event.FLAP);
        }
        if (state.started)
        {
            long n = room.steps_this_tick();
            for (long i = 0; i < n; i++)
            {
                _substep();
                if (!state.alive) break;
            }
            room.ticks += 1;
        }
        state.tick += 1;
    }

    public bool can_revive() => !state.alive && !is_practice() && state.revives < SimConfig.MAX_REVIVES;

    public bool revive()
    {
        if (!can_revive()) return false;
        events.Clear();
        long tick = state.tick;
        long revives = state.revives + 1;
        long flaps = state.flaps;
        state.assign(_entry_state);
        state.tick = tick;
        state.revives = revives;
        state.flaps = flaps;
        state.started = true;
        state.arrival_hold = SimConfig.ARRIVAL_HOLD;
        room = _entry_room.clone_deep();
        _rng = _entry_rng.Clone();
        _spine = _entry_spine.Clone();
        _free_lo = -1;
        _free_hi = -1;
        events.Add(Event.REVIVE);
        return true;
    }

    public long wall_mask(long side)
    {
        if (state.exit_open && state.exit_side == side)
        {
            long open = ((1L << (int)SimConfig.SLOT_COUNT) - 1) & ~ExitPlanner.slots(state);
            return open;
        }
        long mask = room.wall_mask(side, side == 0 ? state.left_spikes : state.right_spikes);
        if (state.exit_preview && state.exit_side == side) mask &= ~ExitPlanner.slots(state);
        return mask;
    }

    public long wall_shift(long side)
    {
        long out_ = 0;
        for (int i = 0; i < room.hazards.Count; i++)
        {
            var h = room.hazards[i];
            if (h.alive) out_ += h.wall_shift(this, side);
        }
        return out_;
    }

    public bool exit_locked()
    {
        for (int i = 0; i < room.hazards.Count; i++)
        {
            var h = room.hazards[i];
            if (h.alive && h.locks_exit(this)) return true;
        }
        return false;
    }

    public long checksum() => SimHash.mix(SimHash.mix(room.checksum(state.checksum()), _rng.state_checksum()), _spine.state_checksum());

    // --- Helpers for hazards ---

    public bool bird_touches_circle(long cx, long cy, long r)
    {
        long dx = state.x - cx;
        long dy = state.y - cy;
        long reach = SimConfig.BIRD_RADIUS + r;
        return dx * dx + dy * dy <= reach * reach;
    }

    public bool bird_touches_rect(long x0, long y0, long x1, long y1)
    {
        long nx = G.clampi(state.x, G.mini(x0, x1), G.maxi(x0, x1));
        long ny = G.clampi(state.y, G.mini(y0, y1), G.maxi(y0, y1));
        long dx = state.x - nx;
        long dy = state.y - ny;
        long r = SimConfig.BIRD_RADIUS;
        return dx * dx + dy * dy <= r * r;
    }

    public void bump_bird_from(long cx, long cy)
    {
        state.vy = state.y < cy ? -BUMP_VY : BUMP_VY;
        if ((state.x < cx) == (state.vx > 0)) state.vx = -state.vx;
    }

    public void collect_coin(long x, long y, long amount = 1)
    {
        state.coins += amount;
        state.pickup_x = x;
        state.pickup_y = y;
        events.Add(Event.COIN);
    }

    public void kill(long cause)
    {
        state.alive = false;
        state.death_cause = cause;
        events.Add(Event.DEATH);
    }

    // --- One step ---

    void _substep()
    {
#if PROF
        long p0 = Prof.now();
        room.step(this);
        Prof.add(Prof.HZSTEP, p0);
        _move();
        p0 = Prof.now();
        _check_spikes();
        if (!state.alive) { Prof.add(Prof.COLLIDE, p0); return; }
        _check_hazards();
        Prof.add(Prof.COLLIDE, p0);
        if (!state.alive) return;
        _check_coin();
        p0 = Prof.now();
        _check_walls();
        Prof.add(Prof.WALLS, p0);
        p0 = Prof.now();
        _check_ceiling_floor();
        Prof.add(Prof.COLLIDE, p0);
#else
        room.step(this);
        _move();
        _check_spikes();
        if (!state.alive) return;
        _check_hazards();
        if (!state.alive) return;
        _check_coin();
        _check_walls();
        _check_ceiling_floor();
#endif
    }

    void _move()
    {
        long g = SimConfig.GRAVITY * room.gravity;
        state.vy = G.clampi(state.vy + g, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY);
        state.x += state.vx;
        state.y += state.vy;
    }

    void _check_hazards()
    {
        for (int i = 0; i < room.hazards.Count; i++)
        {
            var h = room.hazards[i];
            if (h.alive && h.kills(this))
            {
                kill(DeathCause.HAZARD);
                return;
            }
        }
        for (int i = 0; i < room.hazards.Count; i++)
            if (room.hazards[i].alive) room.hazards[i].touch(this);
    }

    void _check_spikes()
    {
        long r = SimConfig.BIRD_RADIUS;
        long left = room.wall_left();
        long right = room.wall_right();
        long reach = room.max_spike_depth();
        if (state.x - r <= left + reach && _hits_wall(0, left, 1)) kill(DeathCause.SPIKE_LEFT);
        else if (state.x + r >= right - reach && _hits_wall(1, right, -1)) kill(DeathCause.SPIKE_RIGHT);
    }

    bool _hits_wall(long side, long base_x, long dir)
    {
        long mask = wall_mask(side);
        if (mask == 0) return false;
        long hb = room.spike_half_base();
        long shift = wall_shift(side);
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            if (!RoomRules.has_slot(mask, slot)) continue;
            long depth = room.slot_depth(side, slot);
            if (depth <= 0) continue;
            long cy = SimConfig.slot_center_y(slot) + shift;
            if (G.absi(state.y - cy) > hb + SimConfig.BIRD_RADIUS) continue;
            long tip_x = base_x + dir * depth;
            if (SimMath.circle_hits_triangle(
                    state.x, state.y, SimConfig.BIRD_RADIUS, base_x, cy - hb, base_x, cy + hb, tip_x, cy))
                return true;
        }
        return false;
    }

    void _check_walls()
    {
        long r = SimConfig.BIRD_RADIUS;
        long left = room.wall_left();
        long right = room.wall_right();
        if (state.vx > 0 && state.x + r >= right)
        {
            if (_take_exit(1)) return;
            _anchor_at_wall(1);
            state.x = 2 * (right - r) - state.x;
            state.vx = -SimConfig.SPEED_X;
            room.on_wall_bounce();
            state.right_spikes = 0;
            _bounce_score();
            _new_wall(0);
            _maybe_open_exit();
        }
        else if (state.vx < 0 && state.x - r <= left)
        {
            if (_take_exit(0)) return;
            _anchor_at_wall(0);
            state.x = 2 * (left + r) - state.x;
            state.vx = SimConfig.SPEED_X;
            room.on_wall_bounce();
            state.left_spikes = 0;
            _bounce_score();
            _new_wall(1);
            _maybe_open_exit();
        }
    }

    bool _take_exit(long side)
    {
        if (!state.exit_open || state.exit_side != side) return false;
        if (exit_locked()) return false;
        long fit = SimConfig.EXIT_FIT;
        long kind = -1;
        long through = 0;
        if (G.absi(state.y - state.exit_a_y) <= fit)
        {
            kind = state.exit_a_kind;
            through = state.exit_a_y;
        }
        else if (state.exit_b_kind != ExitKind.NORMAL && G.absi(state.y - state.exit_b_y) <= fit)
        {
            kind = state.exit_b_kind;
            through = state.exit_b_y;
        }
        if (kind < 0) return false;
#if PROF
        long p0 = Prof.now();
        _go_through(side, kind, through);
        Prof.add(Prof.EXIT, p0);
#else
        _go_through(side, kind, through);
#endif
        return true;
    }

    void _maybe_open_exit()
    {
        if (state.exit_open) return;
        if (state.exit_preview)
        {
            if (_exit_due(state.score))
            {
                state.exit_preview = false;
                state.exit_open = true;
                events.Add(Event.EXIT_OPEN);
                _boss_down();
            }
            return;
        }
        if (_exit_due(state.score + 1) && !room.def.boss)
        {
            state.exit_preview = true;
            ExitPlanner.use_plan(this, SimConfig.EXIT_WALL, state.score + 1);
            events.Add(Event.EXIT_PREVIEW);
        }
        else if (_exit_due(state.score))
        {
            state.exit_open = true;
            ExitPlanner.use_plan(this, SimConfig.EXIT_WALL, state.score);
            events.Add(Event.EXIT_OPEN);
            _boss_down();
        }
    }

    public bool _exit_due(long at)
    {
        if (room.def.boss) return at == room.entry_score + SimConfig.BOSS_POINTS;
        return at % SimConfig.POINTS_PER_ROOM == 0;
    }

    void _boss_down()
    {
        if (!room.def.boss) return;
        events.Add(Event.BOSS_DOWN);
        if (!is_practice())
            collect_coin(state.x, state.y, SimConfig.BOSS_COINS[SimConfig.boss_tier(room.entry_score) - 1]);
    }

    public long next_exit_score()
    {
        if (state.exit_open) return state.score;
        if (room.def != null && room.def.boss) return room.entry_score + SimConfig.BOSS_POINTS;
        long every = SimConfig.POINTS_PER_ROOM;
        return (state.score / every + 1) * every;
    }

    public long _points_override = -1;
    public long _points_also = -1;

    public long points_to_exit() => _points_override >= 0 ? _points_override : next_exit_score() - state.score;

    public long steps_to_exit(long side)
    {
        long r = SimConfig.BIRD_RADIUS;
        long left = room.wall_left() + r;
        long right = room.wall_right() - r;
        long heading = state.vx > 0 ? 1 : 0;
        long ahead = heading == 1 ? right - state.x : state.x - left;
        long touch = points_to_exit() + 1;
        long on = touch % 2 == 1 ? heading : 1 - heading;
        if (on != side) touch += 1;
        return G.maxi(ahead, 0) / SimConfig.SPEED_X + (touch - 1) * ((right - left) / SimConfig.SPEED_X);
    }

    public const long EXIT_STEER = 3;

    long _wall_target()
    {
        long reach = RoomRules.gap_reach(room.def);
        if (reach <= 0 || state.exit_open) return state.anchor_y;
        if (room.def.reach <= 0 && points_to_exit() > EXIT_STEER)
        {
            if (_free_lo >= 0 && reach - (_free_hi - _free_lo) / 2 >= SimConfig.SLOT_SIZE) return -1;
            return state.anchor_y;
        }
        long to = ExitPlanner.planned_y(this, SimConfig.EXIT_WALL, state.anchor_y);
        return state.anchor_y + G.clampi(to - state.anchor_y, -reach / 2, reach / 2);
    }

    public long steps_to_wall(long side)
    {
        long r = SimConfig.BIRD_RADIUS;
        long left = room.wall_left() + r;
        long right = room.wall_right() - r;
        long heading = state.vx > 0 ? 1 : 0;
        long ahead = heading == 1 ? right - state.x : state.x - left;
        long steps = G.maxi(ahead, 0) / SimConfig.SPEED_X;
        if (heading != side) steps += (right - left) / SimConfig.SPEED_X;
        return steps;
    }

    public void _go_through(long side, long kind, long through_y)
    {
        state.exit_open = false;
        state.route = kind;
        if (kind == ExitKind.WILD)
            for (long i = 0; i < SimConfig.WILD_COINS; i++) collect_coin(state.x, state.y);
        state.room_index += 1;
        long door = through_y;
        if (kind != ExitKind.NORMAL)
        {
            state.y += SimConfig.FORK_DOOR_Y - through_y;
            door = SimConfig.FORK_DOOR_Y;
        }
        state.y = _arrival_y(state.y);
        state.anchor_y = _arrival_y(door);
        long next = practice_room;
        if (is_practice()) { }
        else if (_boss_due())
        {
            next = RoomCatalog.pick_boss(_spine, state.bosses_met);
            state.bosses_met |= RoomCatalog.boss_bit(next);
        }
        else next = RoomCatalog.pick_next(_spine, room.index, state.score, season, state.anchor_y);
        _seed_room();
        long skip = memo_arrivals ? ArrivalMemo.retries(this, side, next) : _arrival_retries(side, next);
        for (long i = 0; i < skip; i++) _rng.next_u32();
        _arrive_in(side, next);
    }

    public bool _boss_due() => state.score > 0 && state.score % SimConfig.BOSS_EVERY == 0 && !room.def.boss;

    public static long _arrival_y(long y)
        => G.clampi(y, SimConfig.KILL_TOP + SimConfig.ARRIVAL_EDGE, SimConfig.KILL_BOTTOM - SimConfig.ARRIVAL_EDGE);

    void _seed_room()
    {
        room.rng_seed = _spine.next_u32();
        _rng.reseed(room.rng_seed);
    }

    public long _arrival_retries(long side, long next)
    {
        _arrival_wait = SimConfig.PORTAL_HOLD;
        if (_checking || SimConfig.ARRIVAL_BLIND == 0) return 0;
        long best = 0;
        long best_score = -1;
        foreach (long wait in new[] { SimConfig.PORTAL_HOLD, SimConfig.ARRIVAL_BLIND })
        {
            for (long k = 0; k < SimConfig.ARRIVAL_TRIES; k++)
            {
                long score = _arrival_score(side, next, k, wait);
                if (score < 0)
                {
                    _arrival_wait = wait;
                    return k;
                }
                if (wait == SimConfig.PORTAL_HOLD && score > best_score)
                {
                    best_score = score;
                    best = k;
                }
            }
        }
        _arrival_wait = SimConfig.ARRIVAL_BLIND;
        return best;
    }

    long _arrival_score(long side, long next, long k, long wait)
    {
        long fair = SimConfig.ARRIVAL_BLIND + SimConfig.ARRIVAL_FOLLOW;
        long centre = 0;
        long worst = fair;
        foreach (long dy in ARRIVAL_HEIGHTS)
        {
            var c = clone_deep();
            c._checking = true;
            c._arrival_wait = wait;
            c.state.y = _arrival_y(state.anchor_y + dy);
            for (long i = 0; i < k; i++) c._rng.next_u32();
            c._arrive_in(side, next);
            long lived = G.mini(ArrivalCheck.score(c), fair);
            if (dy == 0) centre = lived;
            worst = G.mini(worst, lived);
            if (worst < fair) break;
        }
        if (worst >= fair) return -1;
        return centre * (fair + 1) + worst;
    }

    public void _arrive_in(long side, long next)
    {
        long r = SimConfig.BIRD_RADIUS;
        state.vx = side == 1 ? SimConfig.SPEED_X : -SimConfig.SPEED_X;
        state.x = side == 1 ? r : SimConfig.WORLD_W - r;
        _enter_room(next);
        _arrive(side, Event.ROOM_CHANGE);
        ExitPlanner.plan_room(this, next_exit_score());
        state.arrival_hold = _arrival_wait;
        if (room.def.boss) state.arrival_hold = G.maxi(state.arrival_hold, SimConfig.BOSS_HOLD);
        _arrival_wait = SimConfig.PORTAL_HOLD;
        _keep_entry();
    }

    void _keep_entry()
    {
        if (is_practice() || _checking) return;
        _entry_room = room.clone_deep();
        _entry_state = state.copy();
        _entry_rng = _rng.Clone();
        _entry_spine = _spine.Clone();
    }

    void _arrive(long side, int ev)
    {
        long r = SimConfig.BIRD_RADIUS;
        if (side == 1)
        {
            state.x = room.wall_left() + r;
            state.vx = SimConfig.SPEED_X;
        }
        else
        {
            state.x = room.wall_right() - r;
            state.vx = -SimConfig.SPEED_X;
        }
        state.vy = 0;
        state.left_spikes = 0;
        state.right_spikes = 0;
        events.Add(ev);
        _new_wall(side);
        if (ev == Event.ROOM_CHANGE) _keep_hold_band_open(side);
    }

    void _keep_hold_band_open(long side)
    {
        long steps = steps_to_wall(side);
        long ticks = 0;
        long done = 0;
        while (done < steps)
        {
            done += room.steps_at(ticks);
            ticks += 1;
        }
        if (ticks > SimConfig.ARRIVAL_BLIND + ARRIVAL_WALL_SPARE) return;
        long g = room.gravity;
        long edge = SimConfig.BIRD_RADIUS + 4 * SimConfig.SUB;
        long spread = SimConfig.EXIT_FIT;
        long up = state.anchor_y - (FairLanes.FIRST_HOP + edge + spread) * g;
        long down = state.anchor_y + (edge + spread) * g;
        long top = G.mini(up, down);
        long bottom = G.maxi(up, down);
        long mask = side == 1 ? state.right_spikes : state.left_spikes;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            long cy = SimConfig.slot_center_y(slot);
            if (cy + SimConfig.SPIKE_HALF_BASE > top && cy - SimConfig.SPIKE_HALF_BASE < bottom) mask &= ~(1L << (int)slot);
        }
        if (side == 1) state.right_spikes = mask;
        else state.left_spikes = mask;
    }

    void _new_wall(long side)
    {
        if (room.walls > 0) _rng.reseed(SimHash.mix(room.rng_seed, room.walls));
        room.walls += 1;
        long reach = -1;
        long target = _wall_target();
        if (target < 0)
        {
            reach = RoomRules.gap_reach(room.def) - (_free_hi - _free_lo) / 2;
            target = (_free_lo + _free_hi) / 2;
        }
        _free_lo = -1;
        _free_hi = -1;
        long bonus = room.spike_bonus(side);
        if (state.route == ExitKind.WILD && room.walls > 1 && !_checking) bonus += SimConfig.WILD_SPIKES;
#if PROF
        long p0 = Prof.now();
#endif
        long mask = RoomRules.generate_wall(_rng, state.score, room.def, target, bonus, reach);
#if PROF
        Prof.add(Prof.GEN, p0);
        p0 = Prof.now();
#endif
        for (int i = 0; i < room.hazards.Count; i++)
            if (room.hazards[i].alive) mask = room.hazards[i].adjust_wall(this, side, mask);
        if (side == 0) state.left_spikes = mask;
        else state.right_spikes = mask;
        room.on_wall_generated(side, mask, this, _rng);
        for (int i = 0; i < room.hazards.Count; i++)
            if (room.hazards[i].alive) room.hazards[i].on_bounce(this, _rng);
#if PROF
        Prof.add(Prof.ONWALL, p0);
#endif
        if (room.def.bounce_coin && !is_practice()) _spawn_coin();
    }

    long _anchor_target()
    {
        if (state.exit_open || points_to_exit() > EXIT_STEER) return state.anchor_y;
        return ExitPlanner.planned_y(this, SimConfig.EXIT_WALL, state.anchor_y);
    }

    long _drawn_mask(long side)
    {
        if (state.exit_open && state.exit_side == side)
            return ((1L << (int)SimConfig.SLOT_COUNT) - 1) & ~ExitPlanner.slots(state);
        long mask = side == 0 ? state.left_spikes : state.right_spikes;
        if (state.exit_preview && state.exit_side == side) mask &= ~ExitPlanner.slots(state);
        return mask;
    }

    void _anchor_at_wall(long side)
    {
        long mask = _drawn_mask(side);
        long target = _anchor_target();
        long best = state.anchor_y;
        long best_d = -1;
        _free_lo = -1;
        _free_hi = -1;
        long slot = 0;
        while (slot < SimConfig.SLOT_COUNT)
        {
            if (RoomRules.has_slot(mask, slot))
            {
                slot += 1;
                continue;
            }
            long lo = slot;
            while (slot + 1 < SimConfig.SLOT_COUNT && !RoomRules.has_slot(mask, slot + 1)) slot += 1;
            long top = SimConfig.slot_center_y(lo);
            long bottom = SimConfig.slot_center_y(slot);
            if (_free_lo < 0) _free_lo = top;
            _free_hi = bottom;
            long y = G.clampi(target, top, bottom);
            long d = G.absi(y - target);
            if (best_d < 0 || d < best_d)
            {
                best = y;
                best_d = d;
            }
            slot += 1;
        }
        state.anchor_y = best;
    }

    void _bounce_score()
    {
        if (state.exit_open)
        {
            events.Add(Event.BOUNCE);
            return;
        }
        _score();
    }

    void _score()
    {
        state.score += 1;
        room.points += 1;
        events.Add(Event.BOUNCE);
        events.Add(Event.SCORE);
    }

    public void _enter_room(long index)
    {
        state.room_kind = index;
        room.start(RoomCatalog.all()[(int)index], index, this, _rng);
    }

    void _spawn_coin()
    {
        bool extra = state.coin_active;
        if (extra && !room.def.bounce_coin_stacks) return;
        long span_x = SimConfig.COIN_MAX_X - SimConfig.COIN_MIN_X + 1;
        long span_y = SimConfig.COIN_MAX_Y - SimConfig.COIN_MIN_Y + 1;
        long x = SimConfig.COIN_MIN_X + _rng.next_below(span_x);
        long y = SimConfig.COIN_MIN_Y + _rng.next_below(span_y);
        if (extra)
        {
            room.add_coin(x, y);
            return;
        }
        state.coin_active = true;
        state.coin_x = x;
        state.coin_y = y;
        events.Add(Event.COIN_SPAWN);
    }

    void _check_coin()
    {
        if (state.coin_active && bird_touches_circle(state.coin_x, state.coin_y, SimConfig.COIN_RADIUS))
        {
            state.coin_active = false;
            collect_coin(state.coin_x, state.coin_y);
        }
    }

    void _check_ceiling_floor()
    {
        long r = SimConfig.BIRD_RADIUS;
        if (state.y - r <= SimConfig.KILL_TOP)
        {
            if (!_edge_guarded(true)) kill(DeathCause.CEILING);
        }
        else if (state.y + r >= SimConfig.KILL_BOTTOM)
        {
            if (!_edge_guarded(false)) kill(DeathCause.FLOOR);
        }
    }

    bool _edge_guarded(bool top)
    {
        for (int i = 0; i < room.hazards.Count; i++)
        {
            var h = room.hazards[i];
            if (h.alive && h.guards_edge(this, top)) return true;
        }
        return false;
    }
}
