//! Port of sim/hazards/piston.gd (Sim/Hazards/Piston.cs).
use crate::prelude::*;

pub struct State;
impl State {
    pub const IDLE: i64 = 0;
    pub const GLOW: i64 = 1;
    pub const EXTEND: i64 = 2;
    pub const HOLD: i64 = 3;
    pub const RETRACT: i64 = 4;
}

#[derive(Clone, Debug)]
pub struct Piston {
    pub base: Base,
    pub side: i64,
    pub y: i64,
    pub delay: i64,
    pub half: i64,
    pub glow_ticks: i64,
    pub share_band: bool,
    pub y_lo: i64,
    pub y_hi: i64,
    pub reach: i64,
    pub follows: bool,
    /// Index of the leading Piston in `room.hazards` (C# `Piston leader`).
    pub leader: Option<usize>,
    pub fixed_y: i64,
    pub skip: bool,
}

impl Piston {
    pub const IDLE_TICKS: i64 = 70;
    pub const GLOW_TICKS: i64 = 32;
    pub const EXTEND_TICKS: i64 = 8;
    pub const HOLD_TICKS: i64 = 34;
    pub const RETRACT_TICKS: i64 = 30;
    pub const PERIOD: i64 =
        Self::IDLE_TICKS + Self::GLOW_TICKS + Self::EXTEND_TICKS + Self::HOLD_TICKS + Self::RETRACT_TICKS;

    pub const REACH: i64 = 200 * SimConfig::SUB;
    pub const HALF_H: i64 = 18 * SimConfig::SUB;
    pub const Y_MIN: i64 = 110 * SimConfig::SUB;
    pub const Y_MAX: i64 = 530 * SimConfig::SUB;
    pub const Y_MID: i64 = 320 * SimConfig::SUB;
    pub const HALF_ALL: i64 = 2;

    /// C# defaults: p_side = 0, p_half = 0, p_delay = 0, p_glow = GLOW_TICKS,
    /// p_share_band = false.
    pub fn new(p_side: i64, p_half: i64, p_delay: i64, p_glow: i64, p_share_band: bool) -> Piston {
        Piston {
            base: Base::new("piston"),
            side: p_side,
            y: 0,
            delay: p_delay,
            half: p_half,
            glow_ticks: p_glow,
            share_band: p_share_band,
            y_lo: Self::Y_MIN,
            y_hi: Self::Y_MAX,
            reach: Self::REACH,
            follows: false,
            leader: None,
            fixed_y: -1,
            skip: false,
        }
    }

    /// `leader.y`.
    fn _leader_y(sim: &GameSim, i: usize) -> i64 {
        match &sim.room.hazards[i] {
            Hz::Piston(p) => p.y,
            _ => panic!("Piston.leader is not a Piston"),
        }
    }

    fn _clear_row(&mut self, sim: &GameSim) {
        if self.fixed_y >= 0 || self.leader.is_some() {
            return;
        }
        let c = ExitZone::clear_y(
            sim,
            if self.half != Self::HALF_ALL { self.side } else { -1 },
            self.y,
            Self::HALF_H,
            self.y_lo,
            self.y_hi,
        );
        if c >= self.y_lo && c <= self.y_hi {
            self.y = c;
        }
    }

    pub fn _pick_y(&mut self, rng: &mut SimRng) {
        self.y = self.y_lo + rng.next_below(self.y_hi - self.y_lo + 1);
    }

    pub fn period(&self) -> i64 {
        Self::IDLE_TICKS + self.glow_ticks + Self::EXTEND_TICKS + Self::HOLD_TICKS + Self::RETRACT_TICKS
    }

    pub fn cycle_pos(&self) -> i64 {
        if self.base.t < self.delay {
            return -1;
        }
        G::posmod(self.base.t - self.delay, self.period())
    }

    fn _reaches_exit(&self, sim: &GameSim) -> bool {
        ExitZone::hits_rect(sim, self.base_x(), self.y - Self::HALF_H, self._far_x(), self.y + Self::HALF_H)
    }

    fn _far_x(&self) -> i64 {
        if self.side == 0 { self.base_x() + self.reach } else { self.base_x() - self.reach }
    }

    pub fn state(&self) -> i64 {
        if self.skip {
            return State::IDLE;
        }
        self._cycle_state()
    }

