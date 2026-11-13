//! Port of sim/hazards/piston.gd (Sim/Hazards/Piston.cs).
use crate::rooms::hazard::{add_warning, WARN_KILL};
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
    pub glow_ticks: i64,
    pub reach: i64,
    pub skip: bool,
}

impl Piston {
    pub const IDLE_TICKS: i64 = 70;
    pub const GLOW_TICKS: i64 = 32;
    pub const EXTEND_TICKS: i64 = 8;
    pub const HOLD_TICKS: i64 = 34;
    pub const RETRACT_TICKS: i64 = 30;

    pub const REACH: i64 = 200 * SimConfig::SUB;
    pub const HALF_H: i64 = 18 * SimConfig::SUB;
    pub const Y_MIN: i64 = 110 * SimConfig::SUB;
    pub const Y_MAX: i64 = 530 * SimConfig::SUB;

    /// GDScript defaults: p_side = 0, p_y = Y_MIN, p_delay = 0, p_glow = GLOW_TICKS, p_reach = REACH.
    pub fn new(p_side: i64, p_y: i64, p_delay: i64, p_glow: i64, p_reach: i64) -> Piston {
        Piston {
            base: Base::new("piston"),
            side: p_side,
            y: p_y,
            delay: p_delay,
            glow_ticks: p_glow,
            reach: p_reach,
            skip: false,
        }
    }

    /// No wall spike shares the ram's row on its own wall: the slots whose spike
    /// would touch the ram's body are cleared. No RNG draws.
    fn _clear_spikes(&self, sim: &mut GameSim) {
        let near = Self::HALF_H + SimConfig::SPIKE_HALF_BASE;
        let mut mask = if self.side == 0 { sim.state.left_spikes } else { sim.state.right_spikes };
        for slot in 0..SimConfig::SLOT_COUNT {
            if G::absi(SimConfig::slot_center_y(slot) - self.y) < near {
                mask &= !(1i64 << slot);
            }
        }
        if self.side == 0 {
            sim.state.left_spikes = mask;
        } else {
            sim.state.right_spikes = mask;
        }
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

    fn on_bounce(&mut self, sim: &mut GameSim, _rng: &mut SimRng) {
        self._clear_spikes(sim);
    }

    fn step(&mut self, sim: &mut GameSim) {
        if self._cycle_state() == State::IDLE {
            self.skip = false;
        } else if !self.skip && self._reaches_exit(sim) {
            self.skip = true;
        }
    }

    fn blocks_exit(&self, sim: &GameSim, p_side: i64, p_y: i64) -> bool {
        ExitZone::rect_in_box(sim, p_side, p_y, self.base_x(), self.y - Self::HALF_H, self._far_x(), self.y + Self::HALF_H)
    }

    fn kills(&self, sim: &GameSim) -> bool {
        let e = self.extent();
        if e <= 0 {
            return false;
        }
        sim.bird_touches_rect(self.base_x(), self.y - Self::HALF_H, self.tip_x(), self.y + Self::HALF_H)
    }

    fn warnings(&self, _sim: &GameSim, out_: &mut Vec<i64>) {
        if self.state() != State::GLOW {
            return;
        }
        add_warning(out_, self.base_x(), self.y - Self::HALF_H, self._far_x(), self.y + Self::HALF_H,
            Self::IDLE_TICKS + self.glow_ticks - self.cycle_pos(), Self::EXTEND_TICKS + Self::HOLD_TICKS + Self::RETRACT_TICKS, WARN_KILL);
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(h, &[self.side, self.y, self.delay, self.glow_ticks, self.reach, G::b(self.skip)])
    }
}
