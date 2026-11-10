namespace FastSim;

/// Port of sim/hazards/lava.gd.
public class Lava : Hazard
{
    public static class Mode { public const long FLOOR = 0, CEILING = 1; }

    public const long SUB = SimConfig.SUB;
    public const long STEP = 30 * SUB;
    public const long MAX_RISES = 7;
    public const long SPEED = 80;
    public const long STONE_RADIUS = 14 * SUB;
    public const long STONE_AFTER = 3;
    public const long STONE_CLEAR = 90 * SUB;
    public const long STONE_EDGE = 80 * SUB;
    public const long EXIT_CLEAR = SimConfig.BIRD_RADIUS + 24 * SUB;
    public const long RUN = 3;

    public long mode = Mode.FLOOR;
    public long line = SimConfig.KILL_BOTTOM;
    public long rises = 0;
    public long counted = 0;
    public bool stone_on = false;
    public long stone_x = 0;
    public long stone_y = 0;

    public Lava(long p_mode = -1)
    {
        kind = "lava";
        mode = p_mode;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        if (mode < 0)
            mode = sim.room.variant_id() == "crusher" ? Mode.CEILING : Mode.FLOOR;
        line = rest();
        counted = sim.room.points;
    }

    public long rest() => mode == Mode.CEILING ? SimConfig.KILL_TOP : SimConfig.KILL_BOTTOM;

    public long line_at(long n)
    {
        if (mode == Mode.CEILING) return SimConfig.KILL_TOP + n * STEP;
        return SimConfig.KILL_BOTTOM - n * STEP;
    }

    public long rises_due(GameSim sim) => G.mini(rises + sim.room.points - counted, MAX_RISES);

    public override void step(GameSim sim)
    {
        line += G.clampi(line_at(rises) - line, -SPEED, SPEED);
    }

    public override bool kills(GameSim sim)
    {
        long r = SimConfig.BIRD_RADIUS;
        if (mode == Mode.CEILING) return line > SimConfig.KILL_TOP && sim.state.y - r <= line;
        return line < SimConfig.KILL_BOTTOM && sim.state.y + r >= line;
    }

    public override void touch(GameSim sim)
    {
        if (stone_on && sim.bird_touches_circle(stone_x, stone_y, STONE_RADIUS))
        {
            stone_on = false;
            rises = 0;
        }
    }

    bool _slot_clear(long slot, long edge)
    {
        long cy = SimConfig.slot_center_y(slot);
        long half = SimConfig.SLOT_SIZE / 2;
        if (mode == Mode.CEILING) return cy - half >= edge + SimConfig.BIRD_RADIUS;
        return cy + half <= edge - SimConfig.BIRD_RADIUS;
    }

    public override long adjust_wall(GameSim sim, long side, long mask)
    {
        if (mask == 0) return mask;
        long edge = line_at(rises_due(sim));
        long run = 0;
        long first_ok = -1;
        long last_ok = -1;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            if (!_slot_clear(slot, edge))
            {
                run = 0;
                continue;
            }
            if (first_ok < 0) first_ok = slot;
            last_ok = slot;
            run = RoomRules.has_slot(mask, slot) ? 0 : run + 1;
            if (run >= RUN) return mask;
        }
        if (first_ok < 0 || last_ok - first_ok + 1 < RUN) return mask;
        long c0 = SimConfig.slot_center_y(0);
        long near = (sim.state.y - c0 + SimConfig.SLOT_SIZE / 2) / SimConfig.SLOT_SIZE;
        long mid = G.clampi(near, first_ok + 1, last_ok - 1);
        for (long slot = mid - 1; slot < mid + 2; slot++) mask &= ~(1L << (int)slot);
        return mask;
    }

    public override void on_bounce(GameSim sim, SimRng rng)
    {
        rises = rises_due(sim);
        counted = sim.room.points;
        if (stone_on || rises < STONE_AFTER) return;
        long heading = line_at(rises);
        long lo = SimConfig.KILL_TOP + STONE_EDGE;
        long hi = heading - STONE_CLEAR;
        if (mode == Mode.CEILING)
        {
            lo = heading + STONE_CLEAR;
            hi = SimConfig.KILL_BOTTOM - STONE_EDGE;
        }
        stone_x = (110 + rng.next_below(141)) * SUB;
        stone_y = lo + rng.next_below(G.maxi(hi - lo, 0) + 1);
        stone_on = true;
    }

    public override bool blocks_exit(GameSim sim, long side, long y)
    {
        long worst = line_at(G.mini(rises_due(sim) + 1, MAX_RISES));
        if (mode == Mode.CEILING) return y < worst + EXIT_CLEAR;
        return y > worst - EXIT_CLEAR;
    }

    public override long checksum(long h) => mix_all(h, mode, line, rises, counted, G.B(stone_on), stone_x, stone_y);
}
