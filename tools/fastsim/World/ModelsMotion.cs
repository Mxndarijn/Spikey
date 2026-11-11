namespace FastSim.Model;

// Hazards that move by a fixed rule of their clock (closed form) or by plain
// physics (bouncers). Their whole future follows from the present state, so
// the model predicts them exactly, except the ones that react to the bird.

/// Mover: saws on a figure-eight (Lissajous x = sin a, y = sin 2a) or a wave
/// (ping-pong x, sine y); the "chase" saw speeds up lap by lap.
public sealed class MoverM : HazardModel
{
    string mode;
    long count, loop_w, loop_h, loop_period, phase;
    bool chase;

    public MoverM(Mover h)
    {
        kind = h.kind;
        mode = h.mode;
        count = h.count;
        loop_w = h.loop_w;
        loop_h = h.loop_h;
        loop_period = h.loop_period;
        phase = h.phase;
        chase = h.chase;
        t = h.t;
        bodies = new Body[count];
        for (int i = 0; i < count; i++) bodies[i] = Body.Kill(Shape.Circle(h.xs[i], h.ys[i], Mover.RADIUS));
    }

    public override void Step(WorldModel w) => Place();

    long ChaseTenths(long tick)
    {
        long start = 0;
        for (long k = 0; k < Mover.CHASE_LAPS; k++)
        {
            long num = Mover.CHASE_DEN + k * Mover.CHASE_STEP;
            long lap = (loop_period * Mover.CHASE_DEN + num - 1) / num;
            if (tick < start + lap) return k * loop_period * Mover.CHASE_DEN + (tick - start) * num;
            start += lap;
        }
        long top = Mover.CHASE_DEN + Mover.CHASE_LAPS * Mover.CHASE_STEP;
        return Mover.CHASE_LAPS * loop_period * Mover.CHASE_DEN + (tick - start) * top;
    }

    void Place()
    {
        for (long i = 0; i < count; i++)
        {
            long nx, ny;
            if (mode == "figure8")
            {
                long k = (t + phase) * Mover.CHASE_DEN;
                if (chase && i == count - 1) k = ChaseTenths(t) + phase * Mover.CHASE_DEN;
                long a = k * SimTrig.TURN / (loop_period * Mover.CHASE_DEN) + i * SimTrig.TURN / count;
                nx = Mover.CENTER_X + loop_w * SimTrig.sin_t(a) / SimTrig.ONE;
                ny = Mover.CENTER_Y + loop_h * SimTrig.sin_t(2 * a) / SimTrig.ONE;
            }
            else
            {
                long k = t + phase - i * Mover.WAVE_SPACING;
                nx = Mover.WAVE_MIN_X + SimTrig.ping_pong(k, Mover.WAVE_PERIOD, Mover.WAVE_MAX_X - Mover.WAVE_MIN_X);
                long a = k * SimTrig.TURN * Mover.WAVE_TURNS / Mover.WAVE_PERIOD;
                ny = Mover.CENTER_Y + Mover.WAVE_AMP * SimTrig.sin_t(a) / SimTrig.ONE;
            }
            bodies[i].s = Shape.Circle(nx, ny, Mover.RADIUS);
        }
    }

    public override string Motion => mode == "figure8" ? (chase ? "figure8_chase" : "figure8") : "wave";

    public override void Params(Dictionary<string, double> p)
    {
        p["count"] = count;
        p["period"] = mode == "figure8" ? loop_period : Mover.WAVE_PERIOD;
        p["phase"] = phase;
        p["half_w"] = Px(mode == "figure8" ? loop_w : (Mover.WAVE_MAX_X - Mover.WAVE_MIN_X) / 2);
        p["half_h"] = Px(mode == "figure8" ? loop_h : Mover.WAVE_AMP);
    }
}

/// Bouncer and its kinds: a ball flying straight, bouncing off the side walls
/// and the margins at the top and bottom. Heavy: falls and is launched up
/// again from the bottom. Revving: speeds up at every bounce (7 levels).
/// Curious: steers its vy toward the bird's height (reacts to the bird).
/// Splitting: after its warning splits in two when the bird is far enough.
public sealed class BouncerM : HazardModel
{
    public enum K { Plain, Curious, Heavy, Revving, Splitting }

    public K k;
    long radius, x, y, vx, vy;
    long look, bounces, level, warn;
    bool split;
    long ox, oy, ovx, ovy, oradius;

