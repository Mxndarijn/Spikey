//! Port of sim/hazards/edge_pad.gd (Sim/Hazards/EdgePad.cs).
//!
//! C# `guards_edge` is not read-only: when it guards, it pushes the bird
//! (sim.state.y, sim.state.vy) and sets `since_bump = 0`. That full version is
//! `guards_edge_mut` (needs `&mut self` and `&mut GameSim`, so the caller,
//! GameSim._edge_guarded, must run it through `with_hazard`). The trait's
//! read-only `guards_edge` gives the same answer without the side effects.
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct EdgePad {
    pub base: Base,
    pub top: bool,
    pub period: i64,
    pub phase: i64,
    pub since_bump: i64,
}

impl EdgePad {
    pub const WIDTH: i64 = 96 * SimConfig::SUB;
    pub const X_MIN: i64 = 30 * SimConfig::SUB;
    pub const X_MAX: i64 = SimConfig::WORLD_W - 30 * SimConfig::SUB - Self::WIDTH;
    pub const GRACE: i64 = SimConfig::BIRD_RADIUS / 2;
    pub const CEILING_VY: i64 = -SimConfig::FLAP_VY * 3 / 5;
    pub const FLOOR_VY: i64 = -SimConfig::FLAP_VY * 6 / 5;

    /// C# defaults: p_top = true, p_period = 300.
    pub fn new(p_top: bool, p_period: i64) -> EdgePad {
        EdgePad { base: Base::new("edge_pad"), top: p_top, period: p_period, phase: 0, since_bump: 1000 }
    }

    pub fn x0(&self) -> i64 {
        Self::X_MIN + SimTrig::ping_pong(self.base.t + self.phase, self.period, Self::X_MAX - Self::X_MIN)
    }

    pub fn x1(&self) -> i64 {
        self.x0() + Self::WIDTH
    }

    pub fn line_y(&self) -> i64 {
        if self.top {
            SimConfig::KILL_TOP
        } else {
            SimConfig::KILL_BOTTOM
        }
    }

    pub fn covers(&self, x: i64) -> bool {
        x >= self.x0() - Self::GRACE && x <= self.x1() + Self::GRACE
    }

    /// C# EdgePad.guards_edge with its side effects (see the top comment).
    pub fn guards_edge_mut(&mut self, sim: &mut GameSim, p_top: bool) -> bool {
        if p_top != self.top || !self.covers(sim.state.x) {
            return false;
        }
        let r = SimConfig::BIRD_RADIUS;
        if self.top {
            sim.state.y = G::maxi(sim.state.y, SimConfig::KILL_TOP + r + 1);
            sim.state.vy = Self::CEILING_VY;
        } else {
            sim.state.y = G::mini(sim.state.y, SimConfig::KILL_BOTTOM - r - 1);
            sim.state.vy = -Self::FLOOR_VY;
        }
        self.since_bump = 0;
        true
    }
}

impl Hazard for EdgePad {
    impl_base!();

    fn setup(&mut self, _sim: &mut GameSim, rng: &mut SimRng) {
        self.phase = rng.next_below(self.period);
    }

    fn step(&mut self, _sim: &mut GameSim) {
        self.since_bump += 1;
    }

    /// The answer of C# guards_edge only; the push and `since_bump = 0` happen
    /// in `guards_edge_mut`.
    fn guards_edge(&self, sim: &GameSim, p_top: bool) -> bool {
        !(p_top != self.top || !self.covers(sim.state.x))
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(h, &[G::b(self.top), self.period, self.phase, self.since_bump])
    }
}
