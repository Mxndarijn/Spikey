namespace FastSim.Model;

/// One hazard as the world model sees it: its bodies (shapes, deadly or not),
/// its motion rule (Step: one substep ahead, from the present state only) and
/// what it does to the bird (Touch: pushes, bumps, carries; Guard: an edge pad
/// that saves the bird from the ceiling or floor).
///
/// A model never runs the sim's own hazard code forward: it holds a copy of
/// the visible state and re-applies the rule a practised player knows
/// ("a gate's gap swings up and down every 400 substeps"). What the sim decides
/// from its RNG (a drop's next column, a stalactite's slide target, a
/// piston's next height) is not read: the model marks those bodies `guess`.
public abstract class HazardModel
{
    public string kind = "";
    public int index;
    public bool alive = true;
    /// The hazard's clock (substeps since the room began), as Hazard.t.
    public long t;
    /// Its motion depends on the bird (a stalker follows it, a dart aims at it),
    /// or the bird changes it (lava's stone, a key taken).
    public bool reactive;
    /// Touching it changes only itself, never the bird (coins, the keepy ball):
    /// a planner may skip its Touch.
    public bool selfish;
    /// Some hidden random choice (or one only taken at a bounce) can change its
    /// future: predictions past that point are guesses.
    public bool random;
    public Body[] bodies = Array.Empty<Body>();

    public abstract void Step(WorldModel w);
    public virtual void Touch(WorldModel w, ref Bird b) { }
    public virtual bool Guard(WorldModel w, ref Bird b, bool top) => false;
    public virtual long WallShift(long side) => 0;
    public virtual void OnBounce(WorldModel w) { }
    public virtual void OnFlap(WorldModel w) { }
    public virtual bool Locks => false;

    /// Motion pattern name and its parameters (px, substeps, turns of 1024), for descriptions.
    public virtual string Motion => "static";
    public virtual void Params(Dictionary<string, double> p) { }
    public virtual string State => "active";

    public HazardModel Copy()
    {
        var c = (HazardModel)MemberwiseClone();
        c.bodies = (Body[])bodies.Clone();
        CopyLists(c);
        return c;
    }

    protected virtual void CopyLists(HazardModel c) { }

    protected static double Px(long v) => v / (double)SimConfig.SUB;
}

/// What one substep did to the bird.
public struct SubResult
{
    public bool dead;
    public long cause;
    /// The wall the bird bounced off this substep (0 left, 1 right), or -1.
    public int bounced;
    public bool exited;
    public long exit_kind;
    /// Inside the safety margin of something deadly (only when a margin is asked).
    public bool near;
    public bool near_guess;
}

/// The structured world: the room (walls, spikes, exit, rules), the bird and
/// every hazard as a model, all read from the present state of a GameSim.
/// Tick() advances the model one tick by the game's own step order, so a
/// model copy predicts the bird's exact path for any taps, and every hazard
/// by its motion rule. It never reads the sim again after Read().
public sealed class WorldModel
{
    public RoomModel room;
    public Bird bird;
    public HazardModel[] hz = Array.Empty<HazardModel>();
    public long tick;
    public long room_index;
    /// Substeps advanced since Read().
    public long sub;
    /// What the last Tick did.
    public bool bounced, exited;
    public int bounce_side = -1;

    public static WorldModel Read(GameSim sim, Memory mem = null)
    {
        var s = sim.state;
        var w = new WorldModel
        {
            room = RoomModel.Read(sim),
            bird = new Bird { x = s.x, y = s.y, vx = s.vx, vy = s.vy, alive = s.alive, cause = s.death_cause },
            tick = s.tick,
            room_index = s.room_index,
        };
        var list = new List<HazardModel>(sim.room.hazards.Count);
        for (int i = 0; i < sim.room.hazards.Count; i++)
        {
            var m = Models.Read(sim.room.hazards[i], sim, mem, i);
            m.index = i;
            m.alive = sim.room.hazards[i].alive;
            list.Add(m);
        }
        w.hz = list.ToArray();
        if (mem != null) w.room.anchor = mem.anchor;
        Models.Link(w);
        return w;
    }

