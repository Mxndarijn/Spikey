namespace FastSim;

/// Port of sim/hazards/rotor.gd.
public class Rotor : Hazard
{
    public static class Spin { public const long STEADY = 0, ROCK = 1, BREATHE = 2; }

    public const long CENTER_X = 180 * SimConfig.SUB;
    public const long CENTER_Y = 320 * SimConfig.SUB;
    public const long SAMPLES = 5;
    public const long HOP = 64 * SimConfig.SUB;
    public const long CLEAR_MARGIN = SimConfig.BIRD_RADIUS + 4 * SimConfig.SUB;
    public const long ROCK_EASE = 24;
    public const long ROCK_RUN = 150;
    public const long ROCK_PAUSE = 18;
    public const long ROCK_HALF = 2 * ROCK_EASE + ROCK_RUN + ROCK_PAUSE;
    public const long BREATHE_HOLD = 60;
    public const long BREATHE_MOVE = 60;
    public const long BREATHE_CYCLE = 2 * (BREATHE_HOLD + BREATHE_MOVE);

    public long blades = 4;
    public long blade_max = 80 * SimConfig.SUB;
    public long blade_min = 80 * SimConfig.SUB;
    public long half_w = 8 * SimConfig.SUB;
    public long hub_radius = 16 * SimConfig.SUB;
    public long period = 360;
    public long spin = Spin.STEADY;
    public long hubs = 1;
    public long spread_x = 0;
    public long spread_y = 0;
    public long lean = 0;

    public long center_x = CENTER_X;
    public long center_y = CENTER_Y;
    public long phase = 0;
    public long dir = 1;
    public long angle = 0;
    public long blade_length = 80 * SimConfig.SUB;

    public Rotor(
        long p_length = 80 * SimConfig.SUB,
        long p_half_w = 8 * SimConfig.SUB,
        long p_hub = 16 * SimConfig.SUB)
    {
        kind = "rotor";
        blade_max = p_length;
        blade_min = p_length;
        blade_length = p_length;
        half_w = p_half_w;
        hub_radius = p_hub;
    }

    public long reach() => blade_max + half_w;

    public long hub_clear() => reach() + CLEAR_MARGIN;

    public override void setup(GameSim sim, SimRng rng)
    {
        center_x = CENTER_X;
        center_y = CENTER_Y;
        long y = sim.state.anchor_y;
        long top = hubs == 2 ? -spread_y : 0;
        long bottom = hubs == 2 ? spread_y : 0;
        long clear = hub_clear();
        long dy = y - CENTER_Y;
        if (sim.state.started && dy > top - clear && dy < bottom + clear + HOP)
        {
            long below = y + clear - top;
            long above = y - clear - HOP - bottom;
            long first = dy < 0 ? below : above;
            long second = dy < 0 ? above : below;
            center_y = _fits(first) ? first : second;
            if (!_fits(center_y))
                center_y = first;
        }
        phase = rng.next_below(SimTrig.TURN);
        dir = rng.next_below(2) == 0 ? 1 : -1;
        if (lean != 0)
        {
            bool right = rng.next_below(2) == 0;
            if (sim.state.started)
                right = sim.state.vx > 0;
            center_x = CENTER_X + (right ? lean : -lean);
        }
        _place();
    }

    public bool _fits(long cy)
    {
        long top = cy - (hubs == 2 ? spread_y : 0) - reach();
        long bottom = cy + (hubs == 2 ? spread_y : 0) + reach();
        return top >= SimConfig.KILL_TOP && bottom <= SimConfig.KILL_BOTTOM;
    }

    public override void step(GameSim sim) => _place();

    public void _place()
    {
        angle = G.posmod(phase + dir * _turned(t), SimTrig.TURN);
        blade_length = _length_at(t);
    }

    public long _turned(long steps)
    {
        if (spin != Spin.ROCK)
            return steps * SimTrig.TURN / period;
        long e = ROCK_EASE;
        long full = 2 * e * e + 2 * e * ROCK_RUN;
        long m = steps % ROCK_HALF;
        long x = full;
        if (m < e)
            x = m * m;
        else if (m < e + ROCK_RUN)
            x = e * e + 2 * e * (m - e);
        else if (m < 2 * e + ROCK_RUN)
        {
            long u = m - e - ROCK_RUN;
            x = e * e + 2 * e * ROCK_RUN + 2 * e * u - u * u;
        }
        if ((steps / ROCK_HALF) % 2 == 1)
            x = full - x;
        return x * SimTrig.TURN / (2 * e * period);
    }

    public long _length_at(long steps)
    {
        if (spin != Spin.BREATHE)
            return blade_max;
        long m = steps % BREATHE_CYCLE;
        long grow = blade_max - blade_min;
        if (m < BREATHE_HOLD)
            return blade_min;
        m -= BREATHE_HOLD;
        if (m < BREATHE_MOVE)
            return blade_min + grow * m / BREATHE_MOVE;
        m -= BREATHE_MOVE;
        if (m < BREATHE_HOLD)
            return blade_max;
        m -= BREATHE_HOLD;
        return blade_max - grow * m / BREATHE_MOVE;
    }

    public long hub_x(long h) => center_x + (2 * h - (hubs - 1)) * spread_x;

    public long hub_y(long h) => center_y + (2 * h - (hubs - 1)) * spread_y;

    public long blade_angle(long h, long i)
    {
        long a = h % 2 == 0 ? angle : SimTrig.TURN - angle;
        return a + i * SimTrig.TURN / blades;
    }

    public override long band_top()
    {
        long out_ = hub_y(0) - reach();
        for (long h = 0; h < hubs; h++) out_ = G.mini(out_, hub_y(h) - reach());
        return out_;
    }

    public override long band_bottom()
    {
        long out_ = hub_y(0) + reach();
        for (long h = 0; h < hubs; h++) out_ = G.maxi(out_, hub_y(h) + reach());
        return out_;
    }

    public override bool kills(GameSim sim)
    {
        for (long h = 0; h < hubs; h++)
        {
            long cx = hub_x(h);
            long cy = hub_y(h);
            if (sim.bird_touches_circle(cx, cy, hub_radius)) return true;
            for (long i = 0; i < blades; i++)
            {
                long a = blade_angle(h, i);
                long c = SimTrig.cos_t(a);
                long s = SimTrig.sin_t(a);
                for (long k = 0; k < SAMPLES; k++)
                {
                    long d = blade_length * (k + 1) / SAMPLES;
                    long px = cx + d * c / SimTrig.ONE;
                    long py = cy + d * s / SimTrig.ONE;
                    if (sim.bird_touches_circle(px, py, half_w)) return true;
                }
            }
        }
        return false;
    }

    public override long checksum(long h) =>
        mix_all(h, phase, dir, angle, center_x, center_y, blade_length);
}
