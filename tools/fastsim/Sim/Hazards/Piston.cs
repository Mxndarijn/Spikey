namespace FastSim;

/// Port of sim/hazards/piston.gd.
public class Piston : Hazard
{
    public static class State
    {
        public const long IDLE = 0, GLOW = 1, EXTEND = 2, HOLD = 3, RETRACT = 4;
    }

    public const long IDLE_TICKS = 70;
    public const long GLOW_TICKS = 32;
    public const long EXTEND_TICKS = 8;
    public const long HOLD_TICKS = 34;
    public const long RETRACT_TICKS = 30;
    public const long PERIOD = IDLE_TICKS + GLOW_TICKS + EXTEND_TICKS + HOLD_TICKS + RETRACT_TICKS;

    public const long REACH = 200 * SimConfig.SUB;
    public const long HALF_H = 18 * SimConfig.SUB;
    public const long Y_MIN = 110 * SimConfig.SUB;
    public const long Y_MAX = 530 * SimConfig.SUB;
    public const long Y_MID = 320 * SimConfig.SUB;
    public const long HALF_ALL = 2;

    public long side = 0;
    public long y = 0;
    public long delay = 0;
    public long half = 0;
    public long glow_ticks = GLOW_TICKS;
    public bool share_band = false;
    public long y_lo = Y_MIN;
    public long y_hi = Y_MAX;
    public long reach = REACH;
    public bool follows = false;
    /// GDScript types this as Hazard; only Pistons are ever stored in it.
    public Piston leader = null;
    public long fixed_y = -1;

    public Piston(long p_side = 0, long p_half = 0, long p_delay = 0, long p_glow = GLOW_TICKS, bool p_share_band = false)
    {
        kind = "piston";
        side = p_side;
        half = p_half;
        delay = p_delay;
        glow_ticks = p_glow;
        share_band = p_share_band;
    }

    public override void remap(Dictionary<Hazard, Hazard> map)
    {
        if (leader != null) leader = (Piston)map[leader];
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        if (fixed_y >= 0)
        {
            y = fixed_y;
            return;
        }
        if (follows)
        {
            leader = null;
            for (int i = 0; i < sim.room.hazards.Count; i++)
            {
                var h = sim.room.hazards[i];
                if (h == this) break;
                if (h.kind == kind) leader = (Piston)h;
            }
            if (leader != null)
            {
                y = leader.y;
                return;
            }
        }
        y_lo = half != 1 ? Y_MIN : Y_MID + HALF_H;
        y_hi = half == 0 ? Y_MID - HALF_H : Y_MAX;
        if (share_band)
        {
            foreach (Hazard h in sim.room.hazards)
            {
                if (h == this || h.band_top() < 0) continue;
                long lo = G.maxi(Y_MIN, h.band_top() + HALF_H);
                long hi = G.mini(Y_MAX, h.band_bottom() - HALF_H);
                if (lo <= hi)
                {
                    y_lo = lo;
                    y_hi = hi;
                }
            }
        }
        _pick_y(rng);
    }

    public override void on_bounce(GameSim sim, SimRng rng)
    {
        if (fixed_y >= 0) return;
        if (leader != null)
        {
            y = leader.y;
            return;
        }
        // Always draw so the RNG order does not depend on the piston state.
        long old = y;
        _pick_y(rng);
        if (state() != State.IDLE) y = old;
    }

    public void _pick_y(SimRng rng)
    {
        y = y_lo + rng.next_below(y_hi - y_lo + 1);
    }

    public long period() => IDLE_TICKS + glow_ticks + EXTEND_TICKS + HOLD_TICKS + RETRACT_TICKS;

    public long cycle_pos()
    {
        if (t < delay) return -1;
        return G.posmod(t - delay, period());
    }

    public long state()
    {
        long p = cycle_pos();
        if (p < IDLE_TICKS) return State.IDLE;
        p -= IDLE_TICKS;
        if (p < glow_ticks) return State.GLOW;
        p -= glow_ticks;
        if (p < EXTEND_TICKS) return State.EXTEND;
        p -= EXTEND_TICKS;
        if (p < HOLD_TICKS) return State.HOLD;
        return State.RETRACT;
    }

    public long glow()
    {
        if (state() != State.GLOW) return 0;
        return SimTrig.ONE * (cycle_pos() - IDLE_TICKS) / glow_ticks;
    }

    public long extent()
    {
        long p = cycle_pos() - IDLE_TICKS - glow_ticks;
        long s = state();
        if (s == State.EXTEND) return reach * (p + 1) / EXTEND_TICKS;
        if (s == State.HOLD) return reach;
        if (s == State.RETRACT)
        {
            p -= EXTEND_TICKS + HOLD_TICKS;
            return reach * (RETRACT_TICKS - p - 1) / RETRACT_TICKS;
        }
        return 0;
    }

    public long base_x() => side == 0 ? 0 : SimConfig.WORLD_W;

    public long tip_x() => side == 0 ? base_x() + extent() : base_x() - extent();

    public override bool kills(GameSim sim)
    {
        long e = extent();
        if (e <= 0) return false;
        return sim.bird_touches_rect(base_x(), y - HALF_H, tip_x(), y + HALF_H);
    }

    public override long checksum(long h) => mix_all(h, side, y, delay, half);
}
