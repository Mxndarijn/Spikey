//! Port of sim/hazards/boss_watcher.gd (Sim/Hazards/BossWatcher.cs). A Boss
//! subclass: the parent is the field `boss`.
use crate::hazards::boss::BossKind;
use crate::prelude::*;

/// `BossWatcher.Beam`.
pub struct Beam;
impl Beam {
    pub const OFF: i64 = 0;
    pub const WARN: i64 = 1;
    pub const ON: i64 = 2;
}

/// `BossWatcher.Dart`.
pub struct Dart;
impl Dart {
    pub const NONE: i64 = 0;
    pub const MARK: i64 = 1;
    pub const FLY: i64 = 2;
}

#[derive(Clone, Debug)]
pub struct BossWatcher {
    pub boss: Boss,
    pub lit: i64,
    pub beam: i64,
    pub beam_t: i64,
    pub dart: i64,
    pub dart_lane: i64,
    pub dart_side: i64,
    pub dart_x: i64,
    pub dart_t: i64,
    pub _lit_k: i64,
}

impl BossWatcher {
    pub const ROWS: [i64; 7] = [
        200 * SimConfig::SUB,
        260 * SimConfig::SUB,
        320 * SimConfig::SUB,
        380 * SimConfig::SUB,
        440 * SimConfig::SUB,
        500 * SimConfig::SUB,
        560 * SimConfig::SUB,
    ];
    pub const CYCLE: i64 = 240;
    pub const TELL: i64 = 60;
    pub const BEAM_ON: i64 = 70;
    pub const HALF_H: i64 = 6 * SimConfig::SUB;
    pub const MAX_RUN: i64 = 3;
    pub const GAZE: i64 = 120;
    pub const GAZE_FAST: i64 = 100;
    pub const GAZE_AT: i64 = 130;
    pub const DART_SPEED: i64 = 10 * SimConfig::SUB;
    pub const DART_LEN: i64 = 34 * SimConfig::SUB;
    pub const DART_HALF: i64 = 10 * SimConfig::SUB;
    pub const LANE_MIN: i64 = 110 * SimConfig::SUB;
    pub const LANE_MAX: i64 = 530 * SimConfig::SUB;

    pub fn new() -> BossWatcher {
        BossWatcher {
            boss: Boss::new("boss_watcher"),
            lit: 0,
            beam: Beam::OFF,
            beam_t: 0,
            dart: Dart::NONE,
            dart_lane: 0,
            dart_side: 0,
            dart_x: 0,
            dart_t: 0,
            _lit_k: -1,
        }
    }

    pub fn boss(&self) -> &Boss {
        &self.boss
    }
    pub fn boss_mut(&mut self) -> &mut Boss {
        &mut self.boss
    }

    pub fn lit_rows(&self, p: i64, k: i64) -> i64 {
        let count = (if p == 1 { 3 } else { 2 }) + (if self.boss.tier >= 2 { 1 } else { 0 });
        let mut rng = SimRng::new(self.boss.draw(k, p));
        for _try in 0..20 {
            let mut mask = 0i64;
            let mut n = 0;
            while n < count {
                let r = rng.next_below(Self::ROWS.len() as i64);
                if ((mask >> r) & 1) == 0 {
                    mask |= 1i64 << r;
                    n += 1;
                }
            }
            if Self::_longest_run(mask) <= Self::MAX_RUN {
                return mask;
            }
        }
        0b1010101 & ((1i64 << Self::ROWS.len() as i64) - 1)
    }

    pub fn _longest_run(mask: i64) -> i64 {
        let mut best = 0;
        let mut run = 0;
        for i in 0..Self::ROWS.len() as i64 {
            run = if ((mask >> i) & 1) == 1 { run + 1 } else { 0 };
            best = G::maxi(best, run);
        }
        best
    }

    pub fn gaze_every(&self) -> i64 {
        if self.boss.tier >= 3 {
            Self::GAZE_FAST
        } else {
            Self::GAZE
        }
    }