    public WorldModel Copy()
    {
        var c = (WorldModel)MemberwiseClone();
        c.room = room.Copy();
        c.hz = new HazardModel[hz.Length];
        for (int i = 0; i < hz.Length; i++) c.hz[i] = hz[i].Copy();
        Models.Link(c);
        return c;
    }

    /// A copy holding only the hazards for which `keep` is true (the planner
    /// keeps the reactive ones per path).
    public HazardModel[] CopyHazards(Func<HazardModel, bool> keep)
    {
        var out_ = new List<HazardModel>();
        foreach (var h in hz)
            if (keep(h)) out_.Add(h.Copy());
        return out_.ToArray();
    }

    public HazardModel Find(int index)
    {
        foreach (var h in hz)
            if (h.index == index) return h;
        return null;
    }

    /// One tick, as GameSim.step(tap).
    public void Tick(bool tap)
    {
        bounced = false;
        exited = false;
        bounce_side = -1;
        if (!bird.alive) return;
        if (room.hold > 0)
        {
            room.hold -= 1;
            tick += 1;
            return;
        }
        if (tap)
        {
            room.started = true;
            bird.vy = SimConfig.FLAP_VY * room.gravity;
            foreach (var h in hz)
                if (h.alive) h.OnFlap(this);
        }
        if (room.started)
        {
            long n = room.StepsAt(room.ticks);
            for (long i = 0; i < n; i++)
            {
                Substep();
                if (!bird.alive || exited) break;
            }
            room.ticks += 1;
        }
        tick += 1;
    }

    void Substep()
    {
        room.t += 1;
        sub += 1;
        foreach (var h in hz)
        {
            if (!h.alive) continue;
            h.t = room.t;
            h.Step(this);
        }
        var r = new SubResult { bounced = -1 };
        Physics.Substep(this, ref bird, room.gravity, hz, null, 0, ref r);
        if (r.dead)
        {
            bird.alive = false;
            bird.cause = r.cause;
            return;
        }
        if (r.exited)
        {
            exited = true;
            return;
        }
        if (r.bounced >= 0) ApplyBounce(r.bounced);
    }

    /// One substep of the room and its hazards with a "ghost" bird that only
    /// flies sideways (no fall, no deaths): what the planner's shared timeline
    /// is built from. The ghost still bounces at the walls when the bird would,
    /// so the room's bounce rules (points, flips, lava, belts) land in time.
    public void GhostSubstep(Action after_hazards = null, bool bounce = true)
    {
        room.t += 1;
        sub += 1;
        foreach (var h in hz)
        {
            if (!h.alive) continue;
            h.t = room.t;
            h.Step(this);
        }
        // The bird checks spikes and hazards before it bounces: snapshot here.
        after_hazards?.Invoke();
        if (!bounce) return;
        bird.x += bird.vx;
        long r = Physics.R;
        if (bird.vx > 0 && bird.x + r >= room.WallRight)
        {
            bird.x = 2 * (room.WallRight - r) - bird.x;
            bird.vx = -SimConfig.SPEED_X;
            ApplyBounce(1);
        }
        else if (bird.vx < 0 && bird.x - r <= room.WallLeft)
        {
            bird.x = 2 * (room.WallLeft + r) - bird.x;
            bird.vx = SimConfig.SPEED_X;
            ApplyBounce(0);
        }
    }

    /// What a wall bounce does to the room (GameSim._check_walls and what it calls):
    /// the known part. The new wall's spikes and a new exit's height are drawn
    /// from the RNG then, so they become unknown.
    public void ApplyBounce(int side)
    {
        bounced = true;
        bounce_side = side;
        room.anchor = RoomModel.NewAnchor(room.Drawn(side), room.anchor);
        if (room.flip_flop) room.gravity = -room.gravity;
        room.spikes[side] = 0;
        room.unknown[side] = false;
        if (!room.exit_open)
        {
            room.score += 1;
            room.points += 1;
        }
        int other = 1 - side;
        room.unknown[other] = true;
        foreach (var h in hz)
            if (h.alive) h.OnBounce(this);
        if (!room.exit_open)
        {
            long every = SimConfig.POINTS_PER_ROOM;
            if (room.exit_preview)
            {
                if (room.score % every == 0)
                {
                    room.exit_preview = false;
                    room.exit_open = true;
                    // An exit wall is all spikes but the exit: known from the preview.
                    if (room.exit_side == other) room.unknown[other] = false;
                }
            }
            else if ((room.score + 1) % every == 0 || room.score % every == 0)
                room.exit_unknown = true;
        }
    }

