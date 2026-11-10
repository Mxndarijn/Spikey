namespace FastSim;

/// Port of sim/hazards/bouncer.gd.
public class Bouncer : Hazard
{
    public const long RADIUS = 20 * SimConfig.SUB;
    public const long SPEED_X = 3 * SimConfig.SUB;
    public const long SPEED_Y = 2 * SimConfig.SUB + 32;
    public const long MARGIN = 44 * SimConfig.SUB;

    public long x = 0;
    public long y = 0;
    public long vx = 0;
    public long vy = 0;

    public Bouncer()
    {
        kind = "bouncer";
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        bool bird_left = sim.state.x < SimConfig.WORLD_W / 2;
        x = bird_left ? (SimConfig.WORLD_W * 3 / 4) : (SimConfig.WORLD_W / 4);
        y = MARGIN + RADIUS + rng.next_below(SimConfig.WORLD_H - 2 * (MARGIN + RADIUS));
        vx = bird_left ? SPEED_X : -SPEED_X;
        vy = rng.next_below(2) == 0 ? SPEED_Y : -SPEED_Y;
    }

    public override void step(GameSim sim)
    {
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
        long top = MARGIN + RADIUS;
        long bottom = SimConfig.WORLD_H - MARGIN - RADIUS;
        if (y < top)
        {
            y = 2 * top - y;
            vy = G.absi(vy);
        }
        else if (y > bottom)
        {
            y = 2 * bottom - y;
            vy = -G.absi(vy);
        }
    }

    public override bool kills(GameSim sim) => sim.bird_touches_circle(x, y, RADIUS);

    public override long checksum(long h) => mix_all(h, x, y, vx, vy);
}