    pub fn _gaze(&mut self, sim: &GameSim, g: i64) {
        if g == 0 {
            self.dart = Dart::MARK;
            self.dart_lane = G::clampi(sim.state.y, Self::LANE_MIN, Self::LANE_MAX);
            self.dart_side = if sim.state.vx > 0 { 1 } else { 0 };
        }
        if self.dart == Dart::MARK {
            self.dart_t = g;
            if g >= Self::TELL {
                self.dart = Dart::FLY;
                self.dart_x = if self.dart_side == 1 { sim.room.wall_right() } else { sim.room.wall_left() };
            }
        } else if self.dart == Dart::FLY {
            self.dart_x += if self.dart_side == 1 { -Self::DART_SPEED } else { Self::DART_SPEED };
            if self.dart_x < -Self::DART_LEN || self.dart_x > SimConfig::WORLD_W + Self::DART_LEN {
                self.dart = Dart::NONE;
            }
        }
    }
}

impl BossKind for BossWatcher {
    fn boss(&self) -> &Boss {
        &self.boss
    }
    fn boss_mut(&mut self) -> &mut Boss {
        &mut self.boss
    }

    fn boss_step(&mut self, sim: &mut GameSim) {
        self.beam = Beam::OFF;
        let c = self.boss.clock();
        if c < 0 {
            self.dart = Dart::NONE;
            return;
        }
        let phase = self.boss.phase;
        if phase != 2 {
            let k = c / Self::CYCLE;
            self.beam_t = c % Self::CYCLE;
            if self._lit_k != k {
                self._lit_k = k;
                self.lit = self.lit_rows(phase, k);
            }
            if self.beam_t < Self::TELL {
                self.beam = Beam::WARN;
            } else if self.beam_t < Self::TELL + Self::BEAM_ON {
                self.beam = Beam::ON;
            }
        }
        let g = if phase == 2 { c % self.gaze_every() } else { (c % Self::CYCLE) - Self::GAZE_AT };
        if phase != 1 {
            self._gaze(sim, g);
        }
    }

    fn boss_down_step(&mut self, _sim: &mut GameSim) {
        self.beam = Beam::OFF;
        self.dart = Dart::NONE;
    }

    fn boss_kills(&self, sim: &GameSim) -> bool {
        if self.beam == Beam::ON {
            for i in 0..Self::ROWS.len() as i64 {
                if ((self.lit >> i) & 1) == 1 {
                    let y = Self::ROWS[i as usize];
                    if sim.bird_touches_rect(
                        sim.room.wall_left(),
                        y - Self::HALF_H,
                        sim.room.wall_right(),
                        y + Self::HALF_H,
                    ) {
                        return true;
                    }
                }
            }
        }
        if self.dart == Dart::FLY {
            let back = if self.dart_side == 1 { self.dart_x + Self::DART_LEN } else { self.dart_x - Self::DART_LEN };
            if sim.bird_touches_rect(self.dart_x, self.dart_lane - Self::DART_HALF, back, self.dart_lane + Self::DART_HALF)
            {
                return true;
            }
        }
        false
    }

    fn safe_y(&self, y: i64, steps: i64) -> bool {
        let phase = self.boss.phase;
        if phase == 2 {
            return true;
        }
        let c = self.boss.clock_in(steps);
        if c < 0 {
            return true;
        }
        let lt = c % Self::CYCLE;
        if lt < Self::TELL || lt >= Self::TELL + Self::BEAM_ON {
            return true;
        }
        let mask = self.lit_rows(phase, c / Self::CYCLE);
        for i in 0..Self::ROWS.len() as i64 {
            if ((mask >> i) & 1) == 1
                && G::absi(y - Self::ROWS[i as usize]) < Self::HALF_H + SimConfig::BIRD_RADIUS + Boss::MARGIN
            {
                return false;
            }
        }
        true
    }
}

impl Hazard for BossWatcher {
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
        mix_all(
            self.boss.checksum(h),
            &[
                self.lit,
                self.beam,
                self.beam_t,
                self.dart,
                self.dart_lane,
                self.dart_side,
                self.dart_x,
                self.dart_t,
                self._lit_k,
            ],
        )
    }
}
