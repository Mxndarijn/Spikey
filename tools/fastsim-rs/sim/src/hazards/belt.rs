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
    pub left_turn: i64,
    pub right_turn: i64,
    pub left_shift: i64,
    pub right_shift: i64,
    pub left_hold: bool,
    pub right_hold: bool,
}

impl Belt {
    pub const SPEED: i64 = 60;
    pub const MAX_SHIFT: i64 = 2 * SimConfig::SLOT_SIZE;
    pub const HOLD_POINTS: i64 = 2;

    /// C# default: p_mode = -1.
    pub fn new(p_mode: i64) -> Belt {
        Belt {
            base: Base::new("belt"),
            mode: p_mode,
            left_dir: -1,
            right_dir: -1,
            left_turn: 1,
            right_turn: 1,
            left_shift: 0,
            right_shift: 0,
            left_hold: false,
            right_hold: false,
        }
    }

    /// One step of a belt at `shift` running `dir`: [new shift, -1 if it turned
    /// round at MAX_SHIFT else 1]. Past the end it bounces back the rest of the step.
    pub fn _slide(shift: i64, dir: i64) -> [i64; 2] {
        let to = shift + dir * Self::SPEED;
        if to > Self::MAX_SHIFT {
            return [2 * Self::MAX_SHIFT - to, -1];
        }
        if to < -Self::MAX_SHIFT {
            return [-2 * Self::MAX_SHIFT - to, -1];
        }
        [to, 1]
    }

    /// The way wall `side`'s spikes run now (1 = down, -1 = up).
    pub fn run_dir(&self, side: i64) -> i64 {
        if side == 0 {
            self.left_dir * self.left_turn
        } else {
            self.right_dir * self.right_turn
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
        if !self.left_hold && !(s.exit_open && s.exit_side == 0) {
            let l = Self::_slide(self.left_shift, self.left_dir * self.left_turn);
            self.left_shift = l[0];
            self.left_turn *= l[1];
        }
        if !self.right_hold && !(s.exit_open && s.exit_side == 1) {
            let r = Self::_slide(self.right_shift, self.right_dir * self.right_turn);
            self.right_shift = r[0];
            self.right_turn *= r[1];
        }
    }

    fn adjust_wall(&mut self, sim: &mut GameSim, side: i64, mask: i64) -> i64 {
        let hold = side == SimConfig::EXIT_WALL && sim.points_to_exit() <= Self::HOLD_POINTS;
        if side == 0 {
            self.left_shift = 0;
            self.left_turn = 1;
            self.left_hold = hold;
        } else {
            self.right_shift = 0;
            self.right_turn = 1;
            self.right_hold = hold;
        }
        mask
    }

    fn on_bounce(&mut self, _sim: &mut GameSim, _rng: &mut SimRng) {
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
        mix_all(
            h,
            &[
                self.mode,
                self.left_dir,
                self.right_dir,
                self.left_shift,
                self.right_shift,
                self.left_hold as i64,
                self.right_hold as i64,
                self.left_turn,
                self.right_turn,
            ],
        )
    }
}
