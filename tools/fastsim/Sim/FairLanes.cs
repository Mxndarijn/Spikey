namespace FastSim;

/// Port of sim/fair_lanes.gd.
public static class FairLanes
{
    public const long START_LANE_H = 100 * SimConfig.SUB;
    public const long START_LANE_BELOW = 12 * SimConfig.SUB;
    public const long START_LANE_W = 150 * SimConfig.SUB;
    public const long START_PATH = 32;
    public const long FIRST_HOP = SimConfig.FLAP_VY * SimConfig.FLAP_VY / (2 * SimConfig.GRAVITY);
    public const long ARRIVAL_PATH_TICKS = SimConfig.ARRIVAL_BLIND + 60;
    public const long ARRIVAL_PATH_MARGIN = 10 * SimConfig.SUB;
    public const long ARRIVAL_PATH_MIN = SimConfig.ARRIVAL_BLIND + 15;

    public static long entry_y(GameSim sim)
    {
        if (sim.state.started) return sim.state.y;
        return sim.state.y - FIRST_HOP / 2 * sim.room.def.gravity_sign;
    }

    public static List<long> arrival_path(GameSim sim)
    {
        var out_ = new List<long>((int)(2 * ARRIVAL_PATH_TICKS));
        long g = sim.room.def.gravity_sign;
        long y = sim.state.y;
        long vy = 0;
        for (long k = 0; k < ARRIVAL_PATH_TICKS; k++)
        {
            if ((y - sim.state.y) * g > 0 && vy * g >= 0) vy = SimConfig.FLAP_VY * g;
            vy = G.clampi(vy + SimConfig.GRAVITY * g, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY);
            y += vy;
            out_.Add(arrival_x(sim, k + 1));
            out_.Add(y);
        }
        return out_;
    }

    public static bool arrival_path_hits(List<long> path, long k, long cx, long cy, long r)
    {
        long dx = cx - path[(int)(2 * k)];
        long dy = cy - path[(int)(2 * k + 1)];
        long reach = SimConfig.BIRD_RADIUS + r + ARRIVAL_PATH_MARGIN;
        return dx * dx + dy * dy < reach * reach;
    }

    public static long arrival_x(GameSim sim, long k)
    {
        long r = SimConfig.BIRD_RADIUS;
        long lo = sim.room.wall_left() + r;
        long span = sim.room.wall_right() - r - lo;
        long at = G.posmod(sim.state.x + sim.state.vx * k - lo, 2 * span);
        return lo + (at <= span ? at : 2 * span - at);
    }

    public static List<long> start_path(GameSim sim)
    {
        var out_ = new List<long>();
        if (sim.state.started) return out_;
        long g = SimConfig.GRAVITY * sim.room.def.gravity_sign;
        long x = sim.state.x;
        long y = sim.state.y;
        long vy = SimConfig.FLAP_VY * sim.room.def.gravity_sign;
        for (long i = 0; i < START_PATH; i++)
        {
            vy = G.clampi(vy + g, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY);
            x += sim.state.vx;
            y += vy;
            out_.Add(x);
            out_.Add(y);
        }
        return out_;
    }

    public static bool start_path_hits_rect(GameSim sim, long x0, long y0, long x1, long y1, long margin)
    {
        var path = start_path(sim);
        long r = SimConfig.BIRD_RADIUS + margin;
        for (int i = 0; i < path.Count; i += 2)
            if (path[i] + r > x0 && path[i] - r < x1 && path[i + 1] + r > y0 && path[i + 1] - r < y1)
                return true;
        return false;
    }

    public static bool blocks_start_lane(GameSim sim, long x0, long y0, long x1, long y1)
    {
        if (sim.state.started) return false;
        long w = START_LANE_W;
        long top = sim.state.y - (START_LANE_H - START_LANE_BELOW) * sim.room.def.gravity_sign;
        long bottom = sim.state.y + START_LANE_BELOW * sim.room.def.gravity_sign;
        long ly0 = G.mini(top, bottom);
        long ly1 = G.maxi(top, bottom);
        long lx0 = sim.state.vx > 0 ? sim.state.x : sim.state.x - w;
        long lx1 = sim.state.vx > 0 ? sim.state.x + w : sim.state.x;
        return x1 > lx0 && x0 < lx1 && y1 > ly0 && y0 < ly1;
    }
}
