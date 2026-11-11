namespace FastSim;

/// Port of sim/hazards/pendulum.gd.
public class Pendulum : Hazard
{
    public const long PIVOT_X = 180 * SimConfig.SUB;
    public const long PIVOT_Y = SimConfig.KILL_TOP;
    public const long LENGTH = 280 * SimConfig.SUB;
    public const long RADIUS = 22 * SimConfig.SUB;
    public const long AMPLITUDE = 52;
    public const long PERIOD = 180;
    public const long ARRIVAL_TRIES = 32;

    public long pivot_x = PIVOT_X;
    public long pivot_y = PIVOT_Y;
    public long length = LENGTH;
    public long radius = RADIUS;
    public long amplitude = AMPLITUDE;
    public long period = PERIOD;
    public long gust = 0;
    public long gust_period = 1;
    public long winch = 0;
    public long winch_period = 1;
    public long twin_x = 0;
    public long twin_length = 0;

    public long phase = 0;
    public long angle = 0;
    public long chain = 0;
    public long x = 0;
    public long y = 0;
    public long x2 = 0;
    public long y2 = 0;

    public Pendulum(
        long p_pivot_x = PIVOT_X,
        long p_length = LENGTH,
        long p_radius = RADIUS,
        long p_amplitude = AMPLITUDE,
        long p_period = PERIOD)
    {
        kind = "pendulum";
        pivot_x = p_pivot_x;
        length = p_length;
        radius = p_radius;
        amplitude = p_amplitude;
        period = p_period;
    }

    public Hazard gusting(long p_gust, long p_period)
    {
        gust = p_gust;
        gust_period = p_period;
        return this;
    }

    public Hazard winding(long p_winch, long p_period)
    {
        winch = p_winch;
        winch_period = p_period;
        return this;
    }

    public Hazard with_twin(long p_x, long p_length)
    {
        twin_x = p_x;
        twin_length = p_length;
        return this;
    }

    public bool has_twin() => twin_length > 0;

    public override void setup(GameSim sim, SimRng rng)
    {
        phase = rng.next_below(SimTrig.TURN);
        long first = phase;
        long pick = phase;
        if (sim.state.started)
        {
            var arrival = FairLanes.arrival_path(sim);
            bool settled = false;
            for (long k = 0; k < ARRIVAL_TRIES; k++)
            {
                phase = (first + k * SimTrig.TURN / ARRIVAL_TRIES) % SimTrig.TURN;
                long clear = _arrival_clear(arrival);
                if (clear >= FairLanes.ARRIVAL_PATH_TICKS)
                {
                    pick = phase;
                    break;
                }
                if (clear >= FairLanes.ARRIVAL_PATH_MIN && !settled)
                {
                    pick = phase;
                    settled = true;
                }
            }
        }
        else
        {
            var start = FairLanes.start_path(sim);
            long best = -1;
            for (long k = 0; k < ARRIVAL_TRIES; k++)
            {
                phase = (first + k * SimTrig.TURN / ARRIVAL_TRIES) % SimTrig.TURN;
                long clear = _path_clear(start);
                if (clear > best)
                {
                    best = clear;
                    pick = phase;
                }
                if (clear >= FairLanes.START_PATH) break;
            }
        }
        phase = pick;
        _place();
    }

    public long _arrival_clear(List<long> arrival) => _path_clear(arrival);

    public long _path_clear(List<long> path)
    {
        long keep = t;
        long out_ = path.Count / 2;
        for (long k = 0; k < path.Count / 2; k++)
        {
            t = k;
            _place();
            if (FairLanes.arrival_path_hits(path, k, x, y, radius))
            {
                out_ = k;
                break;
            }
            if (has_twin() && FairLanes.arrival_path_hits(path, k, x2, y2, radius))
            {
                out_ = k;
                break;
            }
        }
        t = keep;
        _place();
        return out_;
    }

    public override void step(GameSim sim) => _place();

    public void _place()
    {
        long widest = amplitude;
        if (gust != 0)
            widest += gust * SimTrig.sin_t(t * SimTrig.TURN / gust_period) / SimTrig.ONE;
        chain = length;
        if (winch != 0)
        {
            long wind = t * SimTrig.TURN / winch_period - SimTrig.TURN / 4;
            chain += winch * SimTrig.sin_t(wind) / SimTrig.ONE;
        }
        angle = widest * SimTrig.sin_t(phase + t * SimTrig.TURN / period) / SimTrig.ONE;
        x = pivot_x + chain * SimTrig.sin_t(angle) / SimTrig.ONE;
        y = pivot_y + chain * SimTrig.cos_t(angle) / SimTrig.ONE;
        if (has_twin())
        {
            x2 = twin_x - twin_length * SimTrig.sin_t(angle) / SimTrig.ONE;
            y2 = pivot_y + twin_length * SimTrig.cos_t(angle) / SimTrig.ONE;
        }
    }

    public const long SWING_STEP = 4 * SimConfig.SUB;

    public override bool blocks_exit(GameSim sim, long side, long p_y)
    {
        long widest = amplitude + G.absi(gust);
        long longest = length + G.absi(winch);
        if (!_may_reach(sim, side, pivot_x, longest))
            if (!has_twin() || !_may_reach(sim, side, twin_x, twin_length)) return false;
        long a = -widest;
        while (a <= widest)
        {
            long s = SimTrig.sin_t(a);
            long c = SimTrig.cos_t(a);
            long chain_len = length - G.absi(winch);
            while (chain_len <= longest)
            {
                long lx = pivot_x + chain_len * s / SimTrig.ONE;
                long ly = pivot_y + chain_len * c / SimTrig.ONE;
                if (ExitZone.circle_in_box(sim, side, p_y, lx, ly, radius)) return true;
                chain_len += winch != 0 ? SWING_STEP : longest + 1;
            }
            if (has_twin())
            {
                long tx = twin_x - twin_length * s / SimTrig.ONE;
                long ty = pivot_y + twin_length * c / SimTrig.ONE;
                if (ExitZone.circle_in_box(sim, side, p_y, tx, ty, radius)) return true;
            }
            a += 1;
        }
        return false;
    }

    bool _may_reach(GameSim sim, long side, long px, long chain_len)
    {
        long far = chain_len + radius;
        if (side == 0) return px - far <= ExitZone.right_on(sim, 0);
        return px + far >= ExitZone.left_on(sim, 1);
    }

    public override bool kills(GameSim sim)
    {
        if (has_twin() && sim.bird_touches_circle(x2, y2, radius)) return true;
        return sim.bird_touches_circle(x, y, radius);
    }

    public override long checksum(long h) => mix_all(h, phase, angle, chain, x, y, x2, y2);
}