    public BouncerM(Bouncer h)
    {
        kind = h.kind;
        radius = h.radius;
        x = h.x;
        y = h.y;
        vx = h.vx;
        vy = h.vy;
        t = h.t;
        switch (h)
        {
            case CuriousBouncer c:
                k = K.Curious;
                look = c.look;
                reactive = true;
                break;
            case HeavyBouncer hb:
                k = K.Heavy;
                bounces = hb.bounces;
                break;
            case RevvingBouncer rb:
                k = K.Revving;
                level = rb.level;
                break;
            case SplittingBouncer sb:
                k = K.Splitting;
                warn = sb.warn;
                reactive = true;
                if (sb.other != null)
                {
                    split = true;
                    ox = sb.other.x;
                    oy = sb.other.y;
                    ovx = sb.other.vx;
                    ovy = sb.other.vy;
                    oradius = sb.other.radius;
                }
                break;
            default:
                k = K.Plain;
                break;
        }
        bodies = new Body[k == K.Splitting ? 2 : 1];
        Place();
    }

    static long TopY(long r) => Bouncer.MARGIN + r;
    static long BottomY(long r) => SimConfig.WORLD_H - Bouncer.MARGIN - r;

    static bool Move(WorldModel w, long r, ref long x, ref long y, ref long vx, ref long vy)
    {
        x += vx;
        y += vy;
        bool side = Sides(w, r, ref x, ref vx);
        bool top = false, bottom = false;
        if (y < TopY(r))
        {
            y = 2 * TopY(r) - y;
            vy = Math.Abs(vy);
            top = true;
        }
        if (y > BottomY(r))
        {
            y = 2 * BottomY(r) - y;
            vy = -Math.Abs(vy);
            bottom = true;
        }
        return side || top || bottom;
    }

    static bool Sides(WorldModel w, long r, ref long x, ref long vx)
    {
        long left = w.room.WallLeft + r;
        long right = w.room.WallRight - r;
        if (x < left)
        {
            x = 2 * left - x;
            vx = Math.Abs(vx);
            return true;
        }
        if (x > right)
        {
            x = 2 * right - x;
            vx = -Math.Abs(vx);
            return true;
        }
        return false;
    }

    public override void Step(WorldModel w)
    {
        switch (k)
        {
            case K.Plain:
                Move(w, radius, ref x, ref y, ref vx, ref vy);
                break;
            case K.Curious:
            {
                long d = w.bird.y - y;
                look = Math.Sign(d);
                vy = Math.Clamp(vy + Math.Clamp(d / CuriousBouncer.STEER_DIV, -CuriousBouncer.STEER, CuriousBouncer.STEER),
                    -CuriousBouncer.MAX_VY, CuriousBouncer.MAX_VY);
                Move(w, radius, ref x, ref y, ref vx, ref vy);
                break;
            }
            case K.Heavy:
                vy += HeavyBouncer.GRAVITY;
                x += vx;
                y += vy;
                Sides(w, radius, ref x, ref vx);
                if (y < TopY(radius))
                {
                    y = 2 * TopY(radius) - y;
                    vy = Math.Abs(vy);
                }
                if (y > BottomY(radius))
                {
                    y = BottomY(radius);
                    vy = -HeavyBouncer.LAUNCH[bounces % 2];
                    bounces += 1;
                }
                break;
            case K.Revving:
                if (Move(w, radius, ref x, ref y, ref vx, ref vy) && level < RevvingBouncer.MAX_LEVEL)
                {
                    level += 1;
                    vx = Math.Sign(vx) * Bouncer.SPEED_X * (6 + level) / 10;
                    vy = Math.Sign(vy) * Bouncer.SPEED_Y * (6 + level) / 10;
                }
                break;
            case K.Splitting:
                Move(w, radius, ref x, ref y, ref vx, ref vy);
                if (split)
                {
                    Move(w, oradius, ref ox, ref oy, ref ovx, ref ovy);
                    break;
                }
                if (t < SplittingBouncer.SPLIT_AT) break;
                warn = Math.Min(t - SplittingBouncer.SPLIT_AT, SplittingBouncer.WARN);
                if (warn < SplittingBouncer.WARN) break;
                long dx = x - w.bird.x, dy = y - w.bird.y;
                if (dx * dx + dy * dy < SplittingBouncer.CLEAR * SplittingBouncer.CLEAR) break;
                radius = SplittingBouncer.SMALL_RADIUS;
                vx = Math.Sign(vx) * Bouncer.SPEED_X;
                vy = -Bouncer.SPEED_Y;
                split = true;
                ox = x;
                oy = y;
                ovx = vx;
                ovy = Bouncer.SPEED_Y;
                oradius = SplittingBouncer.SMALL_RADIUS;
                break;
        }
        Place();
    }

    void Place()
    {
        bodies[0] = Body.Kill(Shape.Circle(x, y, radius));
        if (k == K.Splitting) bodies[1] = Body.Kill(Shape.Circle(ox, oy, oradius), split);
    }

    public override string Motion => k switch
    {
        K.Heavy => "ballistic_bounce",
        K.Curious => "linear_steer_to_bird",
        K.Revving => "linear_bounce_speedup",
        K.Splitting => "linear_bounce_split",
        _ => "linear_bounce",
    };

