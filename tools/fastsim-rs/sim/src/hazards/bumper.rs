//! Port of sim/hazards/bumper.gd (Sim/Hazards/Bumper.cs).
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Bumper {
    pub base: Base,
    pub radius: i64,
    pub loop_rx: i64,
    pub loop_ry: i64,
    pub period: i64,
    pub x: i64,
    pub y: i64,
    pub phase: i64,
    pub dir: i64,
    pub follows: bool,
}

impl Bumper {
    pub const RADIUS: i64 = 28 * SimConfig::SUB;
    pub const CENTER_X: i64 = 180 * SimConfig::SUB;
    pub const CENTER_Y: i64 = 320 * SimConfig::SUB;
    pub const LOOP_RX: i64 = 80 * SimConfig::SUB;
    pub const LOOP_RY: i64 = 140 * SimConfig::SUB;
    pub const PERIOD: i64 = 600;
    pub const BIG_RADIUS: i64 = 42 * SimConfig::SUB;
    pub const BIG_LOOP_RX: i64 = 56 * SimConfig::SUB;
    pub const BIG_PERIOD: i64 = 720;
    pub const ORBIT_R: i64 = 96 * SimConfig::SUB;
    pub const ORBIT_PERIOD: i64 = 480;

    /// C# default: p_follows = false.
    pub fn new(p_follows: bool) -> Bumper {
        Bumper {
            base: Base::new("bumper"),
            radius: Self::RADIUS,
            loop_rx: Self::LOOP_RX,
            loop_ry: Self::LOOP_RY,
            period: Self::PERIOD,
            x: 0,
            y: 0,
            phase: 0,
            dir: 1,
            follows: p_follows,
        }
    }

    pub fn big(mut self) -> Bumper {
        self.radius = Self::BIG_RADIUS;
        self.loop_rx = Self::BIG_LOOP_RX;
        self.period = Self::BIG_PERIOD;
        self
    }

    pub fn orbit(mut self) -> Bumper {
        self.loop_rx = Self::ORBIT_R;
        self.loop_ry = Self::ORBIT_R;
        self.period = Self::ORBIT_PERIOD;
        self
    }

    pub fn _place(&mut self) {
        let a = self.phase + self.dir * (self.base.t * SimTrig::TURN / self.period);
        self.x = Self::CENTER_X + self.loop_rx * SimTrig::cos_t(a) / SimTrig::ONE;
        self.y = Self::CENTER_Y + self.loop_ry * SimTrig::sin_t(a) / SimTrig::ONE;
    }
}

impl Hazard for Bumper {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        if self.follows {
            let hs = &sim.room.hazards;
            for i in 0..hs.len() {
                // C# `h != this`: our own slot (Taken while setup runs) is skipped.
                if i == self.base.idx {
                    continue;
                }
                let h = &hs[i];
                if h.kind() == self.base.kind {
                    let Hz::Bumper(b) = h else { panic!("kind bumper is not a Bumper") };
                    self.phase = b.phase + SimTrig::TURN / 2;
                    self.dir = b.dir;
                    self._place();
                    return;
                }
            }
        }
        self.phase = rng.next_below(SimTrig::TURN);
        self.dir = if rng.next_below(2) == 0 { 1 } else { -1 };
        self._place();
    }

    fn step(&mut self, _sim: &mut GameSim) {
        self._place();
    }

    fn touch(&mut self, sim: &mut GameSim) {
        if sim.bird_touches_circle(self.x, self.y, self.radius) {
            sim.bump_bird_from(self.x, self.y);
        }
    }

    fn checksum(&self, h: i64) -> i64 {
        let mut out_ = mix_all(h, &[self.x, self.y, self.phase, self.dir, G::b(self.follows)]);
        if self.radius != Self::RADIUS
            || self.loop_rx != Self::LOOP_RX
            || self.loop_ry != Self::LOOP_RY
            || self.period != Self::PERIOD
        {
            out_ = mix_all(out_, &[self.radius, self.loop_rx, self.loop_ry, self.period]);
        }
        out_
    }
}
