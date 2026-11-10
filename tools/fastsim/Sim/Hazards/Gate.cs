namespace FastSim;

/// Port of sim/hazards/gate.gd.
public class Gate : Hazard
{
    public const long HALF_W = 8 * SimConfig.SUB;
    public const long GAP = 176 * SimConfig.SUB;
    public const long SMALL_GAP = 90 * SimConfig.SUB;
    public const long GAP_MIN_Y = 162 * SimConfig.SUB;
    public const long GAP_MAX_Y = 478 * SimConfig.SUB;
    public const long TOP = SimConfig.KILL_TOP;
    public const long BOTTOM = SimConfig.KILL_BOTTOM;
    public const long LAG = 40;
    public const long WALL_CLEAR = 80 * SimConfig.SUB;
    public const long ARRIVAL_HOVER = 30 * SimConfig.SUB;
    public const long EXIT_REACH = 80 * SimConfig.SUB;
    public const long REVIVE_REACH = 80 * SimConfig.SUB;
    public const long SMALL_EXIT_MAX_Y = 490 * SimConfig.SUB;

    public long x = 0;
    public bool follows = false;
    /// The other gate of the pair, or null. GDScript types it Hazard; only a
    /// gate is ever linked here, so it is a Gate.
    public Gate partner = null;
    public long period = 400;
    public long phase = 0;
    public long gap_y = 0;
    public long gap_size = GAP;

    public Gate(long p_x = 0, long p_period = 400, bool p_follows = false, long p_gap = GAP)
    {
        kind = "gate";
        gap_size = p_gap;
        x = p_x;
        period = p_period;
        follows = p_follows;
    }

    public override void remap(Dictionary<Hazard, Hazard> map)
    {
        if (partner != null) partner = (Gate)map[partner];
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        partner = null;
        var hs = sim.room.hazards;
        for (int i = 0; i < hs.Count; i++)
        {
            var h = hs[i];
            if (follows && h != this && h.kind == kind)
            {
                partner = (Gate)h;
                ((Gate)h).partner = this;
            }
        }
        if (follows && partner != null)
        {
            period = partner.period;
            if (sim.state.exit_open || sim.state.exit_preview)
            {
                partner.aim_at_exit(sim);
            }
            else if (sim.state.started && G.absi(x - sim.state.x) < G.absi(partner.x - sim.state.x))
            {
                long shift = _lead(sim, partner.x) - (_lead(sim, x) - LAG);
                partner.phase = G.posmod(partner.phase + shift, period);
                partner._place();
            }
            phase = G.posmod(partner.phase - LAG, period);
            _place();
            return;
        }
        long aim = FairLanes.entry_y(sim);
        long lead = 0;
        if (sim.state.started)
        {
            aim -= ARRIVAL_HOVER * sim.room.gravity;
            lead = _lead(sim, x);
        }
        bool down = rng.next_below(2) == 0;
        if (!sim.state.started && gap_size < GAP)
        {
            var through = _start_crossing(sim);
            if (through.Count != 0)
            {
                aim = through[0];
                lead = through[1];
            }
        }
        phase = _phase_for(aim, lead, down);
        if (sim.state.exit_open || sim.state.exit_preview) aim_at_exit(sim);
        _place();
    }

    public List<long> _start_crossing(GameSim sim)
    {
        var path = FairLanes.start_path(sim);
        long reach = HALF_W + SimConfig.BIRD_RADIUS;
        long first = -1;
        long last = -1;
        long low = 0;
        long high = 0;
        for (long k = 0; k < path.Count / 2; k++)
        {
            if (G.absi(path[(int)(2 * k)] - x) >= reach)
            {
                if (first >= 0) break;
                continue;
            }
            long y = path[(int)(2 * k + 1)];
            if (first < 0)
            {
                first = k;
                low = y;
                high = y;
            }
            last = k;
            low = G.mini(low, y);
            high = G.maxi(high, y);
        }
        if (first < 0) return new List<long>();
        return new List<long> { (low + high) / 2, (first + last) / 2 + 1 };
    }

    public static long _lead(GameSim sim, long gate_x)
        => G.absi(gate_x - sim.state.x) / SimConfig.SPEED_X;

    public override void step(GameSim _sim) { _place(); }

    public void _place() { gap_y = gap_at(t); }

    public long gap_at(long tick)
        => GAP_MIN_Y + SimTrig.ping_pong(tick + phase, period, GAP_MAX_Y - GAP_MIN_Y);

    public long _phase_for(long y, long tick, bool down)
    {
        long span = GAP_MAX_Y - GAP_MIN_Y;
        long at = G.clampi(y - GAP_MIN_Y, 0, span);
        long half = period / 2;
        long rising_phase = at * half / span;
        return G.posmod((down ? rising_phase : period - rising_phase) - tick, period);
    }

    public Gate _last_before(long side)
    {
        if (partner != null && (partner.x > x) == (side == 1)) return partner;
        return this;
    }

    public long _steps_to_pass(GameSim sim, Gate gate, long side)
    {
        long r = SimConfig.BIRD_RADIUS;
        long wall_x = side == 1 ? sim.room.wall_right() - r : sim.room.wall_left() + r;
        return G.maxi(sim.steps_to_wall(side) - G.absi(wall_x - gate.x) / SimConfig.SPEED_X, 0);
    }

    public void aim_at_exit(GameSim sim)
    {
        var s = sim.state;
        var last = _last_before(s.exit_side);
        var first = _last_before(s.vx > 0 ? 0 : 1);
        long first_at = G.absi(first.x - s.x) / SimConfig.SPEED_X - (first == this ? 0 : LAG);
        long last_at = _steps_to_pass(sim, last, s.exit_side) - (last == this ? 0 : LAG);
        long slide = (GAP_MAX_Y - GAP_MIN_Y) * (last_at - first_at) / (period / 2);
        long reach = G.maxi(REVIVE_REACH + slide, 0);
        long from = FairLanes.entry_y(sim);
        long target = G.clampi(G.clampi(s.exit_a_y, GAP_MIN_Y, GAP_MAX_Y), from - reach, from + reach);
        phase = _phase_for(target, t + last_at, target > from);
        _place();
    }

    public override long adjust_wall(GameSim sim, long side, long mask)
    {
        if (follows) return mask;
        var s = sim.state;
        var near = _last_before(side);
        long steps = G.absi(near.x - s.x) / SimConfig.SPEED_X;
        long gap = near.gap_at(t + steps);
        long out_ = mask;
        for (long slot = 0; slot < SimConfig.SLOT_COUNT; slot++)
        {
            if (G.absi(SimConfig.slot_center_y(slot) - gap) < WALL_CLEAR)
                out_ &= ~(1L << (int)slot);
        }
        return out_;
    }

    public override bool blocks_exit(GameSim sim, long side, long y)
    {
        if (gap_size < GAP && y > SMALL_EXIT_MAX_Y) return true;
        if (follows && partner != null) return false;
        var last = _last_before(side);
        long gap = last.gap_at(t + _steps_to_pass(sim, last, side));
        return G.absi(y - gap) > EXIT_REACH;
    }

    public long gap_top() => gap_y - gap_size / 2;

    public long gap_bottom() => gap_y + gap_size / 2;

    public override bool kills(GameSim sim)
    {
        if (sim.bird_touches_rect(x - HALF_W, TOP, x + HALF_W, gap_top())) return true;
        return sim.bird_touches_rect(x - HALF_W, gap_bottom(), x + HALF_W, BOTTOM);
    }

    public override long checksum(long h) => mix_all(h, x, period, phase, gap_y, G.B(follows), gap_size);
}
