namespace FastSim;

/// Port of sim/hazards/boss_saw.gd.
public class BossSaw : Boss
{
    public const long KING_X = 180 * SimConfig.SUB;
    public const long KING_R = 46 * SimConfig.SUB;
    public const long BLADE_R = 12 * SimConfig.SUB;
    public static readonly long[] HEIGHTS = { 180 * SimConfig.SUB, 320 * SimConfig.SUB, 460 * SimConfig.SUB };
    public static readonly long[] RING_YS = { 260 * SimConfig.SUB, 380 * SimConfig.SUB };
    public const long CYCLE = 240;
    public const long CYCLE_FAST = 180;
    public const long TELL = SimConfig.WARN_TICKS;
    public const long JUMP = 30;
    public const long RING_OUT = TELL + JUMP;
    public const long RING_HOLD = 120;
    public const long RING_IN = 180;
    public const long RING_MAX = 115 * SimConfig.SUB;
    public const long RING_MAX_TIER3 = 130 * SimConfig.SUB;
    public const long RING_HOP = 72 * SimConfig.SUB;
    public const long RING_SHOW = 50 * SimConfig.SUB;
    public const long RING_SPEED = 4 * SimConfig.SUB;
    public const long SLIDE = 3 * SimConfig.SUB;
    public const long SPIN = 6;

    public long king_y = 0;
    public long from_y = 0;
    public long to_y = 0;
    public long ring = 0;
    public long angle = 0;
    public long blades = 6;
    public List<long> blade_x = new();
    public List<long> blade_y = new();
    public bool telling = false;
    public long _k = -1;

    public BossSaw()
    {
        kind = "boss_saw";
    }

    public override Hazard clone_deep()
    {
        var c = (BossSaw)MemberwiseClone();
        c.blade_x = new List<long>(blade_x);
        c.blade_y = new List<long>(blade_y);
        return c;
    }

    static void _resize(List<long> xs, long n)
    {
        while (xs.Count > n) xs.RemoveAt(xs.Count - 1);
        while (xs.Count < n) xs.Add(0);
    }

    public override void boss_setup(GameSim sim)
    {
        blades = tier >= 3 ? 8 : 6;
        _resize(blade_x, blades);
        _resize(blade_y, blades);
        long far = 0;
        if (G.absi(HEIGHTS[2] - sim.state.anchor_y) > G.absi(HEIGHTS[0] - sim.state.anchor_y)) far = 2;
        else if (G.absi(HEIGHTS[2] - sim.state.anchor_y) == G.absi(HEIGHTS[0] - sim.state.anchor_y))
            far = 2 * (seed % 2);
        king_y = HEIGHTS[far];
        from_y = king_y;
        to_y = king_y;
        _place_blades();
    }

    public long cycle() => phase == 3 && tier >= 2 ? CYCLE_FAST : CYCLE;

    public long ring_max() => tier >= 3 ? RING_MAX_TIER3 : RING_MAX;

    public static long nearest(long y)
    {
        long best = 0;
        for (long i = 0; i < HEIGHTS.Length; i++)
            if (G.absi(HEIGHTS[i] - y) < G.absi(HEIGHTS[best] - y)) best = i;
        return best;
    }

    public long hop_to(long from, long k)
    {
        if (nearest(from) != 1) return HEIGHTS[1];
        return HEIGHTS[draw(k, phase) % 2 == 0 ? 0 : 2];
    }

    public override void on_phase()
    {
        _k = -1;
    }

