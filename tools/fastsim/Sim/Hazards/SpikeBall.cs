namespace FastSim;

/// Port of sim/hazards/spike_ball.gd.
public sealed class SpikeBall : Hazard
{
    public const long SUB = SimConfig.SUB;
    public const long RADIUS = 15 * SUB;

    public long x = 0;
    public long y = 0;
    public List<long> spots = new();

    public SpikeBall(List<long> p_spots = null)
    {
        kind = "spike_ball";
        spots = p_spots ?? new List<long>();
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        long n = spots.Count / 2;
        long first = rng.next_below(n);
        long pick = first;
        for (long k = 0; k < n; k++)
        {
            long i = (first + k) % n;
            if (!_in_the_way(sim, spots[(int)(2 * i)], spots[(int)(2 * i + 1)]))
            {
                pick = i;
                break;
            }
        }
        x = spots[(int)(2 * pick)];
        y = spots[(int)(2 * pick + 1)];
        var hs = sim.room.hazards;
        for (int j = 0; j < hs.Count; j++)
        {
            if (hs[j] is CoinPickup c && c.x == x && c.y == y) c.alive = false;
        }
    }

    public bool _in_the_way(GameSim sim, long bx, long by)
    {
        long margin = 10 * SUB;
        if (FairLanes.start_path_hits_rect(sim, bx - RADIUS, by - RADIUS, bx + RADIUS, by + RADIUS, margin)) return true;
        if (FairLanes.blocks_start_lane(sim, bx - RADIUS, by - RADIUS, bx + RADIUS, by + RADIUS)) return true;
        if (!sim.state.started) return false;
        var path = FairLanes.arrival_path(sim);
        for (long k = 0; k < FairLanes.ARRIVAL_PATH_TICKS; k++)
        {
            if (FairLanes.arrival_path_hits(path, k, bx, by, RADIUS)) return true;
        }
        return false;
    }

    public override bool kills(GameSim sim) => sim.bird_touches_circle(x, y, RADIUS);

    public override long checksum(long h) => mix_all(h, x, y);
}
