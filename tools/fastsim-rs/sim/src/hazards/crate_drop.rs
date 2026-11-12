//! Port of sim/hazards/crate_drop.gd (Sim/Hazards/CrateDrop.cs). C# passes a
//! null sim to `_next_drop` / `_free_col` from setup: here `Option<&GameSim>`.
use crate::rooms::hazard::{add_warning, WARN_KILL};
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct CrateDrop {
    pub base: Base,
    pub cols: i64,
    pub col_w: i64,
    pub col_x0: i64,
    pub crate_w: i64,
    pub crate_h: i64,
    pub max_height: i64,
    pub pair: bool,

    pub col: i64,
    pub y: i64,
    pub vy: i64,
    pub done: bool,
    pub col_b: i64,
    pub y_b: i64,
    pub vy_b: i64,
    pub done_b: bool,
    pub warn_left: i64,
    pub drops: i64,
    pub salt: i64,
    pub heights: Vec<i64>,
    pub coins: Vec<i64>,
    pub gifts: bool,
}

impl CrateDrop {
    pub const COLS: i64 = 7;
    pub const COL_X0: i64 = 40 * SimConfig::SUB;
    pub const COL_W: i64 = 40 * SimConfig::SUB;
    pub const CRATE: i64 = 36 * SimConfig::SUB;
    pub const MAX_HEIGHT: i64 = 4;
    pub const FLOOR: i64 = SimConfig::KILL_BOTTOM;
    pub const START_DELAY: i64 = 20;
    pub const WARN_TICKS: i64 = 45;
    pub const FALL_ACCEL: i64 = 20;
    pub const MAX_FALL: i64 = 9 * SimConfig::SUB;
    pub const COIN_LIFT: i64 = 4 * SimConfig::SUB;

    /// C# defaults: p_gifts = false, p_cols = COLS, p_col_w = COL_W,
    /// p_crate_w = CRATE, p_crate_h = CRATE, p_max_height = MAX_HEIGHT,
    /// p_pair = false.
    pub fn new(
        p_gifts: bool,
        p_cols: i64,
        p_col_w: i64,
        p_crate_w: i64,
        p_crate_h: i64,
        p_max_height: i64,
        p_pair: bool,
    ) -> CrateDrop {
        let mut h = CrateDrop {
            base: Base::new("crate_drop"),
            cols: Self::COLS,
            col_w: Self::COL_W,
            col_x0: Self::COL_X0,
            crate_w: Self::CRATE,
            crate_h: Self::CRATE,
            max_height: Self::MAX_HEIGHT,
            pair: false,
            col: -1,
            y: 0,
            vy: 0,
            done: false,
            col_b: -1,
            y_b: 0,
            vy_b: 0,
            done_b: false,
            warn_left: 0,
            drops: 0,
            salt: 0,
            heights: Vec::new(),
            coins: Vec::new(),
            gifts: false,
        };
        h.gifts = p_gifts;
        h.cols = p_cols;
        h.col_w = p_col_w;
        h.col_x0 = (SimConfig::WORLD_W - h.cols * h.col_w) / 2;
        h.crate_w = p_crate_w;
        h.crate_h = p_crate_h;
        h.max_height = p_max_height;
        h.pair = p_pair;
        for _i in 0..h.cols {
            h.heights.push(0);
        }
        for _i in 0..h.cols {
            h.coins.push(0);
        }
        h
    }

    pub fn _next_drop(&mut self, sim: Option<&GameSim>, warn: i64) {
        self.col = self._free_col(sim, G::posmod(SimHash::mix(self.salt, self.drops), self.cols), -1);
        self.col_b = -1;
        if self.pair && self.col >= 0 {
            self.col_b = self._free_col(sim, (self.col + self.cols / 2) % self.cols, self.col);
        }
        self.drops += 1;
        self.y = -self.crate_h;
        self.vy = 0;
        self.done = false;
        self.y_b = self.y;
        self.vy_b = 0;
        self.done_b = false;
        self.warn_left = warn;
    }

    pub fn _free_col(&self, sim: Option<&GameSim>, start: i64, skip: i64) -> i64 {
        for i in 0..self.cols {
            let c = (start + i) % self.cols;
            if c != skip
                && self.heights[c as usize] < self.max_height
                && (match sim {
                    None => true,
                    Some(s) => !self._col_in_exit(s, c),
                })
            {
                return c;
            }
        }
        -1
    }

    fn _col_in_exit(&self, sim: &GameSim, c: i64) -> bool {
        let x = self.col_left(c);
        ExitZone::hits_rect(sim, x, -self.crate_h, x + self.crate_w, Self::FLOOR)
    }

    fn _crate_in_exit(&self, sim: &GameSim, c: i64, top: i64) -> bool {
        let x = self.col_left(c);
        ExitZone::hits_rect(sim, x, top, x + self.crate_w, top + self.crate_h)
    }

    pub fn _land(&mut self, c: i64) {
        self.heights[c as usize] += 1;
        if self.gifts && self.heights[c as usize] == 1 {
            self.coins[c as usize] = 1;
        }
    }

    pub fn falling(&self) -> bool {
        self.col >= 0 && self.warn_left == 0
    }

