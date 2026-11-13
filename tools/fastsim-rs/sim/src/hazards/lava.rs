//! Port of sim/hazards/lava.gd (Sim/Hazards/Lava.cs).
use crate::prelude::*;

/// C# `Lava.Mode`.
pub struct Mode;
impl Mode {
    pub const STONE: i64 = 0;
    pub const COLD: i64 = 1;
    pub const RAFTS: i64 = 2;
}

#[derive(Clone, Debug)]
pub struct Lava {
    pub base: Base,
    pub mode: i64,
    pub line: i64,
    pub rises: i64,
    pub counted: i64,
    pub stone_on: bool,
    pub stone_x: i64,
    pub stone_y: i64,
    pub ice_on: bool,
    pub ice_side: i64,
    pub ice_slot: i64,
    pub raft_on: [bool; 2],
    pub raft_x: [i64; 2],
    pub raft_dir: [i64; 2],
    pub raft_age: [i64; 2],
    pub raft_points: i64,
    pub plan_x: Vec<i64>,
    pub plan_dir: Vec<i64>,
}

impl Lava {
    pub const SUB: i64 = SimConfig::SUB;
    pub const STEP: i64 = 30 * Self::SUB;
    pub const MAX_RISES: i64 = 9;
    pub const RAFT_MAX_RISES: i64 = (SimConfig::KILL_BOTTOM - SimConfig::KILL_TOP) / Self::STEP + 1;
    pub const SPEED: i64 = 80;
    pub const STONE_RADIUS: i64 = 14 * Self::SUB;
    pub const STONE_AFTER: i64 = 3;
    pub const STONE_CLEAR: i64 = 90 * Self::SUB;
    pub const STONE_EDGE: i64 = 80 * Self::SUB;
    pub const EXIT_CLEAR: i64 = SimConfig::BIRD_RADIUS + 24 * Self::SUB;
    pub const RUN: i64 = 3;
    pub const ICE_DEPTH: i64 = 12 * Self::SUB;
    pub const ICE_AWAY: i64 = 80 * Self::SUB;
    pub const RAFT_HALF: i64 = 32 * Self::SUB;
    pub const RAFT_HIGH: i64 = 8 * Self::SUB;
    pub const RAFT_SPEED: i64 = 32;
    pub const RAFT_X_MIN: i64 = 70 * Self::SUB + Self::RAFT_HALF;
    pub const RAFT_X_MAX: i64 = SimConfig::WORLD_W - 70 * Self::SUB - Self::RAFT_HALF;
    pub const RAFT_EVERY: i64 = 2;
    pub const RAFT_FROM: i64 = 2;
    pub const RAFT_TWO: i64 = 5;
    pub const MAX_RAFTS: i64 = 2;
    pub const RAFT_RISE: i64 = 60;
    pub const RAFT_SINK: i64 = 2;
    pub const RAFT_VY: i64 = SimConfig::FLAP_VY * 6 / 5;
    pub const RAFT_GAP: i64 = 12 * Self::SUB;
    pub const RAFT_APART: i64 = 2 * Self::RAFT_HALF + Self::RAFT_GAP;
    pub const RAFT_PLAN: i64 = 6;

    pub fn new() -> Lava {
        Lava {
            base: Base::new("lava"),
            mode: Mode::STONE,
            line: SimConfig::KILL_BOTTOM,
            rises: 0,
            counted: 0,
            stone_on: false,
            stone_x: 0,
            stone_y: 0,
            ice_on: false,
            ice_side: 0,
            ice_slot: 0,
            raft_on: [false, false],
            raft_x: [0, 0],
            raft_dir: [1, 1],
            raft_age: [0, 0],
            raft_points: 0,
            plan_x: Vec::new(),
            plan_dir: Vec::new(),
        }
    }

    pub fn rest(&self) -> i64 {
        SimConfig::KILL_BOTTOM
    }

    pub fn line_at(&self, n: i64) -> i64 {
        SimConfig::KILL_BOTTOM - n * Self::STEP
    }