    public override string State => k == K.Splitting ? (split ? "split" : warn > 0 ? "warning" : "whole") : "active";

    public override void Params(Dictionary<string, double> p)
    {
        p["vx"] = Px(vx);
        p["vy"] = Px(vy);
        p["top"] = Px(TopY(radius));
        p["bottom"] = Px(BottomY(radius));
        if (k == K.Heavy) p["gravity"] = Px(HeavyBouncer.GRAVITY);
        if (k == K.Revving) p["level"] = level;
    }
}

/// Bumper: a ball on an ellipse (cos, sin) that bumps the bird away (never kills).
public sealed class BumperM : HazardModel
{
    long radius, rx, ry, period, phase, dir, x, y;

    public BumperM(Bumper h)
    {
        kind = h.kind;
        radius = h.radius;
        rx = h.loop_rx;
        ry = h.loop_ry;
        period = h.period;
        phase = h.phase;
        dir = h.dir;
        x = h.x;
        y = h.y;
        t = h.t;
        bodies = new[] { Body.Soft(Shape.Circle(x, y, radius)) };
    }

    public override void Step(WorldModel w)
    {
        long a = phase + dir * (t * SimTrig.TURN / period);
        x = Bumper.CENTER_X + rx * SimTrig.cos_t(a) / SimTrig.ONE;
        y = Bumper.CENTER_Y + ry * SimTrig.sin_t(a) / SimTrig.ONE;
        bodies[0].s = Shape.Circle(x, y, radius);
    }

    public override void Touch(WorldModel w, ref Bird b)
    {
        if (!bodies[0].s.Hits(b.x, b.y, Physics.R)) return;
        b.vy = b.y < y ? -GameSim.BUMP_VY : GameSim.BUMP_VY;
        if ((b.x < x) == (b.vx > 0)) b.vx = -b.vx;
    }

    public override string Motion => "orbit";

    public override void Params(Dictionary<string, double> p)
    {
        p["cx"] = Px(Bumper.CENTER_X);
        p["cy"] = Px(Bumper.CENTER_Y);
        p["rx"] = Px(rx);
        p["ry"] = Px(ry);
        p["period"] = period;
        p["phase"] = phase;
        p["dir"] = dir;
    }
}

/// Pendulum: a ball on a chain swinging from a pivot (angle = amplitude x sin),
/// with optional gusts (wider swing) and a winch (longer chain), and a twin.
public sealed class PendulumM : HazardModel
{
    long pivot_x, pivot_y, length, radius, amplitude, period, gust, gust_period, winch, winch_period, twin_x,
        twin_length, phase;

    public PendulumM(Pendulum h)
    {
        kind = h.kind;
        pivot_x = h.pivot_x;
        pivot_y = h.pivot_y;
        length = h.length;
        radius = h.radius;
        amplitude = h.amplitude;
        period = h.period;
        gust = h.gust;
        gust_period = h.gust_period;
        winch = h.winch;
        winch_period = h.winch_period;
        twin_x = h.twin_x;
        twin_length = h.twin_length;
        phase = h.phase;
        t = h.t;
        bodies = new[]
        {
            Body.Kill(Shape.Circle(h.x, h.y, radius)),
            Body.Kill(Shape.Circle(h.x2, h.y2, radius), twin_length > 0),
        };
    }

    public override void Step(WorldModel w)
    {
        long widest = amplitude;
        if (gust != 0) widest += gust * SimTrig.sin_t(t * SimTrig.TURN / gust_period) / SimTrig.ONE;
        long chain = length;
        if (winch != 0) chain += winch * SimTrig.sin_t(t * SimTrig.TURN / winch_period - SimTrig.TURN / 4) / SimTrig.ONE;
        long angle = widest * SimTrig.sin_t(phase + t * SimTrig.TURN / period) / SimTrig.ONE;
        bodies[0].s = Shape.Circle(pivot_x + chain * SimTrig.sin_t(angle) / SimTrig.ONE,
            pivot_y + chain * SimTrig.cos_t(angle) / SimTrig.ONE, radius);
        if (twin_length > 0)
            bodies[1].s = Shape.Circle(twin_x - twin_length * SimTrig.sin_t(angle) / SimTrig.ONE,
                pivot_y + twin_length * SimTrig.cos_t(angle) / SimTrig.ONE, radius);
    }

    public override string Motion => "swing";

    public override void Params(Dictionary<string, double> p)
    {
        p["pivot_x"] = Px(pivot_x);
        p["pivot_y"] = Px(pivot_y);
        p["length"] = Px(length);
        p["amplitude"] = amplitude;
        p["period"] = period;
        p["phase"] = phase;
    }
}