    pub fn col_left(&self, c: i64) -> i64 {
        self.col_x0 + c * self.col_w + (self.col_w - self.crate_w) / 2
    }

    pub fn col_center(&self, c: i64) -> i64 {
        self.col_x0 + c * self.col_w + self.col_w / 2
    }

    pub fn _warn_col(&self, out_: &mut Vec<i64>, c: i64) {
        let land = self.stack_top(c) - self.crate_h;
        let mut top = -self.crate_h;
        let mut speed = 0;
        let mut dur = 0;
        while top < land {
            speed = G::mini(speed + Self::FALL_ACCEL, Self::MAX_FALL);
            top += speed;
            dur += 1;
        }
        let x = self.col_left(c);
        add_warning(out_, x, -self.crate_h, x + self.crate_w, self.stack_top(c), self.warn_left, dur, WARN_KILL);
    }

    pub fn stack_top(&self, c: i64) -> i64 {
        Self::FLOOR - self.heights[c as usize] * self.crate_h
    }

    pub fn coin_y(&self, c: i64) -> i64 {
        self.stack_top(c) - Self::COIN_LIFT - SimConfig::COIN_RADIUS
    }
}

impl Hazard for CrateDrop {
    impl_base!();

    fn setup(&mut self, _sim: &mut GameSim, rng: &mut SimRng) {
        self.salt = rng.next_u32();
        self._next_drop(None, Self::START_DELAY + Self::WARN_TICKS);
    }

    fn step(&mut self, sim: &mut GameSim) {
        if self.col < 0 {
            return;
        }
        if self.base.t == 1
            && (self._col_in_exit(sim, self.col) || (self.col_b >= 0 && self._col_in_exit(sim, self.col_b)))
        {
            self.drops -= 1;
            let warn = self.warn_left;
            self._next_drop(Some(sim), warn);
            if self.col < 0 {
                return;
            }
        }
        if self.warn_left > 0 {
            self.warn_left -= 1;
            return;
        }
        if !self.done && self._crate_in_exit(sim, self.col, self.y) {
            self.done = true;
        }
        if self.col_b >= 0 && !self.done_b && self._crate_in_exit(sim, self.col_b, self.y_b) {
            self.done_b = true;
        }
        if !self.done {
            self.vy = G::mini(self.vy + Self::FALL_ACCEL, Self::MAX_FALL);
            self.y += self.vy;
            let land = self.stack_top(self.col) - self.crate_h;
            if self.y >= land {
                self.y = land;
                self._land(self.col);
                self.done = true;
            }
        }
        if self.col_b >= 0 && !self.done_b {
            self.vy_b = G::mini(self.vy_b + Self::FALL_ACCEL, Self::MAX_FALL);
            self.y_b += self.vy_b;
            let land_b = self.stack_top(self.col_b) - self.crate_h;
            if self.y_b >= land_b {
                self.y_b = land_b;
                self._land(self.col_b);
                self.done_b = true;
            }
        }
        if self.done && (self.col_b < 0 || self.done_b) {
            self._next_drop(Some(sim), Self::WARN_TICKS);
        }
    }

    fn blocks_exit(&self, _sim: &GameSim, _side: i64, y: i64) -> bool {
        y > Self::FLOOR - self.max_height * self.crate_h - SimConfig::SLOT_SIZE
    }

    fn kills(&self, sim: &GameSim) -> bool {
        if self.falling() {
            if !self.done {
                let x = self.col_left(self.col);
                if sim.bird_touches_rect(x, self.y, x + self.crate_w, self.y + self.crate_h) {
                    return true;
                }
            }
            if self.col_b >= 0 && !self.done_b {
                let xb = self.col_left(self.col_b);
                if sim.bird_touches_rect(xb, self.y_b, xb + self.crate_w, self.y_b + self.crate_h) {
                    return true;
                }
            }
        }
        for c in 0..self.cols {
            if self.heights[c as usize] > 0 {
                let x = self.col_left(c);
                if sim.bird_touches_rect(x, self.stack_top(c), x + self.crate_w, SimConfig::WORLD_H) {
                    return true;
                }
            }
        }
        false
    }

    fn touch(&mut self, sim: &mut GameSim) {
        for c in 0..self.cols {
            if self.coins[c as usize] == 1
                && sim.bird_touches_circle(self.col_center(c), self.coin_y(c), SimConfig::COIN_RADIUS)
            {
                self.coins[c as usize] = 0;
                sim.collect_coin(self.col_center(c), self.coin_y(c), 1);
            }
        }
    }

    fn warnings(&self, _sim: &GameSim, out_: &mut Vec<i64>) {
        if self.col < 0 || self.warn_left <= 0 {
            return;
        }
        self._warn_col(out_, self.col);
        if self.col_b >= 0 {
            self._warn_col(out_, self.col_b);
        }
    }

    fn checksum(&self, h: i64) -> i64 {
        let mut out_ = mix_all(
            h,
            &[self.col, self.y, self.vy, self.warn_left, self.drops, self.salt, G::b(self.gifts)],
        );
        if self.pair {
            out_ = mix_all(out_, &[self.col_b, self.y_b, self.vy_b, G::b(self.done), G::b(self.done_b)]);
        }
        out_ = mix_all(out_, &self.heights);
        mix_all(out_, &self.coins)
    }
}