    pub fn draw_plan(&mut self, rng: &mut SimRng) {
        self.plan_x.clear();
        self.plan_dir.clear();
        for _k in 0..Self::RAFT_PLAN {
            self.plan_x.push(Self::RAFT_X_MIN + rng.next_below(Self::RAFT_X_MAX - Self::RAFT_X_MIN + 1));
            self.plan_dir.push(if rng.next_below(2) == 0 { 1 } else { -1 });
        }
    }

    pub fn max_rises(&self) -> i64 {
        if self.mode == Mode::RAFTS {
            Self::RAFT_MAX_RISES
        } else {
            Self::MAX_RISES
        }
    }

    pub fn rises_due(&self, sim: &GameSim) -> i64 {
        if sim.state.exit_open {
            return self.rises;
        }
        G::mini(self.rises + sim.room.points - self.counted, self.max_rises())
    }

    pub fn _raft_under(&self, sim: &GameSim) -> i64 {
        for i in 0..Self::MAX_RAFTS as usize {
            if self.raft_on[i] && self.raft_age[i] >= Self::RAFT_RISE {
                if G::absi(sim.state.x - self.raft_x[i]) <= Self::RAFT_HALF {
                    return i as i64;
                }
            }
        }
        -1
    }

    pub fn ice_x0(&self, sim: &GameSim) -> i64 {
        if self.ice_side == 0 {
            sim.room.wall_left()
        } else {
            sim.room.wall_right() - Self::ICE_DEPTH
        }
    }

    pub fn ice_x1(&self, sim: &GameSim) -> i64 {
        if self.ice_side == 0 {
            sim.room.wall_left() + Self::ICE_DEPTH
        } else {
            sim.room.wall_right()
        }
    }

    pub fn ice_y0(&self) -> i64 {
        SimConfig::slot_center_y(self.ice_slot) - SimConfig::SLOT_SIZE / 2
    }

    pub fn ice_y1(&self) -> i64 {
        SimConfig::slot_center_y(self.ice_slot) + SimConfig::SLOT_SIZE / 2
    }

    pub fn _slot_clear(slot: i64, edge: i64) -> bool {
        let cy = SimConfig::slot_center_y(slot);
        let half = SimConfig::SLOT_SIZE / 2;
        cy + half <= edge - SimConfig::BIRD_RADIUS
    }

    pub fn _place_ice(&mut self, sim: &GameSim, rng: &mut SimRng) {
        if self.ice_on || self.rises < Self::STONE_AFTER {
            return;
        }
        let heading = self.line_at(self.rises);
        let lo = SimConfig::KILL_TOP + Self::STONE_EDGE;
        let hi = heading - Self::STONE_CLEAR;
        let mut count = 0;
        for slot in 0..SimConfig::SLOT_COUNT {
            if Self::_ice_fits(sim, slot, lo, hi) {
                count += 1;
            }
        }
        if count == 0 {
            return;
        }
        let mut pick = rng.next_below(count);
        for slot in 0..SimConfig::SLOT_COUNT {
            if !Self::_ice_fits(sim, slot, lo, hi) {
                continue;
            }
            if pick == 0 {
                self.ice_slot = slot;
                break;
            }
            pick -= 1;
        }
        self.ice_side = if sim.state.vx > 0 { 0 } else { 1 };
        self.ice_on = true;
    }

    pub fn _ice_fits(sim: &GameSim, slot: i64, lo: i64, hi: i64) -> bool {
        let cy = SimConfig::slot_center_y(slot);
        cy >= lo && cy <= hi && G::absi(cy - sim.state.anchor_y) >= Self::ICE_AWAY
    }

