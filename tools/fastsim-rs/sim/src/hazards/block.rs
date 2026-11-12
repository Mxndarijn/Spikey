//! Port of sim/hazards/block.gd (Sim/Hazards/Block.cs).
use crate::hazards::Hz;
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Block {
    pub base: Base,
    pub x0: i64,
    pub y0: i64,
    pub x1: i64,
    pub y1: i64,
    pub fade_period: i64,
    pub solid_ticks: i64,
    pub phase: i64,
    pub base_phase: i64,
    pub band: i64,
    pub drift: i64,
    pub home_x: i64,
    pub big: bool,
    pub guards_exit: bool,
}

/// Block `i` of the room, or `this` at its own (taken) index.
fn block_at<'a>(this: &'a Block, sim: &'a GameSim, i: usize) -> &'a Block {
    if i == this.base.idx {
        return this;
    }
    match &sim.room.hazards[i] {
        Hz::Block(b) => b,
        _ => unreachable!("not a Block"),
    }
}

fn block_at_mut<'a>(this: &'a mut Block, sim: &'a mut GameSim, i: usize) -> &'a mut Block {
    if i == this.base.idx {
        return this;
    }
    match &mut sim.room.hazards[i] {
        Hz::Block(b) => b,
        _ => unreachable!("not a Block"),
    }
}

impl Block {
    pub const BAND: i64 = 110 * SimConfig::SUB;
    pub const BAND_TOP: i64 = 96 * SimConfig::SUB;
    pub const SIDE: i64 = 80 * SimConfig::SUB;
    pub const START_MARGIN: i64 = 6 * SimConfig::SUB;
    pub const MIN_GAP: i64 = 95 * SimConfig::SUB;
    pub const PINCH_X: i64 = 48 * SimConfig::SUB;
    pub const ARRIVAL_W: i64 = 200 * SimConfig::SUB;
    pub const ARRIVAL_UP: i64 = 75 * SimConfig::SUB;
    pub const ARRIVAL_DOWN: i64 = 45 * SimConfig::SUB;
    pub const EXIT_CLEAR_X: i64 = 130 * SimConfig::SUB;
    pub const EXIT_MARGIN: i64 = 8 * SimConfig::SUB;
    pub const DRIFT: i64 = 40 * SimConfig::SUB;
    pub const DRIFT_PERIOD: i64 = 300;
    pub const BIG_TOP: i64 = 190 * SimConfig::SUB;
    pub const BIG_BOTTOM: i64 = 450 * SimConfig::SUB;
    pub const BIG_STEP: i64 = 16 * SimConfig::SUB;

    /// C# defaults: all 0.
    pub fn new(p_x0: i64, p_y0: i64, p_x1: i64, p_y1: i64) -> Block {
        Block {
            base: Base::new("block"),
            x0: p_x0,
            y0: p_y0,
            x1: p_x1,
            y1: p_y1,
            fade_period: 0,
            solid_ticks: 0,
            phase: 0,
            base_phase: 0,
            band: -1,
            drift: 0,
            home_x: 0,
            big: false,
            guards_exit: false,
        }
    }

    fn _setup_big(&mut self, sim: &GameSim, rng: &mut SimRng) {
        let sub = SimConfig::SUB;
        let w = (150 + rng.next_below(41)) * sub;
        let h = (28 + rng.next_below(9)) * sub;
        let lo = Self::BIG_TOP;
        let hi = Self::BIG_BOTTOM - h;
        self.x0 = (SimConfig::WORLD_W - w) / 2;
        self.x1 = self.x0 + w;
        self.y0 = lo + rng.next_below(hi - lo + 1);
        self.home_x = self.x0;
        let mut tries: Vec<i64> = vec![self.y0];
        let mut cy = lo;
        while cy < hi + 1 {
            tries.push(cy);
            cy += Self::BIG_STEP;
        }
        for &cy in &tries {
            if !self._in_the_way(sim, self.x0, cy, self.x1, cy + h) {
                self.y0 = cy;
                self.y1 = self.y0 + h;
                return;
            }
        }
        self.y1 = self.y0 + h;
        self.base.alive = false;
    }

    pub fn sway(p_drift: i64, tick: i64) -> i64 {
        p_drift * SimTrig::sin_t(tick * SimTrig::TURN / Self::DRIFT_PERIOD) / SimTrig::ONE
    }