/// Rotor: blades turning round one or two hubs (steady, rocking or breathing).
/// Each blade is sampled as 5 circles, as the sim's hit test does.
public sealed class RotorM : HazardModel
{
    long blades, blade_max, blade_min, half_w, hub_radius, period, spin, hubs, spread_x, spread_y, center_x, center_y,
        phase, dir, angle, blade_length;

    public RotorM(Rotor h)
    {
        kind = h.kind;
        blades = h.blades;
        blade_max = h.blade_max;
        blade_min = h.blade_min;
        half_w = h.half_w;
        hub_radius = h.hub_radius;
        period = h.period;
        spin = h.spin;
        hubs = h.hubs;
        spread_x = h.spread_x;
        spread_y = h.spread_y;
        center_x = h.center_x;
        center_y = h.center_y;
        phase = h.phase;
        dir = h.dir;
        angle = h.angle;
        blade_length = h.blade_length;
        t = h.t;
        bodies = new Body[hubs * (1 + blades * Rotor.SAMPLES)];
        Place();
    }

    long Turned(long steps)
    {
        if (spin != Rotor.Spin.ROCK) return steps * SimTrig.TURN / period;
        long e = Rotor.ROCK_EASE;
        long full = 2 * e * e + 2 * e * Rotor.ROCK_RUN;
        long m = steps % Rotor.ROCK_HALF;
        long x = full;
        if (m < e) x = m * m;
        else if (m < e + Rotor.ROCK_RUN) x = e * e + 2 * e * (m - e);
        else if (m < 2 * e + Rotor.ROCK_RUN)
        {
            long u = m - e - Rotor.ROCK_RUN;
            x = e * e + 2 * e * Rotor.ROCK_RUN + 2 * e * u - u * u;
        }
        if ((steps / Rotor.ROCK_HALF) % 2 == 1) x = full - x;
        return x * SimTrig.TURN / (2 * e * period);
    }

    long LengthAt(long steps)
    {
        if (spin != Rotor.Spin.BREATHE) return blade_max;
        long m = steps % Rotor.BREATHE_CYCLE;
        long grow = blade_max - blade_min;
        if (m < Rotor.BREATHE_HOLD) return blade_min;
        m -= Rotor.BREATHE_HOLD;
        if (m < Rotor.BREATHE_MOVE) return blade_min + grow * m / Rotor.BREATHE_MOVE;
        m -= Rotor.BREATHE_MOVE;
        if (m < Rotor.BREATHE_HOLD) return blade_max;
        m -= Rotor.BREATHE_HOLD;
        return blade_max - grow * m / Rotor.BREATHE_MOVE;
    }

    public override void Step(WorldModel w)
    {
        angle = G.posmod(phase + dir * Turned(t), SimTrig.TURN);
        blade_length = LengthAt(t);
        Place();
    }

    void Place()
    {
        int n = 0;
        for (long hh = 0; hh < hubs; hh++)
        {
            long cx = center_x + (2 * hh - (hubs - 1)) * spread_x;
            long cy = center_y + (2 * hh - (hubs - 1)) * spread_y;
            bodies[n++] = Body.Kill(Shape.Circle(cx, cy, hub_radius));
            for (long i = 0; i < blades; i++)
            {
                long a = (hh % 2 == 0 ? angle : SimTrig.TURN - angle) + i * SimTrig.TURN / blades;
                long c = SimTrig.cos_t(a), s = SimTrig.sin_t(a);
                for (long k = 0; k < Rotor.SAMPLES; k++)
                {
                    long d = blade_length * (k + 1) / Rotor.SAMPLES;
                    bodies[n++] = Body.Kill(Shape.Circle(cx + d * c / SimTrig.ONE, cy + d * s / SimTrig.ONE, half_w));
                }
            }
        }
    }

    public override string Motion => spin switch
    {
        Rotor.Spin.ROCK => "rotate_rocking",
        Rotor.Spin.BREATHE => "rotate_breathing",
        _ => "rotate",
    };

    public override void Params(Dictionary<string, double> p)
    {
        p["cx"] = Px(center_x);
        p["cy"] = Px(center_y);
        p["hubs"] = hubs;
        p["blades"] = blades;
        p["blade_length"] = Px(blade_length);
        p["period"] = period;
        p["phase"] = phase;
        p["dir"] = dir;
    }
}

/// Saw ring: saws on a circle round a centre that turns and grows and shrinks
/// (hold 60, grow 90, hold 60, shrink 90); an optional inner ring turns back.
public sealed class SawRingM : HazardModel
{
    long center_x, center_y, ring_min, ring_max, saw_radius, period, ry_num, ry_den, inner_count, inner_min,
        inner_max, inner_saw, count, phase, dir;

