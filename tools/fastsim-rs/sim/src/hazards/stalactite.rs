//! Port of sim/hazards/stalactite.gd (Sim/Hazards/Stalactite.cs).
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Stalactite {
    pub base: Base,
    pub x: i64,
    pub gap_y: i64,
    pub target_y: i64,
    pub follows: bool,
    /// Index of the partner Stalactite in `room.hazards` (C# `Stalactite partner`).
    pub partner: Option<usize>,
    pub top: bool,
    pub bottom: bool,
    pub gap: i64,
    pub half_w: i64,
    pub fixed_lo: i64,
    pub fixed_hi: i64,
    pub open_top: i64,
    pub open_bottom: i64,
    pub open_until: i64,
}

impl Stalactite {
    pub const GAP: i64 = 150 * SimConfig::SUB;
    pub const HALF_W: i64 = 22 * SimConfig::SUB;
    pub const GAP_MIN: i64 = 150 * SimConfig::SUB;
    pub const GAP_MAX: i64 = 490 * SimConfig::SUB;
    pub const REACH: i64 = 40 * SimConfig::SUB;
    pub const MAX_STEP: i64 = 60 * SimConfig::SUB;
    pub const WALL_CLEAR: i64 = 70 * SimConfig::SUB;
    pub const SLIDE: i64 = 3 * SimConfig::SUB;
    pub const HOP_MID: i64 = 30 * SimConfig::SUB;
    pub const EXIT_NEAR: i64 = 120 * SimConfig::SUB;
    pub const CLOSE: i64 = 2 * SimConfig::SUB;

    /// C# defaults: p_x = 0, p_follows = false.
    pub fn new(p_x: i64, p_follows: bool) -> Stalactite {
        Stalactite {
            base: Base::new("stalactite"),
            x: p_x,
            gap_y: 0,
            target_y: 0,
            follows: p_follows,
            partner: None,
            top: true,
            bottom: true,
            gap: Self::GAP,
            half_w: Self::HALF_W,
            fixed_lo: -1,
            fixed_hi: -1,
            open_top: 0,
            open_bottom: 0,
            open_until: 0,
        }
    }

    fn _partner(sim: &GameSim, i: usize) -> &Stalactite {
        match &sim.room.hazards[i] {
            Hz::Stalactite(s) => s,
            _ => panic!("Stalactite.partner is not a Stalactite"),
        }
    }

    fn _partner_mut(sim: &mut GameSim, i: usize) -> &mut Stalactite {
        match &mut sim.room.hazards[i] {
            Hz::Stalactite(s) => s,
            _ => panic!("Stalactite.partner is not a Stalactite"),
        }
    }

    /// C# `_clear_wall_ahead(sim, column)` reads only `column.target_y`, so
    /// that is what is passed here (the column may be another hazard).
    pub fn _clear_wall_ahead(sim: &mut GameSim, column_target_y: i64) {
        let s = &mut sim.state;
        let mut mask = if s.vx > 0 { s.right_spikes } else { s.left_spikes };
        for slot in 0..SimConfig::SLOT_COUNT {
            if G::absi(SimConfig::slot_center_y(slot) - column_target_y) < Self::WALL_CLEAR {
                mask &= !(1i64 << slot);
            }
        }
        if s.vx > 0 {
            s.right_spikes = mask;
        } else {
            s.left_spikes = mask;
        }
    }

    pub fn _around(rng: &mut SimRng, center: i64, spread: i64) -> i64 {
        let lo = G::maxi(Self::GAP_MIN, center - spread);
        let hi = G::mini(Self::GAP_MAX, center + spread);
        if lo > hi {
            return G::clampi(center, Self::GAP_MIN, Self::GAP_MAX);
        }
        lo + rng.next_below(hi - lo + 1)
    }

    pub fn open_for_arrival(&mut self, sim: &GameSim, p: &VariantParams) {
        if !p.arriving {
            return;
        }
        let reach = self.half_w + SimConfig::BIRD_RADIUS;
        let mut last: i64 = -1;
        for k in 0..FairLanes::OPEN_PATH_TICKS {
            if G::absi(FairLanes::arrival_x(sim, k + 1) - self.x) < reach {
                last = k + 1;
            }
        }
        if last < 0 {
            return;
        }
        self.open_until = last;
        if self.top {
            self.open_top = G::maxi(self.gap_y - self.gap / 2 - p.hold_top(sim), 0);
        }
        if self.bottom {
            self.open_bottom = G::maxi(p.hold_bottom(sim) - (self.gap_y + self.gap / 2), 0);
        }
    }

    pub fn top_tip(&self) -> i64 {
        self.gap_y - self.gap / 2 - self.open_top
    }

    pub fn bottom_tip(&self) -> i64 {
        self.gap_y + self.gap / 2 + self.open_bottom
    }
}