    public string RoomLabel => room.variant == "" ? room.id : room.id + "/" + room.variant;
}

/// The bird's half of a substep, after the hazards moved: the fall, the
/// spikes, the hazards, their pushes, the walls, the ceiling and the floor
/// (GameSim._substep without room.step). Hazards come from up to two lists
/// (the planner keeps the ones that do not depend on the bird in a shared
/// timeline and the rest per path). Changes nothing but the bird; the
/// caller applies a bounce. `margin` > 0 also reports a close pass.
public static class Physics
{
    public const long R = SimConfig.BIRD_RADIUS;

    public static void Substep(WorldModel c, ref Bird b, long grav, HazardModel[] a, HazardModel[] a2, long margin,
        ref SubResult r, bool skip_selfish = false)
    {
        long g = SimConfig.GRAVITY * grav;
        b.vy = Math.Clamp(b.vy + g, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY);
        b.x += b.vx;
        b.y += b.vy;

        var room = c.room;
        long left = room.WallLeft;
        long right = room.WallRight;
        long reach = room.max_depth;
        if (b.x - R <= left + reach && HitsWall(c, a, a2, b, 0, left, 1, R)) Die(ref r, DeathCause.SPIKE_LEFT);
        else if (b.x + R >= right - reach && HitsWall(c, a, a2, b, 1, right, -1, R)) Die(ref r, DeathCause.SPIKE_RIGHT);
        if (r.dead) return;
        if (margin > 0 && !r.near)
        {
            long rm = R + margin;
            if ((b.x - rm <= left + reach && HitsWall(c, a, a2, b, 0, left, 1, rm))
                || (b.x + rm >= right - reach && HitsWall(c, a, a2, b, 1, right, -1, rm)))
                r.near = true;
        }

        if (Kills(a, b, margin, ref r) || Kills(a2, b, margin, ref r))
        {
            Die(ref r, DeathCause.HAZARD);
            return;
        }
        if (a != null)
            foreach (var h in a)
                if (h.alive && !(skip_selfish && h.selfish)) h.Touch(c, ref b);
        if (a2 != null)
            foreach (var h in a2)
                if (h.alive) h.Touch(c, ref b);

        if (b.vx > 0 && b.x + R >= right)
        {
            if (TakeExit(c, a, a2, b, 1, ref r)) return;
            b.x = 2 * (right - R) - b.x;
            b.vx = -SimConfig.SPEED_X;
            r.bounced = 1;
        }
        else if (b.vx < 0 && b.x - R <= left)
        {
            if (TakeExit(c, a, a2, b, 0, ref r)) return;
            b.x = 2 * (left + R) - b.x;
            b.vx = SimConfig.SPEED_X;
            r.bounced = 0;
        }

        if (b.y - R <= SimConfig.KILL_TOP)
        {
            if (!Guard(c, a, a2, ref b, true)) Die(ref r, DeathCause.CEILING);
        }
        else if (b.y + R >= SimConfig.KILL_BOTTOM)
        {
            if (!Guard(c, a, a2, ref b, false)) Die(ref r, DeathCause.FLOOR);
        }
        else if (margin > 0 && (b.y - R - margin <= SimConfig.KILL_TOP || b.y + R + margin >= SimConfig.KILL_BOTTOM))
        {
            // A guarded edge (a pad under the bird) is not a close call.
            var probe = b;
            bool top = b.y - R - margin <= SimConfig.KILL_TOP;
            if (!GuardCovers(a, a2, probe.x, top)) r.near = true;
        }
    }

