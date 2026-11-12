//! Port of sim/hazards/boss_crusher.gd (Sim/Hazards/BossCrusher.cs). A Boss
//! subclass: the parent is the field `boss`. C# `crate` (a Rust keyword) is
//! the field `crate_`.
use crate::hazards::boss::BossKind;
use crate::prelude::*;

/// `BossCrusher.Crate`.
pub struct Crate;
impl Crate {
    pub const NONE: i64 = 0;
    pub const MARK: i64 = 1;
    pub const FALL: i64 = 2;
}

#[derive(Clone, Debug)]
pub struct BossCrusher {
    pub boss: Boss,
    pub press_y: i64,
    pub plate_y: i64,
    pub slam_y: i64,
    pub lane_from: i64,
    pub lane_to: i64,
    pub telling: bool,
    pub crate_x: [i64; 2],
    pub crate_y: [i64; 2],
    pub crate_: [i64; 2],
    pub jaw: bool,
    pub _k: i64,
}

impl BossCrusher {
    pub const CYCLE: i64 = 240;
    pub const TELL: i64 = 60;
    pub const TEETH: i64 = 24 * SimConfig::SUB;
    pub const BITE: i64 = 20 * SimConfig::SUB;
    pub const PRESS_REST: i64 = SimConfig::KILL_TOP - Self::TEETH;
    pub const PLATE_REST: i64 = SimConfig::KILL_BOTTOM + Self::TEETH;
    pub const SLAM_DOWN: i64 = 12 * SimConfig::SUB;
    pub const LIFT: i64 = 6 * SimConfig::SUB;
    pub const SLAM_AT: i64 = Self::TELL;
    pub const LIFT_AT: i64 = 170;
    pub const SLAMS: [i64; 2] = [250 * SimConfig::SUB, 320 * SimConfig::SUB];
    pub const SLAM_TIER: i64 = 30 * SimConfig::SUB;
    pub const LANE_HALF: [i64; 3] = [116 * SimConfig::SUB, 100 * SimConfig::SUB, 90 * SimConfig::SUB];
    pub const LANE_FIRST: i64 = 340 * SimConfig::SUB;
    pub const LANE_STEP_MIN: i64 = 40 * SimConfig::SUB;
    pub const LANE_STEP_MAX: [i64; 3] = [100 * SimConfig::SUB, 80 * SimConfig::SUB, 80 * SimConfig::SUB];
    pub const JAW_SPEED: i64 = 3 * SimConfig::SUB;
    pub const CRATE_AT: i64 = 110;
    pub const CRATE_FALL: i64 = Self::TELL + Self::CRATE_AT;
    pub const CRATE_HALF: i64 = 16 * SimConfig::SUB;
    pub const CRATE_SPEED: i64 = 6 * SimConfig::SUB;
    pub const COLUMNS: i64 = 7;
    pub const COLUMN_X0: i64 = 60 * SimConfig::SUB;
    pub const COLUMN_STEP: i64 = 40 * SimConfig::SUB;
    pub const CRATE_CLEAR: i64 = 60 * SimConfig::SUB;

    pub fn new() -> BossCrusher {
        BossCrusher {
            boss: Boss::new("boss_crusher"),
            press_y: Self::PRESS_REST,
            plate_y: Self::PLATE_REST,
            slam_y: 0,
            lane_from: Self::LANE_FIRST,
            lane_to: Self::LANE_FIRST,
            telling: false,
            crate_x: [0, 0],
            crate_y: [0, 0],
            crate_: [Crate::NONE, Crate::NONE],
            jaw: false,
            _k: -1,
        }
    }

    pub fn boss(&self) -> &Boss {
        &self.boss
    }
    pub fn boss_mut(&mut self) -> &mut Boss {
        &mut self.boss
    }

    pub fn lane_half(&self) -> i64 {
        Self::LANE_HALF[(self.boss.tier - 1) as usize]
    }

    pub fn slam_of(&self, k: i64) -> i64 {
        Self::SLAMS[(self.boss.draw(k, 1) % Self::SLAMS.len() as i64) as usize]
            + (if self.boss.tier >= 2 { Self::SLAM_TIER } else { 0 })
            - Self::TEETH
    }

