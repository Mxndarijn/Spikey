//! Port of sim/hazards/gate.gd (Sim/Hazards/Gate.cs).
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Gate {
    pub base: Base,
    pub x: i64,
    pub follows: bool,
    /// The other gate of the pair (index into `room.hazards`), or None.
    pub partner: Option<usize>,
    pub period: i64,
    pub phase: i64,
    pub gap_y: i64,
    pub gap_size: i64,
    pub lo_y: i64,
    pub hi_y: i64,
    pub lag: i64,
}

#[inline]
fn gate_ref(h: &Hz) -> &Gate {
    match h {
        Hz::Gate(g) => g,
        _ => panic!("Gate.partner is not a Gate"),
    }
}

#[inline]
fn gate_mut(h: &mut Hz) -> &mut Gate {
    match h {
        Hz::Gate(g) => g,
        _ => panic!("Gate.partner is not a Gate"),
    }
}

impl Gate {
    pub const HALF_W: i64 = 8 * SimConfig::SUB;
    pub const GAP: i64 = 176 * SimConfig::SUB;
    pub const SMALL_GAP: i64 = 90 * SimConfig::SUB;
    pub const GAP_MIN_Y: i64 = 162 * SimConfig::SUB;
    pub const GAP_MAX_Y: i64 = 478 * SimConfig::SUB;
    pub const TOP: i64 = SimConfig::KILL_TOP;
    pub const BOTTOM: i64 = SimConfig::KILL_BOTTOM;
    pub const LAG: i64 = 40;
    pub const WALL_CLEAR: i64 = 80 * SimConfig::SUB;
    pub const ARRIVAL_HOVER: i64 = 30 * SimConfig::SUB;
    pub const EXIT_REACH: i64 = 80 * SimConfig::SUB;
    pub const SMALL_EXIT_MAX_Y: i64 = 490 * SimConfig::SUB;
    pub const GEN_SLACK: i64 = 8 * SimConfig::SUB;
    pub const GEN_LO_Y: i64 = 96 * SimConfig::SUB;
    pub const GEN_HI_Y: i64 = 500 * SimConfig::SUB;
    pub const GEN_GAP: i64 = 2 * SimConfig::EXIT_FIT
        + FairLanes::FIRST_HOP
        + 2 * (SimConfig::BIRD_RADIUS + VariantParams::MARGIN)
        + 2 * Self::GEN_SLACK;
    pub const GEN_LAG: i64 = 25;

    /// C# defaults: p_x = 0, p_period = 400, p_follows = false, p_gap = GAP.
    pub fn new(p_x: i64, p_period: i64, p_follows: bool, p_gap: i64) -> Gate {
        Gate {
            base: Base::new("gate"),
            x: p_x,
            follows: p_follows,
            partner: None,
            period: p_period,
            phase: 0,
            gap_y: 0,
            gap_size: p_gap,
            lo_y: Self::GAP_MIN_Y,
            hi_y: Self::GAP_MAX_Y,
            lag: Self::LAG,
        }
    }

    pub fn _start_crossing(&self, sim: &GameSim) -> Vec<i64> {
        let path = FairLanes::start_path(sim);
        let reach = Self::HALF_W + SimConfig::BIRD_RADIUS;
        let mut first: i64 = -1;
        let mut last: i64 = -1;
        let mut low: i64 = 0;
        let mut high: i64 = 0;
        for k in 0..(path.len() as i64) / 2 {
            if G::absi(path[(2 * k) as usize] - self.x) >= reach {
                if first >= 0 {
                    break;
                }
                continue;
            }
            let y = path[(2 * k + 1) as usize];
            if first < 0 {
                first = k;
                low = y;
                high = y;
            }
            last = k;
            low = G::mini(low, y);
            high = G::maxi(high, y);
        }
        if first < 0 {
            return Vec::new();
        }
        vec![(low + high) / 2, (first + last) / 2 + 1]
    }