    static void Die(ref SubResult r, long cause)
    {
        r.dead = true;
        r.cause = cause;
    }

    /// Extra safety margin around bodies the model only guesses (hidden random choices).
    public static long guess_margin = 0;

    static bool Kills(HazardModel[] list, in Bird b, long margin, ref SubResult r)
    {
        if (list == null) return false;
        long rm = R + margin;
        long rg = rm + guess_margin;
        foreach (var h in list)
        {
            if (!h.alive) continue;
            var bodies = h.bodies;
            for (int i = 0; i < bodies.Length; i++)
            {
                ref var body = ref bodies[i];
                if (!body.on || !body.deadly) continue;
                if (body.s.Hits(b.x, b.y, R)) return true;
                if (margin > 0 && !r.near && body.s.Hits(b.x, b.y, body.guess ? rg : rm))
                {
                    r.near = true;
                    r.near_guess = body.guess;
                }
            }
        }
        return false;
    }

    public static long Shift(HazardModel[] a, HazardModel[] a2, long side)
    {
        long out_ = 0;
        if (a != null)
            foreach (var h in a)
                if (h.alive) out_ += h.WallShift(side);
        if (a2 != null)
            foreach (var h in a2)
                if (h.alive) out_ += h.WallShift(side);
        return out_;
    }

    /// GameSim._hits_wall on the model's walls, for a bird of radius `r`.
    public static bool HitsWall(WorldModel c, HazardModel[] a, HazardModel[] a2, in Bird b, long side, long base_x,
        long dir, long r)
    {
        var room = c.room;
        long mask = room.Mask(side);
        if (mask == 0) return false;
        long hb = room.half_base;
        long shift = Shift(a, a2, side);
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            if (((mask >> (int)slot) & 1) == 0) continue;
            long depth = room.SlotDepth(side, slot);
            if (depth <= 0) continue;
            long cy = SimConfig.slot_center_y(slot) + shift;
            if (Math.Abs(b.y - cy) > hb + r) continue;
            long tip_x = base_x + dir * depth;
            if (SimMath.circle_hits_triangle(b.x, b.y, r, base_x, cy - hb, base_x, cy + hb, tip_x, cy)) return true;
        }
        return false;
    }

    static bool TakeExit(WorldModel c, HazardModel[] a, HazardModel[] a2, in Bird b, long side, ref SubResult r)
    {
        var room = c.room;
        if (!room.exit_open || room.exit_side != side || room.unknown[side]) return false;
        if (Locked(a) || Locked(a2)) return false;
        long fit = SimConfig.EXIT_FIT;
        long kind = -1;
        if (Math.Abs(b.y - room.exit_a_y) <= fit) kind = room.exit_a_kind;
        else if (room.exit_b_kind != ExitKind.NORMAL && Math.Abs(b.y - room.exit_b_y) <= fit) kind = room.exit_b_kind;
        if (kind < 0) return false;
        r.exited = true;
        r.exit_kind = kind;
        return true;
    }

    static bool Locked(HazardModel[] list)
    {
        if (list == null) return false;
        foreach (var h in list)
            if (h.alive && h.Locks) return true;
        return false;
    }

    static bool Guard(WorldModel c, HazardModel[] a, HazardModel[] a2, ref Bird b, bool top)
    {
        if (a != null)
            foreach (var h in a)
                if (h.alive && h.Guard(c, ref b, top)) return true;
        if (a2 != null)
            foreach (var h in a2)
                if (h.alive && h.Guard(c, ref b, top)) return true;
        return false;
    }

    static bool GuardCovers(HazardModel[] a, HazardModel[] a2, long x, bool top)
    {
        foreach (var list in new[] { a, a2 })
        {
            if (list == null) continue;
            foreach (var h in list)
                if (h.alive && h is EdgePadM p && p.top == top && p.Covers(x)) return true;
        }
        return false;
    }
}