    pub fn _cycle_state(&self) -> i64 {
        let mut p = self.cycle_pos();
        if p < Self::IDLE_TICKS {
            return State::IDLE;
        }
        p -= Self::IDLE_TICKS;
        if p < self.glow_ticks {
            return State::GLOW;
        }
        p -= self.glow_ticks;
        if p < Self::EXTEND_TICKS {
            return State::EXTEND;
        }
        p -= Self::EXTEND_TICKS;
        if p < Self::HOLD_TICKS {
            return State::HOLD;
        }
        State::RETRACT
    }

    pub fn glow(&self) -> i64 {
        if self.state() != State::GLOW {
            return 0;
        }
        SimTrig::ONE * (self.cycle_pos() - Self::IDLE_TICKS) / self.glow_ticks
    }

    pub fn extent(&self) -> i64 {
        let mut p = self.cycle_pos() - Self::IDLE_TICKS - self.glow_ticks;
        let s = self.state();
        if s == State::EXTEND {
            return self.reach * (p + 1) / Self::EXTEND_TICKS;
        }
        if s == State::HOLD {
            return self.reach;
        }
        if s == State::RETRACT {
            p -= Self::EXTEND_TICKS + Self::HOLD_TICKS;
            return self.reach * (Self::RETRACT_TICKS - p - 1) / Self::RETRACT_TICKS;
        }
        0
    }

    pub fn base_x(&self) -> i64 {
        if self.side == 0 { 0 } else { SimConfig::WORLD_W }
    }

    pub fn tip_x(&self) -> i64 {
        if self.side == 0 { self.base_x() + self.extent() } else { self.base_x() - self.extent() }
    }
}

impl Hazard for Piston {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        if self.fixed_y >= 0 {
            self.y = self.fixed_y;
            return;
        }
        if self.follows {
            self.leader = None;
            for i in 0..sim.room.hazards.len() {
                if i == self.base.idx {
                    break;
                }
                if sim.room.hazards[i].kind() == self.base.kind {
                    self.leader = Some(i);
                }
            }
            if let Some(l) = self.leader {
                self.y = Self::_leader_y(sim, l);
                return;
            }
        }
        self.y_lo = if self.half != 1 { Self::Y_MIN } else { Self::Y_MID + Self::HALF_H };
        self.y_hi = if self.half == 0 { Self::Y_MID - Self::HALF_H } else { Self::Y_MAX };
        if self.share_band {
            for i in 0..sim.room.hazards.len() {
                // C# `h == this`: own slot is Hz::Taken, skip it.
                if i == self.base.idx {
                    continue;
                }
                let h = &sim.room.hazards[i];
                if h.band_top() < 0 {
                    continue;
                }
                let lo = G::maxi(Self::Y_MIN, h.band_top() + Self::HALF_H);
                let hi = G::mini(Self::Y_MAX, h.band_bottom() - Self::HALF_H);
                if lo <= hi {
                    self.y_lo = lo;
                    self.y_hi = hi;
                }
            }
        }
        self._pick_y(rng);
    }

    fn on_bounce(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        if self.fixed_y >= 0 {
            return;
        }
        if let Some(l) = self.leader {
            self.y = Self::_leader_y(sim, l);
            return;
        }
        // Always draw so the RNG order does not depend on the piston state.
        let old = self.y;
        self._pick_y(rng);
        self._clear_row(sim);
        if self._cycle_state() != State::IDLE {
            self.y = old;
        }
    }

    fn step(&mut self, sim: &mut GameSim) {
        if self.base.t == 1 {
            self._clear_row(sim);
            if let Some(l) = self.leader {
                self.y = Self::_leader_y(sim, l);
            }
        }
        if self._cycle_state() == State::IDLE {
            self.skip = false;
        } else if !self.skip && self._reaches_exit(sim) {
            self.skip = true;
        }
    }

    fn blocks_exit(&self, sim: &GameSim, p_side: i64, p_y: i64) -> bool {
        if self.fixed_y < 0 && (self.skip || self._cycle_state() == State::IDLE) {
            return false;
        }
        ExitZone::rect_in_box(sim, p_side, p_y, self.base_x(), self.y - Self::HALF_H, self._far_x(), self.y + Self::HALF_H)
    }

    fn kills(&self, sim: &GameSim) -> bool {
        let e = self.extent();
        if e <= 0 {
            return false;
        }
        sim.bird_touches_rect(self.base_x(), self.y - Self::HALF_H, self.tip_x(), self.y + Self::HALF_H)
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(h, &[self.side, self.y, self.delay, self.half, G::b(self.skip)])
    }
}
