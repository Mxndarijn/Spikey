namespace FastSim;

/// Port of sim/hazards/exit_key.gd.
public class ExitKey : Hazard
{
    public static class Mode { public const long STILL = 0, ORBIT = 1, TWO = 2; }

    public const long SUB = SimConfig.SUB;
    public const long RADIUS = 12 * SUB;
    public const long COINS = 3;
    public const long MAX_LOCKED_BOUNCES = 4;
    public const long ORBIT_CX = 180 * SUB;
    public const long ORBIT_CY = 330 * SUB;
    public const long ORBIT_RX = 105 * SUB;
    public const long ORBIT_RY = 150 * SUB;
    public const long ORBIT_STEPS = 540;

    public long mode = Mode.STILL;
    public long x0 = 0;
    public long y0 = 0;
    public long x1 = 0;
    public long y1 = 0;
    public long phase = 0;
    public bool taken = false;
    public long locked_bounces = 0;
    public bool door_open = false;
    public long door_side = 0;
    public long door_a_y = 0;
    public long door_b_y = 0;

    public ExitKey(long p_mode = -1)
    {
        kind = "exit_key";
        mode = p_mode;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        if (mode < 0)
        {
            switch (sim.room.variant_id())
            {
                case "orbit": mode = Mode.ORBIT; break;
                case "two": mode = Mode.TWO; break;
                default: mode = Mode.STILL; break;
            }
        }
        if (mode == Mode.ORBIT)
        {
            phase = rng.next_below(SimTrig.TURN);
            _place_orbit();
        }
        else if (mode == Mode.TWO)
        {
            x0 = (110 + rng.next_below(61)) * SUB;
            y0 = (140 + rng.next_below(141)) * SUB;
            x1 = (190 + rng.next_below(61)) * SUB;
            y1 = (380 + rng.next_below(121)) * SUB;
        }
        else
        {
            x0 = (130 + rng.next_below(101)) * SUB;
            y0 = (150 + rng.next_below(341)) * SUB;
        }
    }

    public override void step(GameSim sim)
    {
        if (mode == Mode.ORBIT && !taken) _place_orbit();
        var s = sim.state;
        door_open = s.exit_open;
        door_side = s.exit_side;
        door_a_y = s.exit_a_y;
        door_b_y = s.exit_b_kind != ExitKind.NORMAL ? s.exit_b_y : 0;
    }

    void _place_orbit()
    {
        long a = phase + t * SimTrig.TURN / ORBIT_STEPS;
        x0 = ORBIT_CX + ORBIT_RX * SimTrig.cos_t(a) / SimTrig.ONE;
        y0 = ORBIT_CY + ORBIT_RY * SimTrig.sin_t(a) / SimTrig.ONE;
    }

    public override void touch(GameSim sim)
    {
        if (taken) return;
        bool hit = sim.bird_touches_circle(x0, y0, RADIUS);
        long at_x = x0;
        long at_y = y0;
        if (!hit && mode == Mode.TWO && sim.bird_touches_circle(x1, y1, RADIUS))
        {
            hit = true;
            at_x = x1;
            at_y = y1;
        }
        if (!hit) return;
        taken = true;
        for (long i = 0; i < COINS; i++) sim.collect_coin(at_x, at_y);
    }

    public override bool locks_exit(GameSim sim) => !taken && locked_bounces < MAX_LOCKED_BOUNCES;

    public bool locked() => !taken && locked_bounces < MAX_LOCKED_BOUNCES;

    public override void on_bounce(GameSim sim, SimRng rng)
    {
        if (sim.state.exit_open && !taken) locked_bounces += 1;
    }

    public override long checksum(long h) => mix_all(h, mode, x0, y0, x1, y1, phase, G.B(taken), locked_bounces,
        G.B(door_open), door_side, door_a_y, door_b_y);
}
