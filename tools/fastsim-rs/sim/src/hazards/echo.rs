//! Port of sim/hazards/echo.gd (Sim/Hazards/Echo.cs).
use crate::prelude::*;

pub struct Mode;
impl Mode {
    pub const ECHO: i64 = 0;
    pub const MIRROR: i64 = 1;
}

#[derive(Clone, Debug)]
pub struct Echo {
    pub base: Base,
    pub mode: i64,
    pub x: i64,
    pub y: i64,
    pub shown: bool,
    pub facing: i64,
    pub xs: Vec<i64>,
    pub ys: Vec<i64>,
    pub head: i64,
}

impl Echo {
    pub const DELAY: i64 = SimConfig::TICKS_PER_SECOND;
    pub const RADIUS: i64 = 10 * SimConfig::SUB;

    /// C# default: p_mode = -1.
    pub fn new(p_mode: i64) -> Echo {
        Echo {
            base: Base::new("echo"),
            mode: p_mode,
            x: 0,
            y: 0,
            shown: false,
            facing: 1,
            xs: Vec::new(),
            ys: Vec::new(),
            head: 0,
        }
    }
}

impl Hazard for Echo {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, _rng: &mut SimRng) {
        if self.mode < 0 {
            self.mode = if sim.room.variant_id() == "mirror" { Mode::MIRROR } else { Mode::ECHO };
        }
        self.xs = Vec::new();
        self.ys = Vec::new();
        for _i in 0..Self::DELAY {
            self.xs.push(sim.state.x);
            self.ys.push(sim.state.y);
        }
        self.head = 0;
        self.x = sim.state.x;
        self.y = sim.state.y;
    }

    fn step(&mut self, sim: &mut GameSim) {
        self.shown = self.base.t > Self::DELAY;
        if self.mode == Mode::MIRROR {
            self.x = SimConfig::WORLD_W - sim.state.x;
            self.y = SimConfig::WORLD_H - sim.state.y;
            self.facing = if sim.state.vx > 0 { -1 } else { 1 };
            self.x = ExitZone::push_x(sim, self.x, self.y, Self::RADIUS);
            return;
        }
        let old_x = self.xs[self.head as usize];
        self.facing = if old_x >= self.x { 1 } else { -1 };
        self.x = old_x;
        self.y = self.ys[self.head as usize];
        self.xs[self.head as usize] = sim.state.x;
        self.ys[self.head as usize] = sim.state.y;
        self.head = (self.head + 1) % Self::DELAY;
        self.x = ExitZone::push_x(sim, self.x, self.y, Self::RADIUS);
    }

    fn kills(&self, sim: &GameSim) -> bool {
        self.shown && sim.bird_touches_circle(self.x, self.y, Self::RADIUS)
    }

    fn checksum(&self, h: i64) -> i64 {
        let mut out_ =
            mix_all(h, &[self.mode, self.x, self.y, G::b(self.shown), self.facing, self.head]);
        for i in 0..self.xs.len() {
            out_ = SimHash::mix(SimHash::mix(out_, self.xs[i]), self.ys[i]);
        }
        out_
    }
}