    fn _time_faders_for_arrival(&mut self, sim: &mut GameSim) {
        let path = FairLanes::arrival_path(sim);
        let margin = 4 * SimConfig::SUB;
        let reach = SimConfig::BIRD_RADIUS + margin;
        let kind = self.base.kind;
        // C# keeps the Blocks themselves; here their indices (own index = this).
        let mut all: Vec<usize> = Vec::new();
        let mut touches: Vec<Vec<i64>> = Vec::new();
        let me = self.base.idx;
        for i in 0..sim.room.hazards.len() {
            let h: &mut Block = if i == me {
                &mut *self
            } else {
                match &mut sim.room.hazards[i] {
                    Hz::Block(b) => b,
                    _ => continue,
                }
            };
            if h.base.kind != kind || h.fade_period <= 0 {
                continue;
            }
            h.phase = h.base_phase;
            all.push(i);
            let mut at: Vec<i64> = Vec::new();
            for k in 0..FairLanes::ARRIVAL_PATH_TICKS {
                let px = path[(2 * k) as usize];
                let py = path[(2 * k + 1) as usize];
                let nx = G::clampi(px, h.x0, h.x1);
                let ny = G::clampi(py, h.y0, h.y1);
                if (px - nx) * (px - nx) + (py - ny) * (py - ny) < reach * reach {
                    at.push(k);
                }
            }
            touches.push(at);
        }
        let mut best = 0;
        let mut best_hits = -1;
        let mut shift = 0;
        while shift < self.fade_period {
            let mut hits = 0;
            for i in 0..all.len() {
                let b = block_at(self, sim, all[i]);
                for &k in &touches[i] {
                    if G::posmod(k + 1 + b.phase + shift, b.fade_period) < b.solid_ticks {
                        hits += if k < FairLanes::ARRIVAL_PATH_MIN { 1000 } else { 1 };
                    }
                }
            }
            if best_hits < 0 || hits < best_hits {
                best_hits = hits;
                best = shift;
            }
            if hits == 0 {
                break;
            }
            shift += 1;
        }
        for &i in &all {
            let b = block_at_mut(self, sim, i);
            b.phase = G::posmod(b.phase + best, b.fade_period);
        }
    }

    pub fn _in_the_way(&self, sim: &GameSim, bx0: i64, by0: i64, bx1: i64, by1: i64) -> bool {
        let sx0 = bx0 - self.drift;
        let sx1 = bx1 + self.drift;
        FairLanes::start_path_hits_rect(sim, sx0, by0, sx1, by1, Self::START_MARGIN)
            || FairLanes::blocks_start_lane(sim, sx0, by0, sx1, by1)
            || self._blocks_arrival(sim, sx0, by0, sx1, by1)
            || self._crowds_neighbour(sim, bx0, by0, bx1)
    }

    pub fn _blocks_arrival(&self, sim: &GameSim, bx0: i64, by0: i64, bx1: i64, by1: i64) -> bool {
        let st = &sim.state;
        if !st.started {
            return false;
        }
        let up = st.anchor_y - (Self::ARRIVAL_UP + SimConfig::EXIT_FIT) * sim.room.gravity;
        let down = st.anchor_y + (Self::ARRIVAL_DOWN + SimConfig::EXIT_FIT) * sim.room.gravity;
        let top = G::mini(up, down);
        let bottom = G::maxi(up, down);
        if by1 > top && by0 < bottom {
            if st.vx > 0 && bx0 < sim.room.wall_left() + Self::ARRIVAL_W {
                return true;
            }
            if st.vx < 0 && bx1 > sim.room.wall_right() - Self::ARRIVAL_W {
                return true;
            }
        }
        false
    }

    /// The island of the band above, as [x0, x1, y1]; empty if there is none.
    pub fn _neighbour(&self, sim: &GameSim) -> Vec<i64> {
        let hs = &sim.room.hazards;
        for i in 0..hs.len() {
            // C# `other != this`: our own slot holds Hz::Taken.
            if i == self.base.idx {
                continue;
            }
            let other = &hs[i];
            if other.kind() == self.base.kind && other.alive() {
                let o = match other {
                    Hz::Block(b) => b,
                    _ => unreachable!("kind block that is not a Block"),
                };
                if o.band == self.band - 1 {
                    return vec![o.x0, o.x1, o.y1];
                }
            }
        }
        Vec::new()
    }

    pub fn _crowds_neighbour(&self, sim: &GameSim, bx0: i64, by0: i64, bx1: i64) -> bool {
        let other = self._neighbour(sim);
        if other.is_empty() {
            return false;
        }
        let beside = bx0 - other[1] >= Self::PINCH_X || other[0] - bx1 >= Self::PINCH_X;
        !beside && by0 - other[2] < Self::MIN_GAP
    }