    public SawRingM(SawRing h)
    {
        kind = h.kind;
        center_x = h.center_x;
        center_y = h.center_y;
        ring_min = h.ring_min;
        ring_max = h.ring_max;
        saw_radius = h.saw_radius;
        period = h.period;
        ry_num = h.ry_num;
        ry_den = h.ry_den;
        inner_count = h.inner_count;
        inner_min = h.inner_min;
        inner_max = h.inner_max;
        inner_saw = h.inner_saw;
        count = h.count;
        phase = h.phase;
        dir = h.dir;
        t = h.t;
        bodies = new Body[count + inner_count];
        for (int i = 0; i < bodies.Length; i++)
            bodies[i] = Body.Kill(Shape.Circle(h.xs[i], h.ys[i], i < count ? saw_radius : inner_saw));
    }

    public override void Step(WorldModel w)
    {
        long radius = SawRing.scaled(t, ring_min, ring_max);
        long angle = G.posmod(phase + dir * (t * SimTrig.TURN / period), SimTrig.TURN);
        for (long i = 0; i < count; i++)
        {
            long a = angle + i * SimTrig.TURN / count;
            bodies[i].s = Shape.Circle(center_x + radius * SimTrig.cos_t(a) / SimTrig.ONE,
                center_y + radius * SimTrig.sin_t(a) * ry_num / ry_den / SimTrig.ONE, saw_radius);
        }
        if (inner_count == 0) return;
        long inner = SawRing.scaled(t, inner_min, inner_max);
        long back = G.posmod(phase - dir * (t * SimTrig.TURN / period), SimTrig.TURN);
        for (long i = 0; i < inner_count; i++)
        {
            long a = back + i * SimTrig.TURN / inner_count;
            bodies[count + i].s = Shape.Circle(center_x + inner * SimTrig.cos_t(a) / SimTrig.ONE,
                center_y + inner * SimTrig.sin_t(a) * ry_num / ry_den / SimTrig.ONE, inner_saw);
        }
    }

    public override string Motion => "orbit_pulsing";

    public override void Params(Dictionary<string, double> p)
    {
        p["cx"] = Px(center_x);
        p["cy"] = Px(center_y);
        p["radius_min"] = Px(ring_min);
        p["radius_max"] = Px(ring_max);
        p["count"] = count;
        p["period"] = period;
        p["phase"] = phase;
        p["dir"] = dir;
    }
}

/// Crawler: a chain of segments running round a rectangle at constant speed.
public sealed class CrawlerM : HazardModel
{
    long start, segments, seg_radius, spacing, speed;

    public CrawlerM(Crawler h)
    {
        kind = h.kind;
        start = h.start;
        segments = h.segments;
        seg_radius = h.seg_radius;
        spacing = h.spacing;
        speed = h.speed;
        t = h.t;
        bodies = new Body[segments];
        for (int i = 0; i < segments; i++) bodies[i] = Body.Kill(Shape.Circle(h.xs[i], h.ys[i], seg_radius));
    }

    static long PathX(long s)
    {
        if (s < Crawler.W) return Crawler.LEFT + s;
        if (s < Crawler.W + Crawler.H) return Crawler.RIGHT;
        if (s < 2 * Crawler.W + Crawler.H) return Crawler.RIGHT - (s - Crawler.W - Crawler.H);
        return Crawler.LEFT;
    }

    static long PathY(long s)
    {
        if (s < Crawler.W) return Crawler.TOP;
        if (s < Crawler.W + Crawler.H) return Crawler.TOP + s - Crawler.W;
        if (s < 2 * Crawler.W + Crawler.H) return Crawler.BOTTOM;
        return Crawler.BOTTOM - (s - 2 * Crawler.W - Crawler.H);
    }

    public override void Step(WorldModel w)
    {
        long tail = start + t * speed;
        for (long i = 0; i < segments; i++)
        {
            long s = G.posmod(tail + (segments - 1 - i) * spacing, Crawler.PERIMETER);
            bodies[i].s = Shape.Circle(PathX(s), PathY(s), seg_radius);
        }
    }

    public override string Motion => "perimeter_loop";

    public override void Params(Dictionary<string, double> p)
    {
        p["speed"] = Px(speed);
        p["segments"] = segments;
        p["left"] = Px(Crawler.LEFT);
        p["right"] = Px(Crawler.RIGHT);
        p["top"] = Px(Crawler.TOP);
        p["bottom"] = Px(Crawler.BOTTOM);
    }
}

/// Gate: a wall column with a gap that slides up and down (ping-pong).
public sealed class GateM : HazardModel
{
    public long x, period, phase, gap_y, gap_size;

    public GateM(Gate h)
    {
        kind = h.kind;
        x = h.x;
        period = h.period;
        phase = h.phase;
        gap_y = h.gap_y;
        gap_size = h.gap_size;
        t = h.t;
        bodies = new Body[2];
        Place();
    }

    public long GapAt(long tick) => Gate.GAP_MIN_Y + SimTrig.ping_pong(tick + phase, period, Gate.GAP_MAX_Y - Gate.GAP_MIN_Y);

