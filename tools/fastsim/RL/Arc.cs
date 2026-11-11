namespace FastSim.Rl;

/// Part of the observation (Observer layout 4):
/// the bird's own path if it waits and if it taps now (its fall, its speed
/// across, the room's step rate, a bounce at the walls), probed against every
/// live hazard where the hazards are NOW (what a player sees; no hazard is
/// stepped) and the ceiling and floor. Fine where the danger grid is coarse.
public static class Arc
{
    public static readonly int[] AT = { 1, 2, 3, 4, 6, 8, 10, 13, 16, 20, 25, 30, 36, 42, 50, 60 };
    /// Per path: a value per AT tick plus the ticks to the first hit.
    public const int PER = 17;
    public const int SIZE = 2 * PER;

    /// The arcs probed against `past` hazards (a room copy from earlier
    /// ticks: what the player saw then), the bird where it is now.
    public static void fill_past(GameSim sim, RoomRuntime past, float[] f, int at)
    {
        var now = sim.room;
        var hz_now = now.hazards;
        // Only the hazards are swapped: the step rate and walls stay this tick's.
        var keep = now.hazards;
        now.hazards = past.hazards;
        try { fill(sim, f, at); }
        finally { now.hazards = keep; }
    }

    public static void fill(GameSim sim, float[] f, int at)
    {
        var saved = sim.state.copy();
        var hz = sim.room.hazards;
        long r = SimConfig.BIRD_RADIUS;
        long left = sim.room.wall_left() + r, right = sim.room.wall_right() - r;
        long g = SimConfig.GRAVITY * sim.room.gravity;
        for (int p = 0; p < 2; p++)
        {
            bool tap = p == 1;
            long x = saved.x, y = saved.y, vx = saved.vx;
            long vy = tap ? SimConfig.FLAP_VY * sim.room.gravity : saved.vy;
            int k = 0, first = -1;
            long tick = sim.room.ticks;
            for (int t = 1; t <= AT[^1]; t++)
            {
                long n = sim.state.started ? sim.room.steps_at(tick + t - 1) : 0;
                for (long q = 0; q < n; q++)
                {
                    vy = Math.Clamp(vy + g, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY);
                    x += vx;
                    y += vy;
                    if (x >= right) { x = right; vx = -Math.Abs(vx); }
                    if (x <= left) { x = left; vx = Math.Abs(vx); }
                }
                bool hit = false;
                if (first < 0 || t == AT[k])
                {
                    hit = y - r <= SimConfig.KILL_TOP || y + r >= SimConfig.KILL_BOTTOM;
                    if (!hit)
                    {
                        var s = sim.state;
                        s.x = x;
                        s.y = y;
                        for (int h = 0; h < hz.Count && !hit; h++) hit = hz[h].alive && hz[h].kills(sim);
                        sim.state = saved.copy();
                    }
                    if (hit && first < 0) first = t;
                }
                if (t == AT[k])
                {
                    f[at + p * PER + k] = hit ? 1f : -1f;
                    k++;
                }
            }
            f[at + p * PER + AT.Length] = first < 0 ? 1f : first / 30f - 1f;
        }
        sim.state = saved;
    }
}
