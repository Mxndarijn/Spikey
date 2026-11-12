//! Port of sim/hazards/firework.gd (Sim/Hazards/Firework.cs).
use crate::prelude::*;

/// C# `Firework.Phase`.
pub struct Phase;
impl Phase {
    pub const PAD: i64 = 0;
    pub const CLIMB: i64 = 1;
    pub const BURST: i64 = 2;
    pub const REST: i64 = 3;
}

/// C# `Firework.Style`.
pub struct Style;
impl Style {
    pub const RING: i64 = 0;
    pub const DOUBLE: i64 = 1;
    pub const CROSS: i64 = 2;
}

#[derive(Clone, Debug)]
pub struct Firework {
    pub base: Base,
    pub x: i64,
    pub y: i64,
    pub burst_y: i64,
    pub phase: i64,
    pub timer: i64,
    pub spread: i64,
    pub delay: i64,
    pub style: i64,
    pub spent: i64,
    pub _rng: SimRng,
}

impl Firework {
    pub const SUB: i64 = SimConfig::SUB;
    pub const ROCKET_RADIUS: i64 = 8 * Self::SUB;
    pub const SPARK_RADIUS: i64 = 6 * Self::SUB;
    pub const SPARKS: i64 = 8;
    pub const PAD: i64 = 60;
    pub const CLIMB_VY: i64 = 8 * Self::SUB;
    pub const SPARK_SPEED: i64 = 4 * Self::SUB;
    pub const BURST: i64 = 44;
    pub const SPARK_DEADLY: i64 = 30;
    pub const REST: i64 = 20;
    pub const ECHO: i64 = 16;
    pub const ARMS: i64 = 4;
    pub const ARM_SPARKS: i64 = 3;
    pub const MIN_X: i64 = 80 * Self::SUB;
    pub const MAX_X: i64 = 280 * Self::SUB;
    pub const MIN_BURST_Y: i64 = 170 * Self::SUB;
    pub const MAX_BURST_Y: i64 = 380 * Self::SUB;
    pub const PAD_Y: i64 = SimConfig::KILL_BOTTOM - Self::ROCKET_RADIUS;

    /// C# defaults: p_delay = 0, p_style = Style.RING.
    pub fn new(p_delay: i64, p_style: i64) -> Firework {
        Firework {
            base: Base::new("firework"),
            x: 0,
            y: Self::PAD_Y,
            burst_y: 0,
            phase: Phase::PAD,
            timer: 0,
            spread: 0,
            delay: p_delay,
            style: p_style,
            spent: 0,
            _rng: SimRng::new(0),
        }
    }

    pub fn _load(&mut self) {
        self.phase = Phase::PAD;
        self.timer = Self::PAD;
        self.spread = 0;
        self.spent = 0;
        self.x = Self::MIN_X + self._rng.next_below(Self::MAX_X - Self::MIN_X + 1);
        self.burst_y = Self::MIN_BURST_Y + self._rng.next_below(Self::MAX_BURST_Y - Self::MIN_BURST_Y + 1);
        self.y = Self::PAD_Y;
    }

    pub fn burst_steps(&self) -> i64 {
        if self.style == Style::DOUBLE {
            Self::BURST + Self::ECHO
        } else {
            Self::BURST
        }
    }

    pub fn spark_count(&self) -> i64 {
        match self.style {
            Style::DOUBLE => return 2 * Self::SPARKS,
            Style::CROSS => return Self::ARMS * Self::ARM_SPARKS,
            _ => {}
        }
        Self::SPARKS
    }

    pub fn spark_start(&self, i: i64) -> i64 {
        if self.style == Style::DOUBLE && i >= Self::SPARKS {
            Self::ECHO
        } else {
            0
        }
    }

    pub fn spark_age(&self, i: i64) -> i64 {
        self.timer - self.spark_start(i)
    }

    pub fn spark_alpha(&self) -> i64 {
        self.spark_alpha_of(0)
    }

    pub fn spark_alpha_of(&self, i: i64) -> i64 {
        let age = self.spark_age(i);
        if self.phase != Phase::BURST || age < 0 || (self.spent & (1i64 << i)) != 0 {
            return 0;
        }
        if age < Self::SPARK_DEADLY {
            return SimTrig::ONE;
        }
        G::maxi(0, SimTrig::ONE * (Self::BURST - age) / (Self::BURST - Self::SPARK_DEADLY))
    }