    public override void Step(WorldModel w)
    {
        gap_y = GapAt(t);
        Place();
    }

    void Place()
    {
        bodies[0] = Body.Kill(Shape.Rect(x - Gate.HALF_W, Gate.TOP, x + Gate.HALF_W, gap_y - gap_size / 2));
        bodies[1] = Body.Kill(Shape.Rect(x - Gate.HALF_W, gap_y + gap_size / 2, x + Gate.HALF_W, Gate.BOTTOM));
    }

    public override string Motion => "gap_ping_pong";

    public override void Params(Dictionary<string, double> p)
    {
        p["x"] = Px(x);
        p["gap_y"] = Px(gap_y);
        p["gap"] = Px(gap_size);
        p["period"] = period;
        p["phase"] = phase;
        p["min_y"] = Px(Gate.GAP_MIN_Y);
        p["max_y"] = Px(Gate.GAP_MAX_Y);
    }
}

/// Block (islands): a rectangle, still or swaying sideways, solid or fading in and out.
public sealed class BlockM : HazardModel
{
    long x0, y0, x1, y1, fade_period, solid_ticks, phase, drift, home_x;

    public BlockM(Block h)
    {
        kind = h.kind;
        x0 = h.x0;
        y0 = h.y0;
        x1 = h.x1;
        y1 = h.y1;
        fade_period = h.fade_period;
        solid_ticks = h.solid_ticks;
        phase = h.phase;
        drift = h.drift;
        home_x = h.home_x;
        t = h.t;
        bodies = new[] { Body.Kill(Shape.Rect(x0, y0, x1, y1), Solid()) };
    }

    bool Solid() => fade_period <= 0 || G.posmod(t + phase, fade_period) < solid_ticks;

    public override void Step(WorldModel w)
    {
        if (drift > 0)
        {
            long wd = x1 - x0;
            x0 = home_x + Block.sway(drift, t);
            x1 = x0 + wd;
        }
        bodies[0] = Body.Kill(Shape.Rect(x0, y0, x1, y1), Solid());
    }

    public override string Motion => drift > 0 ? "sway" : "static";
    public override string State => Solid() ? "active" : "faded";

    public override void Params(Dictionary<string, double> p)
    {
        if (drift > 0)
        {
            p["drift"] = Px(drift);
            p["period"] = Block.DRIFT_PERIOD;
        }
        if (fade_period > 0)
        {
            p["fade_period"] = fade_period;
            p["solid_ticks"] = solid_ticks;
            p["phase"] = phase;
        }
    }
}

/// Spike ball: a still ball.
public sealed class SpikeBallM : HazardModel
{
    public SpikeBallM(SpikeBall h)
    {
        kind = h.kind;
        t = h.t;
        bodies = new[] { Body.Kill(Shape.Circle(h.x, h.y, SpikeBall.RADIUS)) };
    }

    public override void Step(WorldModel w) { }
}

/// Edge pad: a pad sliding along the ceiling or floor (ping-pong) that bounces
/// the bird back instead of letting the edge kill it.
public sealed class EdgePadM : HazardModel
{
    public bool top;
    long period, phase;

    public EdgePadM(EdgePad h)
    {
        kind = h.kind;
        top = h.top;
        period = h.period;
        phase = h.phase;
        t = h.t;
        bodies = new Body[1];
        Place();
    }

    public long X0 => EdgePad.X_MIN + SimTrig.ping_pong(t + phase, period, EdgePad.X_MAX - EdgePad.X_MIN);

    public bool Covers(long x) => x >= X0 - EdgePad.GRACE && x <= X0 + EdgePad.WIDTH + EdgePad.GRACE;

    void Place()
    {
        long ly = top ? SimConfig.KILL_TOP : SimConfig.KILL_BOTTOM;
        bodies[0] = Body.Soft(Shape.Rect(X0, ly - 4 * SimConfig.SUB, X0 + EdgePad.WIDTH, ly + 4 * SimConfig.SUB));
    }

    public override void Step(WorldModel w) => Place();

    public override bool Guard(WorldModel w, ref Bird b, bool p_top)
    {
        if (p_top != top || !Covers(b.x)) return false;
        if (top)
        {
            b.y = Math.Max(b.y, SimConfig.KILL_TOP + Physics.R + 1);
            b.vy = EdgePad.CEILING_VY;
        }
        else
        {
            b.y = Math.Min(b.y, SimConfig.KILL_BOTTOM - Physics.R - 1);
            b.vy = -EdgePad.FLOOR_VY;
        }
        return true;
    }

    public override string Motion => "slide_ping_pong";

    public override void Params(Dictionary<string, double> p)
    {
        p["period"] = period;
        p["phase"] = phase;
        p["width"] = Px(EdgePad.WIDTH);
        p["top"] = top ? 1 : 0;
    }
}

