//! Port of sim/hazards/cave_rock.gd.
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct CaveRock {
    pub base: Base,
    pub top_x: Vec<i64>,
    pub top_y: Vec<i64>,
    pub bot_x: Vec<i64>,
    pub bot_y: Vec<i64>,
    pub isle_x: Vec<i64>,
    pub isle_top: Vec<i64>,
    pub isle_bot: Vec<i64>,
}

impl CaveRock {
    pub const FREE_RUN: i64 = 3;
    pub const EXIT_MARGIN: i64 = 4 * SimConfig::SUB;
    pub const MOUTH_STEP: i64 = 4 * SimConfig::SUB;

    pub fn new() -> CaveRock {
        CaveRock {
            base: Base::new("cave_rock"),
            top_x: Vec::new(),
            top_y: Vec::new(),
            bot_x: Vec::new(),
            bot_y: Vec::new(),
            isle_x: Vec::new(),
            isle_top: Vec::new(),
            isle_bot: Vec::new(),
        }
    }

    pub fn edge_at(xs: &[i64], ys: &[i64], x: i64) -> i64 {
        if x <= xs[0] {
            return ys[0];
        }
        for i in 1..xs.len() {
            if x <= xs[i] {
                let span = xs[i] - xs[i - 1];
                if span <= 0 {
                    return ys[i];
                }
                return ys[i - 1] + (ys[i] - ys[i - 1]) * (x - xs[i - 1]) / span;
            }
        }
        ys[ys.len() - 1]
    }

    pub fn _hits_face(sim: &GameSim, xs: &[i64], ys: &[i64], below: bool) -> bool {
        let bx = sim.state.x;
        let by = sim.state.y;
        let r = SimConfig::BIRD_RADIUS;
        let at = Self::edge_at(xs, ys, bx);
        if if below { by > at } else { by < at } {
            return true;
        }
        for i in 1..xs.len() {
            if xs[i] < bx - r || xs[i - 1] > bx + r {
                continue;
            }
            if SimMath::circle_hits_segment(bx, by, r, xs[i - 1], ys[i - 1], xs[i], ys[i]) {
                return true;
            }
        }
        false
    }

    pub fn _hits_isle(&self, sim: &GameSim) -> bool {
        if self.isle_x.is_empty() {
            return false;
        }
        let bx = sim.state.x;
        let by = sim.state.y;
        let r = SimConfig::BIRD_RADIUS;
        if bx + r < self.isle_x[0] {
            return false;
        }
        if bx >= self.isle_x[0]
            && by > Self::edge_at(&self.isle_x, &self.isle_top, bx)
            && by < Self::edge_at(&self.isle_x, &self.isle_bot, bx)
        {
            return true;
        }
        for i in 1..self.isle_x.len() {
            if self.isle_x[i] < bx - r || self.isle_x[i - 1] > bx + r {
                continue;
            }
            let x0 = self.isle_x[i - 1];
            let x1 = self.isle_x[i];
            if SimMath::circle_hits_segment(bx, by, r, x0, self.isle_top[i - 1], x1, self.isle_top[i]) {
                return true;
            }
            if SimMath::circle_hits_segment(bx, by, r, x0, self.isle_bot[i - 1], x1, self.isle_bot[i]) {
                return true;
            }
        }
        false
    }

    pub fn mouths(&self, side: i64) -> Vec<i64> {
        let wx = if side == 0 { 0 } else { SimConfig::WORLD_W };
        let dir = if side == 0 { 1 } else { -1 };
        let mut top = -SimConfig::WORLD_H;
        let mut bottom = 2 * SimConfig::WORLD_H;
        let mut isle_top_y = 2 * SimConfig::WORLD_H;
        let mut isle_bot_y = -SimConfig::WORLD_H;
        let mut isle = false;
        let mut d = 0;
        while d < ExitZone::DEPTH + 1 {
            let x = wx + dir * d;
            top = G::maxi(top, Self::edge_at(&self.top_x, &self.top_y, x));
            bottom = G::mini(bottom, Self::edge_at(&self.bot_x, &self.bot_y, x));
            if !self.isle_x.is_empty() && x >= self.isle_x[0] && x <= self.isle_x[self.isle_x.len() - 1] {
                isle = true;
                isle_top_y = G::mini(isle_top_y, Self::edge_at(&self.isle_x, &self.isle_top, x));
                isle_bot_y = G::maxi(isle_bot_y, Self::edge_at(&self.isle_x, &self.isle_bot, x));
            }
            d += Self::MOUTH_STEP;
        }
        if !isle || isle_bot_y <= isle_top_y {
            return vec![top, bottom];
        }
        vec![top, isle_top_y, isle_bot_y, bottom]
    }

