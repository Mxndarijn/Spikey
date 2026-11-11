namespace FastSim.Model;

// Hazards that run on a cycle or a fuse (beams, pistons, darts, drops,
// fireworks, crates) and ones the sim moves with hidden random choices
// (stalactite slide targets, a bubble's next column). The visible part (a
// warning, a glow, a marker, the current cycle) is read; a choice the sim has
// not shown yet becomes a guess.

/// Beam: rows that fire across the room on a fixed cycle (off, warning, on).
/// "Yielding" beams skip a cycle when another hazard is near their row: that
/// is decided at the start of each cycle, so later cycles are guesses.
public sealed class BeamM : HazardModel
{
    long[] rows, delays, skip;
    bool[] guess;
    long warn_ticks;
    bool yields;

    public BeamM(Beam h)
    {
        kind = h.kind;
        rows = h.rows.ToArray();
        delays = h.delays.ToArray();
        skip = h.skip.ToArray();
        guess = new bool[rows.Length];
        warn_ticks = h.warn_ticks;
        yields = h.yields;
        random = yields;
        t = h.t;
        bodies = new Body[rows.Length];
        Place(null);
    }

    protected override void CopyLists(HazardModel c)
    {
        var b = (BeamM)c;
        b.skip = (long[])skip.Clone();
        b.guess = (bool[])guess.Clone();
    }

    long CyclePos(long i) => t < delays[i] ? -1 : G.posmod(t - delays[i], Beam.PERIOD);

    long StateOf(long i)
    {
        long p = CyclePos(i);
        if (p < 0 || p >= warn_ticks + Beam.ON_TICKS || skip[i] == 1) return Beam.State.OFF;
        return p < warn_ticks ? Beam.State.WARN : Beam.State.ON;
    }

    public override void Step(WorldModel w)
    {
        if (yields)
            for (long i = 0; i < rows.Length; i++)
                if (CyclePos(i) == 0)
                {
                    skip[i] = 0;
                    guess[i] = true;
                }
        Place(w);
    }

    void Place(WorldModel w)
    {
        long left = w?.room.WallLeft ?? 0, right = w?.room.WallRight ?? SimConfig.WORLD_W;
        for (long i = 0; i < rows.Length; i++)
        {
            bodies[i] = Body.Kill(Shape.Rect(left, rows[i] - Beam.HALF_H, right, rows[i] + Beam.HALF_H),
                StateOf(i) == Beam.State.ON);
            bodies[i].guess = guess[i];
        }
    }

    public override string Motion => "cycle";

    public override string State
    {
        get
        {
            bool warn = false;
            for (long i = 0; i < rows.Length; i++)
            {
                if (StateOf(i) == Beam.State.ON) return "active";
                warn |= StateOf(i) == Beam.State.WARN;
            }
            return warn ? "warning" : "off";
        }
    }

    public override void Params(Dictionary<string, double> p)
    {
        p["rows"] = rows.Length;
        p["period"] = Beam.PERIOD;
        p["warn"] = warn_ticks;
        p["on"] = Beam.ON_TICKS;
    }
}

/// Piston: a ram from a side wall at a fixed height on a cycle (idle, glow,
/// extend, hold, retract). At a bounce an idle piston may move to a new
/// random height: a guess until it glows.
public sealed class PistonM : HazardModel
{
    public long side, y, delay, glow_ticks, reach, fixed_y;
    public int leader_index = -1;
    public PistonM leader;
    bool y_guess;

    public PistonM(Piston h, GameSim sim)
    {
        kind = h.kind;
        side = h.side;
        y = h.y;
        delay = h.delay;
        glow_ticks = h.glow_ticks;
        reach = h.reach;
        fixed_y = h.fixed_y;
        if (h.leader != null) leader_index = sim.room.hazards.IndexOf(h.leader);
        random = fixed_y < 0;
        t = h.t;
        bodies = new Body[1];
        Place();
    }

    long Period => Piston.IDLE_TICKS + glow_ticks + Piston.EXTEND_TICKS + Piston.HOLD_TICKS + Piston.RETRACT_TICKS;
    long CyclePos => t < delay ? -1 : G.posmod(t - delay, Period);

    public long StateNow()
    {
        long p = CyclePos;
        if (p < Piston.IDLE_TICKS) return Piston.State.IDLE;
        p -= Piston.IDLE_TICKS;
        if (p < glow_ticks) return Piston.State.GLOW;
        p -= glow_ticks;
        if (p < Piston.EXTEND_TICKS) return Piston.State.EXTEND;
        p -= Piston.EXTEND_TICKS;
        if (p < Piston.HOLD_TICKS) return Piston.State.HOLD;
        return Piston.State.RETRACT;
    }

    long Extent()
    {
        long p = CyclePos - Piston.IDLE_TICKS - glow_ticks;
        long s = StateNow();
        if (s == Piston.State.EXTEND) return reach * (p + 1) / Piston.EXTEND_TICKS;
        if (s == Piston.State.HOLD) return reach;
        if (s == Piston.State.RETRACT)
        {
            p -= Piston.EXTEND_TICKS + Piston.HOLD_TICKS;
            return reach * (Piston.RETRACT_TICKS - p - 1) / Piston.RETRACT_TICKS;
        }
        return 0;
    }

    public override void Step(WorldModel w)
    {
        if (StateNow() != Piston.State.IDLE) y_guess = false;
        Place();
    }

    void Place()
    {
        long e = Extent();
        long bx = side == 0 ? 0 : SimConfig.WORLD_W;
        long tip = side == 0 ? bx + e : bx - e;
        bodies[0] = Body.Kill(Shape.Rect(bx, y - Piston.HALF_H, tip, y + Piston.HALF_H), e > 0);
        bodies[0].guess = y_guess;
    }