/// Updraft: a column that lifts the bird (vy -= lift each substep inside),
/// optionally drifting sideways and/or gusting (off, warning, on).
public sealed class UpdraftM : HazardModel
{
    long x0, x1, half_w, lift, drift_min, drift_span, gust, phase;

    public UpdraftM(Updraft h)
    {
        kind = h.kind;
        x0 = h.x0;
        x1 = h.x1;
        half_w = h.half_w;
        lift = h.lift;
        drift_min = h.drift_min;
        drift_span = h.drift_span;
        gust = h.gust;
        phase = h.phase;
        t = h.t;
        bodies = new Body[1];
        Place();
    }

    bool Blowing => gust == Updraft.Gust.NONE || gust == Updraft.Gust.ON;

    public override void Step(WorldModel w)
    {
        if (drift_span > 0)
        {
            long c = drift_min + SimTrig.ping_pong(t + phase, 2 * drift_span / SimConfig.SUB, drift_span);
            x0 = c - half_w;
            x1 = c + half_w;
        }
        if (gust != Updraft.Gust.NONE)
        {
            long m = G.posmod(t + phase, Updraft.GUST_PERIOD);
            gust = m < Updraft.GUST_OFF ? Updraft.Gust.OFF
                : m < Updraft.GUST_OFF + Updraft.GUST_WARN ? Updraft.Gust.WARN : Updraft.Gust.ON;
        }
        Place();
    }

    void Place() => bodies[0] = Body.Soft(Shape.Rect(x0, SimConfig.KILL_TOP, x1, SimConfig.KILL_BOTTOM), Blowing);

    public override void Touch(WorldModel w, ref Bird b)
    {
        if (Blowing && b.x >= x0 && b.x <= x1)
            b.vy = Math.Clamp(b.vy - lift, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY);
    }

    public override string Motion => drift_span > 0 ? "force_column_drift" : "force_column";
    public override string State => gust == Updraft.Gust.WARN ? "warning" : Blowing ? "active" : "off";

    public override void Params(Dictionary<string, double> p)
    {
        p["x0"] = Px(x0);
        p["x1"] = Px(x1);
        p["lift"] = lift;
        if (gust != Updraft.Gust.NONE) p["gust_period"] = Updraft.GUST_PERIOD;
    }
}

/// Wind: one or two height bands that push the bird sideways (x += dir x push), steady or gusty.
public sealed class WindM : HazardModel
{
    long mode, a_y0, a_y1, a_dir, b_y0, b_y1, b_dir;

    public WindM(Wind h)
    {
        kind = h.kind;
        mode = h.mode;
        a_y0 = h.a_y0;
        a_y1 = h.a_y1;
        a_dir = h.a_dir;
        b_y0 = h.b_y0;
        b_y1 = h.b_y1;
        b_dir = h.b_dir;
        t = h.t;
        bodies = new Body[2];
        Place();
    }

    bool Blowing => mode != Wind.Mode.GUSTY || G.posmod(t, Wind.GUST_PERIOD) >= Wind.GUST_CALM + Wind.GUST_WARN;

    void Place()
    {
        bodies[0] = Body.Soft(Shape.Rect(0, a_y0, SimConfig.WORLD_W, a_y1), Blowing);
        bodies[1] = Body.Soft(Shape.Rect(0, b_y0, SimConfig.WORLD_W, b_y1), Blowing && b_dir != 0);
    }

    public override void Step(WorldModel w) => Place();

    public override void Touch(WorldModel w, ref Bird b)
    {
        if (!Blowing) return;
        if (b.y >= a_y0 && b.y <= a_y1) b.x += a_dir * Wind.PUSH;
        else if (b_dir != 0 && b.y >= b_y0 && b.y <= b_y1) b.x += b_dir * Wind.PUSH;
    }

    public override string Motion => "force_band";

    public override string State
    {
        get
        {
            if (mode != Wind.Mode.GUSTY) return "active";
            long p = G.posmod(t, Wind.GUST_PERIOD);
            return p >= Wind.GUST_CALM + Wind.GUST_WARN ? "active" : p >= Wind.GUST_CALM ? "warning" : "off";
        }
    }

    public override void Params(Dictionary<string, double> p)
    {
        p["push_x"] = Px(a_dir * Wind.PUSH);
        p["y0"] = Px(a_y0);
        p["y1"] = Px(a_y1);
        if (b_dir != 0)
        {
            p["b_push_x"] = Px(b_dir * Wind.PUSH);
            p["b_y0"] = Px(b_y0);
            p["b_y1"] = Px(b_y1);
        }
    }
}

/// Belt: the spikes on each wall slide up or down (shift), reset at a bounce;
/// switchback turns both directions round at every bounce.
public sealed class BeltM : HazardModel
{
    long mode, left_dir, right_dir, left_shift, right_shift;

