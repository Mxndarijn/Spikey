//! Port of sim/hazards/boss_saw.gd (Sim/Hazards/BossSaw.cs). A Boss subclass:
//! the parent is the field `boss`.
use crate::hazards::boss::BossKind;
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct BossSaw {
    pub boss: Boss,
    pub king_y: i64,
    pub from_y: i64,
    pub to_y: i64,
    pub ring: i64,
    pub angle: i64,
    pub blades: i64,
    pub blade_x: Vec<i64>,
    pub blade_y: Vec<i64>,
    pub telling: bool,
    pub _k: i64,
}

impl BossSaw {
    pub const KING_X: i64 = 180 * SimConfig::SUB;
    pub const KING_R: i64 = 46 * SimConfig::SUB;
    pub const BLADE_R: i64 = 12 * SimConfig::SUB;
    pub const HEIGHTS: [i64; 3] = [180 * SimConfig::SUB, 320 * SimConfig::SUB, 460 * SimConfig::SUB];
    pub const RING_YS: [i64; 2] = [260 * SimConfig::SUB, 380 * SimConfig::SUB];
    pub const CYCLE: i64 = 240;
    pub const CYCLE_FAST: i64 = 180;
    pub const TELL: i64 = 60;
    pub const JUMP: i64 = 30;
    pub const RING_OUT: i64 = Self::TELL + Self::JUMP;
    pub const RING_HOLD: i64 = 120;
    pub const RING_IN: i64 = 180;
    pub const RING_MAX: i64 = 115 * SimConfig::SUB;
    pub const RING_MAX_TIER3: i64 = 130 * SimConfig::SUB;
    pub const RING_HOP: i64 = 72 * SimConfig::SUB;
    pub const RING_SHOW: i64 = 50 * SimConfig::SUB;
    pub const RING_SPEED: i64 = 4 * SimConfig::SUB;
    pub const SLIDE: i64 = 3 * SimConfig::SUB;
    pub const SPIN: i64 = 6;

    pub fn new() -> BossSaw {
        BossSaw {
            boss: Boss::new("boss_saw"),
            king_y: 0,
            from_y: 0,
            to_y: 0,
            ring: 0,
            angle: 0,
            blades: 6,
            blade_x: Vec::new(),
            blade_y: Vec::new(),
            telling: false,
            _k: -1,
        }
    }

    pub fn boss(&self) -> &Boss {
        &self.boss
    }
    pub fn boss_mut(&mut self) -> &mut Boss {
        &mut self.boss
    }

    fn _resize(xs: &mut Vec<i64>, n: i64) {
        while xs.len() as i64 > n {
            xs.pop();
        }
        while (xs.len() as i64) < n {
            xs.push(0);
        }
    }

    pub fn cycle(&self) -> i64 {
        if self.boss.phase == 3 && self.boss.tier >= 2 {
            Self::CYCLE_FAST
        } else {
            Self::CYCLE
        }
    }

    pub fn ring_max(&self) -> i64 {
        if self.boss.tier >= 3 {
            Self::RING_MAX_TIER3
        } else {
            Self::RING_MAX
        }
    }

    pub fn nearest(y: i64) -> i64 {
        let mut best = 0i64;
        for i in 0..Self::HEIGHTS.len() as i64 {
            if G::absi(Self::HEIGHTS[i as usize] - y) < G::absi(Self::HEIGHTS[best as usize] - y) {
                best = i;
            }
        }
        best
    }

    pub fn hop_to(&self, from: i64, k: i64) -> i64 {
        if Self::nearest(from) != 1 {
            return Self::HEIGHTS[1];
        }
        Self::HEIGHTS[if self.boss.draw(k, self.boss.phase) % 2 == 0 { 0 } else { 2 }]
    }

    pub fn _jump(&self, lt: i64) -> i64 {
        if lt < Self::TELL {
            return self.from_y;
        }
        if lt < Self::TELL + Self::JUMP {
            return self.from_y + (self.to_y - self.from_y) * (lt - Self::TELL) / Self::JUMP;
        }
        self.to_y
    }

    pub fn _toward(from: i64, to: i64, speed: i64) -> i64 {
        if to > from {
            return G::mini(from + speed, to);
        }
        G::maxi(from - speed, to)
    }

    pub fn _place_blades(&mut self) {
        for i in 0..self.blades {
            let a = self.angle + i * SimTrig::TURN / self.blades;
            self.blade_x[i as usize] = Self::KING_X + self.ring * SimTrig::cos_t(a) / SimTrig::ONE;
            self.blade_y[i as usize] = self.king_y + self.ring * SimTrig::sin_t(a) / SimTrig::ONE;
        }
    }
}

impl BossKind for BossSaw {
    fn boss(&self) -> &Boss {
        &self.boss
    }
    fn boss_mut(&mut self) -> &mut Boss {
        &mut self.boss
    }

