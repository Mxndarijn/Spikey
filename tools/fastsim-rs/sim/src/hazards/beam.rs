//! Port of sim/hazards/beam.gd (Sim/Hazards/Beam.cs).
use crate::rooms::hazard::{add_warning, WARN_KILL};
use crate::prelude::*;

pub struct State;
impl State {
    pub const OFF: i64 = 0;
    pub const WARN: i64 = 1;
    pub const ON: i64 = 2;
}

#[derive(Clone, Debug)]
pub struct Beam {
    pub base: Base,
    pub rows: Vec<i64>,
    pub delays: Vec<i64>,
    pub warn_ticks: i64,
    pub yields: bool,
    pub skip: Vec<i64>,
    pub preset: bool,
    pub exit_ys: Vec<i64>,
    pub calm_spikes: i64,
}

impl Beam {
    pub const ROWS: i64 = 4;
    pub const PERIOD: i64 = 180;
    pub const WARN_TICKS: i64 = SimConfig::WARN_TICKS;
    pub const ON_TICKS: i64 = 50;
    pub const START_DELAY: i64 = 20;
    pub const BAND_TOP: i64 = 130 * SimConfig::SUB;
    pub const SPAN: i64 = 480 * SimConfig::SUB;
    pub const JITTER: i64 = 40 * SimConfig::SUB;
    pub const HALF_H: i64 = 6 * SimConfig::SUB;
    pub const YIELD_GAP: i64 = 2 * SimConfig::BIRD_RADIUS + 8 * SimConfig::SUB;
    pub const YIELD_LEAD: i64 = 20;
    pub const WALL_FROM: i64 = -6;
    pub const WALL_TO: i64 = 30;
    pub const WALL_STEP: i64 = 6;
    pub const MARGIN: i64 = 4 * SimConfig::SUB;
    pub const REACH_UP: i64 = 2 * SimConfig::SUB;
    pub const REACH_DOWN: i64 = 4 * SimConfig::SUB;
    pub const REACH_SPARE: i64 = 10;

    /// C# defaults: count = ROWS, p_warn = WARN_TICKS, p_yields = false.
    pub fn new(count: i64, p_warn: i64, p_yields: bool) -> Beam {
        let mut b = Beam {
            base: Base::new("beam"),
            rows: Vec::new(),
            delays: Vec::new(),
            warn_ticks: Self::WARN_TICKS,
            yields: false,
            skip: Vec::new(),
            preset: false,
            exit_ys: Vec::new(),
            calm_spikes: 0,
        };
        for _i in 0..count {
            b.rows.push(0);
            b.delays.push(0);
            b.skip.push(0);
        }
        b.warn_ticks = p_warn;
        b.yields = p_yields;
        b
    }

    pub fn cycle_pos(&self, i: i64) -> i64 {
        if self.base.t < self.delays[i as usize] {
            return -1;
        }
        G::posmod(self.base.t - self.delays[i as usize], Self::PERIOD)
    }

    pub fn state(&self, i: i64) -> i64 {
        let p = self.cycle_pos(i);
        if p < 0 || p >= self.warn_ticks + Self::ON_TICKS || self.skip[i as usize] == 1 {
            return State::OFF;
        }
        if p < self.warn_ticks {
            State::WARN
        } else {
            State::ON
        }
    }

    pub fn warn_progress(&self, i: i64) -> i64 {
        if self.state(i) != State::WARN {
            return 0;
        }
        SimTrig::ONE * self.cycle_pos(i) / self.warn_ticks
    }

    pub fn live_count(&self) -> i64 {
        let mut n = 0;
        for i in 0..self.rows.len() as i64 {
            if self.state(i) == State::ON {
                n += 1;
            }
        }
        n
    }

    pub fn beam_left(&self, sim: &GameSim, i: i64) -> i64 {
        if self._crosses_exit(sim, i, 0) {
            return ExitZone::right_on(sim, 0) + 1;
        }
        sim.room.wall_left()
    }

    pub fn beam_right(&self, sim: &GameSim, i: i64) -> i64 {
        if self._crosses_exit(sim, i, 1) {
            return ExitZone::left_on(sim, 1) - 1;
        }
        sim.room.wall_right()
    }

    fn _crosses_exit(&self, sim: &GameSim, i: i64, side: i64) -> bool {
        ExitZone::hits_rect_on(
            sim,
            side,
            sim.room.wall_left(),
            self.rows[i as usize] - Self::HALF_H,
            sim.room.wall_right(),
            self.rows[i as usize] + Self::HALF_H,
        )
    }

