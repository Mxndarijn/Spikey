//! Port of sim/rooms/hazard.gd (Sim/Rooms/Hazard.cs).
//!
//! Rust layout (see docs/FASTSIM_RS.md):
//! - Every hazard is a struct with a `base: Base` field (kind, alive, t) and
//!   implements `Hazard`. A GDScript subclass holds its parent as a field
//!   (`HeavyBouncer { b: Bouncer, .. }`) and forwards to it.
//! - The room keeps hazards by value in one enum, `Hz` (hazards/mod.rs), so a
//!   room copy is one Vec clone.
//! - A method that changes the hazard and the sim (setup, step, touch,
//!   adjust_wall, on_bounce, on_flap) runs with the hazard taken out of the
//!   room list (`GameSim::with_hazard`): its slot holds `Hz::Taken` meanwhile.
//!   A hazard that walks `sim.room.hazards` itself sees `Taken` at its own
//!   index (`self.base.idx`) and uses `self` there. Touching `Taken` panics,
//!   so an unexpected re-entry can never pass silently.
//! - Read-only methods (kills, blocks_exit, guards_edge, near_row, ...) take
//!   `&self` and `&GameSim`.
//! - References to other hazards (Gate.partner, ...) are indices into
//!   `room.hazards`; hazards are never removed or reordered, so a room copy
//!   needs no remap.
use crate::game_sim::GameSim;
use crate::sim_math::SimHash;
use crate::sim_rng::SimRng;

#[derive(Clone, Debug)]
pub struct Base {
    pub kind: &'static str,
    pub alive: bool,
    pub t: i64,
    /// This hazard's index in `room.hazards` (set when it is added).
    pub idx: usize,
}

impl Default for Base {
    fn default() -> Self {
        Base { kind: "", alive: true, t: 0, idx: usize::MAX }
    }
}

impl Base {
    pub fn new(kind: &'static str) -> Base {
        Base { kind, ..Default::default() }
    }
}

#[allow(unused_variables)]
pub trait Hazard: Clone {
    fn base(&self) -> &Base;
    fn base_mut(&mut self) -> &mut Base;

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {}
    fn step(&mut self, sim: &mut GameSim) {}
    fn kills(&self, sim: &GameSim) -> bool {
        false
    }
    fn touch(&mut self, sim: &mut GameSim) {}
    fn adjust_wall(&mut self, sim: &mut GameSim, side: i64, mask: i64) -> i64 {
        mask
    }
    fn on_bounce(&mut self, sim: &mut GameSim, rng: &mut SimRng) {}
    fn on_flap(&mut self, sim: &mut GameSim) {}
    fn blocks_exit(&self, sim: &GameSim, side: i64, y: i64) -> bool {
        false
    }
    fn guards_edge(&self, sim: &GameSim, top: bool) -> bool {
        false
    }
    fn band_top(&self) -> i64 {
        -1
    }
    fn band_bottom(&self) -> i64 {
        -1
    }
    fn near_row(&self, sim: &GameSim, y: i64, half: i64, from: i64, to: i64) -> bool {
        false
    }
    fn wall_shift(&self, sim: &GameSim, side: i64) -> i64 {
        0
    }
    fn locks_exit(&self, sim: &GameSim) -> bool {
        false
    }
    fn checksum(&self, h: i64) -> i64 {
        h
    }
}

/// `Hazard.mix_all(h, a, b, c)`.
#[inline]
pub fn mix_all(h: i64, values: &[i64]) -> i64 {
    let mut out_ = h;
    for &v in values {
        out_ = SimHash::mix(out_, v);
    }
    out_
}

/// `base` / `base_mut` for a hazard whose base sits at `self.$($f).+`.
#[macro_export]
macro_rules! impl_base {
    () => {
        #[inline(always)]
        fn base(&self) -> &$crate::rooms::hazard::Base {
            &self.base
        }
        #[inline(always)]
        fn base_mut(&mut self) -> &mut $crate::rooms::hazard::Base {
            &mut self.base
        }
    };
    ($($f:ident).+) => {
        #[inline(always)]
        fn base(&self) -> &$crate::rooms::hazard::Base {
            &self.$($f).+
        }
        #[inline(always)]
        fn base_mut(&mut self) -> &mut $crate::rooms::hazard::Base {
            &mut self.$($f).+
        }
    };
}
