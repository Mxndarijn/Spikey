namespace FastSim;

/// Port of sim/hazards/bouncer.gd.
public class Bouncer : Hazard
{
    public const long RADIUS = 20 * SimConfig.SUB;
    public const long SPEED_X = 3 * SimConfig.SUB;
    public const long SPEED_Y = 2 * SimConfig.SUB + 32;
    public const long MARGIN = 44 * SimConfig.SUB;
    public const long TWIN_RADIUS = 15 * SimConfig.SUB;

    public static class Lane
    {
        public const long ANY = 0, UPPER = 1, LOWER = 2;
    }

    public long radius = RADIUS;
    public long lane = Lane.ANY;
    public long x = 0;
    public long y = 0;
    public long vx = 0;
    public long vy = 0;

    public Bouncer(long p_radius = RADIUS, long p_lane = Lane.ANY)
    {
        kind = "bouncer";
        radius = p_radius;
        lane = p_lane;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        bool bird_left = sim.state.x < SimConfig.WORLD_W / 2;
        long top = MARGIN + radius;
        long span = SimConfig.WORLD_H - 2 * top;
        if (lane == Lane.UPPER)
        {
            x = bird_left ? (SimConfig.WORLD_W * 3 / 4) : (SimConfig.WORLD_W / 4);
            y = top + rng.next_below(span / 2);
            vy = SPEED_Y;
        }
        else if (lane == Lane.LOWER)
        {
            x = bird_left ? (SimConfig.WORLD_W * 5 / 8) : (SimConfig.WORLD_W * 3 / 8);
            y = top + span / 2 + rng.next_below(span / 2);
            vy = -SPEED_Y;
        }
        else
        {
            x = bird_left ? (SimConfig.WORLD_W * 3 / 4) : (SimConfig.WORLD_W / 4);
            y = top + rng.next_below(span);
            vy = rng.next_below(2) == 0 ? SPEED_Y : -SPEED_Y;
        }
        vx = bird_left ? SPEED_X : -SPEED_X;
    }

    public override void step(GameSim sim)
    {
        move(sim);
    }

    public bool move(GameSim sim)
    {
        x += vx;
        y += vy;
        bool side = bounce_sides(sim);
        bool top = bounce_top();
        bool bottom = bounce_bottom();
        return side || top || bottom;
    }

    public bool bounce_sides(GameSim sim)
    {
        long left = sim.room.wall_left() + radius;
        long right = sim.room.wall_right() - radius;
        bool out_ = false;
        if (x < left)
        {
            x = 2 * left - x;
            vx = G.absi(vx);
            out_ = true;
        }
        else if (x > right)
        {
            x = 2 * right - x;
            vx = -G.absi(vx);
            out_ = true;
        }
        var b = ExitZone.bounce(sim, x, y, vx, vy, radius);
        if (b != null)
        {
            x = b[0];
            y = b[1];
            vx = b[2];
            vy = b[3];
            out_ = true;
        }
        return out_;
    }

    public bool bounce_top()
    {
        if (y < top_y())
        {
            y = 2 * top_y() - y;
            vy = G.absi(vy);
            return true;
        }
        return false;
    }

    public bool bounce_bottom()
    {
        if (y > bottom_y())
        {
            y = 2 * bottom_y() - y;
            vy = -G.absi(vy);
            return true;
        }
        return false;
    }

    public long top_y() => MARGIN + radius;

    public long bottom_y() => SimConfig.WORLD_H - MARGIN - radius;

    public override bool kills(GameSim sim) => sim.bird_touches_circle(x, y, radius);

    public virtual bool straight_path() => true;

    public override bool near_row(GameSim sim, long p_y, long half, long from, long to)
    {
        if (!straight_path()) return false;
        long keep_x = x;
        long keep_y = y;
        long keep_vx = vx;
        long keep_vy = vy;
        bool out_ = false;
        for (long k = 0; k < to; k++)
        {
            move(sim);
            if (k + 1 >= from && G.absi(y - p_y) < radius + half)
            {
                out_ = true;
                break;
            }
        }
        x = keep_x;
        y = keep_y;
        vx = keep_vx;
        vy = keep_vy;
        return out_;
    }

    public override long checksum(long h) => mix_all(h, x, y, vx, vy);
}
