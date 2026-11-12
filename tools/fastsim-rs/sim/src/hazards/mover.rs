//! Port of sim/hazards/mover.gd (Sim/Hazards/Mover.cs).
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Mover {
    pub base: Base,
    pub mode: &'static str,
    pub count: i64,
    pub loop_w: i64,
    pub loop_h: i64,
    pub loop_period: i64,
    pub chase: bool,
    pub phase: i64,
    pub xs: Vec<i64>,
    pub ys: Vec<i64>,
    pub facing: Vec<i64>,
}

impl Mover {
    pub const SUB: i64 = SimConfig::SUB;
    pub const RADIUS: i64 = 12 * Self::SUB;
    pub const START_MARGIN: i64 = 10 * Self::SUB;
    pub const PHASE_TRIES: i64 = 16;
    pub const ARRIVAL_TRIES: i64 = 60;
    pub const CENTER_X: i64 = 180 * Self::SUB;
    pub const CENTER_Y: i64 = 320 * Self::SUB;
    // Figure-eight.
    pub const LOOP_W: i64 = 80 * Self::SUB;
    pub const LOOP_H: i64 = 90 * Self::SUB;
    pub const LOOP_PERIOD: i64 = 480;
    // Wave.
    pub const WAVE_MIN_X: i64 = 96 * Self::SUB;
    pub const WAVE_MAX_X: i64 = 264 * Self::SUB;
    pub const WAVE_PERIOD: i64 = 300;
    pub const WAVE_AMP: i64 = 70 * Self::SUB;
    pub const WAVE_TURNS: i64 = 3;
    pub const WAVE_SPACING: i64 = 22;
    pub const CHASE_DEN: i64 = 10;
    pub const CHASE_STEP: i64 = 1;
    pub const CHASE_LAPS: i64 = 3;

    /// C# defaults: p_mode = "figure8", p_count = 3.
    pub fn new(p_mode: &'static str, p_count: i64) -> Mover {
        let mut m = Mover {
            base: Base::new("mover"),
            mode: p_mode,
            count: p_count,
            loop_w: Self::LOOP_W,
            loop_h: Self::LOOP_H,
            loop_period: Self::LOOP_PERIOD,
            chase: false,
            phase: 0,
            xs: Vec::new(),
            ys: Vec::new(),
            facing: Vec::new(),
        };
        for _i in 0..m.count {
            m.xs.push(0);
            m.ys.push(0);
            m.facing.push(1);
        }
        m
    }

    pub fn _arrival_clear(&mut self, arrival: &[i64]) -> i64 {
        let keep = self.base.t;
        let mut out_ = FairLanes::ARRIVAL_PATH_TICKS;
        for k in 0..FairLanes::ARRIVAL_PATH_TICKS {
            self.base.t = k;
            self._place();
            for c in 0..self.count {
                if FairLanes::arrival_path_hits(arrival, k, self.xs[c as usize], self.ys[c as usize], Self::RADIUS) {
                    out_ = k;
                }
            }
            if out_ < FairLanes::ARRIVAL_PATH_TICKS {
                break;
            }
        }
        self.base.t = keep;
        out_
    }

    pub fn _meets_path(&mut self, path: &[i64]) -> bool {
        let keep = self.base.t;
        let reach = SimConfig::BIRD_RADIUS + Self::RADIUS + Self::START_MARGIN;
        let mut hit = false;
        let mut i: i64 = 0;
        while i < path.len() as i64 {
            self.base.t = i / 2 + 1;
            self._place();
            for c in 0..self.count {
                let dx = self.xs[c as usize] - path[i as usize];
                let dy = self.ys[c as usize] - path[i as usize + 1];
                if dx * dx + dy * dy < reach * reach {
                    hit = true;
                }
            }
            if hit {
                break;
            }
            i += 2;
        }
        self.base.t = keep;
        hit
    }

    pub fn period(&self) -> i64 {
        if self.mode == "figure8" {
            self.loop_period
        } else {
            Self::WAVE_PERIOD
        }
    }