    fn boss_setup(&mut self, sim: &mut GameSim) {
        self.blades = if self.boss.tier >= 3 { 8 } else { 6 };
        Self::_resize(&mut self.blade_x, self.blades);
        Self::_resize(&mut self.blade_y, self.blades);
        let mut far = 0;
        if G::absi(Self::HEIGHTS[2] - sim.state.anchor_y) > G::absi(Self::HEIGHTS[0] - sim.state.anchor_y) {
            far = 2;
        } else if G::absi(Self::HEIGHTS[2] - sim.state.anchor_y) == G::absi(Self::HEIGHTS[0] - sim.state.anchor_y) {
            far = 2 * (self.boss.seed % 2);
        }
        self.king_y = Self::HEIGHTS[far as usize];
        self.from_y = self.king_y;
        self.to_y = self.king_y;
        self._place_blades();
    }

    fn on_phase(&mut self) {
        self._k = -1;
    }

    // C# initialises ring_to = ring and every branch overwrites it: kept literal.
    #[allow(unused_assignments)]
    fn boss_step(&mut self, _sim: &mut GameSim) {
        self.angle = G::posmod(self.angle + Self::SPIN, SimTrig::TURN);
        self.telling = false;
        let c = self.boss.clock();
        let phase = self.boss.phase;
        let mut ring_to = self.ring;
        if c < 0 {
            ring_to = if phase == 3 { Self::RING_HOP } else { 0 };
            if phase != 2 {
                self.king_y = Self::_toward(self.king_y, Self::HEIGHTS[Self::nearest(self.king_y) as usize], Self::SLIDE);
            }
        } else if phase == 2 {
            let k = c / Self::CYCLE;
            let lt = c % Self::CYCLE;
            if self._k != k {
                self._k = k;
                self.from_y = self.king_y;
                self.to_y = Self::RING_YS[(self.boss.draw(k, 2) % 2) as usize];
            }
            self.telling = lt < Self::RING_OUT;
            self.king_y = self._jump(lt);
            ring_to = if lt >= Self::RING_OUT && lt < Self::RING_IN { self.ring_max() } else { 0 };
        } else {
            let k = c / self.cycle();
            let lt = c % self.cycle();
            if self._k != k {
                self._k = k;
                self.from_y = self.king_y;
                self.to_y = self.hop_to(self.from_y, k);
            }
            self.telling = lt < Self::TELL;
            self.king_y = self._jump(lt);
            ring_to = if phase == 3 { Self::RING_HOP } else { 0 };
        }
        self.ring = Self::_toward(self.ring, ring_to, Self::RING_SPEED);
        self._place_blades();
    }

    fn boss_down_step(&mut self, _sim: &mut GameSim) {
        self.telling = false;
        self.ring = Self::_toward(self.ring, 0, Self::RING_SPEED);
        self._place_blades();
    }

    fn boss_kills(&self, sim: &GameSim) -> bool {
        if sim.bird_touches_circle(Self::KING_X, self.king_y, Self::KING_R) {
            return true;
        }
        if self.ring >= Self::RING_SHOW {
            for i in 0..self.blades {
                if sim.bird_touches_circle(self.blade_x[i as usize], self.blade_y[i as usize], Self::BLADE_R) {
                    return true;
                }
            }
        }
        false
    }

    fn safe_y(&self, y: i64, steps: i64) -> bool {
        if self.boss.phase != 2 {
            return true;
        }
        let c = self.boss.clock_in(steps);
        if c < 0 {
            return true;
        }
        let lt = c % Self::CYCLE;
        if lt < Self::RING_OUT || lt >= Self::RING_IN {
            return true;
        }
        let k = c / Self::CYCLE;
        let at = if k == self._k { self.to_y } else { Self::RING_YS[(self.boss.draw(k, 2) % 2) as usize] };
        G::absi(y - at) >= self.ring_max() + Self::BLADE_R + SimConfig::BIRD_RADIUS + Boss::MARGIN
    }
}

impl Hazard for BossSaw {
    impl_base!(boss.base);

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        Boss::setup(self, sim, rng);
    }

    fn step(&mut self, sim: &mut GameSim) {
        Boss::step(self, sim);
    }

    fn kills(&self, sim: &GameSim) -> bool {
        Boss::kills(self, sim)
    }

    fn adjust_wall(&mut self, sim: &mut GameSim, side: i64, mask: i64) -> i64 {
        Boss::adjust_wall(self, sim, side, mask)
    }

    fn checksum(&self, h: i64) -> i64 {
        let mut out_ = mix_all(
            self.boss.checksum(h),
            &[
                self.king_y,
                self.from_y,
                self.to_y,
                self.ring,
                self.angle,
                self.blades,
                G::b(self.telling),
                self._k,
            ],
        );
        for i in 0..self.blades {
            out_ = mix_all(out_, &[self.blade_x[i as usize], self.blade_y[i as usize]]);
        }
        out_
    }
}
