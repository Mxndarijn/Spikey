//! Port of sim/hazards/rotor.gd (Sim/Hazards/Rotor.cs).
use crate::prelude::*;

pub struct Spin;
impl Spin {
    pub const STEADY: i64 = 0;
    pub const ROCK: i64 = 1;
    pub const BREATHE: i64 = 2;
}

#[derive(Clone, Debug)]
pub struct Rotor {
    pub base: Base,
    pub blades: i64,
    pub blade_max: i64,
    pub blade_min: i64,
    pub half_w: i64,
    pub hub_radius: i64,
    pub period: i64,
    pub spin: i64,
    pub hubs: i64,
    pub spread_x: i64,
    pub spread_y: i64,
    pub lean: i64,

    pub center_x: i64,
    pub center_y: i64,
    pub phase: i64,
    pub dir: i64,
    pub angle: i64,
    pub blade_length: i64,
}

impl Rotor {
    pub const CENTER_X: i64 = 180 * SimConfig::SUB;
    pub const CENTER_Y: i64 = 320 * SimConfig::SUB;
    pub const SAMPLES: i64 = 5;
    pub const HOP: i64 = 64 * SimConfig::SUB;
    pub const CLEAR_MARGIN: i64 = SimConfig::BIRD_RADIUS + 4 * SimConfig::SUB;
    pub const ROCK_EASE: i64 = 24;
    pub const ROCK_RUN: i64 = 150;
    pub const ROCK_PAUSE: i64 = 18;
    pub const ROCK_HALF: i64 = 2 * Self::ROCK_EASE + Self::ROCK_RUN + Self::ROCK_PAUSE;
    pub const BREATHE_HOLD: i64 = 60;
    pub const BREATHE_MOVE: i64 = 60;
    pub const BREATHE_CYCLE: i64 = 2 * (Self::BREATHE_HOLD + Self::BREATHE_MOVE);

    /// C# defaults: p_length = 80 * SUB, p_half_w = 8 * SUB, p_hub = 16 * SUB.
    pub fn new(p_length: i64, p_half_w: i64, p_hub: i64) -> Rotor {
        Rotor {
            base: Base::new("rotor"),
            blades: 4,
            blade_max: p_length,
            blade_min: p_length,
            half_w: p_half_w,
            hub_radius: p_hub,
            period: 360,
            spin: Spin::STEADY,
            hubs: 1,
            spread_x: 0,
            spread_y: 0,
            lean: 0,
            center_x: Self::CENTER_X,
            center_y: Self::CENTER_Y,
            phase: 0,
            dir: 1,
            angle: 0,
            blade_length: p_length,
        }
    }

    pub fn reach(&self) -> i64 {
        self.blade_max + self.half_w
    }

    pub fn hub_clear(&self) -> i64 {
        self.reach() + Self::CLEAR_MARGIN
    }

    pub fn _fits(&self, cy: i64) -> bool {
        let top = cy - (if self.hubs == 2 { self.spread_y } else { 0 }) - self.reach();
        let bottom = cy + (if self.hubs == 2 { self.spread_y } else { 0 }) + self.reach();
        top >= SimConfig::KILL_TOP && bottom <= SimConfig::KILL_BOTTOM
    }

    pub fn _place(&mut self) {
        self.angle = G::posmod(self.phase + self.dir * self._turned(self.base.t), SimTrig::TURN);
        self.blade_length = self._length_at(self.base.t);
    }

    pub fn _turned(&self, steps: i64) -> i64 {
        if self.spin != Spin::ROCK {
            return steps * SimTrig::TURN / self.period;
        }
        let e = Self::ROCK_EASE;
        let full = 2 * e * e + 2 * e * Self::ROCK_RUN;
        let m = steps % Self::ROCK_HALF;
        let mut x = full;
        if m < e {
            x = m * m;
        } else if m < e + Self::ROCK_RUN {
            x = e * e + 2 * e * (m - e);
        } else if m < 2 * e + Self::ROCK_RUN {
            let u = m - e - Self::ROCK_RUN;
            x = e * e + 2 * e * Self::ROCK_RUN + 2 * e * u - u * u;
        }
        if (steps / Self::ROCK_HALF) % 2 == 1 {
            x = full - x;
        }
        x * SimTrig::TURN / (2 * e * self.period)
    }

    pub fn _length_at(&self, steps: i64) -> i64 {
        if self.spin != Spin::BREATHE {
            return self.blade_max;
        }
        let mut m = steps % Self::BREATHE_CYCLE;
        let grow = self.blade_max - self.blade_min;
        if m < Self::BREATHE_HOLD {
            return self.blade_min;
        }
        m -= Self::BREATHE_HOLD;
        if m < Self::BREATHE_MOVE {
            return self.blade_min + grow * m / Self::BREATHE_MOVE;
        }
        m -= Self::BREATHE_MOVE;
        if m < Self::BREATHE_HOLD {
            return self.blade_max;
        }
        m -= Self::BREATHE_HOLD;
        self.blade_max - grow * m / Self::BREATHE_MOVE
    }

    pub fn hub_x(&self, h: i64) -> i64 {
        self.center_x + (2 * h - (self.hubs - 1)) * self.spread_x
    }