    pub fn _place_raft(&mut self, sim: &GameSim) {
        if self.rises < Self::RAFT_FROM || sim.room.points - self.raft_points < Self::RAFT_EVERY {
            return;
        }
        let allowed = if self.rises >= Self::RAFT_TWO { Self::MAX_RAFTS } else { 1 };
        let mut out_ = 0;
        let mut free: i64 = -1;
        for i in 0..Self::MAX_RAFTS {
            if self.raft_on[i as usize] {
                out_ += 1;
            } else if free < 0 {
                free = i;
            }
        }
        if out_ >= allowed || free < 0 {
            return;
        }
        let f = free as usize;
        let k = ((sim.room.points / Self::RAFT_EVERY) % Self::RAFT_PLAN) as usize;
        let mut x = self.plan_x[k];
        let mut way = self.plan_dir[k];
        let other = 1 - f;
        if self.raft_on[other] && G::absi(x - self.raft_x[other]) < Self::RAFT_APART {
            let o = self.raft_x[other];
            let mut side = if x >= o { 1 } else { -1 };
            if o + side * Self::RAFT_APART < Self::RAFT_X_MIN || o + side * Self::RAFT_APART > Self::RAFT_X_MAX {
                side = -side;
            }
            x = o + side * Self::RAFT_APART;
            way = side;
        }
        self.raft_x[f] = x;
        self.raft_dir[f] = way;
        self.raft_age[f] = 0;
        self.raft_on[f] = true;
        self.raft_points = sim.room.points;
    }
}

