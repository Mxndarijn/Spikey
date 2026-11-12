//! Port of sim/hazards/dart.gd (Sim/Hazards/Dart.cs).
use crate::prelude::*;

/// `Dart.State`.
pub struct State;
impl State {
    pub const IDLE: i64 = 0;
    pub const GLOW: i64 = 1;
    pub const FLY: i64 = 2;
}

#[derive(Clone, Debug)]
pub struct Dart {
    pub base: Base,
    pub lanes: bool,
    pub lane_count: i64,
    pub lane_min: i64,
    pub lane_max: i64,
    pub lanes_speed: i64,
    pub lanes_flash: i64,
    pub pair: bool,
    pub lane2_y: i64,
    pub slot: i64,
    pub home: i64,
    pub state: i64,
    pub since: i64,
    pub wait: i64,
    pub side: i64,
    pub lane_y: i64,
    pub x: i64,
    pub shots: i64,
    pub salt: i64,
}

impl Dart {
    pub const START_DELAY: i64 = 60;
    pub const IDLE_TICKS: i64 = 50;
    pub const GLOW_TICKS: i64 = 40;
    pub const SPEED: i64 = 7 * SimConfig::SUB;
    pub const LENGTH: i64 = 30 * SimConfig::SUB;
    pub const HALF_H: i64 = 5 * SimConfig::SUB;
    pub const LANE_MIN: i64 = 90 * SimConfig::SUB;
    pub const LANE_MAX: i64 = 550 * SimConfig::SUB;
    pub const LANES: i64 = 8;
    pub const LANE_STEP: i64 = (Self::LANE_MAX - Self::LANE_MIN) / (Self::LANES - 1);
    pub const LANES_SPEED: i64 = 6 * SimConfig::SUB;
    pub const LANES_FLASH: i64 = 45;
    pub const LANES_IDLE: i64 = 40;
    pub const SLOT_DELAY: i64 = 70;
    pub const TWIN_DELAY: i64 = 75;

    /// C# defaults: p_lanes = false, p_slot = 0, p_home = -1.
    pub fn new(p_lanes: bool, p_slot: i64, p_home: i64) -> Dart {
        Dart {
            base: Base::new("dart"),
            lanes: p_lanes,
            lane_count: Self::LANES,
            lane_min: Self::LANE_MIN,
            lane_max: Self::LANE_MAX,
            lanes_speed: Self::LANES_SPEED,
            lanes_flash: Self::LANES_FLASH,
            pair: false,
            lane2_y: 0,
            slot: p_slot,
            home: p_home,
            state: State::IDLE,
            since: 0,
            wait: Self::START_DELAY,
            side: 1,
            lane_y: 0,
            x: 0,
            shots: 0,
            salt: 0,
        }
    }

    pub fn _base_x(&self) -> i64 {
        if self.side == 0 {
            0
        } else {
            SimConfig::WORLD_W
        }
    }

    pub fn _dir(&self) -> i64 {
        if self.side == 0 {
            1
        } else {
            -1
        }
    }

    fn _land(&mut self) {
        self.state = State::IDLE;
        self.since = self.base.t;
        self.wait = if self.lanes { Self::LANES_IDLE } else { Self::IDLE_TICKS };
        self.shots += 1;
        self.x = self._base_x();
    }

    fn _in_exit(&self, sim: &GameSim) -> bool {
        if ExitZone::hits_rect(sim, self.tail_x(), self.lane_y - Self::HALF_H, self.x, self.lane_y + Self::HALF_H) {
            return true;
        }
        self.pair
            && ExitZone::hits_rect(sim, self.tail_x(), self.lane2_y - Self::HALF_H, self.x, self.lane2_y + Self::HALF_H)
    }

    pub fn _aim(&mut self, sim: &GameSim) {
        if self.lanes {
            let r = SimHash::mix(self.salt, self.shots);
            let lane = G::posmod(r, self.lane_count);
            self.lane_y = self.lane_min + lane * self.lane_step();
            self.side = (r >> 8) & 1;
            if self.pair {
                let other = (lane + 1 + G::posmod(r >> 12, self.lane_count - 1)) % self.lane_count;
                self.lane2_y = self.lane_min + other * self.lane_step();
            }
            return;
        }
        // The far wall from the bird, at the bird's height right now.
        self.side = if sim.state.x < SimConfig::WORLD_W / 2 { 1 } else { 0 };
        if self.home >= 0 {
            self.side = self.home;
        }
        self.lane_y = G::clampi(sim.state.y, Self::LANE_MIN, Self::LANE_MAX);
    }

    pub fn lane_step(&self) -> i64 {
        (self.lane_max - self.lane_min) / (self.lane_count - 1)
    }

    pub fn glow(&self) -> i64 {
        if self.state != State::GLOW {
            return 0;
        }
        SimTrig::ONE * (self.base.t - self.since) / (if self.lanes { self.lanes_flash } else { Self::GLOW_TICKS })
    }

    pub fn tail_x(&self) -> i64 {
        self.x - self._dir() * Self::LENGTH
    }
}

impl Hazard for Dart {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        self.salt = rng.next_u32();
        self.state = State::IDLE;
        self.since = 0;
        self.wait = Self::START_DELAY + self.slot * (if self.lanes { Self::SLOT_DELAY } else { Self::TWIN_DELAY });
        self.side = if sim.state.x < SimConfig::WORLD_W / 2 { 1 } else { 0 };
        if self.home >= 0 {
            self.side = self.home;
        }
        self.lane_y = Self::LANE_MIN;
        self.x = self._base_x();
    }

    fn step(&mut self, sim: &mut GameSim) {
        let t = self.base.t;
        if self.state == State::IDLE {
            if t - self.since >= self.wait {
                self._aim(sim);
                self.state = State::GLOW;
                self.since = t;
            }
        } else if self.state == State::GLOW {
            if t - self.since >= (if self.lanes { self.lanes_flash } else { Self::GLOW_TICKS }) {
                self.state = State::FLY;
                self.since = t;
                self.x = self._base_x();
                if self._in_exit(sim) {
                    self._land();
                }
            }
        } else if self.state == State::FLY {
            self.x += self._dir() * (if self.lanes { self.lanes_speed } else { Self::SPEED });
            if self.x < -Self::LENGTH || self.x > SimConfig::WORLD_W + Self::LENGTH || self._in_exit(sim) {
                self._land();
            }
        }
    }

    fn kills(&self, sim: &GameSim) -> bool {
        if self.state != State::FLY {
            return false;
        }
        if self.pair
            && sim.bird_touches_rect(self.tail_x(), self.lane2_y - Self::HALF_H, self.x, self.lane2_y + Self::HALF_H)
        {
            return true;
        }
        sim.bird_touches_rect(self.tail_x(), self.lane_y - Self::HALF_H, self.x, self.lane_y + Self::HALF_H)
    }

    fn checksum(&self, h: i64) -> i64 {
        let mut out_ = mix_all(
            h,
            &[
                G::b(self.lanes),
                self.slot,
                self.home,
                self.state,
                self.since,
                self.wait,
                self.side,
                self.lane_y,
                self.x,
                self.shots,
                self.salt,
            ],
        );
        if self.pair
            || self.lane_count != Self::LANES
            || self.lanes_speed != Self::LANES_SPEED
            || self.lanes_flash != Self::LANES_FLASH
        {
            out_ = mix_all(
                out_,
                &[G::b(self.pair), self.lane2_y, self.lane_count, self.lane_min, self.lanes_speed, self.lanes_flash],
            );
        }
        out_
    }
}
