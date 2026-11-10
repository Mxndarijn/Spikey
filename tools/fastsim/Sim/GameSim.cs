namespace FastSim;

public static class Event
{
    public const int START = 0, FLAP = 1, BOUNCE = 2, SCORE = 3, ROOM_CHANGE = 4, DEATH = 5,
        COIN_SPAWN = 6, COIN = 7, EXIT_OPEN = 8, EXIT_PREVIEW = 9, REVIVE = 10;
}

/// Port of sim/game_sim.gd. Same names, same order of everything.
/// Loops over room.hazards use indexes and re-read Count, like GDScript's
/// array iteration, so a hazard added during a loop is visited too.
public sealed class GameSim
{
    public const long BUMP_VY = -SimConfig.FLAP_VY * 6 / 5;
    public const long START_LANE_H = 100 * SimConfig.SUB;
    public const long START_LANE_BELOW = 12 * SimConfig.SUB;
    public const long START_LANE_W = 150 * SimConfig.SUB;
    public const long START_PATH = 32;
    public const long FIRST_HOP = SimConfig.FLAP_VY * SimConfig.FLAP_VY / (2 * SimConfig.GRAVITY);
    public const long PRACTICE_START_GAP = 40 * SimConfig.SUB;

    public long seed_value;
    public long season;
    public long practice_room = -1;
    public SimState state = new SimState();
    public RoomRuntime room = new RoomRuntime();
    public List<int> events = new List<int>(8);
    public SimRng _rng;

    GameSim() { }

    public GameSim(long p_seed, long p_season = Seasons.NONE, long p_practice_room = -1)
    {
        seed_value = p_seed;
        season = p_season;
        _rng = new SimRng(p_seed);
        if (p_practice_room >= 0 && p_practice_room < RoomCatalog.all().Count)
        {
            practice_room = p_practice_room;
            state.score = RoomCatalog.all()[(int)practice_room].from_score;
            state.x = PRACTICE_START_GAP;
            _enter_room(practice_room);
        }
        else
        {
            _enter_room(RoomCatalog.first_index());
        }
    }

    /// Deep copy (what SimClone.copy does in GDScript).
    public GameSim clone_deep()
    {
        var c = new GameSim();
        c.seed_value = seed_value;
        c.season = season;
        c.practice_room = practice_room;
        c.state = state.copy();
        c.room = room.clone_deep();
        c.events = new List<int>(events);
        c._rng = _rng.Clone();
        return c;
    }

    public long entry_y()
    {
        if (state.started) return state.y;
        return state.y - FIRST_HOP / 2 * room.def.gravity_sign;
    }

    public List<long> start_path()
    {
        var out_ = new List<long>();
        if (state.started) return out_;
        long g = SimConfig.GRAVITY * room.def.gravity_sign;
        long x = state.x;
        long y = state.y;
        long vy = SimConfig.FLAP_VY * room.def.gravity_sign;
        for (long i = 0; i < START_PATH; i++)
        {
            vy = G.clampi(vy + g, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY);
            x += state.vx;
            y += vy;
            out_.Add(x);
            out_.Add(y);
        }
        return out_;
    }

    public bool start_path_hits_rect(long x0, long y0, long x1, long y1, long margin)
    {
        var path = start_path();
        long r = SimConfig.BIRD_RADIUS + margin;
        for (int i = 0; i < path.Count; i += 2)
            if (path[i] + r > x0 && path[i] - r < x1 && path[i + 1] + r > y0 && path[i + 1] - r < y1)
                return true;
        return false;
    }

    public bool blocks_start_lane(long x0, long y0, long x1, long y1)
    {
        if (state.started) return false;
        long w = START_LANE_W;
        long top = state.y - (START_LANE_H - START_LANE_BELOW) * room.def.gravity_sign;
        long bottom = state.y + START_LANE_BELOW * room.def.gravity_sign;
        long ly0 = G.mini(top, bottom);
        long ly1 = G.maxi(top, bottom);
        long lx0 = state.vx > 0 ? state.x : state.x - w;
        long lx1 = state.vx > 0 ? state.x + w : state.x;
        return x1 > lx0 && x0 < lx1 && y1 > ly0 && y0 < ly1;
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
            state.vy = SimConfig.FLAP_VY * room.def.gravity_sign;
            state.flaps += 1;
            for (int i = 0; i < room.hazards.Count; i++)
                if (room.hazards[i].alive) room.hazards[i].on_flap(this);
            events.Add(Event.FLAP);
        }
        if (state.started)
        {
            long n = _arrival_steps(room.steps_this_tick());
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
        state.alive = true;
        state.death_cause = DeathCause.NONE;
        state.revives += 1;
        long side = state.vx > 0 ? 1 : 0;
        if (state.exit_open) side = state.exit_side;
        else if (state.exit_preview) side = 1 - state.exit_side;
        long r = SimConfig.BIRD_RADIUS;
        state.vx = side == 1 ? SimConfig.SPEED_X : -SimConfig.SPEED_X;
        state.x = side == 1 ? r : SimConfig.WORLD_W - r;
        state.y = SimConfig.BIRD_START_Y;
        state.vy = 0;
        _enter_room(room.index);
        _arrive(side, Event.REVIVE);
        return true;
    }