    pub fn _lead(sim: &GameSim, gate_x: i64) -> i64 {
        G::absi(gate_x - sim.state.x) / SimConfig::SPEED_X
    }

    pub fn _place(&mut self) {
        self.gap_y = self.gap_at(self.base.t);
    }

    pub fn gap_at(&self, tick: i64) -> i64 {
        self.lo_y + SimTrig::ping_pong(tick + self.phase, self.period, self.hi_y - self.lo_y)
    }

    pub fn _phase_for(&self, y: i64, tick: i64, down: bool) -> i64 {
        let span = self.hi_y - self.lo_y;
        let at = G::clampi(y - self.lo_y, 0, span);
        let half = self.period / 2;
        let rising_phase = at * half / span;
        G::posmod((if down { rising_phase } else { self.period - rising_phase }) - tick, self.period)
    }

    pub fn _last_before<'a>(&'a self, sim: &'a GameSim, side: i64) -> &'a Gate {
        if let Some(pi) = self.partner {
            let p = gate_ref(&sim.room.hazards[pi]);
            if (p.x > self.x) == (side == 1) {
                return p;
            }
        }
        self
    }

    pub fn _steps_to_pass(sim: &GameSim, gate: &Gate, side: i64) -> i64 {
        let r = SimConfig::BIRD_RADIUS;
        let wall_x = if side == 1 { sim.room.wall_right() - r } else { sim.room.wall_left() + r };
        G::maxi(sim.steps_to_exit(side) - G::absi(wall_x - gate.x) / SimConfig::SPEED_X, 0)
    }

    /// Makes this a generated gate (see gate.gd `wide`). Before setup.
    pub fn wide(mut self) -> Gate {
        self.gap_size = Self::GEN_GAP;
        self.lo_y = Self::GEN_LO_Y;
        self.hi_y = Self::GEN_HI_Y;
        self.lag = Self::GEN_LAG;
        self
    }

    /// gate.gd `fit_arrival`: `gates` are indexes into `sim.room.hazards`, the leader first.
    pub fn fit_arrival(sim: &mut GameSim, p: &VariantParams, gates: &[usize]) -> bool {
        if !p.arriving {
            return true;
        }
        let (lead_phase, lead_period) = {
            let lead = gate_ref(&sim.room.hazards[gates[0]]);
            (lead.phase, lead.period)
        };
        for d in 0..lead_period {
            let ph = G::posmod(lead_phase + d, lead_period);
            if Self::_fits(sim, p, gates, ph) {
                for &i in gates {
                    let g = gate_mut(&mut sim.room.hazards[i]);
                    g.phase = G::posmod(ph - (if g.follows { g.lag } else { 0 }), g.period);
                    g._place();
                }
                return true;
            }
        }
        false
    }

    pub fn _fits(sim: &GameSim, p: &VariantParams, gates: &[usize], ph: i64) -> bool {
        let reach = Self::HALF_W + SimConfig::BIRD_RADIUS;
        for &i in gates {
            let g = gate_ref(&sim.room.hazards[i]);
            let gph = G::posmod(ph - (if g.follows { g.lag } else { 0 }), g.period);
            for k in 1..VariantCheck::HOLD_STEPS + 1 {
                if G::absi(FairLanes::arrival_x(sim, k) - g.x) >= reach {
                    continue;
                }
                let mid = g.lo_y + SimTrig::ping_pong(k + gph, g.period, g.hi_y - g.lo_y);
                if mid - g.gap_size / 2 > p.hold_top(sim) || mid + g.gap_size / 2 < p.hold_bottom(sim) {
                    return false;
                }
            }
        }
        true
    }

    pub fn gap_top(&self) -> i64 {
        self.gap_y - self.gap_size / 2
    }

    pub fn gap_bottom(&self) -> i64 {
        self.gap_y + self.gap_size / 2
    }
}

