namespace FastSim;

/// Port of sim/hazards/belt.gd.
public class Belt : Hazard
{
    public static class Mode { public const long UP = 0, COUNTER = 1, SWITCHBACK = 2; }

    public const long SPEED = 29;
    public const long MAX_SHIFT = 2 * SimConfig.SLOT_SIZE;

    public long mode = Mode.UP;
    public long left_dir = -1;
    public long right_dir = -1;
    public long left_shift = 0;
    public long right_shift = 0;

    public Belt(long p_mode = -1)
    {
        kind = "belt";
        mode = p_mode;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        if (mode < 0)
        {
            switch (sim.room.variant_id())
            {
                case "counter": mode = Mode.COUNTER; break;
                case "switchback": mode = Mode.SWITCHBACK; break;
                default: mode = Mode.UP; break;
            }
        }
        left_dir = -1;
        right_dir = mode == Mode.COUNTER ? 1 : -1;
    }

    public override void step(GameSim sim)
    {
        if (t <= SimConfig.ARRIVAL_BLIND) return;
        var s = sim.state;
        if (!(s.exit_open && s.exit_side == 0))
            left_shift = G.clampi(left_shift + left_dir * SPEED, -MAX_SHIFT, MAX_SHIFT);
        if (!(s.exit_open && s.exit_side == 1))
            right_shift = G.clampi(right_shift + right_dir * SPEED, -MAX_SHIFT, MAX_SHIFT);
    }

    public override void on_bounce(GameSim sim, SimRng rng)
    {
        if (sim.state.vx > 0) right_shift = 0;
        else left_shift = 0;
        if (mode == Mode.SWITCHBACK)
        {
            left_dir = -left_dir;
            right_dir = -right_dir;
        }
    }

    public override long wall_shift(GameSim sim, long side) => side == 0 ? left_shift : right_shift;

    public override long checksum(long h) => mix_all(h, mode, left_dir, right_dir, left_shift, right_shift);
}