    public override void OnBounce(WorldModel w)
    {
        if (fixed_y >= 0) return;
        if (leader != null)
        {
            y = leader.y;
            y_guess = leader.y_guess;
            return;
        }
        if (StateNow() == Piston.State.IDLE) y_guess = true;
    }

    public override string Motion => "piston_cycle";

    public override string State => StateNow() switch
    {
        Piston.State.IDLE => "idle",
        Piston.State.GLOW => "warning",
        Piston.State.RETRACT => "retracting",
        _ => "active",
    };

    public override void Params(Dictionary<string, double> p)
    {
        p["side"] = side;
        p["y"] = Px(y);
        p["period"] = Period;
        p["phase"] = CyclePos;
        p["reach"] = Px(reach);
    }
}

/// Dart: idles, glows on its lane, then flies across. A plain dart aims at the
/// bird's height when it starts to glow (reacts to the bird); a lanes dart picks
/// a hidden random lane (a guess until it glows).
public sealed class DartM : HazardModel
{
    bool lanes, pair, lane_guess;
    long lane_count, lane_min, lane_max, lanes_speed, lanes_flash, lane2_y, home, state, since, wait, side, lane_y, x;

    public DartM(Dart h)
    {
        kind = h.kind;
        lanes = h.lanes;
        pair = h.pair;
        lane_count = h.lane_count;
        lane_min = h.lane_min;
        lane_max = h.lane_max;
        lanes_speed = h.lanes_speed;
        lanes_flash = h.lanes_flash;
        lane2_y = h.lane2_y;
        home = h.home;
        state = h.state;
        since = h.since;
        wait = h.wait;
        side = h.side;
        lane_y = h.lane_y;
        x = h.x;
        t = h.t;
        reactive = !lanes;
        random = lanes;
        bodies = new Body[2];
        Place();
    }

    long BaseX => side == 0 ? 0 : SimConfig.WORLD_W;
    long Dir => side == 0 ? 1 : -1;

    public override void Step(WorldModel w)
    {
        if (state == Dart.State.IDLE)
        {
            if (t - since >= wait)
            {
                if (lanes) lane_guess = true;
                else
                {
                    side = w.bird.x < SimConfig.WORLD_W / 2 ? 1 : 0;
                    if (home >= 0) side = home;
                    lane_y = Math.Clamp(w.bird.y, Dart.LANE_MIN, Dart.LANE_MAX);
                }
                state = Dart.State.GLOW;
                since = t;
            }
        }
        else if (state == Dart.State.GLOW)
        {
            if (t - since >= (lanes ? lanes_flash : Dart.GLOW_TICKS))
            {
                state = Dart.State.FLY;
                since = t;
                x = BaseX;
            }
        }
        else if (state == Dart.State.FLY)
        {
            x += Dir * (lanes ? lanes_speed : Dart.SPEED);
            if (x < -Dart.LENGTH || x > SimConfig.WORLD_W + Dart.LENGTH)
            {
                state = Dart.State.IDLE;
                since = t;
                wait = lanes ? Dart.LANES_IDLE : Dart.IDLE_TICKS;
                x = BaseX;
            }
        }
        Place();
    }

    void Place()
    {
        bool fly = state == Dart.State.FLY;
        long tail = x - Dir * Dart.LENGTH;
        bodies[0] = Body.Kill(Shape.Rect(tail, lane_y - Dart.HALF_H, x, lane_y + Dart.HALF_H), fly);
        bodies[1] = Body.Kill(Shape.Rect(tail, lane2_y - Dart.HALF_H, x, lane2_y + Dart.HALF_H), fly && pair);
        bodies[0].guess = bodies[1].guess = lane_guess;
    }

    public override string Motion => lanes ? "shot_random_lane" : "shot_aimed_at_bird";

    public override string State => state switch
    {
        Dart.State.GLOW => "warning",
        Dart.State.FLY => "active",
        _ => "idle",
    };

    public override void Params(Dictionary<string, double> p)
    {
        p["lane_y"] = Px(lane_y);
        p["side"] = side;
        p["speed"] = Px(lanes ? lanes_speed : Dart.SPEED);
        p["glow"] = lanes ? lanes_flash : Dart.GLOW_TICKS;
        p["timer"] = t - since;
    }
}

/// Drop: waits, warns at a column, falls (plain, wobbling, shattering into
/// two shards, or staking into the floor as a growing spike). The next column
/// is random (a guess) unless the drop alternates between two fixed columns.
public sealed class DropM : HazardModel
{
    long x, y, phase, timer, speed, gap, warn, radius, style, column, base_x, fall_t, shard_t, shard_x, shard_dx,
        shard_y, shard_vy;
    bool x_guess;

    public DropM(Drop h)
    {
        kind = h.kind;
        x = h.x;
        y = h.y;
        phase = h.phase;
        timer = h.timer;
        speed = h.speed;
        gap = h.gap;
        warn = h.warn;
        radius = h.radius;
        style = h.style;
        column = h.column;
        base_x = h.base_x;
        fall_t = h.fall_t;
        shard_t = h.shard_t;
        shard_x = h.shard_x;
        shard_dx = h.shard_dx;
        shard_y = h.shard_y;
        shard_vy = h.shard_vy;
        random = column < 0;
        t = h.t;
        bodies = new Body[4];
        Place();
    }