    #[allow(clippy::too_many_arguments)]
    pub fn _fronts_exit(
        &self,
        sim: &GameSim,
        side: i64,
        y: i64,
        margin: i64,
        bx0: i64,
        by0: i64,
        bx1: i64,
        by1: i64,
    ) -> bool {
        let away = if side == 0 { bx0 - sim.room.wall_left() } else { sim.room.wall_right() - bx1 };
        if away >= Self::EXIT_CLEAR_X {
            return false;
        }
        let reach = SimConfig::BIRD_RADIUS + margin;
        by1 + reach > y && by0 - reach < y
    }

    pub fn solid(&self) -> bool {
        if self.fade_period <= 0 {
            return true;
        }
        G::posmod(self.base.t + self.phase, self.fade_period) < self.solid_ticks
    }

    pub fn opacity(&self) -> i64 {
        if self.fade_period <= 0 {
            return SimTrig::ONE;
        }
        let p = G::posmod(self.base.t + self.phase, self.fade_period);
        if p < self.solid_ticks {
            return SimTrig::ONE;
        }
        let fade = self.fade_period - self.solid_ticks;
        let into = p - self.solid_ticks;
        let third = G::maxi(fade / 3, 1);
        if into < third {
            return SimTrig::ONE - SimTrig::ONE * into / third;
        }
        if into > fade - third {
            return SimTrig::ONE * (into - (fade - third)) / third;
        }
        0
    }
}

impl Hazard for Block {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        if self.band < 0 {
            self.base_phase = self.phase;
            self.home_x = self.x0;
            if self.fade_period > 0 && sim.state.started {
                self._time_faders_for_arrival(sim);
            }
            return;
        }
        if self.big {
            self._setup_big(sim, rng);
            return;
        }
        let sim: &GameSim = sim;
        let sub = SimConfig::SUB;
        let side = Self::SIDE + self.drift;
        let mut w = (50 + rng.next_below(41)) * sub;
        if self.drift > 0 {
            w = (40 + rng.next_below(25)) * sub;
        }
        let h = (24 + rng.next_below(13)) * sub;
        self.x0 = side + rng.next_below(SimConfig::WORLD_W - 2 * side - w);
        self.y0 = Self::BAND_TOP + self.band * Self::BAND + 10 * sub + rng.next_below(Self::BAND - h - 20 * sub);
        let band_top = Self::BAND_TOP + self.band * Self::BAND + 10 * sub;
        let band_bottom = Self::BAND_TOP + (self.band + 1) * Self::BAND - 10 * sub - h;
        let far_x = SimConfig::WORLD_W - side - w;
        let mid_x = (SimConfig::WORLD_W - w) / 2;
        let mut clear_y = band_top;
        let mut right_x = far_x;
        let mut left_x = side;
        let above = self._neighbour(sim);
        if !above.is_empty() {
            clear_y = above[2] + Self::MIN_GAP;
            right_x = above[1] + Self::PINCH_X;
            left_x = above[0] - Self::PINCH_X - w;
        }
        clear_y = G::clampi(G::maxi(clear_y, self.y0), band_top, band_bottom);
        right_x = G::clampi(right_x, side, far_x);
        left_x = G::clampi(left_x, side, far_x);
        let mut found = false;
        // The candidate arrays are built once, before the loops (as in GDScript).
        let cxs: [i64; 6] = [self.x0, right_x, left_x, far_x, side, mid_x];
        let cys: [i64; 4] = [self.y0, clear_y, band_top, band_bottom];
        for &cx in &cxs {
            for &cy in &cys {
                if self._in_the_way(sim, cx, cy, cx + w, cy + h) {
                    continue;
                }
                self.x0 = cx;
                self.y0 = cy;
                found = true;
                break;
            }
            if found {
                break;
            }
        }
        self.x1 = self.x0 + w;
        self.y1 = self.y0 + h;
        self.home_x = self.x0;
        if !found {
            self.base.alive = false;
        }
    }

    fn step(&mut self, _sim: &mut GameSim) {
        if self.drift <= 0 {
            return;
        }
        let w = self.x1 - self.x0;
        self.x0 = self.home_x + Self::sway(self.drift, self.base.t);
        self.x1 = self.x0 + w;
    }

    fn blocks_exit(&self, sim: &GameSim, side: i64, y: i64) -> bool {
        if self.band < 0 && !self.guards_exit {
            return false;
        }
        let w = self.x1 - self.x0;
        self._fronts_exit(
            sim,
            side,
            y,
            Self::EXIT_MARGIN,
            self.home_x - self.drift,
            self.y0,
            self.home_x + w + self.drift,
            self.y1,
        )
    }

    fn kills(&self, sim: &GameSim) -> bool {
        self.solid() && sim.bird_touches_rect(self.x0, self.y0, self.x1, self.y1)
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(h, &[self.x0, self.y0, self.x1, self.y1, self.fade_period, self.solid_ticks, self.phase])
    }
}