    pub fn hub_y(&self, h: i64) -> i64 {
        self.center_y + (2 * h - (self.hubs - 1)) * self.spread_y
    }

    pub fn blade_angle(&self, h: i64, i: i64) -> i64 {
        let a = if h % 2 == 0 { self.angle } else { SimTrig::TURN - self.angle };
        a + i * SimTrig::TURN / self.blades
    }
}

impl Hazard for Rotor {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        self.center_x = Self::CENTER_X;
        self.center_y = Self::CENTER_Y;
        let y = sim.state.anchor_y;
        let top = if self.hubs == 2 { -self.spread_y } else { 0 };
        let bottom = if self.hubs == 2 { self.spread_y } else { 0 };
        let clear = self.hub_clear();
        let dy = y - Self::CENTER_Y;
        if sim.state.started && dy > top - clear && dy < bottom + clear + Self::HOP {
            let below = y + clear - top;
            let above = y - clear - Self::HOP - bottom;
            let first = if dy < 0 { below } else { above };
            let second = if dy < 0 { above } else { below };
            self.center_y = if self._fits(first) { first } else { second };
            if !self._fits(self.center_y) {
                self.center_y = first;
            }
        }
        self.phase = rng.next_below(SimTrig::TURN);
        self.dir = if rng.next_below(2) == 0 { 1 } else { -1 };
        if self.lean != 0 {
            let mut right = rng.next_below(2) == 0;
            if sim.state.started {
                right = sim.state.vx > 0;
            }
            self.center_x = Self::CENTER_X + if right { self.lean } else { -self.lean };
        }
        self._place();
    }

    fn step(&mut self, _sim: &mut GameSim) {
        self._place();
    }

    fn band_top(&self) -> i64 {
        let mut out_ = self.hub_y(0) - self.reach();
        for h in 0..self.hubs {
            out_ = G::mini(out_, self.hub_y(h) - self.reach());
        }
        out_
    }

    fn band_bottom(&self) -> i64 {
        let mut out_ = self.hub_y(0) + self.reach();
        for h in 0..self.hubs {
            out_ = G::maxi(out_, self.hub_y(h) + self.reach());
        }
        out_
    }

    fn kills(&self, sim: &GameSim) -> bool {
        for h in 0..self.hubs {
            let cx = self.hub_x(h);
            let cy = self.hub_y(h);
            if sim.bird_touches_circle(cx, cy, self.hub_radius) {
                return true;
            }
            for i in 0..self.blades {
                let a = self.blade_angle(h, i);
                let c = SimTrig::cos_t(a);
                let s = SimTrig::sin_t(a);
                for k in 0..Self::SAMPLES {
                    let d = self.blade_length * (k + 1) / Self::SAMPLES;
                    let px = cx + d * c / SimTrig::ONE;
                    let py = cy + d * s / SimTrig::ONE;
                    if sim.bird_touches_circle(px, py, self.half_w) {
                        return true;
                    }
                }
            }
        }
        false
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(h, &[self.phase, self.dir, self.angle, self.center_x, self.center_y, self.blade_length, self.spread_y])
    }
}

impl Rotor {
    pub const GENERATE_SPINS: i64 = 8;
    pub const MIN_SPREAD_Y: i64 = 24 * SimConfig::SUB;

    pub fn place_for_arrival(&mut self, sim: &GameSim, p: &VariantParams) {
        if !p.arriving {
            return;
        }
        let sy = if self.hubs == 2 { self.spread_y } else { 0 };
        let above = p.hold_top(sim) - sy - self.reach();
        let below = p.hold_bottom(sim) + sy + self.reach();
        let first = if G::absi(above - Self::CENTER_Y) <= G::absi(below - Self::CENTER_Y) { above } else { below };
        let second = if first == above { below } else { above };
        if self._fits(first) {
            self.center_y = first;
        } else if self._fits(second) {
            self.center_y = second;
        } else if self.hubs == 2 {
            let room_above = p.hold_top(sim) - SimConfig::KILL_TOP;
            let room_below = SimConfig::KILL_BOTTOM - p.hold_bottom(sim);
            let fit = (G::maxi(room_above, room_below) - 2 * self.reach()) / 2;
            if fit >= Self::MIN_SPREAD_Y {
                self.spread_y = G::mini(self.spread_y, fit);
                if room_above >= room_below {
                    self.center_y = p.hold_top(sim) - self.spread_y - self.reach();
                } else {
                    self.center_y = p.hold_bottom(sim) + self.spread_y + self.reach();
                }
            }
        }
        self._place();
    }

    pub fn fallback_spots(&self, sim: &GameSim, p: &VariantParams) -> [i64; 5] {
        let sy = if self.hubs == 2 { self.spread_y } else { 0 };
        let lo = SimConfig::KILL_TOP + sy + self.reach();
        let hi = SimConfig::KILL_BOTTOM - sy - self.reach();
        [
            G::clampi(p.hold_top(sim) - sy - self.reach(), lo, hi),
            G::clampi(p.hold_bottom(sim) + sy + self.reach(), lo, hi),
            Self::CENTER_Y,
            lo,
            hi,
        ]
    }

    pub fn fallback_angle(k: i64) -> i64 {
        k * SimTrig::TURN / Self::GENERATE_SPINS
    }
}