    public override void Step(WorldModel w)
    {
        if (shard_t > 0)
        {
            shard_t -= 1;
            shard_dx += Drop.SHARD_VX;
            shard_vy += Drop.SHARD_GRAVITY;
            shard_y += shard_vy;
            if (shard_y > Drop.SHARD_FLOOR)
            {
                shard_y = Drop.SHARD_FLOOR;
                shard_vy = -Math.Abs(shard_vy) * 45 / 100;
            }
        }
        switch (phase)
        {
            case Drop.Phase.WAIT:
                timer -= 1;
                if (timer <= 0)
                {
                    phase = Drop.Phase.WARN;
                    timer = warn;
                    if (column >= 0)
                    {
                        base_x = column;
                        column = SimConfig.WORLD_W - column;
                    }
                    else
                    {
                        base_x = SimConfig.WORLD_W / 2;
                        x_guess = true;
                    }
                    x = base_x;
                    y = Drop.TOP;
                    fall_t = 0;
                }
                break;
            case Drop.Phase.WARN:
                timer -= 1;
                if (timer <= 0)
                {
                    phase = Drop.Phase.FALL;
                    y = Drop.TOP;
                }
                break;
            case Drop.Phase.FALL:
                y += speed;
                fall_t += 1;
                if (style == Drop.Style.WOBBLE)
                    x = base_x + Drop.SWAY * SimTrig.sin_t(fall_t * SimTrig.TURN / Drop.SWAY_PERIOD) / SimTrig.ONE;
                if (style == Drop.Style.SHATTER && y + radius >= SimConfig.KILL_BOTTOM)
                {
                    shard_t = Drop.SHARD_LIFE;
                    shard_x = x;
                    shard_dx = 0;
                    shard_y = SimConfig.KILL_BOTTOM - Drop.SHARD_START;
                    shard_vy = Drop.SHARD_VY;
                    phase = Drop.Phase.WAIT;
                    timer = gap;
                }
                else if (style == Drop.Style.STAKE && y + radius >= SimConfig.KILL_BOTTOM)
                {
                    y = SimConfig.KILL_BOTTOM - radius;
                    phase = Drop.Phase.STAKE;
                    timer = Drop.STAKE_STEPS;
                }
                else if (y - radius > SimConfig.WORLD_H)
                {
                    phase = Drop.Phase.WAIT;
                    timer = gap;
                }
                break;
            case Drop.Phase.STAKE:
                timer -= 1;
                if (timer <= 0)
                {
                    phase = Drop.Phase.WAIT;
                    timer = gap;
                }
                break;
        }
        Place();
    }

    long StakeHeight()
    {
        if (phase != Drop.Phase.STAKE) return 0;
        long age = Drop.STAKE_STEPS - timer;
        if (age < Drop.STAKE_GROW) return Drop.STAKE_HEIGHT * (age + 1) / Drop.STAKE_GROW;
        if (timer < Drop.STAKE_SINK) return Drop.STAKE_HEIGHT * timer / Drop.STAKE_SINK;
        return Drop.STAKE_HEIGHT;
    }

    void Place()
    {
        bodies[0] = Body.Kill(Shape.Circle(x, y, radius), phase == Drop.Phase.FALL);
        bodies[1] = Body.Kill(Shape.Circle(shard_x - shard_dx, shard_y, Drop.SHARD_RADIUS), shard_t > 0);
        bodies[2] = Body.Kill(Shape.Circle(shard_x + shard_dx, shard_y, Drop.SHARD_RADIUS), shard_t > 0);
        long tip = SimConfig.KILL_BOTTOM - StakeHeight();
        long ex = Drop.FLOOR_SPIKE_W / 2 + StakeHeight() / 10;
        bodies[3] = Body.Kill(Shape.Tri(base_x, tip, base_x - ex, Drop.FLOOR_BASE, base_x + ex, Drop.FLOOR_BASE),
            phase == Drop.Phase.STAKE);
        bodies[0].guess = bodies[1].guess = bodies[2].guess = bodies[3].guess = x_guess;
    }

    public override string Motion => style switch
    {
        Drop.Style.WOBBLE => "fall_wobble",
        Drop.Style.SHATTER => "fall_shatter",
        Drop.Style.STAKE => "fall_stake",
        _ => "fall",
    };

    public override string State => phase switch
    {
        Drop.Phase.WARN => "warning",
        Drop.Phase.FALL => "active",
        Drop.Phase.STAKE => "active",
        _ => shard_t > 0 ? "active" : "idle",
    };

    public override void Params(Dictionary<string, double> p)
    {
        p["column_x"] = Px(base_x);
        p["speed"] = Px(speed);
        p["timer"] = timer;
        p["gap"] = gap;
        p["warn"] = warn;
    }
}

/// Firework: sits on its pad (the burst height is shown as a ring), climbs,
/// bursts into sparks flying out at a fixed speed, rests, then reloads at a
/// new random spot (a guess until it is on the pad).
public sealed class FireworkM : HazardModel
{
    long x, y, burst_y, phase, timer, spread, style;
    bool spot_guess;

    public FireworkM(Firework h)
    {
        kind = h.kind;
        x = h.x;
        y = h.y;
        burst_y = h.burst_y;
        phase = h.phase;
        timer = h.timer;
        spread = h.spread;
        style = h.style;
        random = true;
        t = h.t;
        bodies = new Body[1 + SparkCount];
        Place();
    }

    long SparkCount => style == Firework.Style.DOUBLE ? 2 * Firework.SPARKS
        : style == Firework.Style.CROSS ? Firework.ARMS * Firework.ARM_SPARKS : Firework.SPARKS;

    long BurstSteps => style == Firework.Style.DOUBLE ? Firework.BURST + Firework.ECHO : Firework.BURST;