impl Hazard for Stalactite {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, _rng: &mut SimRng) {
        self.partner = None;
        if self.fixed_lo >= 0 {
            self.gap_y = G::clampi(FairLanes::entry_y(sim) - Self::HOP_MID, self.fixed_lo, self.fixed_hi);
            self.target_y = self.gap_y;
            return;
        }
        if self.follows {
            for i in 0..sim.room.hazards.len() {
                // C# `h != this`: own slot is Hz::Taken, skip it.
                if i != self.base.idx && sim.room.hazards[i].kind() == self.base.kind {
                    let me = self.base.idx;
                    let s = Self::_partner_mut(sim, i);
                    self.partner = Some(i);
                    s.partner = Some(me);
                }
            }
        }
        self.gap_y = G::clampi(FairLanes::entry_y(sim), Self::GAP_MIN, Self::GAP_MAX);
        self.target_y = self.gap_y;
    }

    fn on_bounce(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        if self.follows {
            return;
        }
        if self.fixed_lo >= 0 {
            Self::_clear_wall_ahead(sim, self.target_y);
            return;
        }
        // near = this, far = partner; swapped: near = partner, far = this.
        let mut swapped = false;
        if let Some(p) = self.partner {
            if (Self::_partner(sim, p).x > self.x) == (sim.state.vx < 0) {
                swapped = true;
            }
        }
        let t = self.base.t;
        let far_exists = swapped || self.partner.is_some();
        if self.base.t == 0 {
            // Just came out of a portal into this room: the gap ahead stays at
            // the bird's height (set in setup).
            if swapped {
                let p = Self::_partner_mut(sim, self.partner.unwrap());
                p.target_y = p.gap_y;
            } else {
                self.target_y = self.gap_y;
            }
        } else {
            // With a partner the near column keeps its gap, except once the exit
            // (or its ghost) shows; the draw stays, so the RNG order does too.
            let drawn = Self::_around(rng, sim.state.anchor_y, Self::REACH);
            if !far_exists || sim.state.exit_open || sim.state.exit_preview {
                if swapped {
                    Self::_partner_mut(sim, self.partner.unwrap()).target_y = drawn;
                } else {
                    self.target_y = drawn;
                }
            }
            // An arrival opening (generated variants): the gap stays put while open.
            if swapped {
                let n = Self::_partner_mut(sim, self.partner.unwrap());
                if n.open_until > t {
                    n.target_y = n.gap_y;
                }
            } else if self.open_until > t {
                self.target_y = self.gap_y;
            }
        }
        let near_target = if swapped { Self::_partner(sim, self.partner.unwrap()).target_y } else { self.target_y };
        let mut column_target_y = near_target;
        if far_exists {
            // The far column walks toward the anchor, within MAX_STEP of the near one.
            let n = near_target;
            let mut far_target =
                G::clampi(Self::_around(rng, sim.state.anchor_y, Self::MAX_STEP), n - Self::MAX_STEP, n + Self::MAX_STEP);
            if swapped {
                if self.open_until > t {
                    far_target = self.gap_y;
                }
                self.target_y = far_target;
            } else {
                let far = Self::_partner_mut(sim, self.partner.unwrap());
                if far.open_until > t {
                    far_target = far.gap_y;
                }
                far.target_y = far_target;
            }
            column_target_y = far_target;
        }
        Self::_clear_wall_ahead(sim, column_target_y);
    }

    fn blocks_exit(&self, _sim: &GameSim, side: i64, y: i64) -> bool {
        if self.fixed_lo < 0 {
            return false;
        }
        let wall = if side == 0 { 0 } else { SimConfig::WORLD_W };
        if G::absi(self.x - wall) > Self::EXIT_NEAR {
            return false;
        }
        let r = SimConfig::BIRD_RADIUS;
        if self.top && y < self.gap_y - self.gap / 2 + r {
            return true;
        }
        self.bottom && y > self.gap_y + self.gap / 2 - r
    }

    fn step(&mut self, _sim: &mut GameSim) {
        if self.gap_y < self.target_y {
            self.gap_y = G::mini(self.gap_y + Self::SLIDE, self.target_y);
        } else if self.gap_y > self.target_y {
            self.gap_y = G::maxi(self.gap_y - Self::SLIDE, self.target_y);
        }
        if self.base.t > self.open_until {
            self.open_top = G::maxi(self.open_top - Self::CLOSE, 0);
            self.open_bottom = G::maxi(self.open_bottom - Self::CLOSE, 0);
        }
    }

    fn kills(&self, sim: &GameSim) -> bool {
        (self.top && sim.bird_touches_rect(self.x - self.half_w, 0, self.x + self.half_w, self.top_tip()))
            || (self.bottom
                && sim.bird_touches_rect(self.x - self.half_w, self.bottom_tip(), self.x + self.half_w, SimConfig::WORLD_H))
    }

    fn checksum(&self, h: i64) -> i64 {
        let out_ = mix_all(
            h,
            &[
                self.x,
                self.gap_y,
                self.target_y,
                G::b(self.follows),
                G::b(self.top),
                G::b(self.bottom),
                self.gap,
                self.half_w,
                self.fixed_lo,
            ],
        );
        if self.open_top != 0 || self.open_bottom != 0 || self.open_until != 0 {
            return mix_all(out_, &[self.open_top, self.open_bottom, self.open_until]);
        }
        out_
    }
}