    pub fn _next_lane(&self, k: i64) -> i64 {
        let lo = Self::PRESS_REST + Self::TEETH + self.lane_half();
        let hi = Self::PLATE_REST - Self::TEETH - self.lane_half();
        let span = Self::LANE_STEP_MAX[(self.boss.tier - 1) as usize] - Self::LANE_STEP_MIN;
        let key = k + self.boss.phase * 1000;
        let mut d = Self::LANE_STEP_MIN + self.boss.draw(key, 2) % (span / SimConfig::SUB + 1) * SimConfig::SUB;
        if self.boss.draw(key, 3) % 2 == 0 {
            d = -d;
        }
        let mut to = self.lane_from + d;
        if to < lo || to > hi {
            to = self.lane_from - d;
        }
        G::clampi(to, lo, hi)
    }

    pub fn _toward(from: i64, to: i64, down: i64, up: i64) -> i64 {
        if to > from {
            return G::mini(from + down, to);
        }
        G::maxi(from - up, to)
    }

    pub fn _crates(&mut self, sim: &GameSim, lt: i64) {
        if lt == Self::CRATE_AT {
            let count = if self.boss.tier >= 2 { 2 } else { 1 };
            let mut used = -1;
            for i in 0..count {
                let col = self._pick_column(sim, used, i);
                used = col;
                self.crate_[i as usize] = Crate::MARK;
                self.crate_x[i as usize] = Self::COLUMN_X0 + col * Self::COLUMN_STEP;
            }
            for i in count..2 {
                self.crate_[i as usize] = Crate::NONE;
            }
        }
        for i in 0..2usize {
            if self.crate_[i] == Crate::NONE {
                continue;
            }
            if self.crate_[i] == Crate::MARK {
                self.crate_y[i] = self.press_y + Self::TEETH + Self::CRATE_HALF;
                if lt >= Self::CRATE_FALL {
                    self.crate_[i] = Crate::FALL;
                }
            } else {
                self.crate_y[i] += Self::CRATE_SPEED;
                if self.crate_y[i] + Self::CRATE_HALF >= self.plate_y - Self::TEETH {
                    self.crate_[i] = Crate::NONE;
                }
            }
        }
    }

    pub fn _pick_column(&self, sim: &GameSim, used: i64, i: i64) -> i64 {
        let fall = (2 * self.lane_half()) / Self::CRATE_SPEED + 2;
        let mut ok: Vec<i64> = Vec::new();
        let mut far = 0;
        let mut far_d = -1;
        for col in 0..Self::COLUMNS {
            if col == used {
                continue;
            }
            let x = Self::COLUMN_X0 + col * Self::COLUMN_STEP;
            let mut near = SimConfig::WORLD_W;
            let mut s = Self::CRATE_FALL - Self::CRATE_AT;
            while s < Self::CRATE_FALL - Self::CRATE_AT + fall + 1 {
                near = G::mini(near, G::absi(Boss::x_after(sim, s) - x));
                s += 2;
            }
            if near >= Self::CRATE_CLEAR {
                ok.push(col);
            }
            if near > far_d {
                far_d = near;
                far = col;
            }
        }
        if ok.is_empty() {
            return far;
        }
        ok[(self.boss.draw(self._k + self.boss.phase * 1000, 10 + i) % ok.len() as i64) as usize]
    }
}

impl BossKind for BossCrusher {
    fn boss(&self) -> &Boss {
        &self.boss
    }
    fn boss_mut(&mut self) -> &mut Boss {
        &mut self.boss
    }