    pub fn _free_run(mask: i64, top: i64, bottom: i64) -> i64 {
        let half = SimConfig::SPIKE_HALF_BASE;
        let mut first: i64 = -1;
        let mut last: i64 = -1;
        for slot in 0..SimConfig::SLOT_COUNT {
            let yc = SimConfig::slot_center_y(slot);
            if yc - half >= top && yc + half <= bottom {
                if first < 0 {
                    first = slot;
                }
                last = slot;
            }
        }
        if first < 0 {
            return mask;
        }
        let mut run = 0;
        for slot in first..last + 1 {
            run = if (mask & (1i64 << slot)) != 0 { 0 } else { run + 1 };
            if run >= Self::FREE_RUN {
                return mask;
            }
        }
        let mut out_ = mask;
        let mid = (first + last) / 2;
        let lo = G::clampi(mid - Self::FREE_RUN / 2, first, G::maxi(first, last - Self::FREE_RUN + 1));
        for slot in lo..G::mini(lo + Self::FREE_RUN, last + 1) {
            out_ &= !(1i64 << slot);
        }
        out_
    }
}

impl Default for CaveRock {
    fn default() -> Self {
        Self::new()
    }
}

impl Hazard for CaveRock {
    impl_base!();

    fn kills(&self, sim: &GameSim) -> bool {
        Self::_hits_face(sim, &self.top_x, &self.top_y, false)
            || Self::_hits_face(sim, &self.bot_x, &self.bot_y, true)
            || self._hits_isle(sim)
    }

    fn blocks_exit(&self, _sim: &GameSim, side: i64, y: i64) -> bool {
        let m = self.mouths(side);
        let keep = ExitZone::HALF + Self::EXIT_MARGIN;
        let mut i = 0;
        while i < m.len() {
            if y >= m[i] + keep && y <= m[i + 1] - keep {
                return false;
            }
            i += 2;
        }
        true
    }

    fn adjust_wall(&mut self, _sim: &mut GameSim, side: i64, mask: i64) -> i64 {
        let mut out_ = mask;
        let half = SimConfig::SPIKE_HALF_BASE;
        let m = self.mouths(side);
        for slot in 0..SimConfig::SLOT_COUNT {
            let yc = SimConfig::slot_center_y(slot);
            let mut open = false;
            let mut i = 0;
            while i < m.len() {
                if yc + half > m[i] && yc - half < m[i + 1] {
                    open = true;
                }
                i += 2;
            }
            if !open {
                out_ &= !(1i64 << slot);
            }
        }
        let mut i = 0;
        while i < m.len() {
            out_ = Self::_free_run(out_, m[i], m[i + 1]);
            i += 2;
        }
        out_
    }

    fn checksum(&self, h: i64) -> i64 {
        let mut out_ = mix_all(h, &[self.top_x.len() as i64, self.bot_x.len() as i64, self.isle_x.len() as i64]);
        let mut ys: Vec<i64> = Vec::new();
        ys.extend_from_slice(&self.top_y);
        ys.extend_from_slice(&self.bot_y);
        ys.extend_from_slice(&self.isle_top);
        ys.extend_from_slice(&self.isle_bot);
        out_ = mix_all(out_, &ys);
        let mut xs: Vec<i64> = Vec::new();
        xs.extend_from_slice(&self.top_x);
        xs.extend_from_slice(&self.bot_x);
        xs.extend_from_slice(&self.isle_x);
        mix_all(out_, &xs)
    }
}
