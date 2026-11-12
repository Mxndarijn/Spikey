//! Port of sim/hazards/belt.gd (Sim/Hazards/Belt.cs).
use crate::prelude::*;

pub struct Mode;
impl Mode {
    pub const UP: i64 = 0;
    pub const COUNTER: i64 = 1;
    pub const SWITCHBACK: i64 = 2;
}

#[derive(Clone, Debug)]
pub struct Belt {
    pub base: Base,
    pub mode: i64,
    pub left_dir: i64,
    pub right_dir: i64,
    pub left_shift: i64,
    pub right_shift: i64,
}

impl Belt {
    pub const SPEED: i64 = 29;
    pub const MAX_SHIFT: i64 = 2 * SimConfig::SLOT_SIZE;

    /// C# default: p_mode = -1.
    pub fn new(p_mode: i64) -> Belt {
        Belt {
            base: Base::new("belt"),
            mode: p_mode,
            left_dir: -1,
            right_dir: -1,
            left_shift: 0,
            right_shift: 0,
        }
    }
}

impl Hazard for Belt {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, _rng: &mut SimRng) {
        if self.mode < 0 {
            match sim.room.variant_id() {
                "counter" => self.mode = Mode::COUNTER,
                "switchback" => self.mode = Mode::SWITCHBACK,
                _ => self.mode = Mode::UP,
            }
        }
        self.left_dir = -1;
        self.right_dir = if self.mode == Mode::COUNTER { 1 } else { -1 };
    }

    fn step(&mut self, sim: &mut GameSim) {
        if self.base.t <= SimConfig::ARRIVAL_BLIND {
            return;
        }
        let s = &sim.state;
        if !(s.exit_open && s.exit_side == 0) {
            self.left_shift =
                G::clampi(self.left_shift + self.left_dir * Self::SPEED, -Self::MAX_SHIFT, Self::MAX_SHIFT);
        }
        if !(s.exit_open && s.exit_side == 1) {
            self.right_shift =
                G::clampi(self.right_shift + self.right_dir * Self::SPEED, -Self::MAX_SHIFT, Self::MAX_SHIFT);
        }
    }

    fn on_bounce(&mut self, sim: &mut GameSim, _rng: &mut SimRng) {
        if sim.state.vx > 0 {
            self.right_shift = 0;
        } else {
            self.left_shift = 0;
        }
        if self.mode == Mode::SWITCHBACK {
            self.left_dir = -self.left_dir;
            self.right_dir = -self.right_dir;
        }
    }

    fn wall_shift(&self, _sim: &GameSim, side: i64) -> i64 {
        if side == 0 {
            self.left_shift
        } else {
            self.right_shift
        }
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(h, &[self.mode, self.left_dir, self.right_dir, self.left_shift, self.right_shift])
    }
}