    public BeltM(Belt h)
    {
        kind = h.kind;
        mode = h.mode;
        left_dir = h.left_dir;
        right_dir = h.right_dir;
        left_shift = h.left_shift;
        right_shift = h.right_shift;
        t = h.t;
    }

    public override void Step(WorldModel w)
    {
        if (t <= SimConfig.ARRIVAL_BLIND) return;
        var r = w.room;
        if (!(r.exit_open && r.exit_side == 0))
            left_shift = Math.Clamp(left_shift + left_dir * Belt.SPEED, -Belt.MAX_SHIFT, Belt.MAX_SHIFT);
        if (!(r.exit_open && r.exit_side == 1))
            right_shift = Math.Clamp(right_shift + right_dir * Belt.SPEED, -Belt.MAX_SHIFT, Belt.MAX_SHIFT);
    }

    public override void OnBounce(WorldModel w)
    {
        if (w.bird.vx > 0) right_shift = 0;
        else left_shift = 0;
        if (mode == Belt.Mode.SWITCHBACK)
        {
            left_dir = -left_dir;
            right_dir = -right_dir;
        }
    }

    public override long WallShift(long side) => side == 0 ? left_shift : right_shift;

    public override string Motion => "wall_shift";

    public override void Params(Dictionary<string, double> p)
    {
        p["left_shift"] = Px(left_shift);
        p["right_shift"] = Px(right_shift);
        p["left_speed"] = Px(left_dir * Belt.SPEED);
        p["right_speed"] = Px(right_dir * Belt.SPEED);
    }
}

/// Echo: a ghost that flies the bird's own path one second late (the model
/// keeps the bird's last 60 substeps, which the player saw), or the mirror
/// image of the bird. Both react to the bird.
public sealed class EchoM : HazardModel
{
    long mode, x, y, head;
    bool shown;
    long[] xs, ys;

    public EchoM(Echo h)
    {
        kind = h.kind;
        reactive = true;
        mode = h.mode;
        x = h.x;
        y = h.y;
        head = h.head;
        shown = h.shown;
        xs = h.xs.ToArray();
        ys = h.ys.ToArray();
        t = h.t;
        bodies = new[] { Body.Kill(Shape.Circle(x, y, Echo.RADIUS), shown) };
    }

    protected override void CopyLists(HazardModel c)
    {
        var e = (EchoM)c;
        e.xs = (long[])xs.Clone();
        e.ys = (long[])ys.Clone();
    }

    public override void Step(WorldModel w)
    {
        shown = t > Echo.DELAY;
        if (mode == Echo.Mode.MIRROR)
        {
            x = SimConfig.WORLD_W - w.bird.x;
            y = SimConfig.WORLD_H - w.bird.y;
        }
        else
        {
            x = xs[head];
            y = ys[head];
            xs[head] = w.bird.x;
            ys[head] = w.bird.y;
            head = (head + 1) % Echo.DELAY;
        }
        bodies[0] = Body.Kill(Shape.Circle(x, y, Echo.RADIUS), shown);
    }

    public override string Motion => mode == Echo.Mode.MIRROR ? "mirror_of_bird" : "bird_path_delayed";

    public override void Params(Dictionary<string, double> p) => p["delay"] = Echo.DELAY;
}

/// Stalker: a double spike on the wall ahead that slides toward the bird's height (80/substep).
public sealed class StalkerM : HazardModel
{
    long side, y, x;

    public StalkerM(Stalker h)
    {
        kind = h.kind;
        reactive = true;
        side = h.side;
        y = h.y;
        x = h.x;
        t = h.t;
        bodies = new Body[2];
        Place();
    }

    public override void Step(WorldModel w)
    {
        side = w.bird.vx > 0 ? 1 : 0;
        long target = Math.Clamp(w.bird.y, Stalker.MIN_Y, Stalker.MAX_Y);
        y += Math.Clamp(target - y, -Stalker.MAX_SPEED, Stalker.MAX_SPEED);
        x = side == 0 ? w.room.WallLeft : w.room.WallRight;
        Place();
    }

    void Place()
    {
        long dir = side == 0 ? 1 : -1;
        long tip = x + dir * Stalker.DEPTH;
        long hb = Stalker.HALF_BASE;
        long cy = y - hb;
        bodies[0] = Body.Kill(Shape.Tri(x, cy - hb, x, cy + hb, tip, cy));
        cy = y + hb;
        bodies[1] = Body.Kill(Shape.Tri(x, cy - hb, x, cy + hb, tip, cy));
    }

    public override string Motion => "follow_bird_y";

    public override void Params(Dictionary<string, double> p)
    {
        p["max_speed"] = Px(Stalker.MAX_SPEED);
        p["side"] = side;
    }
}
