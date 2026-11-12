//! Port of sim/hazards/saw_ring.gd (Sim/Hazards/SawRing.cs).
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct SawRing {
    pub base: Base,
    pub center_x: i64,
    pub ring_min: i64,
    pub ring_max: i64,
    pub saw_radius: i64,
    pub period: i64,
    pub fixed_count: i64,
    pub ry_num: i64,
    pub ry_den: i64,
    pub inner_count: i64,
    pub inner_min: i64,
    pub inner_max: i64,
    pub inner_saw: i64,

    pub center_y: i64,
    pub count: i64,
    pub phase: i64,
    pub dir: i64,
    pub radius: i64,
    pub inner_radius: i64,
    pub angle: i64,
    pub xs: Vec<i64>,
    pub ys: Vec<i64>,
}

impl SawRing {
    pub const CENTER_X: i64 = 180 * SimConfig::SUB;
    pub const CENTER_Y: i64 = 320 * SimConfig::SUB;
    pub const SAW_RADIUS: i64 = 18 * SimConfig::SUB;
    pub const RING_MIN: i64 = 50 * SimConfig::SUB;
    pub const RING_MAX: i64 = 92 * SimConfig::SUB;
    pub const HOLD: i64 = 60;
    /// Grow and shrink take 1.5 s each (playtest: 1 s came back too fast).
    pub const MOVE: i64 = 90;
    pub const CYCLE: i64 = 2 * (Self::HOLD + Self::MOVE);
    pub const PERIOD: i64 = 300;
    pub const ARRIVAL_CLEAR: i64 =
        Self::RING_MAX + Self::SAW_RADIUS + SimConfig::BIRD_RADIUS + 4 * SimConfig::SUB;
    pub const HOP: i64 = 64 * SimConfig::SUB;

    pub fn new() -> SawRing {
        SawRing {
            base: Base::new("saw_ring"),
            center_x: Self::CENTER_X,
            ring_min: Self::RING_MIN,
            ring_max: Self::RING_MAX,
            saw_radius: Self::SAW_RADIUS,
            period: Self::PERIOD,
            fixed_count: 0,
            ry_num: 1,
            ry_den: 1,
            inner_count: 0,
            inner_min: 0,
            inner_max: 0,
            inner_saw: 0,
            center_y: Self::CENTER_Y,
            count: 4,
            phase: 0,
            dir: 1,
            radius: Self::RING_MIN,
            inner_radius: 0,
            angle: 0,
            xs: Vec::new(),
            ys: Vec::new(),
        }
    }

    fn _resize(xs: &mut Vec<i64>, n: i64) {
        while xs.len() as i64 > n {
            xs.pop();
        }
        while (xs.len() as i64) < n {
            xs.push(0);
        }
    }

    pub fn reach_y(&self) -> i64 {
        let mut out_ = self.ring_max * self.ry_num / self.ry_den + self.saw_radius;
        if self.inner_count > 0 {
            out_ = G::maxi(out_, self.inner_max * self.ry_num / self.ry_den + self.inner_saw);
        }
        out_
    }

    pub fn arrival_clear(&self) -> i64 {
        self.reach_y() + SimConfig::BIRD_RADIUS + 4 * SimConfig::SUB
    }

    pub fn radius_at(tick: i64) -> i64 {
        let mut p = G::posmod(tick, Self::CYCLE);
        let span = Self::RING_MAX - Self::RING_MIN;
        if p < Self::HOLD {
            return Self::RING_MIN;
        }
        p -= Self::HOLD;
        if p < Self::MOVE {
            return Self::RING_MIN + span * p / Self::MOVE;
        }
        p -= Self::MOVE;
        if p < Self::HOLD {
            return Self::RING_MAX;
        }
        p -= Self::HOLD;
        Self::RING_MAX - span * p / Self::MOVE
    }

    pub fn scaled(tick: i64, lo: i64, hi: i64) -> i64 {
        lo + (hi - lo) * (Self::radius_at(tick) - Self::RING_MIN) / (Self::RING_MAX - Self::RING_MIN)
    }

    pub fn _place(&mut self) {
        let t = self.base.t;
        self.radius = Self::scaled(t, self.ring_min, self.ring_max);
        self.angle = G::posmod(self.phase + self.dir * (t * SimTrig::TURN / self.period), SimTrig::TURN);
        for i in 0..self.count {
            let a = self.angle + i * SimTrig::TURN / self.count;
            self.xs[i as usize] = self.center_x + self.radius * SimTrig::cos_t(a) / SimTrig::ONE;
            self.ys[i as usize] =
                self.center_y + self.radius * SimTrig::sin_t(a) * self.ry_num / self.ry_den / SimTrig::ONE;
        }
        if self.inner_count == 0 {
            return;
        }
        self.inner_radius = Self::scaled(t, self.inner_min, self.inner_max);
        let back = G::posmod(self.phase - self.dir * (t * SimTrig::TURN / self.period), SimTrig::TURN);
        for i in 0..self.inner_count {
            let a = back + i * SimTrig::TURN / self.inner_count;
            self.xs[(self.count + i) as usize] = self.center_x + self.inner_radius * SimTrig::cos_t(a) / SimTrig::ONE;
            self.ys[(self.count + i) as usize] =
                self.center_y + self.inner_radius * SimTrig::sin_t(a) * self.ry_num / self.ry_den / SimTrig::ONE;
        }
    }

    pub fn saw_r(&self, i: i64) -> i64 {
        if i < self.count { self.saw_radius } else { self.inner_saw }
    }
}

impl Hazard for SawRing {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        self.center_y = Self::CENTER_Y;
        let y = sim.state.anchor_y;
        let clear = self.arrival_clear();
        if sim.state.started && y - Self::CENTER_Y > -clear && y - Self::CENTER_Y < clear + Self::HOP {
            self.center_y = y + clear;
            if self.center_y + self.reach_y() > SimConfig::KILL_BOTTOM {
                self.center_y = y - clear - Self::HOP;
            }
        }
        self.count = 4 + rng.next_below(2);
        self.phase = rng.next_below(SimTrig::TURN);
        self.dir = if rng.next_below(2) == 0 { 1 } else { -1 };
        if self.fixed_count > 0 {
            self.count = self.fixed_count;
        }
        Self::_resize(&mut self.xs, self.count + self.inner_count);
        Self::_resize(&mut self.ys, self.count + self.inner_count);
        self._place();
    }

    fn step(&mut self, _sim: &mut GameSim) {
        self._place();
    }

    fn kills(&self, sim: &GameSim) -> bool {
        for i in 0..self.count + self.inner_count {
            if sim.bird_touches_circle(self.xs[i as usize], self.ys[i as usize], self.saw_r(i)) {
                return true;
            }
        }
        false
    }

    fn checksum(&self, h: i64) -> i64 {
        let mut out_ = mix_all(h, &[self.count, self.phase, self.dir, self.radius, self.angle, self.center_y]);
        for i in 0..self.count {
            out_ = mix_all(out_, &[self.xs[i as usize], self.ys[i as usize]]);
        }
        if self.inner_count > 0 || self.center_x != Self::CENTER_X || self.period != Self::PERIOD || self.ry_num != self.ry_den
        {
            out_ = mix_all(
                out_,
                &[self.center_x, self.period, self.ry_num, self.ry_den, self.inner_count, self.inner_radius],
            );
            for i in 0..self.inner_count {
                out_ = mix_all(out_, &[self.xs[(self.count + i) as usize], self.ys[(self.count + i) as usize]]);
            }
        }
        out_
    }
}