    pub fn chase_tenths(&self, tick: i64) -> i64 {
        let mut start = 0;
        for k in 0..Self::CHASE_LAPS {
            let num = Self::CHASE_DEN + k * Self::CHASE_STEP;
            let lap = (self.loop_period * Self::CHASE_DEN + num - 1) / num;
            if tick < start + lap {
                return k * self.loop_period * Self::CHASE_DEN + (tick - start) * num;
            }
            start += lap;
        }
        let top = Self::CHASE_DEN + Self::CHASE_LAPS * Self::CHASE_STEP;
        Self::CHASE_LAPS * self.loop_period * Self::CHASE_DEN + (tick - start) * top
    }

    pub fn _place(&mut self) {
        let t = self.base.t;
        for i in 0..self.count {
            let nx;
            let ny;
            if self.mode == "figure8" {
                let mut k = (t + self.phase) * Self::CHASE_DEN;
                if self.chase && i == self.count - 1 {
                    k = self.chase_tenths(t) + self.phase * Self::CHASE_DEN;
                }
                let a = k * SimTrig::TURN / (self.loop_period * Self::CHASE_DEN) + i * SimTrig::TURN / self.count;
                nx = Self::CENTER_X + self.loop_w * SimTrig::sin_t(a) / SimTrig::ONE;
                ny = Self::CENTER_Y + self.loop_h * SimTrig::sin_t(2 * a) / SimTrig::ONE;
            } else {
                let k = t + self.phase - i * Self::WAVE_SPACING;
                nx = Self::WAVE_MIN_X + SimTrig::ping_pong(k, Self::WAVE_PERIOD, Self::WAVE_MAX_X - Self::WAVE_MIN_X);
                let a = k * SimTrig::TURN * Self::WAVE_TURNS / Self::WAVE_PERIOD;
                ny = Self::CENTER_Y + Self::WAVE_AMP * SimTrig::sin_t(a) / SimTrig::ONE;
            }
            let iu = i as usize;
            if nx != self.xs[iu] {
                self.facing[iu] = if nx > self.xs[iu] { 1 } else { -1 };
            }
            self.xs[iu] = nx;
            self.ys[iu] = ny;
        }
    }
}

impl Hazard for Mover {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        self.phase = rng.next_below(self.period());
        let path = FairLanes::start_path(sim);
        let arrival = if sim.state.started { FairLanes::arrival_path(sim) } else { Vec::new() };
        let first = self.phase;
        let tries = if sim.state.started { Self::ARRIVAL_TRIES } else { Self::PHASE_TRIES };
        let mut pick = self.phase;
        let mut settled = false;
        for k in 0..tries {
            self.phase = (first + k * self.period() / tries) % self.period();
            if sim.state.started {
                let clear = self._arrival_clear(&arrival);
                if clear >= FairLanes::ARRIVAL_PATH_TICKS {
                    pick = self.phase;
                    break;
                }
                if clear >= FairLanes::ARRIVAL_PATH_MIN && !settled {
                    pick = self.phase;
                    settled = true;
                }
            } else if !self._meets_path(&path) {
                break;
            }
        }
        if sim.state.started {
            self.phase = pick;
        }
        self._place();
    }

    fn step(&mut self, _sim: &mut GameSim) {
        self._place();
    }

    fn kills(&self, sim: &GameSim) -> bool {
        for i in 0..self.count {
            if sim.bird_touches_circle(self.xs[i as usize], self.ys[i as usize], Self::RADIUS) {
                return true;
            }
        }
        false
    }

    fn checksum(&self, h: i64) -> i64 {
        let mut out_ = mix_all(h, &[self.count, self.phase, G::b(self.mode == "figure8")]);
        if self.chase || self.loop_w != Self::LOOP_W || self.loop_h != Self::LOOP_H || self.loop_period != Self::LOOP_PERIOD {
            out_ = mix_all(out_, &[G::b(self.chase), self.loop_w, self.loop_h, self.loop_period]);
        }
        for i in 0..self.count {
            let iu = i as usize;
            out_ = mix_all(out_, &[self.xs[iu], self.ys[iu], self.facing[iu]]);
        }
        out_
    }
}
