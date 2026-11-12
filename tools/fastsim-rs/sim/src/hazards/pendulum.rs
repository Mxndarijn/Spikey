//! Port of sim/hazards/pendulum.gd (Sim/Hazards/Pendulum.cs).
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Pendulum {
    pub base: Base,
    pub pivot_x: i64,
    pub pivot_y: i64,
    pub length: i64,
    pub radius: i64,
    pub amplitude: i64,
    pub period: i64,
    pub gust: i64,
    pub gust_period: i64,
    pub winch: i64,
    pub winch_period: i64,
    pub twin_x: i64,
    pub twin_length: i64,

    pub phase: i64,
    pub angle: i64,
    pub chain: i64,
    pub x: i64,
    pub y: i64,
    pub x2: i64,
    pub y2: i64,
}

impl Pendulum {
    pub const PIVOT_X: i64 = 180 * SimConfig::SUB;
    pub const PIVOT_Y: i64 = SimConfig::KILL_TOP;
    pub const LENGTH: i64 = 280 * SimConfig::SUB;
    pub const RADIUS: i64 = 22 * SimConfig::SUB;
    pub const AMPLITUDE: i64 = 52;
    pub const PERIOD: i64 = 180;
    pub const ARRIVAL_TRIES: i64 = 32;
    pub const SWING_STEP: i64 = 4 * SimConfig::SUB;

    /// C# defaults: p_pivot_x = PIVOT_X, p_length = LENGTH, p_radius = RADIUS,
    /// p_amplitude = AMPLITUDE, p_period = PERIOD.
    pub fn new(p_pivot_x: i64, p_length: i64, p_radius: i64, p_amplitude: i64, p_period: i64) -> Pendulum {
        Pendulum {
            base: Base::new("pendulum"),
            pivot_x: p_pivot_x,
            pivot_y: Self::PIVOT_Y,
            length: p_length,
            radius: p_radius,
            amplitude: p_amplitude,
            period: p_period,
            gust: 0,
            gust_period: 1,
            winch: 0,
            winch_period: 1,
            twin_x: 0,
            twin_length: 0,
            phase: 0,
            angle: 0,
            chain: 0,
            x: 0,
            y: 0,
            x2: 0,
            y2: 0,
        }
    }

    pub fn gusting(mut self, p_gust: i64, p_period: i64) -> Pendulum {
        self.gust = p_gust;
        self.gust_period = p_period;
        self
    }

    pub fn winding(mut self, p_winch: i64, p_period: i64) -> Pendulum {
        self.winch = p_winch;
        self.winch_period = p_period;
        self
    }

    pub fn with_twin(mut self, p_x: i64, p_length: i64) -> Pendulum {
        self.twin_x = p_x;
        self.twin_length = p_length;
        self
    }

    pub fn has_twin(&self) -> bool {
        self.twin_length > 0
    }

    pub fn _arrival_clear(&mut self, arrival: &[i64]) -> i64 {
        self._path_clear(arrival)
    }

    pub fn _path_clear(&mut self, path: &[i64]) -> i64 {
        let keep = self.base.t;
        let mut out_ = path.len() as i64 / 2;
        for k in 0..path.len() as i64 / 2 {
            self.base.t = k;
            self._place();
            if FairLanes::arrival_path_hits(path, k, self.x, self.y, self.radius) {
                out_ = k;
                break;
            }
            if self.has_twin() && FairLanes::arrival_path_hits(path, k, self.x2, self.y2, self.radius) {
                out_ = k;
                break;
            }
        }
        self.base.t = keep;
        self._place();
        out_
    }