    pub fn spark_live(&self, i: i64) -> bool {
        let age = self.spark_age(i);
        self.phase == Phase::BURST && age >= 0 && age < Self::SPARK_DEADLY && (self.spent & (1i64 << i)) == 0
    }

    pub fn spark_angle(&self, i: i64) -> i64 {
        match self.style {
            Style::DOUBLE => {
                return (2 * (i % Self::SPARKS) + (if i >= Self::SPARKS { 1 } else { 0 })) * SimTrig::TURN
                    / (2 * Self::SPARKS)
            }
            Style::CROSS => return (i / Self::ARM_SPARKS) * SimTrig::TURN / Self::ARMS,
            _ => {}
        }
        i * SimTrig::TURN / Self::SPARKS
    }

    pub fn spark_dist(&self, i: i64) -> i64 {
        match self.style {
            Style::DOUBLE => return G::maxi(0, self.spark_age(i)) * Self::SPARK_SPEED,
            Style::CROSS => return self.spread * (i % Self::ARM_SPARKS + 1) / Self::ARM_SPARKS,
            _ => {}
        }
        self.spread
    }

    pub fn fuse_progress(&self) -> i64 {
        if self.phase != Phase::PAD {
            return 0;
        }
        SimTrig::ONE - SimTrig::ONE * G::mini(self.timer, Self::PAD) / Self::PAD
    }

    pub fn spark_x(&self, i: i64) -> i64 {
        self.x + self.spark_dist(i) * SimTrig::cos_t(self.spark_angle(i)) / SimTrig::ONE
    }

    pub fn spark_y(&self, i: i64) -> i64 {
        self.y + self.spark_dist(i) * SimTrig::sin_t(self.spark_angle(i)) / SimTrig::ONE
    }
}

impl Hazard for Firework {
    impl_base!();

    fn setup(&mut self, _sim: &mut GameSim, rng: &mut SimRng) {
        self._rng.reseed(rng.next_u32());
        self._load();
        self.timer += self.delay;
    }

    fn step(&mut self, sim: &mut GameSim) {
        match self.phase {
            Phase::PAD => {
                self.timer -= 1;
                if self.timer <= 0 {
                    self.phase = Phase::CLIMB;
                }
            }
            Phase::CLIMB => {
                self.y -= Self::CLIMB_VY;
                if self.y <= self.burst_y {
                    self.y = self.burst_y;
                    self.phase = Phase::BURST;
                    self.timer = 0;
                    self.spread = 0;
                }
            }
            Phase::BURST => {
                self.timer += 1;
                self.spread += Self::SPARK_SPEED;
                for i in 0..self.spark_count() {
                    if self.spark_live(i) && ExitZone::hits_circle(sim, self.spark_x(i), self.spark_y(i), Self::SPARK_RADIUS) {
                        self.spent |= 1i64 << i;
                    }
                }
                if self.timer >= self.burst_steps() {
                    self.phase = Phase::REST;
                    self.timer = Self::REST;
                }
            }
            Phase::REST => {
                self.timer -= 1;
                if self.timer <= 0 {
                    self._load();
                }
            }
            _ => {}
        }
    }

    fn kills(&self, sim: &GameSim) -> bool {
        if self.phase == Phase::CLIMB {
            return sim.bird_touches_circle(self.x, self.y, Self::ROCKET_RADIUS);
        }
        if self.phase == Phase::BURST {
            for i in 0..self.spark_count() {
                if self.spark_live(i) && sim.bird_touches_circle(self.spark_x(i), self.spark_y(i), Self::SPARK_RADIUS) {
                    return true;
                }
            }
        }
        false
    }

    fn checksum(&self, h: i64) -> i64 {
        let mut out_ = mix_all(
            h,
            &[
                self.x,
                self.y,
                self.burst_y,
                self.phase,
                self.timer,
                self.spread,
                self.delay,
                self._rng.state_checksum(),
                self.spent,
            ],
        );
        if self.style != Style::RING {
            out_ = mix_all(out_, &[self.style]);
        }
        out_
    }
}