    public override void Step(WorldModel w)
    {
        switch (phase)
        {
            case Firework.Phase.PAD:
                timer -= 1;
                if (timer <= 0) phase = Firework.Phase.CLIMB;
                break;
            case Firework.Phase.CLIMB:
                y -= Firework.CLIMB_VY;
                if (y <= burst_y)
                {
                    y = burst_y;
                    phase = Firework.Phase.BURST;
                    timer = 0;
                    spread = 0;
                }
                break;
            case Firework.Phase.BURST:
                timer += 1;
                spread += Firework.SPARK_SPEED;
                if (timer >= BurstSteps)
                {
                    phase = Firework.Phase.REST;
                    timer = Firework.REST;
                }
                break;
            case Firework.Phase.REST:
                timer -= 1;
                if (timer <= 0)
                {
                    phase = Firework.Phase.PAD;
                    timer = Firework.PAD;
                    spread = 0;
                    x = SimConfig.WORLD_W / 2;
                    burst_y = (Firework.MIN_BURST_Y + Firework.MAX_BURST_Y) / 2;
                    y = Firework.PAD_Y;
                    spot_guess = true;
                }
                break;
        }
        Place();
    }

    long SparkStart(long i) => style == Firework.Style.DOUBLE && i >= Firework.SPARKS ? Firework.ECHO : 0;

    long SparkAngle(long i) => style switch
    {
        Firework.Style.DOUBLE => (2 * (i % Firework.SPARKS) + (i >= Firework.SPARKS ? 1 : 0)) * SimTrig.TURN / (2 * Firework.SPARKS),
        Firework.Style.CROSS => (i / Firework.ARM_SPARKS) * SimTrig.TURN / Firework.ARMS,
        _ => i * SimTrig.TURN / Firework.SPARKS,
    };

    long SparkDist(long i) => style switch
    {
        Firework.Style.DOUBLE => Math.Max(0, timer - SparkStart(i)) * Firework.SPARK_SPEED,
        Firework.Style.CROSS => spread * (i % Firework.ARM_SPARKS + 1) / Firework.ARM_SPARKS,
        _ => spread,
    };

    void Place()
    {
        bodies[0] = Body.Kill(Shape.Circle(x, y, Firework.ROCKET_RADIUS), phase == Firework.Phase.CLIMB);
        for (long i = 0; i < SparkCount; i++)
        {
            long age = timer - SparkStart(i);
            bool live = phase == Firework.Phase.BURST && age >= 0 && age < Firework.SPARK_DEADLY;
            long d = SparkDist(i);
            long a = SparkAngle(i);
            bodies[1 + i] = Body.Kill(Shape.Circle(x + d * SimTrig.cos_t(a) / SimTrig.ONE,
                y + d * SimTrig.sin_t(a) / SimTrig.ONE, Firework.SPARK_RADIUS), live);
        }
        for (int i = 0; i < bodies.Length; i++) bodies[i].guess = spot_guess;
    }

    public override string Motion => "rocket_burst";

    public override string State => phase switch
    {
        Firework.Phase.PAD => "warning",
        Firework.Phase.REST => "idle",
        _ => "active",
    };

    public override void Params(Dictionary<string, double> p)
    {
        p["burst_y"] = Px(burst_y);
        p["climb_speed"] = Px(Firework.CLIMB_VY);
        p["spark_speed"] = Px(Firework.SPARK_SPEED);
        p["timer"] = timer;
    }
}

/// Crate drop: crates fall (accelerating) into columns and stack up from the
/// floor. The falling column is marked during the warning; the column after
/// that is hidden (a guess).
public sealed class CrateDropM : HazardModel
{
    long cols, col_w, col_x0, crate_w, crate_h, col, y, vy, col_b, y_b, vy_b, warn_left;
    bool pair, done, done_b, col_guess;
    long[] heights;

    public CrateDropM(CrateDrop h)
    {
        kind = h.kind;
        cols = h.cols;
        col_w = h.col_w;
        col_x0 = h.col_x0;
        crate_w = h.crate_w;
        crate_h = h.crate_h;
        col = h.col;
        y = h.y;
        vy = h.vy;
        col_b = h.col_b;
        y_b = h.y_b;
        vy_b = h.vy_b;
        warn_left = h.warn_left;
        pair = h.pair;
        done = h.done;
        done_b = h.done_b;
        heights = h.heights.ToArray();
        random = true;
        t = h.t;
        bodies = new Body[2 + cols];
        Place();
    }

    protected override void CopyLists(HazardModel c) => ((CrateDropM)c).heights = (long[])heights.Clone();

    long ColLeft(long c) => col_x0 + c * col_w + (col_w - crate_w) / 2;
    long StackTop(long c) => CrateDrop.FLOOR - heights[c] * crate_h;

    public override void Step(WorldModel w)
    {
        if (col < 0) return;
        if (warn_left > 0)
        {
            warn_left -= 1;
            Place();
            return;
        }
        if (!done)
        {
            vy = Math.Min(vy + CrateDrop.FALL_ACCEL, CrateDrop.MAX_FALL);
            y += vy;
            long land = StackTop(col) - crate_h;
            if (y >= land)
            {
                y = land;
                if (!col_guess) heights[col] += 1;
                done = true;
            }
        }
        if (col_b >= 0 && !done_b)
        {
            vy_b = Math.Min(vy_b + CrateDrop.FALL_ACCEL, CrateDrop.MAX_FALL);
            y_b += vy_b;
            long land_b = StackTop(col_b) - crate_h;
            if (y_b >= land_b)
            {
                y_b = land_b;
                if (!col_guess) heights[col_b] += 1;
                done_b = true;
            }
        }
        if (done && (col_b < 0 || done_b))
        {
            // The next column comes from a hidden hash: guess the middle one.
            col_guess = true;
            col = cols / 2;
            col_b = pair ? (col + cols / 2) % cols : -1;
            y = -crate_h;
            vy = 0;
            done = false;
            y_b = y;
            vy_b = 0;
            done_b = false;
            warn_left = CrateDrop.WARN_TICKS;
        }
        Place();
    }

