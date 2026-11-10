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

    public long side = 0;
    public long y = 0;
    public long delay = 0;
    public long half = 0;

    public Piston(long p_side = 0, long p_half = 0, long p_delay = 0)
    {
        kind = "piston";
        side = p_side;
        half = p_half;
        delay = p_delay;
    }

    public override void setup(GameSim sim, SimRng rng) => _pick_y(rng);

    public override void on_bounce(GameSim sim, SimRng rng)
    {
        // Always draw so the RNG order does not depend on the piston state.
        long old = y;
        _pick_y(rng);
        if (state() != State.IDLE) y = old;
    }

    public void _pick_y(SimRng rng)
    {
        long lo = half == 0 ? Y_MIN : Y_MID + HALF_H;
        long hi = half == 0 ? Y_MID - HALF_H : Y_MAX;
        y = lo + rng.next_below(hi - lo + 1);
    }

    public long cycle_pos()
    {
        if (t < delay) return -1;
        return G.posmod(t - delay, PERIOD);
    }

    public long state()
    {
        long p = cycle_pos();
        if (p < IDLE_TICKS) return State.IDLE;
        p -= IDLE_TICKS;
        if (p < GLOW_TICKS) return State.GLOW;
        p -= GLOW_TICKS;
        if (p < EXTEND_TICKS) return State.EXTEND;
        p -= EXTEND_TICKS;
        if (p < HOLD_TICKS) return State.HOLD;
        return State.RETRACT;
    }

    public long glow()
    {
        if (state() != State.GLOW) return 0;
        return SimTrig.ONE * (cycle_pos() - IDLE_TICKS) / GLOW_TICKS;
    }

    public long extent()
    {
        long p = cycle_pos() - IDLE_TICKS - GLOW_TICKS;
        long s = state();
        if (s == State.EXTEND) return REACH * (p + 1) / EXTEND_TICKS;
        if (s == State.HOLD) return REACH;
        if (s == State.RETRACT)
        {
            p -= EXTEND_TICKS + HOLD_TICKS;
            return REACH * (RETRACT_TICKS - p - 1) / RETRACT_TICKS;
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