/// What the bot remembers from earlier ticks (a player's memory, not a peek):
/// where each stalactite gap was a moment ago (to see it slide) and the bird's
/// height at the last wall bounce. Update it once per tick with the present.
public sealed class Memory
{
    public long room_index = -1;
    public long last_tick = -1;
    public long last_t;
    public Dictionary<int, long> gap = new();
    public Dictionary<int, long> gap_v = new();
    public long bounce_y = -1;
    public long bounce_tick = -1000;
    /// The bird's sideways speed just after the last bounce.
    public long bounce_vx;
    /// The room's anchor height, tracked from the walls the bird bounced off
    /// (RoomModel.NewAnchor) and the exit it came through.
    public long anchor = SimConfig.BIRD_START_Y;
    long _last_vx, _last_y;
    readonly long[] _last_drawn = new long[2];
    bool _last_exit_open;
    long _last_exit_a, _last_exit_b, _last_exit_b_kind;

    static long Drawn(SimState s, long side)
    {
        long reach = SimConfig.EXIT_HALF + SimConfig.SPIKE_HALF_BASE;
        long slots = 0;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            long cy = SimConfig.slot_center_y(slot);
            if (Math.Abs(cy - s.exit_a_y) < reach) slots |= 1L << (int)slot;
            if (s.exit_b_kind != ExitKind.NORMAL && Math.Abs(cy - s.exit_b_y) < reach) slots |= 1L << (int)slot;
        }
        if (s.exit_open && s.exit_side == side) return ((1L << (int)SimConfig.SLOT_COUNT) - 1) & ~slots;
        long mask = side == 0 ? s.left_spikes : s.right_spikes;
        if (s.exit_preview && s.exit_side == side) mask &= ~slots;
        return mask;
    }

    public void Observe(GameSim sim)
    {
        var s = sim.state;
        if (s.room_index != room_index)
        {
            // Came through an exit: the room anchors at the exit's height.
            if (room_index >= 0 && _last_exit_open)
            {
                long through = Math.Abs(_last_y - _last_exit_a) <= SimConfig.EXIT_FIT || _last_exit_b_kind == ExitKind.NORMAL
                    ? _last_exit_a : _last_exit_b;
                anchor = Math.Clamp(through, SimConfig.KILL_TOP + SimConfig.ARRIVAL_EDGE,
                    SimConfig.KILL_BOTTOM - SimConfig.ARRIVAL_EDGE);
            }
            room_index = s.room_index;
            gap.Clear();
            gap_v.Clear();
            bounce_y = s.y;
            bounce_tick = -1000;
            last_tick = -1;
        }
        // A wall bounce (a bumper also turns the bird round, but not at a wall).
        bool flipped = _last_vx != 0 && Math.Sign(_last_vx) != Math.Sign(s.vx);
        long r = SimConfig.BIRD_RADIUS;
        bool at_wall = s.x - r <= sim.room.wall_left() + SimConfig.SPEED_X * 3
            || s.x + r >= sim.room.wall_right() - SimConfig.SPEED_X * 3;
        if (flipped && at_wall)
        {
            long side = _last_vx > 0 ? 1 : 0;
            anchor = RoomModel.NewAnchor(_last_drawn[side], anchor);
            bounce_y = s.y;
            bounce_tick = s.tick;
            bounce_vx = s.vx;
        }
        _last_vx = s.vx;
        _last_y = s.y;
        _last_drawn[0] = Drawn(s, 0);
        _last_drawn[1] = Drawn(s, 1);
        _last_exit_open = s.exit_open;
        _last_exit_a = s.exit_a_y;
        _last_exit_b = s.exit_b_y;
        _last_exit_b_kind = s.exit_b_kind;
        long dt = sim.room.t - last_t;
        for (int i = 0; i < sim.room.hazards.Count; i++)
        {
            if (sim.room.hazards[i] is not Stalactite st) continue;
            if (gap.TryGetValue(i, out long before) && dt > 0) gap_v[i] = (st.gap_y - before) / dt;
            else if (dt > 0) gap_v[i] = 0;
            gap[i] = st.gap_y;
        }
        last_t = sim.room.t;
        last_tick = s.tick;
    }
}