    void Place()
    {
        bool falling = col >= 0 && warn_left == 0;
        long xa = ColLeft(Math.Max(col, 0));
        bodies[0] = Body.Kill(Shape.Rect(xa, y, xa + crate_w, y + crate_h), falling && !done);
        long xb = ColLeft(Math.Max(col_b, 0));
        bodies[1] = Body.Kill(Shape.Rect(xb, y_b, xb + crate_w, y_b + crate_h), falling && col_b >= 0 && !done_b);
        bodies[0].guess = bodies[1].guess = col_guess;
        for (long c = 0; c < cols; c++)
        {
            long x = ColLeft(c);
            bodies[2 + c] = Body.Kill(Shape.Rect(x, StackTop(c), x + crate_w, SimConfig.WORLD_H), heights[c] > 0);
        }
    }

    public override string Motion => "fall_and_stack";
    public override string State => col >= 0 && warn_left > 0 ? "warning" : "active";

    public override void Params(Dictionary<string, double> p)
    {
        p["column"] = col;
        p["warn_left"] = warn_left;
        p["crate"] = Px(crate_h);
        for (long c = 0; c < cols; c++) p["stack" + c] = heights[c];
    }
}

/// Bubble: rises from the floor and pops at the top. A plain bubble carries the
/// bird (a tap pops it); a spiked one kills. Where the next bubble rises is a
/// hidden random column (a guess).
public sealed class BubbleM : HazardModel
{
    public bool carrying;
    long x, y, vy, cooldown, radius, wait;
    bool spiked, x_guess;

    public BubbleM(Bubble h)
    {
        kind = h.kind;
        reactive = true;
        random = true;
        carrying = h.carrying;
        x = h.x;
        y = h.y;
        vy = h.vy;
        cooldown = h.cooldown;
        radius = h.radius;
        wait = h.wait;
        spiked = h.spiked;
        t = h.t;
        bodies = new Body[1];
        Place();
    }

    public override void Step(WorldModel w)
    {
        if (cooldown > 0) cooldown -= 1;
        if (wait > 0)
        {
            wait -= 1;
            Place();
            return;
        }
        y += vy;
        if (y - radius <= Bubble.POP_TOP) Pop();
        Place();
    }

    void Pop()
    {
        carrying = false;
        cooldown = Bubble.REGRAB;
        x = (Bubble.MIN_X + Bubble.MAX_X) / 2;
        x_guess = true;
        y = SimConfig.WORLD_H + radius;
        if (spiked) wait = Bubble.WARN;
    }

    void Place()
    {
        bodies[0] = spiked ? Body.Kill(Shape.Circle(x, y, radius), wait == 0) : Body.Soft(Shape.Circle(x, y, radius));
        bodies[0].guess = x_guess;
    }

    public override void Touch(WorldModel w, ref Bird b)
    {
        if (spiked) return;
        if (carrying) Hold(ref b);
        else if (cooldown == 0 && !x_guess && Shape.Circle(x, y, radius - Physics.R).Hits(b.x, b.y, Physics.R))
        {
            foreach (var h in w.hz)
                if (h != this && h.alive && h is BubbleM o && o.carrying) return;
            carrying = true;
            Hold(ref b);
        }
    }

    void Hold(ref Bird b)
    {
        x = b.x;
        b.y = y;
        b.vy = vy;
        Place();
    }

    public override void OnFlap(WorldModel w)
    {
        if (carrying) Pop();
    }

    public override string Motion => "rise";
    public override string State => carrying ? "carrying" : wait > 0 ? "warning" : "active";

    public override void Params(Dictionary<string, double> p)
    {
        p["rise"] = Px(-vy);
        p["spiked"] = spiked ? 1 : 0;
        p["wait"] = wait;
    }
}

/// Stalactite: a column with spikes from the ceiling and floor and a gap that
/// slides (3 px/substep) toward a target height drawn at each bounce (near the
/// bird's height then). The target is hidden: the model sees the slide (from
/// memory of the last tick) and guesses it stops near the bird's bounce height.
public sealed class StalactiteM : HazardModel
{
    long x, gap_y, gap, half_w, est_target;
    bool top, bottom, fixed_gap, moving_guess;

    public StalactiteM(Stalactite h, Memory mem, int index)
    {
        kind = h.kind;
        x = h.x;
        gap_y = h.gap_y;
        gap = h.gap;
        half_w = h.half_w;
        top = h.top;
        bottom = h.bottom;
        fixed_gap = h.fixed_lo >= 0;
        random = !fixed_gap;
        t = h.t;
        est_target = gap_y;
        if (!fixed_gap && mem != null && mem.gap_v.TryGetValue(index, out long v) && v != 0)
        {
            moving_guess = true;
            long guess = mem.bounce_y >= 0 ? Math.Clamp(mem.bounce_y, Stalactite.GAP_MIN, Stalactite.GAP_MAX) : gap_y;
            if (Math.Sign(guess - gap_y) != Math.Sign(v)) guess = gap_y + Math.Sign(v) * Stalactite.REACH;
            est_target = Math.Clamp(guess, Stalactite.GAP_MIN, Stalactite.GAP_MAX);
        }
        bodies = new Body[2];
        Place();
    }

    public override void Step(WorldModel w)
    {
        if (gap_y < est_target) gap_y = Math.Min(gap_y + Stalactite.SLIDE, est_target);
        else if (gap_y > est_target) gap_y = Math.Max(gap_y - Stalactite.SLIDE, est_target);
        Place();
    }

    public override void OnBounce(WorldModel w)
    {
        if (fixed_gap) return;
        est_target = Math.Clamp(w.bird.y, Stalactite.GAP_MIN, Stalactite.GAP_MAX);
        moving_guess = true;
    }