    public long wall_mask(long side)
    {
        if (state.exit_open && state.exit_side == side)
            return ((1L << (int)SimConfig.SLOT_COUNT) - 1) & ~exit_slots();
        long mask = room.wall_mask(side, side == 0 ? state.left_spikes : state.right_spikes);
        if (state.exit_preview && state.exit_side == side) mask &= ~exit_slots();
        return mask;
    }

    public long exit_slots()
    {
        long out_ = 0;
        long reach = SimConfig.EXIT_HALF + SimConfig.SPIKE_HALF_BASE;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            long cy = SimConfig.slot_center_y(slot);
            if (G.absi(cy - state.exit_a_y) < reach) out_ |= 1L << (int)slot;
            if (state.exit_b_kind != ExitKind.NORMAL && G.absi(cy - state.exit_b_y) < reach)
                out_ |= 1L << (int)slot;
        }
        return out_;
    }

    public long checksum() => SimHash.mix(room.checksum(state.checksum()), _rng.state_checksum());

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

    public void collect_coin(long x, long y)
    {
        state.coins += 1;
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
        room.step(this);
        _move();
        _check_spikes();
        if (!state.alive) return;
        _check_hazards();
        if (!state.alive) return;
        _check_coin();
        _check_walls();
        _check_ceiling_floor();
    }

    void _move()
    {
        long g = SimConfig.GRAVITY * room.def.gravity_sign;
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
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            if (!RoomRules.has_slot(mask, slot)) continue;
            long depth = room.slot_depth(side, slot);
            if (depth <= 0) continue;
            long cy = SimConfig.slot_center_y(slot);
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
            state.x = 2 * (right - r) - state.x;
            state.vx = -SimConfig.SPEED_X;
            state.right_spikes = 0;
            _bounce_score();
            _new_wall(0);
            _maybe_open_exit(0);
        }
        else if (state.vx < 0 && state.x - r <= left)
        {
            if (_take_exit(0)) return;
            state.x = 2 * (left + r) - state.x;
            state.vx = SimConfig.SPEED_X;
            state.left_spikes = 0;
            _bounce_score();
            _new_wall(1);
            _maybe_open_exit(1);
        }
    }

    bool _take_exit(long side)
    {
        if (!state.exit_open || state.exit_side != side) return false;
        long fit = SimConfig.EXIT_FIT;
        long kind = -1;
        if (G.absi(state.y - state.exit_a_y) <= fit) kind = state.exit_a_kind;
        else if (state.exit_b_kind != ExitKind.NORMAL && G.absi(state.y - state.exit_b_y) <= fit)
            kind = state.exit_b_kind;
        if (kind < 0) return false;
        _go_through(side, kind);
        return true;
    }

    void _maybe_open_exit(long side)
    {
        if (state.exit_open) return;
        long every = SimConfig.POINTS_PER_ROOM;
        if (state.exit_preview)
        {
            if (state.score % every == 0)
            {
                state.exit_preview = false;
                state.exit_open = true;
                events.Add(Event.EXIT_OPEN);
            }
            return;
        }
        if ((state.score + 1) % every == 0)
        {
            _plan_exit(1 - side, state.score + 1);
            state.exit_preview = true;
            events.Add(Event.EXIT_PREVIEW);
        }
        else if (state.score % every == 0)
        {
            _plan_exit(side, state.score);
            state.exit_open = true;
            events.Add(Event.EXIT_OPEN);
        }
    }

    void _plan_exit(long side, long at)
    {
        state.exit_side = side;
        bool fork = at % SimConfig.FORK_EVERY == 0 && !is_practice();
        if (fork)
        {
            long top = _random_exit_y(SimConfig.EXIT_MIN_Y, SimConfig.FORK_SPLIT_Y - SimConfig.EXIT_HALF);
            long bottom = _random_exit_y(SimConfig.FORK_SPLIT_Y + SimConfig.EXIT_HALF, SimConfig.EXIT_MAX_Y);
            bool calm_on_top = _rng.next_below(2) == 0;
            state.exit_a_y = top;
            state.exit_b_y = bottom;
            state.exit_a_kind = calm_on_top ? ExitKind.CALM : ExitKind.WILD;
            state.exit_b_kind = calm_on_top ? ExitKind.WILD : ExitKind.CALM;
        }
        else
        {
            state.exit_a_y = _random_exit_y(SimConfig.EXIT_MIN_Y, SimConfig.EXIT_MAX_Y);
            state.exit_a_kind = ExitKind.NORMAL;
            state.exit_b_y = 0;
            state.exit_b_kind = ExitKind.NORMAL;
        }
    }

    long _random_exit_y(long lo, long hi)
    {
        long c0 = SimConfig.slot_center_y(0);
        long first = (lo - c0 + SimConfig.SLOT_SIZE - 1) / SimConfig.SLOT_SIZE;
        long last = (hi - c0) / SimConfig.SLOT_SIZE;
        var open = new List<long>();
        for (long slot = first; slot < last + 1; slot++)
            if (!_exit_blocked(SimConfig.slot_center_y(slot))) open.Add(slot);
        if (open.Count == 0)
        {
            long any = first + _rng.next_below(last - first + 1);
            if (room.def.reach > 0)
                any = G.clampi((state.y - c0 + SimConfig.SLOT_SIZE / 2) / SimConfig.SLOT_SIZE, first, last);
            return SimConfig.slot_center_y(any);
        }
        return SimConfig.slot_center_y(open[(int)_rng.next_below(open.Count)]);
    }

    bool _exit_blocked(long y)
    {
        if (room.def.reach > 0 && G.absi(y - state.y) > room.def.reach) return true;
        for (int i = 0; i < room.hazards.Count; i++)
        {
            var h = room.hazards[i];
            if (h.alive && h.blocks_exit(this, state.exit_side, y)) return true;
        }
        return false;
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

    void _go_through(long side, long kind)
    {
        state.exit_open = false;
        if (kind != ExitKind.NORMAL) state.route = kind;
        if (kind == ExitKind.WILD)
            for (long i = 0; i < SimConfig.WILD_COINS; i++) collect_coin(state.x, state.y);
        state.room_index += 1;
        long next = practice_room;
        if (!is_practice()) next = RoomCatalog.pick_next(_rng, room.index, state.score, season, state.route);
        _arrive_in(side, next);
    }

    void _arrive_in(long side, long next)
    {
        long r = SimConfig.BIRD_RADIUS;
        state.vx = side == 1 ? SimConfig.SPEED_X : -SimConfig.SPEED_X;
        state.x = side == 1 ? r : SimConfig.WORLD_W - r;
        _enter_room(next);
        _arrive(side, Event.ROOM_CHANGE);
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
        state.arrival_slow_acc = 0;
        if (ev == Event.REVIVE)
        {
            state.arrival_hold = SimConfig.ARRIVAL_HOLD;
            state.arrival_slow = 0;
        }
        else
        {
            state.arrival_slow = SimConfig.ARRIVAL_SLOW_TICKS;
        }
        state.left_spikes = 0;
        state.right_spikes = 0;
        events.Add(ev);
        _new_wall(side);
    }

    long _arrival_steps(long steps)
    {
        if (state.arrival_slow <= 0) return steps;
        long elapsed = SimConfig.ARRIVAL_SLOW_TICKS - state.arrival_slow;
        long pct = SimConfig.ARRIVAL_SLOW_PCT;
        if (elapsed >= SimConfig.ARRIVAL_SLOW_FLAT)
        {
            long ramp = SimConfig.ARRIVAL_SLOW_TICKS - SimConfig.ARRIVAL_SLOW_FLAT;
            pct += (100 - pct) * (elapsed - SimConfig.ARRIVAL_SLOW_FLAT) / ramp;
        }
        state.arrival_slow_acc += steps * pct;
        long out_ = state.arrival_slow_acc / 100;
        state.arrival_slow_acc -= out_ * 100;
        state.arrival_slow -= 1;
        if (state.arrival_slow == 0) state.arrival_slow_acc = 0;
        return out_;
    }

    void _new_wall(long side)
    {
        long mask = RoomRules.generate_wall(_rng, state.score, room.def, state.y, room.spike_bonus());
        if (side == 0) state.left_spikes = mask;
        else state.right_spikes = mask;
        room.on_wall_generated(side, mask, this, _rng);
        for (int i = 0; i < room.hazards.Count; i++)
            if (room.hazards[i].alive) room.hazards[i].on_bounce(this, _rng);
        if (room.def.bounce_coin && !is_practice()) _spawn_coin();
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

    void _enter_room(long index)
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
