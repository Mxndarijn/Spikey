//! Port of sim/hazards/beam.gd (Sim/Hazards/Beam.cs).
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
}

impl Beam {
    pub const ROWS: i64 = 4;
    pub const PERIOD: i64 = 180;
    pub const WARN_TICKS: i64 = 40;
    pub const ON_TICKS: i64 = 50;
    pub const START_DELAY: i64 = 20;
    pub const BAND_TOP: i64 = 130 * SimConfig::SUB;
    pub const SPAN: i64 = 480 * SimConfig::SUB;
    pub const JITTER: i64 = 40 * SimConfig::SUB;
    pub const HALF_H: i64 = 6 * SimConfig::SUB;
    pub const YIELD_GAP: i64 = 2 * SimConfig::BIRD_RADIUS + 8 * SimConfig::SUB;
    pub const YIELD_LEAD: i64 = 20;

    /// C# defaults: count = ROWS, p_warn = WARN_TICKS, p_yields = false.
    pub fn new(count: i64, p_warn: i64, p_yields: bool) -> Beam {
        let mut b = Beam {
            base: Base::new("beam"),
            rows: Vec::new(),
            delays: Vec::new(),
            warn_ticks: Self::WARN_TICKS,
            yields: false,
            skip: Vec::new(),
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
}

impl Hazard for Beam {
    impl_base!();

    fn setup(&mut self, _sim: &mut GameSim, rng: &mut SimRng) {
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

    fn checksum(&self, h: i64) -> i64 {
        let mut out_ = mix_all(mix_all(h, &self.rows), &self.delays);
        if self.yields {
            out_ = mix_all(out_, &self.skip);
        }
        out_
    }
}