    /// Steps a bird at `y` at step `t` needs to get into `lo`..`hi` (beam.gd).
    pub fn reach_time(p_rows: &[i64], p_delays: &[i64], y: i64, t: i64, lo: i64, hi: i64) -> i64 {
        let t0 = t;
        let mut t = t;
        if y >= lo && y <= hi {
            return 0;
        }
        let down = y < lo;
        let target = if down { lo } else { hi };
        let speed = if down { Self::REACH_DOWN } else { Self::REACH_UP };
        let reach = Self::HALF_H + SimConfig::BIRD_RADIUS;
        let mut order: Vec<usize> = Vec::new();
        for i in 0..p_rows.len() {
            let r = p_rows[i];
            if (down && r > y && r < target) || (!down && r < y && r > target) {
                order.push(i);
            }
        }
        if !down {
            order.reverse();
        }
        let mut at = y;
        for i in order {
            let near = if down { p_rows[i] - reach } else { p_rows[i] + reach };
            t += G::absi(near - at) / speed;
            let cross = 2 * reach / speed;
            t += Self::_wait_off(p_delays[i], t, cross);
            t += cross;
            at = if down { p_rows[i] + reach } else { p_rows[i] - reach };
        }
        t += G::absi(target - at) / speed;
        t - t0
    }


    /// Slots of wall side (drawn now, met after the other wall) a bird gets to in time from
    /// every free slot of the other wall (reach_time, REACH_SPARE to spare); all slots if the
    /// bird meets side first.
    pub fn reachable_slots(&self, sim: &GameSim, side: i64) -> i64 {
        let all = (1i64 << SimConfig::SLOT_COUNT) - 1;
        let heading = if sim.state.vx > 0 { 1 } else { 0 };
        if heading == side {
            return all;
        }
        let first = sim.steps_to_wall(heading);
        let c = sim.steps_to_wall(side) - first;
        let other = if heading == 0 { sim.state.left_spikes } else { sim.state.right_spikes };
        let t_b = self.base.t + first;
        let half = SimConfig::SLOT_SIZE / 2;
        let mut out_ = 0;
        for slot in 0..SimConfig::SLOT_COUNT {
            let cy = SimConfig::slot_center_y(slot);
            let mut ok = true;
            for from in 0..SimConfig::SLOT_COUNT {
                if RoomRules::has_slot(other, from) {
                    continue;
                }
                let to = Self::reach_time(&self.rows, &self.delays, SimConfig::slot_center_y(from), t_b, cy - half, cy + half);
                if to > c - Self::REACH_SPARE {
                    ok = false;
                    break;
                }
            }
            if ok {
                out_ |= 1i64 << slot;
            }
        }
        out_
    }

    pub fn _wait_off(d: i64, t: i64, length: i64) -> i64 {
        let q = G::posmod(t - d - Self::WARN_TICKS, Self::PERIOD);
        if q < Self::ON_TICKS {
            return Self::ON_TICKS - q;
        }
        if q + length > Self::PERIOD {
            return Self::PERIOD - q + Self::ON_TICKS;
        }
        0
    }

    /// True if row i's beam is live `steps` from now (a turn it might sit out
    /// counts as live).
    pub fn live_in(&self, i: i64, steps: i64) -> bool {
        let at = self.base.t + steps;
        if at < self.delays[i as usize] {
            return false;
        }
        let p = G::posmod(at - self.delays[i as usize], Self::PERIOD);
        p >= self.warn_ticks && p < self.warn_ticks + Self::ON_TICKS
    }
}

impl Hazard for Beam {
    impl_base!();

    fn setup(&mut self, _sim: &mut GameSim, rng: &mut SimRng) {
        if self.preset {
            return;
        }
        let n = self.rows.len() as i64;
        let band = Self::SPAN / n;
        let stagger = Self::PERIOD / n;
        let mut order: Vec<i64> = Vec::new();
        for i in 0..n {
            order.push(i);
        }
        // Fisher-Yates: the order rows fire in.
        let mut i = n - 1;
        while i > 0 {
            let j = rng.next_below(i + 1);
            let tmp = order[i as usize];
            order[i as usize] = order[j as usize];
            order[j as usize] = tmp;
            i -= 1;
        }
        for i in 0..n {
            self.rows[i as usize] = Self::BAND_TOP + i * band + rng.next_below(Self::JITTER + 1);
            self.delays[i as usize] = Self::START_DELAY + order[i as usize] * stagger;
        }
    }