    fn boss_step(&mut self, sim: &mut GameSim) {
        self.telling = false;
        let c = self.boss.clock();
        let phase = self.boss.phase;
        let mut press_to = if self.jaw { self.press_y } else { Self::PRESS_REST };
        let mut plate_to = self.plate_y;
        if c >= 0 && phase == 1 {
            let k = c / Self::CYCLE;
            let lt = c % Self::CYCLE;
            self.slam_y = self.slam_of(k);
            self.telling = lt < Self::SLAM_AT;
            press_to = if lt >= Self::SLAM_AT && lt < Self::LIFT_AT { self.slam_y } else { Self::PRESS_REST };
        } else if c >= 0 {
            let k = c / Self::CYCLE;
            let lt = c % Self::CYCLE;
            if self._k != k {
                self._k = k;
                self.lane_from = if self.jaw { self.lane_to } else { -1 };
                self.lane_to = if self.jaw { self._next_lane(k) } else { Self::LANE_FIRST };
                self.jaw = true;
            }
            self.telling = lt < Self::TELL;
            let lane = if lt >= Self::TELL { self.lane_to } else { self.lane_from };
            if lane >= 0 {
                press_to = lane - self.lane_half() - Self::TEETH;
                plate_to = lane + self.lane_half() + Self::TEETH;
            }
            if phase == 3 {
                self._crates(sim, lt);
            }
        }
        self.press_y = Self::_toward(
            self.press_y,
            press_to,
            if phase == 1 { Self::SLAM_DOWN } else { Self::JAW_SPEED },
            Self::LIFT,
        );
        self.plate_y = Self::_toward(self.plate_y, plate_to, Self::JAW_SPEED, Self::JAW_SPEED);
    }

    fn on_phase(&mut self) {
        self._k = -1;
        self.crate_ = [Crate::NONE, Crate::NONE];
    }

    fn boss_down_step(&mut self, _sim: &mut GameSim) {
        self.telling = false;
        self.crate_ = [Crate::NONE, Crate::NONE];
        self.press_y = Self::_toward(self.press_y, Self::PRESS_REST, Self::LIFT, Self::LIFT);
        self.plate_y = Self::_toward(self.plate_y, Self::PLATE_REST, Self::LIFT, Self::LIFT);
    }

    fn boss_kills(&self, sim: &GameSim) -> bool {
        if sim.state.y - SimConfig::BIRD_RADIUS <= self.press_y + Self::BITE {
            return true;
        }
        if sim.state.y + SimConfig::BIRD_RADIUS >= self.plate_y - Self::BITE {
            return true;
        }
        for i in 0..2usize {
            if self.crate_[i] == Crate::FALL {
                let x = self.crate_x[i];
                let y = self.crate_y[i];
                if sim.bird_touches_rect(
                    x - Self::CRATE_HALF,
                    y - Self::CRATE_HALF,
                    x + Self::CRATE_HALF,
                    y + Self::CRATE_HALF,
                ) {
                    return true;
                }
            }
        }
        false
    }

    fn safe_y(&self, y: i64, steps: i64) -> bool {
        let mut top = self.press_y;
        let mut bottom = self.plate_y;
        let c = self.boss.clock_in(steps);
        if c >= 0 && self.boss.phase == 1 {
            let lt = c % Self::CYCLE;
            if lt >= Self::SLAM_AT && lt < Self::LIFT_AT {
                top = G::maxi(top, self.slam_of(c / Self::CYCLE));
            }
        } else if c >= 0 {
            let k = c / Self::CYCLE;
            let lt = c % Self::CYCLE;
            let lane = if self.jaw { self.lane_to } else { Self::LANE_FIRST };
            let mut spread = 0;
            if k > self._k && self.jaw && lt >= Self::TELL {
                spread = G::mini((lt - Self::TELL) * Self::JAW_SPEED, Self::LANE_STEP_MAX[(self.boss.tier - 1) as usize]);
            }
            top = G::maxi(top, lane - self.lane_half() - Self::TEETH + spread);
            bottom = G::mini(bottom, lane + self.lane_half() + Self::TEETH - spread);
        }
        let r = SimConfig::BIRD_RADIUS + Boss::MARGIN;
        y - r > top + Self::BITE && y + r < bottom - Self::BITE
    }
}

impl Hazard for BossCrusher {
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
                self.press_y,
                self.plate_y,
                self.slam_y,
                self.lane_from,
                self.lane_to,
                G::b(self.telling),
                G::b(self.jaw),
                self.crate_x[0],
                self.crate_y[0],
                self.crate_[0],
                self.crate_x[1],
                self.crate_y[1],
                self.crate_[1],
                self._k,
            ],
        )
    }
}
