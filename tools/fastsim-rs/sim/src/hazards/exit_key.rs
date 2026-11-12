//! Port of sim/hazards/exit_key.gd (Sim/Hazards/ExitKey.cs, Locked Out).
use crate::prelude::*;

/// C# `ExitKey.Mode`.
pub struct Mode;
impl Mode {
    pub const CLASSIC: i64 = 0;
    pub const ORBIT: i64 = 1;
    pub const TRIO: i64 = 2;
    pub const QUAD: i64 = 3;
    pub const CHAIN: i64 = 4;
}

#[derive(Clone, Debug)]
pub struct ExitKey {
    pub base: Base,
    pub mode: i64,
    pub count: i64,
    pub got: i64,
    pub taken_mask: i64,
    pub kx: [i64; 4],
    pub ky: [i64; 4],
    pub born: [i64; 4],
    pub chain_off: [i64; 4],
    pub chain_d: [i64; 4],
    pub phase: i64,
    pub locked_bounces: i64,
    pub walls_left: i64,
    pub walls_right: i64,
    pub door_open: bool,
    pub door_side: i64,
    pub door_a_y: i64,
    pub door_b_y: i64,
}

impl ExitKey {
    pub const SUB: i64 = SimConfig::SUB;
    pub const RADIUS: i64 = 12 * Self::SUB;
    pub const COINS: i64 = 3;
    pub const MAX_KEYS: i64 = 4;
    pub const MAX_LOCKED_BOUNCES: i64 = 8;
    pub const LOCKDOWN_MAX: i64 = 4;
    pub const KEY_OFF_MIN: i64 = 62 * Self::SUB;
    pub const KEY_OFF_MAX: i64 = 96 * Self::SUB;
    pub const KEY_MIN_Y: i64 = 130 * Self::SUB;
    pub const KEY_MAX_Y: i64 = 510 * Self::SUB;
    pub const SPOT_HALF: i64 = 30 * Self::SUB;
    pub const EXIT_NEAR: i64 = 100 * Self::SUB;
    pub const LAYOUT_TOP: i64 = 120;
    pub const LAYOUT_SPAN: i64 = 400;
    pub const LAYOUT_MARGIN: i64 = 15;
    pub const ZONE_LO: [i64; 3] = [62, 160, 264];
    pub const ZONE_HI: [i64; 3] = [96, 200, 298];
    pub const KEYS_APART: i64 = 110 * Self::SUB;
    pub const ZONE_APART: i64 = 150 * Self::SUB;
    pub const PLACE_TRIES: i64 = 12;
    pub const CHAIN_OFF_MAX: i64 = 150 * Self::SUB;
    pub const CHAIN_D_MIN: i64 = 160 * Self::SUB;
    pub const CHAIN_D_MAX: i64 = 200 * Self::SUB;
    pub const MID_Y: i64 = 320 * Self::SUB;
    pub const ORBIT_CX: i64 = 180 * Self::SUB;
    pub const ORBIT_CY: i64 = 330 * Self::SUB;
    pub const ORBIT_RX: i64 = 128 * Self::SUB;
    pub const ORBIT_RY: i64 = 165 * Self::SUB;
    pub const ORBIT_STEPS: i64 = 540;

    /// C# default: p_mode = -1 (pick from the room variant).
    pub fn new(p_mode: i64) -> ExitKey {
        ExitKey {
            base: Base::new("exit_key"),
            mode: p_mode,
            count: 1,
            got: 0,
            taken_mask: 0,
            kx: [0; 4],
            ky: [0; 4],
            born: [0; 4],
            chain_off: [0; 4],
            chain_d: [0; 4],
            phase: 0,
            locked_bounces: 0,
            walls_left: 0,
            walls_right: 0,
            door_open: false,
            door_side: 0,
            door_a_y: 0,
            door_b_y: 0,
        }
    }

    pub fn _lay_out(&mut self, rng: &mut SimRng) {
        let band = Self::LAYOUT_SPAN / self.count;
        let mut zones = [0i64; 4];
        for _attempt in 0..Self::PLACE_TRIES {
            let mut order: Vec<i64> = vec![0, 1, 2];
            for i in [2i64, 1] {
                let j = rng.next_below(i + 1) as usize;
                let swap = order[i as usize];
                order[i as usize] = order[j];
                order[j] = swap;
            }
            while (order.len() as i64) < self.count {
                order.push(if rng.next_below(2) == 0 { 0 } else { 2 });
            }
            for i in 0..self.count {
                let iu = i as usize;
                let z = order[iu];
                zones[iu] = z;
                let zu = z as usize;
                self.kx[iu] = (Self::ZONE_LO[zu] + rng.next_below(Self::ZONE_HI[zu] - Self::ZONE_LO[zu] + 1)) * Self::SUB;
                let top = Self::LAYOUT_TOP + i * band + Self::LAYOUT_MARGIN;
                self.ky[iu] = (top + rng.next_below(band - 2 * Self::LAYOUT_MARGIN + 1)) * Self::SUB;
            }
            if self._layout_ok(&zones) {
                return;
            }
        }
        for i in 0..self.count {
            let iu = i as usize;
            self.kx[iu] = (if i % 2 == 0 { 80 } else { 280 }) * Self::SUB;
            self.ky[iu] = (Self::LAYOUT_TOP + i * band + band / 2) * Self::SUB;
        }
    }

