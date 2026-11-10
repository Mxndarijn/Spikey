namespace FastSim;

/// Port of sim/hazards/dart.gd.
public class Dart : Hazard
{
    public static class State
    {
        public const long IDLE = 0, GLOW = 1, FLY = 2;
    }

    public const long START_DELAY = 60;
    public const long IDLE_TICKS = 50;
    public const long GLOW_TICKS = 40;
    public const long SPEED = 7 * SimConfig.SUB;
    public const long LENGTH = 30 * SimConfig.SUB;
    public const long HALF_H = 5 * SimConfig.SUB;
    public const long LANE_MIN = 90 * SimConfig.SUB;
    public const long LANE_MAX = 550 * SimConfig.SUB;
    public const long LANES = 8;
    public const long LANE_STEP = (LANE_MAX - LANE_MIN) / (LANES - 1);
    public const long LANES_SPEED = 6 * SimConfig.SUB;
    public const long LANES_FLASH = 45;
    public const long LANES_IDLE = 40;
    public const long SLOT_DELAY = 70;
    public const long TWIN_DELAY = 75;

    public bool lanes = false;
    public long lane_count = LANES;
    public long lane_min = LANE_MIN;
    public long lane_max = LANE_MAX;
    public long lanes_speed = LANES_SPEED;
    public long lanes_flash = LANES_FLASH;
    public bool pair = false;
    public long lane2_y = 0;
    public long slot = 0;
    public long home = -1;
    public long state = State.IDLE;
    public long since = 0;
    public long wait = START_DELAY;
    public long side = 1;
    public long lane_y = 0;
    public long x = 0;
    public long shots = 0;
    public long salt = 0;

    public Dart(bool p_lanes = false, long p_slot = 0, long p_home = -1)
    {
        kind = "dart";
        lanes = p_lanes;
        slot = p_slot;
        home = p_home;
    }

    public override void setup(GameSim sim, SimRng rng)
    {
        salt = rng.next_u32();
        state = State.IDLE;
        since = 0;
        wait = START_DELAY + slot * (lanes ? SLOT_DELAY : TWIN_DELAY);
        side = sim.state.x < SimConfig.WORLD_W / 2 ? 1 : 0;
        if (home >= 0) side = home;
        lane_y = LANE_MIN;
        x = _base_x();
    }

    public long _base_x() => side == 0 ? 0 : SimConfig.WORLD_W;

    public long _dir() => side == 0 ? 1 : -1;

    public override void step(GameSim sim)
    {
        if (state == State.IDLE)
        {
            if (t - since >= wait)
            {
                _aim(sim);
                state = State.GLOW;
                since = t;
            }
        }
        else if (state == State.GLOW)
        {
            if (t - since >= (lanes ? lanes_flash : GLOW_TICKS))
            {
                state = State.FLY;
                since = t;
                x = _base_x();
            }
        }
        else if (state == State.FLY)
        {
            x += _dir() * (lanes ? lanes_speed : SPEED);
            if (x < -LENGTH || x > SimConfig.WORLD_W + LENGTH)
            {
                state = State.IDLE;
                since = t;
                wait = lanes ? LANES_IDLE : IDLE_TICKS;
                shots += 1;
                x = _base_x();
            }
        }
    }

    public void _aim(GameSim sim)
    {
        if (lanes)
        {
            long r = SimHash.mix(salt, shots);
            long lane = G.posmod(r, lane_count);
            lane_y = lane_min + lane * lane_step();
            side = (r >> 8) & 1;
            if (pair)
            {
                long other = (lane + 1 + G.posmod(r >> 12, lane_count - 1)) % lane_count;
                lane2_y = lane_min + other * lane_step();
            }
            return;
        }
        // The far wall from the bird, at the bird's height right now.
        side = sim.state.x < SimConfig.WORLD_W / 2 ? 1 : 0;
        if (home >= 0) side = home;
        lane_y = G.clampi(sim.state.y, LANE_MIN, LANE_MAX);
    }

    public long lane_step() => (lane_max - lane_min) / (lane_count - 1);

    public long glow()
    {
        if (state != State.GLOW) return 0;
        return SimTrig.ONE * (t - since) / (lanes ? lanes_flash : GLOW_TICKS);
    }

    public long tail_x() => x - _dir() * LENGTH;

    public override bool kills(GameSim sim)
    {
        if (state != State.FLY) return false;
        if (pair && sim.bird_touches_rect(tail_x(), lane2_y - HALF_H, x, lane2_y + HALF_H)) return true;
        return sim.bird_touches_rect(tail_x(), lane_y - HALF_H, x, lane_y + HALF_H);
    }

    public override long checksum(long h)
    {
        long out_ = mix_all(h, G.B(lanes), slot, home, state, since, wait, side, lane_y, x, shots, salt);
        if (pair || lane_count != LANES || lanes_speed != LANES_SPEED || lanes_flash != LANES_FLASH)
            out_ = mix_all(out_, G.B(pair), lane2_y, lane_count, lane_min, lanes_speed, lanes_flash);
        return out_;
    }
}