    pub fn _place(&mut self) {
        let t = self.base.t;
        let mut widest = self.amplitude;
        if self.gust != 0 {
            widest += self.gust * SimTrig::sin_t(t * SimTrig::TURN / self.gust_period) / SimTrig::ONE;
        }
        self.chain = self.length;
        if self.winch != 0 {
            let wind = t * SimTrig::TURN / self.winch_period - SimTrig::TURN / 4;
            self.chain += self.winch * SimTrig::sin_t(wind) / SimTrig::ONE;
        }
        self.angle = widest * SimTrig::sin_t(self.phase + t * SimTrig::TURN / self.period) / SimTrig::ONE;
        self.x = self.pivot_x + self.chain * SimTrig::sin_t(self.angle) / SimTrig::ONE;
        self.y = self.pivot_y + self.chain * SimTrig::cos_t(self.angle) / SimTrig::ONE;
        if self.has_twin() {
            self.x2 = self.twin_x - self.twin_length * SimTrig::sin_t(self.angle) / SimTrig::ONE;
            self.y2 = self.pivot_y + self.twin_length * SimTrig::cos_t(self.angle) / SimTrig::ONE;
        }
    }

    fn _may_reach(&self, sim: &GameSim, side: i64, px: i64, chain_len: i64) -> bool {
        let far = chain_len + self.radius;
        if side == 0 {
            return px - far <= ExitZone::right_on(sim, 0);
        }
        px + far >= ExitZone::left_on(sim, 1)
    }
}

impl Hazard for Pendulum {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        self.phase = rng.next_below(SimTrig::TURN);
        let first = self.phase;
        let mut pick = self.phase;
        if sim.state.started {
            let arrival = FairLanes::arrival_path(sim);
            let mut settled = false;
            for k in 0..Self::ARRIVAL_TRIES {
                self.phase = (first + k * SimTrig::TURN / Self::ARRIVAL_TRIES) % SimTrig::TURN;
                let clear = self._arrival_clear(&arrival);
                if clear >= FairLanes::ARRIVAL_PATH_TICKS {
                    pick = self.phase;
                    break;
                }
                if clear >= FairLanes::ARRIVAL_PATH_MIN && !settled {
                    pick = self.phase;
                    settled = true;
                }
            }
        } else {
            let start = FairLanes::start_path(sim);
            let mut best = -1;
            for k in 0..Self::ARRIVAL_TRIES {
                self.phase = (first + k * SimTrig::TURN / Self::ARRIVAL_TRIES) % SimTrig::TURN;
                let clear = self._path_clear(&start);
                if clear > best {
                    best = clear;
                    pick = self.phase;
                }
                if clear >= FairLanes::START_PATH {
                    break;
                }
            }
        }
        self.phase = pick;
        self._place();
    }

    fn step(&mut self, _sim: &mut GameSim) {
        self._place();
    }

    fn blocks_exit(&self, sim: &GameSim, side: i64, p_y: i64) -> bool {
        let widest = self.amplitude + G::absi(self.gust);
        let longest = self.length + G::absi(self.winch);
        if !self._may_reach(sim, side, self.pivot_x, longest) {
            if !self.has_twin() || !self._may_reach(sim, side, self.twin_x, self.twin_length) {
                return false;
            }
        }
        let mut a = -widest;
        while a <= widest {
            let s = SimTrig::sin_t(a);
            let c = SimTrig::cos_t(a);
            let mut chain_len = self.length - G::absi(self.winch);
            while chain_len <= longest {
                let lx = self.pivot_x + chain_len * s / SimTrig::ONE;
                let ly = self.pivot_y + chain_len * c / SimTrig::ONE;
                if ExitZone::circle_in_box(sim, side, p_y, lx, ly, self.radius) {
                    return true;
                }
                chain_len += if self.winch != 0 { Self::SWING_STEP } else { longest + 1 };
            }
            if self.has_twin() {
                let tx = self.twin_x - self.twin_length * s / SimTrig::ONE;
                let ty = self.pivot_y + self.twin_length * c / SimTrig::ONE;
                if ExitZone::circle_in_box(sim, side, p_y, tx, ty, self.radius) {
                    return true;
                }
            }
            a += 1;
        }
        false
    }

    fn kills(&self, sim: &GameSim) -> bool {
        if self.has_twin() && sim.bird_touches_circle(self.x2, self.y2, self.radius) {
            return true;
        }
        sim.bird_touches_circle(self.x, self.y, self.radius)
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(h, &[self.phase, self.angle, self.chain, self.x, self.y, self.x2, self.y2])
    }
}