    pub fn _layout_ok(&self, zones: &[i64; 4]) -> bool {
        for i in 0..self.count as usize {
            for j in (i + 1)..self.count as usize {
                let dx = self.kx[i] - self.kx[j];
                let dy = self.ky[i] - self.ky[j];
                if dx * dx + dy * dy < Self::KEYS_APART * Self::KEYS_APART {
                    return false;
                }
                if zones[i] == zones[j] && G::absi(dy) < Self::ZONE_APART {
                    return false;
                }
            }
        }
        true
    }

    pub fn _from_wall(sim: &GameSim, side: i64, off: i64) -> i64 {
        if side == 0 {
            sim.room.wall_left() + off
        } else {
            sim.room.wall_right() - off
        }
    }

    pub fn _place_orbit(&mut self) {
        let a = self.phase + self.base.t * SimTrig::TURN / Self::ORBIT_STEPS;
        self.kx[0] = Self::ORBIT_CX + Self::ORBIT_RX * SimTrig::cos_t(a) / SimTrig::ONE;
        self.ky[0] = Self::ORBIT_CY + Self::ORBIT_RY * SimTrig::sin_t(a) / SimTrig::ONE;
    }

    pub fn done(&self) -> bool {
        self.got >= self.count
    }

    pub fn shown(&self, i: i64) -> bool {
        if i >= self.count || ((self.taken_mask >> i) & 1) == 1 {
            return false;
        }
        self.mode != Mode::CHAIN || i == self.got
    }

    pub fn _show_next(&mut self, sim: &GameSim, i: i64) {
        let s = &sim.state;
        let iu = i as usize;
        self.kx[iu] = Self::_from_wall(sim, if s.vx > 0 { 0 } else { 1 }, self.chain_off[iu]);
        let y = if s.y > Self::MID_Y { s.y - self.chain_d[iu] } else { s.y + self.chain_d[iu] };
        self.ky[iu] = G::clampi(y, Self::KEY_MIN_Y, Self::KEY_MAX_Y);
        self.born[iu] = self.base.t;
    }

    pub fn band_key(&self, side: i64) -> i64 {
        if self.mode == Mode::ORBIT {
            return -1;
        }
        for i in 0..self.count {
            if !self.shown(i) {
                continue;
            }
            let off = if side == 0 { self.kx[i as usize] } else { SimConfig::WORLD_W - self.kx[i as usize] };
            if off <= Self::CHAIN_OFF_MAX {
                return i;
            }
        }
        -1
    }

    pub fn _add_spikes(mask: i64, n: i64, keep: i64) -> i64 {
        let run = RoomRules::longest_gap_mask(mask);
        if run == 0 {
            return mask;
        }
        let mut lo: i64 = 0;
        while ((run >> lo) & 1) == 0 {
            lo += 1;
        }
        let mut hi = lo;
        while hi + 1 < SimConfig::SLOT_COUNT && ((run >> (hi + 1)) & 1) == 1 {
            hi += 1;
        }
        let mut out_ = mask;
        let mut added = 0;
        for d in 1..SimConfig::SLOT_COUNT {
            for slot in [lo - d, hi + d] {
                if added >= n {
                    return out_;
                }
                if slot < 0 || slot >= SimConfig::SLOT_COUNT {
                    continue;
                }
                if ((out_ >> slot) & 1) == 1 || ((keep >> slot) & 1) == 1 {
                    continue;
                }
                out_ |= 1i64 << slot;
                added += 1;
            }
        }
        out_
    }

    pub fn locked(&self) -> bool {
        !self.done() && self.locked_bounces < Self::MAX_LOCKED_BOUNCES
    }
}

