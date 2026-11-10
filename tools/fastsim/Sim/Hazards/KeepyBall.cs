namespace FastSim;

/// Port of sim/hazards/keepy_ball.gd.
public sealed class KeepyBall : Hazard
{
    public const long SUB = SimConfig.SUB;
    public const long RADIUS = 22 * SUB;
    public const long GRAVITY = 18;
    public const long MAX_VY = 7 * SUB;
    public const long KICK_VY = 9 * SUB;
    public const long KICK_VX = 3 * SUB;
    public const long COOLDOWN = 15;
    public const long MIN_X = 120 * SUB;
    public const long MAX_X = 240 * SUB;
    public const long HEAVY_GRAVITY = 27;
    public const long HEAVY_KICK_VY = 7 * SUB;
    public const long SECOND_DROP = 120;
    public const long REDROP = 90;

    public long gravity = GRAVITY;
    public long kick_vy = KICK_VY;
    public long waiting = 0;
    public long redrop = 0;

    public long x = 0;
    public long y = -RADIUS;
    public long vx = 0;
    public long vy = 0;
    public long cooldown = 0;
    public long bumps = 0;

    public KeepyBall()
    {
        kind = "keepy_ball";
    }

    public Hazard heavy()
    {
        gravity = HEAVY_GRAVITY;
        kick_vy = HEAVY_KICK_VY;
        return this;
    }

    public Hazard dropping(long delay)
    {
        waiting = delay;
        redrop = REDROP;
        return this;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        x = MIN_X + rng.next_below(MAX_X - MIN_X + 1);
        y = -RADIUS;
    }

    public override void step(GameSim sim)
    {
        if (waiting > 0)
        {
            waiting -= 1;
            return;
        }
        if (cooldown > 0) cooldown -= 1;
        vy = G.mini(vy + gravity, MAX_VY);
        x += vx;
        y += vy;
        long left = sim.room.wall_left() + RADIUS;
        long right = sim.room.wall_right() - RADIUS;
        if (x < left)
        {
            x = 2 * left - x;
            vx = G.absi(vx);
        }
        else if (x > right)
        {
            x = 2 * right - x;
            vx = -G.absi(vx);
        }
        long top = SimConfig.KILL_TOP + RADIUS;
        if (vy < 0 && y < top)
        {
            y = 2 * top - y;
            vy = -vy;
        }
        if (y + RADIUS >= SimConfig.KILL_BOTTOM)
        {
            if (redrop == 0)
            {
                alive = false;
                return;
            }
            waiting = redrop;
            x = G.clampi(SimConfig.WORLD_W - x, MIN_X, MAX_X);
            y = -RADIUS;
            vx = 0;
            vy = 0;
            cooldown = 0;
        }
    }

    public override void touch(GameSim sim)
    {
        if (waiting > 0 || cooldown > 0 || !sim.bird_touches_circle(x, y, RADIUS)) return;
        long dx = x - sim.state.x;
        long reach = SimConfig.BIRD_RADIUS + RADIUS;
        vx = G.clampi(dx, -reach, reach) * KICK_VX / reach;
        vy = -kick_vy;
        long above = sim.state.y - reach;
        if (y > above) y = above;
        cooldown = COOLDOWN;
        bumps += 1;
        sim.collect_coin(x, y);
    }

    public override long checksum(long h)
    {
        long out_ = mix_all(h, x, y, vx, vy, cooldown, bumps);
        if (gravity != GRAVITY || kick_vy != KICK_VY || redrop != 0)
            out_ = mix_all(out_, gravity, kick_vy, waiting, redrop);
        return out_;
    }
}
