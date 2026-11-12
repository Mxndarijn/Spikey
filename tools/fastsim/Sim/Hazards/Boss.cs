namespace FastSim;

/// Port of sim/hazards/boss.gd (base of the boss hazards).
public class Boss : Hazard
{
    public static readonly long[] PHASE_AT = { 7, 14 };
    public const long STAGGER = 70;
    public const long FIRST_DELAY = SimConfig.ARRIVAL_BLIND + SimConfig.ARRIVAL_FOLLOW / 2;
    public const long WALL_FROM = -6;
    public const long WALL_TO = 30;
    public const long WALL_STEP = 6;
    public const long MARGIN = 4 * SimConfig.SUB;

    public long tier = 1;
    public long phase = 1;
    public long phase_start = FIRST_DELAY;
    public long down_at = -1;
    public long seed = 0;

    public override void setup(GameSim sim, SimRng rng)
    {
        tier = SimConfig.boss_tier(sim.room.entry_score);
        seed = rng.next_u32();
        boss_setup(sim);
    }

    public override void step(GameSim sim)
    {
        if (down_at < 0 && (sim.state.exit_open || sim.state.exit_preview)) down_at = t;
        if (down_at >= 0)
        {
            boss_down_step(sim);
            return;
        }
        long p = phase_of(sim.room.points);
        if (p != phase)
        {
            phase = p;
            phase_start = t + STAGGER;
            on_phase();
        }
        boss_step(sim);
    }

    public override bool kills(GameSim sim)
    {
        if (down_at >= 0) return false;
        return boss_kills(sim);
    }

    public static long phase_of(long points)
    {
        if (points >= PHASE_AT[1]) return 3;
        if (points >= PHASE_AT[0]) return 2;
        return 1;
    }

    public long clock() => t - phase_start;

    public long clock_in(long steps) => t + steps - phase_start;

    public long draw(long k, long salt) => SimHash.mix(SimHash.mix(SimHash.mix(SimHash.SEED, seed), k), salt);

    public static long x_after(GameSim sim, long steps)
    {
        long r = SimConfig.BIRD_RADIUS;
        long lo = sim.room.wall_left() + r;
        long hi = sim.room.wall_right() - r;
        long span = hi - lo;
        if (span <= 0) return sim.state.x;
        long pos = sim.state.vx > 0 ? sim.state.x - lo : 2 * span - (sim.state.x - lo);
        pos = G.posmod(pos + steps * G.absi(sim.state.vx), 2 * span);
        return lo + (pos <= span ? pos : 2 * span - pos);
    }

    public override long adjust_wall(GameSim sim, long side, long mask)
    {
        if (down_at >= 0) return mask;
        long at = sim.steps_to_wall(side);
        long free = RoomRules.longest_gap_mask(mask);
        long mid = 0;
        long n = 0;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            if (!RoomRules.has_slot(mask, slot))
            {
                long y = SimConfig.slot_center_y(slot);
                if (_safe_span(y, at)) return mask;
                if (((free >> (int)slot) & 1) == 1)
                {
                    mid += y;
                    n += 1;
                }
                if (slot + 1 < SimConfig.SLOT_COUNT && !RoomRules.has_slot(mask, slot + 1))
                    if (_safe_span(y + SimConfig.SLOT_SIZE / 2, at)) return mask;
            }
        }
        if (n > 0) mid /= n;
        long best = -1;
        long best_d = 0;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            long y = SimConfig.slot_center_y(slot);
            if (!_safe_span(y, at)) continue;
            long d = G.absi(y - mid);
            if (best < 0 || d < best_d)
            {
                best = slot;
                best_d = d;
            }
        }
        if (best < 0) return mask;
        for (long slot = G.maxi(best - 1, 0); slot < G.mini(best + 2, SimConfig.SLOT_COUNT); slot++)
            mask &= ~(1L << (int)slot);
        return mask;
    }

    public bool _safe_span(long y, long at)
    {
        for (long d = WALL_FROM; d < WALL_TO + 1; d += WALL_STEP)
            if (!safe_y(y, at + d)) return false;
        return true;
    }

    public virtual bool safe_y(long _y, long _steps) => true;

    public virtual void boss_setup(GameSim _sim) { }

    public virtual void on_phase() { }

    public virtual void boss_step(GameSim _sim) { }

    public virtual void boss_down_step(GameSim _sim) { }

    public virtual bool boss_kills(GameSim _sim) => false;

    public override long checksum(long h) => mix_all(h, tier, phase, phase_start, down_at, seed);
}