impl Hazard for ExitKey {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        if self.mode < 0 {
            self.mode = match sim.room.variant_id() {
                "orbit" => Mode::ORBIT,
                "trio" => Mode::TRIO,
                "quad" => Mode::QUAD,
                "chain" => Mode::CHAIN,
                _ => Mode::CLASSIC,
            };
        }
        if self.mode == Mode::TRIO {
            self.count = 3;
        } else if self.mode == Mode::QUAD {
            self.count = 4;
        } else if self.mode == Mode::CHAIN {
            self.count = 3;
        } else {
            self.count = 1;
        }
        if self.mode == Mode::ORBIT {
            self.phase = rng.next_below(SimTrig::TURN);
            self._place_orbit();
        } else if self.mode == Mode::TRIO || self.mode == Mode::QUAD {
            self._lay_out(rng);
        } else {
            let side = rng.next_below(2);
            let off = Self::KEY_OFF_MIN + rng.next_below(Self::KEY_OFF_MAX - Self::KEY_OFF_MIN + 1);
            self.kx[0] = Self::_from_wall(sim, side, off);
            self.ky[0] = Self::KEY_MIN_Y + rng.next_below(Self::KEY_MAX_Y - Self::KEY_MIN_Y + 1);
            if self.mode == Mode::CHAIN {
                for i in 1..self.count as usize {
                    self.chain_off[i] = Self::KEY_OFF_MIN + rng.next_below(Self::CHAIN_OFF_MAX - Self::KEY_OFF_MIN + 1);
                    self.chain_d[i] = Self::CHAIN_D_MIN + rng.next_below(Self::CHAIN_D_MAX - Self::CHAIN_D_MIN + 1);
                }
            }
        }
    }

    fn step(&mut self, sim: &mut GameSim) {
        if self.mode == Mode::ORBIT && !self.done() {
            self._place_orbit();
        }
        let s = &sim.state;
        self.door_open = s.exit_open;
        self.door_side = s.exit_side;
        self.door_a_y = s.exit_a_y;
        self.door_b_y = if s.exit_b_kind != ExitKind::NORMAL { s.exit_b_y } else { 0 };
    }

    fn touch(&mut self, sim: &mut GameSim) {
        for i in 0..self.count {
            let iu = i as usize;
            if !self.shown(i) || !sim.bird_touches_circle(self.kx[iu], self.ky[iu], Self::RADIUS) {
                continue;
            }
            self.taken_mask |= 1i64 << i;
            self.got += 1;
            if self.count == 1 {
                for _c in 0..Self::COINS {
                    sim.collect_coin(self.kx[iu], self.ky[iu], 1);
                }
            } else {
                sim.collect_coin(self.kx[iu], self.ky[iu], 1);
                if self.done() {
                    sim.collect_coin(self.kx[iu], self.ky[iu], self.count);
                }
            }
            if self.mode == Mode::CHAIN && !self.done() {
                let got = self.got;
                self._show_next(sim, got);
            }
            return;
        }
    }

    fn adjust_wall(&mut self, sim: &mut GameSim, side: i64, mask: i64) -> i64 {
        let walls;
        if side == 0 {
            self.walls_left += 1;
            walls = self.walls_left;
        } else {
            self.walls_right += 1;
            walls = self.walls_right;
        }
        let mut out_ = mask;
        let mut spot = 0;
        let k = self.band_key(side);
        if k >= 0 && walls % 2 == 0 {
            for slot in 0..SimConfig::SLOT_COUNT {
                if G::absi(SimConfig::slot_center_y(slot) - self.ky[k as usize]) <= Self::SPOT_HALF {
                    spot |= 1i64 << slot;
                }
            }
            out_ &= !spot;
        }
        if sim.state.exit_open && self.locked() {
            out_ = Self::_add_spikes(out_, G::mini(Self::LOCKDOWN_MAX, self.locked_bounces + 1), spot);
        }
        out_
    }

    fn blocks_exit(&self, _sim: &GameSim, side: i64, y: i64) -> bool {
        let k = self.band_key(side);
        k >= 0 && G::absi(y - self.ky[k as usize]) > Self::EXIT_NEAR
    }

    fn locks_exit(&self, _sim: &GameSim) -> bool {
        self.locked()
    }

    fn on_bounce(&mut self, sim: &mut GameSim, _rng: &mut SimRng) {
        if sim.state.exit_open && !self.done() {
            self.locked_bounces += 1;
        }
    }

    fn checksum(&self, h: i64) -> i64 {
        let mut out_ = mix_all(
            h,
            &[
                self.mode,
                self.count,
                self.got,
                self.taken_mask,
                self.phase,
                self.locked_bounces,
                self.walls_left,
                self.walls_right,
                G::b(self.door_open),
                self.door_side,
                self.door_a_y,
                self.door_b_y,
            ],
        );
        for i in 0..Self::MAX_KEYS as usize {
            out_ = mix_all(out_, &[self.kx[i], self.ky[i], self.born[i], self.chain_off[i], self.chain_d[i]]);
        }
        out_
    }
}