    void Place()
    {
        bodies[0] = Body.Kill(Shape.Rect(x - half_w, 0, x + half_w, gap_y - gap / 2), top);
        bodies[1] = Body.Kill(Shape.Rect(x - half_w, gap_y + gap / 2, x + half_w, SimConfig.WORLD_H), bottom);
        bodies[0].guess = bodies[1].guess = moving_guess;
    }

    public override string Motion => fixed_gap ? "static" : "gap_slide_to_hidden_target";

    public override void Params(Dictionary<string, double> p)
    {
        p["x"] = Px(x);
        p["gap_y"] = Px(gap_y);
        p["gap"] = Px(gap);
        p["slide"] = Px(Stalactite.SLIDE);
        p["target_guess"] = Px(est_target);
    }
}

/// Lava: a floor (or ceiling) line that rises one step (30 px) per point,
/// moving 80/substep toward its level; touching the stone lowers it again.
public sealed class LavaM : HazardModel
{
    long line, rises, counted, stone_x, stone_y;
    bool stone_on, stone_guess;

    public LavaM(Lava h)
    {
        kind = h.kind;
        line = h.line;
        rises = h.rises;
        counted = h.counted;
        stone_on = h.stone_on;
        stone_x = h.stone_x;
        stone_y = h.stone_y;
        reactive = true;
        t = h.t;
        bodies = new Body[2];
        Place();
    }

    // Lava only rises from the floor (the ceiling crusher variant was removed).
    long LineAt(long n) => SimConfig.KILL_BOTTOM - n * Lava.STEP;

    public override void Step(WorldModel w)
    {
        line += Math.Clamp(LineAt(rises) - line, -Lava.SPEED, Lava.SPEED);
        Place();
    }

    void Place()
    {
        const long FAR = 1L << 28;
        bodies[0] = Body.Kill(Shape.Rect(-FAR, line, FAR, FAR), line < SimConfig.KILL_BOTTOM);
        bodies[1] = Body.Soft(Shape.Circle(stone_x, stone_y, Lava.STONE_RADIUS), stone_on);
        bodies[1].guess = stone_guess;
    }

    public override void Touch(WorldModel w, ref Bird b)
    {
        if (stone_on && !stone_guess && bodies[1].s.Hits(b.x, b.y, Physics.R))
        {
            stone_on = false;
            rises = 0;
            Place();
        }
    }

    public override void OnBounce(WorldModel w)
    {
        rises = Math.Min(rises + w.room.points - counted, Lava.MAX_RISES);
        counted = w.room.points;
        if (!stone_on && rises >= Lava.STONE_AFTER)
        {
            stone_on = true;
            stone_guess = true;
        }
        Place();
    }

    public override string Motion => "rise_per_point";

    public override void Params(Dictionary<string, double> p)
    {
        p["line"] = Px(line);
        p["target"] = Px(LineAt(rises));
        p["step"] = Px(Lava.STEP);
        p["speed"] = Px(Lava.SPEED);
    }
}

/// Keepy ball: a ball that falls; the bird kicks it up for coins (never kills).
public sealed class KeepyBallM : HazardModel
{
    long gravity, kick_vy, waiting, redrop, x, y, vx, vy, cooldown;

    public KeepyBallM(KeepyBall h)
    {
        kind = h.kind;
        gravity = h.gravity;
        kick_vy = h.kick_vy;
        waiting = h.waiting;
        redrop = h.redrop;
        x = h.x;
        y = h.y;
        vx = h.vx;
        vy = h.vy;
        cooldown = h.cooldown;
        selfish = true;
        t = h.t;
        bodies = new Body[1];
        Place();
    }

    void Place() => bodies[0] = Body.Soft(Shape.Circle(x, y, KeepyBall.RADIUS), waiting == 0);

    public override void Step(WorldModel w)
    {
        if (waiting > 0)
        {
            waiting -= 1;
            Place();
            return;
        }
        if (cooldown > 0) cooldown -= 1;
        vy = Math.Min(vy + gravity, KeepyBall.MAX_VY);
        x += vx;
        y += vy;
        long left = w.room.WallLeft + KeepyBall.RADIUS;
        long right = w.room.WallRight - KeepyBall.RADIUS;
        if (x < left)
        {
            x = 2 * left - x;
            vx = Math.Abs(vx);
        }
        else if (x > right)
        {
            x = 2 * right - x;
            vx = -Math.Abs(vx);
        }
        long top = SimConfig.KILL_TOP + KeepyBall.RADIUS;
        if (vy < 0 && y < top)
        {
            y = 2 * top - y;
            vy = -vy;
        }
        if (y + KeepyBall.RADIUS >= SimConfig.KILL_BOTTOM)
        {
            if (redrop == 0)
            {
                alive = false;
                return;
            }
            waiting = redrop;
            x = Math.Clamp(SimConfig.WORLD_W - x, KeepyBall.MIN_X, KeepyBall.MAX_X);
            y = -KeepyBall.RADIUS;
            vx = 0;
            vy = 0;
            cooldown = 0;
        }
        Place();
    }

    public override void Touch(WorldModel w, ref Bird b)
    {
        if (waiting > 0 || cooldown > 0 || !bodies[0].s.Hits(b.x, b.y, Physics.R)) return;
        long dx = x - b.x;
        long reach = Physics.R + KeepyBall.RADIUS;
        vx = Math.Clamp(dx, -reach, reach) * KeepyBall.KICK_VX / reach;
        vy = -kick_vy;
        long above = b.y - reach;
        if (y > above) y = above;
        cooldown = KeepyBall.COOLDOWN;
        Place();
    }

    public override string Motion => "ballistic";