impl Hazard for Gate {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        self.partner = None;
        let n = sim.room.hazards.len();
        for i in 0..n {
            // C# `h != this`: our own slot holds Hz::Taken.
            if i == self.base.idx {
                continue;
            }
            if self.follows && sim.room.hazards[i].kind() == self.base.kind {
                self.partner = Some(i);
                gate_mut(&mut sim.room.hazards[i]).partner = Some(self.base.idx);
            }
        }
        if self.follows {
            if let Some(pi) = self.partner {
                let (p_x, p_period, p_lag) = {
                    let p = gate_ref(&sim.room.hazards[pi]);
                    (p.x, p.period, p.lag)
                };
                self.period = p_period;
                if sim.state.started && G::absi(self.x - sim.state.x) < G::absi(p_x - sim.state.x) {
                    let shift = Self::_lead(sim, p_x) - (Self::_lead(sim, self.x) - p_lag);
                    let period = self.period;
                    let p = gate_mut(&mut sim.room.hazards[pi]);
                    p.phase = G::posmod(p.phase + shift, period);
                    p._place();
                }
                let p_phase = gate_ref(&sim.room.hazards[pi]).phase;
                self.lag = p_lag;
                self.phase = G::posmod(p_phase - self.lag, self.period);
                self._place();
                return;
            }
        }
        let mut aim = FairLanes::entry_y(sim);
        let mut lead = 0;
        if sim.state.started {
            aim -= Self::ARRIVAL_HOVER * sim.room.gravity;
            lead = Self::_lead(sim, self.x);
        }
        let down = rng.next_below(2) == 0;
        if !sim.state.started && self.gap_size < Self::GAP {
            let through = self._start_crossing(sim);
            if !through.is_empty() {
                aim = through[0];
                lead = through[1];
            }
        }
        self.phase = self._phase_for(aim, lead, down);
        self._place();
    }

    fn step(&mut self, _sim: &mut GameSim) {
        self._place();
    }

    fn adjust_wall(&mut self, sim: &mut GameSim, side: i64, mask: i64) -> i64 {
        if self.follows {
            return mask;
        }
        let sim: &GameSim = sim;
        let s = &sim.state;
        let near = self._last_before(sim, side);
        let steps = G::absi(near.x - s.x) / SimConfig::SPEED_X;
        let gap = near.gap_at(self.base.t + steps);
        let mut out_ = mask;
        for slot in 0..SimConfig::SLOT_COUNT {
            if G::absi(SimConfig::slot_center_y(slot) - gap) < Self::WALL_CLEAR {
                out_ &= !(1i64 << slot);
            }
        }
        out_
    }

    fn blocks_exit(&self, sim: &GameSim, side: i64, y: i64) -> bool {
        if self.gap_size < Self::GAP && y > Self::SMALL_EXIT_MAX_Y {
            return true;
        }
        if self.follows && self.partner.is_some() {
            return false;
        }
        let last = self._last_before(sim, side);
        let gap = last.gap_at(self.base.t + Self::_steps_to_pass(sim, last, side));
        G::absi(y - gap) > Self::EXIT_REACH
    }

    fn kills(&self, sim: &GameSim) -> bool {
        if sim.bird_touches_rect(self.x - Self::HALF_W, Self::TOP, self.x + Self::HALF_W, self.gap_top()) {
            return true;
        }
        sim.bird_touches_rect(self.x - Self::HALF_W, self.gap_bottom(), self.x + Self::HALF_W, Self::BOTTOM)
    }

    fn checksum(&self, h: i64) -> i64 {
        let out_ = mix_all(h, &[self.x, self.period, self.phase, self.gap_y, G::b(self.follows), self.gap_size]);
        if self.lo_y != Self::GAP_MIN_Y || self.hi_y != Self::GAP_MAX_Y || self.lag != Self::LAG {
            return mix_all(out_, &[self.lo_y, self.hi_y, self.lag]);
        }
        out_
    }
}