impl Hazard for Lava {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        self.mode = match sim.room.variant_id() {
            "cold" => Mode::COLD,
            "rafts" => Mode::RAFTS,
            _ => Mode::STONE,
        };
        self.line = self.rest();
        self.counted = sim.room.points;
        self.raft_points = sim.room.points;
        if self.mode == Mode::RAFTS {
            self.draw_plan(rng);
        }
    }

    fn step(&mut self, _sim: &mut GameSim) {
        self.line += G::clampi(self.line_at(self.rises) - self.line, -Self::SPEED, Self::SPEED);
        for i in 0..Self::MAX_RAFTS as usize {
            if !self.raft_on[i] {
                continue;
            }
            self.raft_age[i] += 1;
            self.raft_x[i] += self.raft_dir[i] * Self::RAFT_SPEED;
            if self.raft_x[i] <= Self::RAFT_X_MIN || self.raft_x[i] >= Self::RAFT_X_MAX {
                self.raft_x[i] = G::clampi(self.raft_x[i], Self::RAFT_X_MIN, Self::RAFT_X_MAX);
                self.raft_dir[i] = -self.raft_dir[i];
            }
        }
        if self.raft_on[0] && self.raft_on[1] {
            let d = self.raft_x[1] - self.raft_x[0];
            if G::absi(d) <= Self::RAFT_APART && (self.raft_dir[1] - self.raft_dir[0]) * G::signi(d) < 0 {
                self.raft_dir[0] = -self.raft_dir[0];
                self.raft_dir[1] = -self.raft_dir[1];
            }
        }
    }

    fn kills(&self, sim: &GameSim) -> bool {
        let r = SimConfig::BIRD_RADIUS;
        if self.line >= SimConfig::KILL_BOTTOM || sim.state.y + r < self.line {
            return false;
        }
        self._raft_under(sim) < 0
    }

    fn touch(&mut self, sim: &mut GameSim) {
        if self.stone_on && sim.bird_touches_circle(self.stone_x, self.stone_y, Self::STONE_RADIUS) {
            self.stone_on = false;
            self.rises = 0;
        }
        if self.ice_on && sim.bird_touches_rect(self.ice_x0(sim), self.ice_y0(), self.ice_x1(sim), self.ice_y1()) {
            self.ice_on = false;
            self.rises = 0;
        }
        let r = SimConfig::BIRD_RADIUS;
        for i in 0..Self::MAX_RAFTS as usize {
            if !self.raft_on[i] || self.raft_age[i] < Self::RAFT_RISE {
                continue;
            }
            let x0 = self.raft_x[i] - Self::RAFT_HALF;
            let x1 = self.raft_x[i] + Self::RAFT_HALF;
            let top = self.line - Self::RAFT_HIGH;
            let over = self._raft_under(sim) == i as i64 && sim.state.y + r >= top;
            if over || sim.bird_touches_rect(x0, top, x1, self.line) {
                self.raft_on[i] = false;
                self.rises = G::maxi(self.rises - Self::RAFT_SINK, 0);
                sim.state.y = G::mini(sim.state.y, top - r - 1);
                sim.state.vy = Self::RAFT_VY;
                return;
            }
        }
    }

    fn adjust_wall(&mut self, sim: &mut GameSim, side: i64, mut mask: i64) -> i64 {
        if self.ice_on && side == self.ice_side {
            let mut slot = G::maxi(self.ice_slot - 1, 0);
            while slot < G::mini(self.ice_slot + 2, SimConfig::SLOT_COUNT) {
                mask &= !(1i64 << slot);
                slot += 1;
            }
        }
        if mask == 0 {
            return mask;
        }
        let edge = self.line_at(self.rises_due(sim));
        let mut run = 0;
        let mut first_ok: i64 = -1;
        let mut last_ok: i64 = -1;
        for slot in 0..SimConfig::SLOT_COUNT {
            if !Self::_slot_clear(slot, edge) {
                run = 0;
                continue;
            }
            if first_ok < 0 {
                first_ok = slot;
            }
            last_ok = slot;
            run = if RoomRules::has_slot(mask, slot) { 0 } else { run + 1 };
            if run >= Self::RUN {
                return mask;
            }
        }
        if first_ok < 0 {
            return mask;
        }
        if last_ok - first_ok + 1 < Self::RUN {
            for slot in first_ok..(last_ok + 1) {
                mask &= !(1i64 << slot);
            }
            return mask;
        }
        let c0 = SimConfig::slot_center_y(0);
        let near = (sim.state.anchor_y - c0 + SimConfig::SLOT_SIZE / 2) / SimConfig::SLOT_SIZE;
        let mid = G::clampi(near, first_ok + 1, last_ok - 1);
        for slot in (mid - 1)..(mid + 2) {
            mask &= !(1i64 << slot);
        }
        mask
    }

    fn on_bounce(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        self.rises = self.rises_due(sim);
        self.counted = sim.room.points;
        if self.mode == Mode::COLD {
            self._place_ice(sim, rng);
            return;
        }
        if self.mode == Mode::RAFTS {
            self._place_raft(sim);
            return;
        }
        if self.stone_on || self.rises < Self::STONE_AFTER {
            return;
        }
        let heading = self.line_at(self.rises);
        let lo = SimConfig::KILL_TOP + Self::STONE_EDGE;
        let hi = heading - Self::STONE_CLEAR;
        self.stone_x = (110 + rng.next_below(141)) * Self::SUB;
        self.stone_y = lo + rng.next_below(G::maxi(hi - lo, 0) + 1);
        self.stone_on = true;
    }

    fn blocks_exit(&self, sim: &GameSim, _side: i64, y: i64) -> bool {
        let worst = self.line_at(G::mini(self.rises_due(sim) + sim.points_to_exit(), self.max_rises()));
        y > worst - Self::EXIT_CLEAR
    }

    fn checksum(&self, h: i64) -> i64 {
        let mut out_ = mix_all(
            h,
            &[self.mode, self.line, self.rises, self.counted, G::b(self.stone_on), self.stone_x, self.stone_y],
        );
        if self.mode == Mode::COLD {
            out_ = mix_all(out_, &[G::b(self.ice_on), self.ice_side, self.ice_slot]);
        } else if self.mode == Mode::RAFTS {
            out_ = mix_all(out_, &[self.raft_points]);
            for i in 0..Self::MAX_RAFTS as usize {
                out_ = mix_all(out_, &[G::b(self.raft_on[i]), self.raft_x[i], self.raft_dir[i], self.raft_age[i]]);
            }
        }
        out_
    }
}