    public override void Params(Dictionary<string, double> p)
    {
        p["vx"] = Px(vx);
        p["vy"] = Px(vy);
        p["gravity"] = gravity;
    }
}

/// A coin: still, swaying with an island, falling, appearing later, orbiting a
/// point, or riding an edge pad. Never kills.
public sealed class CoinM : HazardModel
{
    long x, y, appear_at, vy, drift, home_x, cx, cy, radius, phase, wait;
    bool orbit, pad, on_top;

    public CoinM(CoinPickup h)
    {
        kind = h.kind;
        x = h.x;
        y = h.y;
        appear_at = h.appear_at;
        vy = h.vy;
        drift = h.drift;
        home_x = h.home_x;
        selfish = true;
        t = h.t;
        if (h is OrbitCoin o)
        {
            orbit = true;
            cx = o.cx;
            cy = o.cy;
            radius = o.radius;
            phase = o.phase;
        }
        if (h is PadCoin p)
        {
            pad = true;
            on_top = p.on_top;
            wait = p.wait;
        }
        bodies = new Body[1];
        Place();
    }

    bool Visible => pad ? wait == 0 : t >= appear_at;

    void Place() => bodies[0] = Body.Soft(Shape.Circle(x, y, SimConfig.COIN_RADIUS), Visible);

    public override void Step(WorldModel w)
    {
        if (orbit)
        {
            long a = phase + t * SimTrig.TURN / OrbitCoin.PERIOD;
            x = cx + radius * SimTrig.cos_t(a) / SimTrig.ONE;
            y = cy + radius * SimTrig.sin_t(a) / SimTrig.ONE;
        }
        else if (pad)
        {
            if (wait > 0) wait -= 1;
            Follow(w);
        }
        else
        {
            if (drift > 0) x = home_x + Block.sway(drift, t);
            if (vy != 0 && Visible)
            {
                y += vy;
                if (y > SimConfig.KILL_BOTTOM + SimConfig.COIN_RADIUS) alive = false;
            }
        }
        Place();
    }

    void Follow(WorldModel w)
    {
        foreach (var h in w.hz)
            if (h is EdgePadM p && p.top == on_top)
            {
                x = Math.Clamp((p.X0 + p.X0 + EdgePad.WIDTH) / 2, SimConfig.COIN_MIN_X, SimConfig.COIN_MAX_X);
                y = on_top ? SimConfig.COIN_MIN_Y : SimConfig.COIN_MAX_Y;
                return;
            }
    }

    public override void Touch(WorldModel w, ref Bird b)
    {
        if (!Visible || !bodies[0].s.Hits(b.x, b.y, Physics.R)) return;
        if (pad)
        {
            on_top = !on_top;
            wait = PadCoin.RESPAWN;
            Follow(w);
        }
        else alive = false;
        Place();
    }

    public override string Motion => orbit ? "orbit" : pad ? "ride_pad" : vy != 0 ? "fall" : drift > 0 ? "sway" : "static";
}

/// Orchard: coins dropping from five columns; a new one every 36 substeps
/// from a hidden random column (guessed).
public sealed class OrchardM : HazardModel
{
    long[] xs, ys;
    bool[] live, guess;

    public OrchardM(OrchardSpawner h)
    {
        kind = h.kind;
        random = true;
        selfish = true;
        xs = h.xs.ToArray();
        ys = h.ys.ToArray();
        live = h.live.ToArray();
        guess = new bool[xs.Length];
        t = h.t;
        bodies = new Body[xs.Length];
        Place();
    }

    protected override void CopyLists(HazardModel c)
    {
        var o = (OrchardM)c;
        o.xs = (long[])xs.Clone();
        o.ys = (long[])ys.Clone();
        o.live = (bool[])live.Clone();
        o.guess = (bool[])guess.Clone();
    }

    public override void Step(WorldModel w)
    {
        for (int i = 0; i < xs.Length; i++)
            if (live[i])
            {
                ys[i] += OrchardSpawner.FALL;
                if (ys[i] > SimConfig.KILL_BOTTOM + SimConfig.COIN_RADIUS) live[i] = false;
            }
        if (t % OrchardSpawner.SPAWN_EVERY == 1)
            for (int i = 0; i < xs.Length; i++)
                if (!live[i])
                {
                    live[i] = true;
                    guess[i] = true;
                    xs[i] = OrchardSpawner.COLUMNS[2];
                    ys[i] = OrchardSpawner.START_Y;
                    break;
                }
        Place();
    }

    void Place()
    {
        for (int i = 0; i < xs.Length; i++)
        {
            bodies[i] = Body.Soft(Shape.Circle(xs[i], ys[i], SimConfig.COIN_RADIUS), live[i]);
            bodies[i].guess = guess[i];
        }
    }

    public override void Touch(WorldModel w, ref Bird b)
    {
        for (int i = 0; i < xs.Length; i++)
            if (live[i] && !guess[i] && bodies[i].s.Hits(b.x, b.y, Physics.R)) live[i] = false;
    }

    public override string Motion => "fall";
}

/// Locked Out: keys that must be taken before the exit lets the bird through
/// (still, one on an orbit, or a chain where each key shows after the last).
public sealed class ExitKeyM : HazardModel
{
    long mode, count, got, taken_mask, phase, locked_bounces;
    long[] kx, ky, chain_off, chain_d;

    public ExitKeyM(ExitKey h)
    {
        kind = h.kind;
        mode = h.mode;
        count = h.count;
        got = h.got;
        taken_mask = h.taken_mask;
        phase = h.phase;
        locked_bounces = h.locked_bounces;
        kx = (long[])h.kx.Clone();
        ky = (long[])h.ky.Clone();
        chain_off = (long[])h.chain_off.Clone();
        chain_d = (long[])h.chain_d.Clone();
        reactive = true;
        t = h.t;
        bodies = new Body[ExitKey.MAX_KEYS];
        Place();
    }