    public override void boss_step(GameSim _sim)
    {
        angle = G.posmod(angle + SPIN, SimTrig.TURN);
        telling = false;
        long c = clock();
        long ring_to = ring;
        if (c < 0)
        {
            ring_to = phase == 3 ? RING_HOP : 0;
            if (phase != 2) king_y = _toward(king_y, HEIGHTS[nearest(king_y)], SLIDE);
        }
        else if (phase == 2)
        {
            long k = c / CYCLE;
            long lt = c % CYCLE;
            if (_k != k)
            {
                _k = k;
                from_y = king_y;
                to_y = RING_YS[draw(k, 2) % 2];
            }
            telling = lt < RING_OUT;
            king_y = _jump(lt);
            ring_to = lt >= RING_OUT && lt < RING_IN ? ring_max() : 0;
        }
        else
        {
            long k = c / cycle();
            long lt = c % cycle();
            if (_k != k)
            {
                _k = k;
                from_y = king_y;
                to_y = hop_to(from_y, k);
            }
            telling = lt < TELL;
            king_y = _jump(lt);
            ring_to = phase == 3 ? RING_HOP : 0;
        }
        ring = _toward(ring, ring_to, RING_SPEED);
        _place_blades();
    }

    public long _jump(long lt)
    {
        if (lt < TELL) return from_y;
        if (lt < TELL + JUMP) return from_y + (to_y - from_y) * (lt - TELL) / JUMP;
        return to_y;
    }

    public static long _toward(long from, long to, long speed)
    {
        if (to > from) return G.mini(from + speed, to);
        return G.maxi(from - speed, to);
    }

    public void _place_blades()
    {
        for (long i = 0; i < blades; i++)
        {
            long a = angle + i * SimTrig.TURN / blades;
            blade_x[(int)i] = KING_X + ring * SimTrig.cos_t(a) / SimTrig.ONE;
            blade_y[(int)i] = king_y + ring * SimTrig.sin_t(a) / SimTrig.ONE;
        }
    }

    public override void boss_down_step(GameSim _sim)
    {
        telling = false;
        ring = _toward(ring, 0, RING_SPEED);
        _place_blades();
    }

    public override bool boss_kills(GameSim sim)
    {
        if (sim.bird_touches_circle(KING_X, king_y, KING_R)) return true;
        if (ring >= RING_SHOW)
            for (long i = 0; i < blades; i++)
                if (sim.bird_touches_circle(blade_x[(int)i], blade_y[(int)i], BLADE_R)) return true;
        return false;
    }

    public override bool safe_y(long y, long steps)
    {
        if (phase != 2) return true;
        long c = clock_in(steps);
        if (c < 0) return true;
        long lt = c % CYCLE;
        if (lt < RING_OUT || lt >= RING_IN) return true;
        long k = c / CYCLE;
        long at = k == _k ? to_y : RING_YS[draw(k, 2) % 2];
        return G.absi(y - at) >= ring_max() + BLADE_R + SimConfig.BIRD_RADIUS + MARGIN;
    }

    public override long checksum(long h)
    {
        long out_ = mix_all(base.checksum(h), king_y, from_y, to_y, ring, angle, blades, G.B(telling), _k);
        for (long i = 0; i < blades; i++)
            out_ = mix_all(out_, blade_x[(int)i], blade_y[(int)i]);
        return out_;
    }

    public override void warnings(GameSim sim, List<long> out_)
    {
        if (down_at >= 0 || clock() < 0 || !telling) return;
        long lt = clock() % cycle();
        long top = G.mini(from_y, to_y);
        long bottom = G.maxi(from_y, to_y);
        if (lt < TELL)
        {
            long r = KING_R + (phase == 3 ? RING_HOP + BLADE_R : 0);
            add_warning(out_, KING_X - r, top - r, KING_X + r, bottom + r, TELL - lt, cycle() - TELL, WARN_KILL);
        }
        if (phase == 2)
        {
            long far = ring_max() + BLADE_R;
            long eta = RING_OUT - lt + (RING_SHOW + RING_SPEED - 1) / RING_SPEED;
            long dur = RING_IN - RING_OUT + ring_max() / RING_SPEED;
            add_warning(out_, KING_X - far, to_y - far, KING_X + far, to_y + far, eta, dur, WARN_KILL);
        }
    }
}
