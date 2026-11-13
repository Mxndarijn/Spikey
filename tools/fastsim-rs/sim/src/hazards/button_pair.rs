//! Port of sim/hazards/button_pair.gd: Buttons, a button in the ceiling and one in the floor,
//! pressed in turn.
//!
//! GDScript `guards_edge` is not read-only: when it guards, it pushes the bird and may score a
//! press. That full version is `guards_edge_mut` (GameSim._edge_guarded runs it through
//! `with_hazard`). The trait's read-only `guards_edge` gives the same answer.
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct ButtonPair {
    pub base: Base,
    pub width: i64,
    pub top_x0: i64,
    pub bottom_x0: i64,
    pub lit_top: bool,
    pub presses: i64,
    pub since_press: i64,
    pub since_wrong: i64,
    pub last_top: bool,
}

impl ButtonPair {
    pub const SUB: i64 = SimConfig::SUB;
    pub const WIDE: i64 = 120 * Self::SUB;
    pub const SLIM: i64 = 96 * Self::SUB;
    pub const GRID: i64 = 8 * Self::SUB;
    pub const MARGIN: i64 = 32 * Self::SUB;
    pub const APART_MIN: i64 = 140 * Self::SUB;
    pub const GRACE: i64 = SimConfig::BIRD_RADIUS / 2;
    pub const TOP_VY: i64 = -SimConfig::FLAP_VY * 3 / 5;
    pub const BOTTOM_VY: i64 = SimConfig::FLAP_VY * 6 / 5;

    pub fn new() -> ButtonPair {
        ButtonPair {
            base: Base::new("button_pair"),
            width: Self::WIDE,
            top_x0: 0,
            bottom_x0: 0,
            lit_top: true,
            presses: 0,
            since_press: 1000,
            since_wrong: 1000,
            last_top: true,
        }
    }

    pub fn _spots(lo: i64, hi: i64) -> i64 {
        G::maxi((hi - lo) / Self::GRID + 1, 1)
    }

    pub fn _snap(x: i64) -> i64 {
        if x <= Self::MARGIN {
            return Self::MARGIN;
        }
        Self::MARGIN + (x - Self::MARGIN + Self::GRID - 1) / Self::GRID * Self::GRID
    }

    pub fn x0(&self, top: bool) -> i64 {
        if top {
            self.top_x0
        } else {
            self.bottom_x0
        }
    }

    pub fn x1(&self, top: bool) -> i64 {
        self.x0(top) + self.width
    }

    pub fn covers(&self, top: bool, x: i64) -> bool {
        x >= self.x0(top) - Self::GRACE && x <= self.x1(top) + Self::GRACE
    }

    /// GDScript ButtonPair.guards_edge with its side effects (see the top comment).
    pub fn guards_edge_mut(&mut self, sim: &mut GameSim, p_top: bool) -> bool {
        if !self.covers(p_top, sim.state.x) {
            return false;
        }
        let r = SimConfig::BIRD_RADIUS;
        if p_top {
            sim.state.y = G::maxi(sim.state.y, SimConfig::KILL_TOP + r + 1);
            sim.state.vy = Self::TOP_VY;
        } else {
            sim.state.y = G::mini(sim.state.y, SimConfig::KILL_BOTTOM - r - 1);
            sim.state.vy = Self::BOTTOM_VY;
        }
        self.last_top = p_top;
        if p_top == self.lit_top && sim._score_press() {
            self.lit_top = !self.lit_top;
            self.presses += 1;
            self.since_press = 0;
        } else {
            self.since_wrong = 0;
        }
        true
    }
}

impl Hazard for ButtonPair {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        let mut apart = false;
        match sim.room.variant_id() {
            "slim" => self.width = Self::SLIM,
            "apart" => {
                self.width = Self::SLIM;
                apart = true;
            }
            _ => self.width = Self::WIDE,
        }
        let width = self.width;
        let mut lo = Self::MARGIN;
        let mut hi = SimConfig::WORLD_W - Self::MARGIN - width;
        let mid = SimConfig::WORLD_W / 2;
        if apart {
            let left_hi = mid - Self::APART_MIN / 2 - width / 2;
            let right_lo = Self::_snap(mid + Self::APART_MIN / 2 - width / 2);
            let n_left = Self::_spots(lo, left_hi);
            let k = rng.next_below(n_left + Self::_spots(right_lo, hi));
            self.top_x0 = if k < n_left { lo + Self::GRID * k } else { right_lo + Self::GRID * (k - n_left) };
        } else {
            self.top_x0 = lo + Self::GRID * rng.next_below(Self::_spots(lo, hi));
        }
        if apart {
            let top_c = self.top_x0 + width / 2;
            if top_c < mid {
                lo = G::maxi(lo, G::maxi(mid, top_c + Self::APART_MIN) - width / 2);
            } else {
                hi = G::mini(hi, G::mini(mid, top_c - Self::APART_MIN) - width / 2);
            }
            lo = Self::_snap(lo);
        }
        self.bottom_x0 = lo + Self::GRID * rng.next_below(Self::_spots(lo, hi));
    }

    fn step(&mut self, _sim: &mut GameSim) {
        self.since_press += 1;
        self.since_wrong += 1;
    }

    /// The answer of GDScript guards_edge only; the push and the press happen in
    /// `guards_edge_mut`.
    fn guards_edge(&self, sim: &GameSim, p_top: bool) -> bool {
        self.covers(p_top, sim.state.x)
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(
            h,
            &[
                self.width,
                self.top_x0,
                self.bottom_x0,
                G::b(self.lit_top),
                self.presses,
                self.since_press,
                self.since_wrong,
                G::b(self.last_top),
            ],
        )
    }
}