    fn step(&mut self, sim: &mut GameSim) {
        if !self.yields {
            return;
        }
        let sim: &GameSim = sim;
        for i in 0..self.rows.len() as i64 {
            if self.cycle_pos(i) != 0 {
                continue;
            }
            self.skip[i as usize] = 0;
            for (j, h) in sim.room.hazards.iter().enumerate() {
                // C# `h == this`: our own slot holds Hz::Taken, skipped here.
                if j == self.base.idx || !h.alive() {
                    continue;
                }
                let half = Self::HALF_H + Self::YIELD_GAP;
                if h.near_row(
                    sim,
                    self.rows[i as usize],
                    half,
                    self.warn_ticks - Self::YIELD_LEAD,
                    self.warn_ticks + Self::ON_TICKS,
                ) {
                    self.skip[i as usize] = 1;
                }
            }
        }
    }

    fn adjust_wall(&mut self, sim: &mut GameSim, side: i64, mask: i64) -> i64 {
        let at = sim.steps_to_wall(side);
        let reach = Self::HALF_H + SimConfig::BIRD_RADIUS + Self::MARGIN;
        let mut blocked = 0;
        for i in 0..self.rows.len() as i64 {
            let mut live = false;
            let mut d = Self::WALL_FROM;
            while d < Self::WALL_TO + 1 {
                if self.live_in(i, at + d) {
                    live = true;
                }
                d += Self::WALL_STEP;
            }
            if !live {
                continue;
            }
            for slot in 0..SimConfig::SLOT_COUNT {
                if G::absi(SimConfig::slot_center_y(slot) - self.rows[i as usize]) < reach {
                    blocked |= 1i64 << slot;
                }
            }
        }
        let mut safe = ((1i64 << SimConfig::SLOT_COUNT) - 1) & !blocked;
        let mut need = G::mini(sim.room.def().gap, RoomRules::longest_gap(blocked));
        // Generated Beam Gates: the free run is also one a bird can get to through the beams from
        // anywhere in the other wall's free run, the wall it bounces off first.
        if self.calm_spikes > 0 {
            let reach = self.reachable_slots(sim, side);
            let both = safe & reach;
            let both_need = G::mini(sim.room.def().gap, RoomRules::longest_gap(((1i64 << SimConfig::SLOT_COUNT) - 1) & !both));
            if both_need > 0 {
                safe = both;
                need = both_need;
            }
        }
        let mut out_ = RoomRules::keep_run(mask, need, safe);
        // Generated Beam Gates: a wall the bird gets to once the exit's ghost shows keeps at most
        // calm_spikes, those farthest from the exit's height staying.
        if self.calm_spikes > 0 && !self.exit_ys.is_empty() {
            let heading = if sim.state.vx > 0 { 1 } else { 0 };
            let hits = if heading == side { 1 } else { 2 };
            if sim.state.exit_open || sim.state.exit_preview || sim.state.score + hits >= sim.next_exit_score() - 1 {
                let e = self.exit_ys[0];
                while (out_ as u64).count_ones() as i64 > self.calm_spikes {
                    let mut near = -1;
                    for slot in 0..SimConfig::SLOT_COUNT {
                        if RoomRules::has_slot(out_, slot)
                            && (near < 0 || G::absi(SimConfig::slot_center_y(slot) - e) < G::absi(SimConfig::slot_center_y(near) - e))
                        {
                            near = slot;
                        }
                    }
                    out_ &= !(1i64 << near);
                }
            }
        }
        out_
    }

    fn kills(&self, sim: &GameSim) -> bool {
        for i in 0..self.rows.len() as i64 {
            if self.state(i) == State::ON {
                let y0 = self.rows[i as usize] - Self::HALF_H;
                let y1 = self.rows[i as usize] + Self::HALF_H;
                if sim.bird_touches_rect(self.beam_left(sim, i), y0, self.beam_right(sim, i), y1) {
                    return true;
                }
            }
        }
        false
    }

    fn warnings(&self, sim: &GameSim, out_: &mut Vec<i64>) {
        for i in 0..self.rows.len() as i64 {
            if self.state(i) != State::WARN {
                continue;
            }
            let r = self.rows[i as usize];
            add_warning(out_, self.beam_left(sim, i), r - Self::HALF_H, self.beam_right(sim, i), r + Self::HALF_H,
                self.warn_ticks - self.cycle_pos(i), Self::ON_TICKS, WARN_KILL);
        }
    }

    fn checksum(&self, h: i64) -> i64 {
        let mut out_ = mix_all(mix_all(h, &self.rows), &self.delays);
        if self.yields {
            out_ = mix_all(out_, &self.skip);
        }
        out_
    }
}