    protected override void CopyLists(HazardModel c)
    {
        var e = (ExitKeyM)c;
        e.kx = (long[])kx.Clone();
        e.ky = (long[])ky.Clone();
    }

    bool Done => got >= count;

    bool Shown(long i) => i < count && ((taken_mask >> (int)i) & 1) == 0 && (mode != ExitKey.Mode.CHAIN || i == got);

    void Place()
    {
        for (int i = 0; i < ExitKey.MAX_KEYS; i++)
            bodies[i] = Body.Soft(Shape.Circle(kx[i], ky[i], ExitKey.RADIUS), Shown(i));
    }

    public override void Step(WorldModel w)
    {
        if (mode == ExitKey.Mode.ORBIT && !Done)
        {
            long a = phase + t * SimTrig.TURN / ExitKey.ORBIT_STEPS;
            kx[0] = ExitKey.ORBIT_CX + ExitKey.ORBIT_RX * SimTrig.cos_t(a) / SimTrig.ONE;
            ky[0] = ExitKey.ORBIT_CY + ExitKey.ORBIT_RY * SimTrig.sin_t(a) / SimTrig.ONE;
        }
        Place();
    }

    public override void Touch(WorldModel w, ref Bird b)
    {
        for (long i = 0; i < count; i++)
        {
            if (!Shown(i) || !bodies[i].s.Hits(b.x, b.y, Physics.R)) continue;
            taken_mask |= 1L << (int)i;
            got += 1;
            if (mode == ExitKey.Mode.CHAIN && !Done)
            {
                long side = b.vx > 0 ? 0 : 1;
                kx[got] = side == 0 ? w.room.WallLeft + chain_off[got] : w.room.WallRight - chain_off[got];
                long ny = b.y > ExitKey.MID_Y ? b.y - chain_d[got] : b.y + chain_d[got];
                ky[got] = Math.Clamp(ny, ExitKey.KEY_MIN_Y, ExitKey.KEY_MAX_Y);
            }
            Place();
            return;
        }
    }

    public override bool Locks => !Done && locked_bounces < ExitKey.MAX_LOCKED_BOUNCES;

    public override void OnBounce(WorldModel w)
    {
        if (w.room.exit_open && !Done) locked_bounces += 1;
    }

    public override string Motion => mode == ExitKey.Mode.ORBIT ? "orbit" : mode == ExitKey.Mode.CHAIN ? "chain" : "static";
    public override string State => Done ? "unlocked" : "locked";

    public override void Params(Dictionary<string, double> p)
    {
        p["keys"] = count;
        p["got"] = got;
    }
}

/// A hazard class the model does not know (none today): no bodies.
public sealed class UnknownM : HazardModel
{
    public UnknownM(Hazard h)
    {
        kind = h.kind;
        random = true;
    }

    public override void Step(WorldModel w) { }
    public override string Motion => "unknown";
}

/// Reads each hazard class into its model.
public static class Models
{
    public static HazardModel Read(Hazard h, GameSim sim, Memory mem, int index) => h switch
    {
        Mover m => new MoverM(m),
        Bouncer b => new BouncerM(b),
        Bumper b => new BumperM(b),
        Pendulum p => new PendulumM(p),
        Rotor r => new RotorM(r),
        SawRing s => new SawRingM(s),
        Crawler c => new CrawlerM(c),
        Gate g => new GateM(g),
        Block b => new BlockM(b),
        SpikeBall s => new SpikeBallM(s),
        EdgePad p => new EdgePadM(p),
        Updraft u => new UpdraftM(u),
        Wind wd => new WindM(wd),
        Belt b => new BeltM(b),
        Echo e => new EchoM(e),
        Stalker s => new StalkerM(s),
        Beam b => new BeamM(b),
        Piston p => new PistonM(p, sim),
        Dart d => new DartM(d),
        Drop d => new DropM(d),
        Firework f => new FireworkM(f),
        CrateDrop c => new CrateDropM(c),
        Bubble b => new BubbleM(b),
        Stalactite s => new StalactiteM(s, mem, index),
        Lava l => new LavaM(l),
        KeepyBall k => new KeepyBallM(k),
        CoinPickup c => new CoinM(c),
        OrchardSpawner o => new OrchardM(o),
        ExitKey e => new ExitKeyM(e),
        _ => new UnknownM(h),
    };

    /// Re-points links between models (a follower piston to its leader) after a read or a copy.
    public static void Link(WorldModel w)
    {
        foreach (var h in w.hz)
            if (h is PistonM p && p.leader_index >= 0) p.leader = w.Find(p.leader_index) as PistonM;
    }

    /// Every hazard class FastSim has, for coverage checks.
    public static readonly Type[] CLASSES =
    {
        typeof(Mover), typeof(Bouncer), typeof(CuriousBouncer), typeof(HeavyBouncer), typeof(RevvingBouncer),
        typeof(SplittingBouncer), typeof(Bumper), typeof(Pendulum), typeof(Rotor), typeof(SawRing), typeof(Crawler),
        typeof(Gate), typeof(Block), typeof(SpikeBall), typeof(EdgePad), typeof(Updraft), typeof(Wind), typeof(Belt),
        typeof(Echo), typeof(Stalker), typeof(Beam), typeof(Piston), typeof(Dart), typeof(Drop), typeof(Firework),
        typeof(CrateDrop), typeof(Bubble), typeof(Stalactite), typeof(Lava), typeof(KeepyBall), typeof(CoinPickup),
        typeof(OrbitCoin), typeof(PadCoin), typeof(OrchardSpawner), typeof(ExitKey),
    };
}
