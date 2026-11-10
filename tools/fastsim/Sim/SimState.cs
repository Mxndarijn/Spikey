namespace FastSim;

public static class DeathCause
{
    public const long NONE = 0, CEILING = 1, FLOOR = 2, SPIKE_LEFT = 3, SPIKE_RIGHT = 4, HAZARD = 5;
    public static readonly string[] NAMES = { "NONE", "CEILING", "FLOOR", "SPIKE_LEFT", "SPIKE_RIGHT", "HAZARD" };
}

public static class ExitKind
{
    public const long NORMAL = 0, CALM = 1, WILD = 2;
}

/// Port of sim/sim_state.gd (fields generated from it).
public sealed class SimState
{
    public long tick = 0;
    public bool started = false;
    public bool alive = true;
    public long death_cause = DeathCause.NONE;
    public long x = SimConfig.BIRD_START_X;
    public long y = SimConfig.BIRD_START_Y;
    public long vx = SimConfig.SPEED_X;
    public long vy = 0;
    public long score = 0;
    public long room_index = 0;
    public long room_kind = 0;
    public long left_spikes = 0;
    public long right_spikes = 0;
    public bool coin_active = false;
    public long coin_x = 0;
    public long coin_y = 0;
    public long coins = 0;
    public long flaps = 0;
    public bool exit_open = false;
    public bool exit_preview = false;
    public long exit_side = 0;
    public long exit_a_y = 0;
    public long exit_a_kind = 0;
    public long exit_b_y = 0;
    public long exit_b_kind = 0;
    public long route = 0;
    public long pickup_x = 0;
    public long pickup_y = 0;
    public long arrival_hold = 0;
    public long revives = 0;

    public SimState copy() => (SimState)MemberwiseClone();

    public long checksum()
    {
        long h = SimHash.SEED;
        h = SimHash.mix(h, tick);
        h = SimHash.mix(h, G.B(started));
        h = SimHash.mix(h, G.B(alive));
        h = SimHash.mix(h, death_cause);
        h = SimHash.mix(h, x);
        h = SimHash.mix(h, y);
        h = SimHash.mix(h, vx);
        h = SimHash.mix(h, vy);
        h = SimHash.mix(h, score);
        h = SimHash.mix(h, room_index);
        h = SimHash.mix(h, room_kind);
        h = SimHash.mix(h, left_spikes);
        h = SimHash.mix(h, right_spikes);
        h = SimHash.mix(h, G.B(coin_active));
        h = SimHash.mix(h, coin_x);
        h = SimHash.mix(h, coin_y);
        h = SimHash.mix(h, coins);
        h = SimHash.mix(h, flaps);
        h = SimHash.mix(h, G.B(exit_open));
        h = SimHash.mix(h, exit_side);
        h = SimHash.mix(h, exit_a_y);
        h = SimHash.mix(h, exit_a_kind);
        h = SimHash.mix(h, exit_b_y);
        h = SimHash.mix(h, exit_b_kind);
        h = SimHash.mix(h, route);
        h = SimHash.mix(h, arrival_hold);
        h = SimHash.mix(h, G.B(exit_preview));
        h = SimHash.mix(h, revives);
        return h;
    }
}
