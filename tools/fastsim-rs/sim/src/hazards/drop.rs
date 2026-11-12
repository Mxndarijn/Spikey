//! Port of sim/hazards/drop.gd (Sim/Hazards/Drop.cs).
use crate::rooms::hazard::{add_warning, WARN_KILL};
use crate::prelude::*;

pub struct Phase;
impl Phase {
    pub const WAIT: i64 = 0;
    pub const WARN: i64 = 1;
    pub const FALL: i64 = 2;
    pub const STAKE: i64 = 3;
}

pub struct Style;
impl Style {
    pub const PLAIN: i64 = 0;
    pub const SHATTER: i64 = 1;
    pub const WOBBLE: i64 = 2;
    pub const STAKE: i64 = 3;
}

#[derive(Clone, Debug)]
pub struct Drop {
    pub base: Base,
    pub x: i64,
    pub y: i64,
    pub phase: i64,
    pub timer: i64,
    pub speed: i64,
    pub gap: i64,
    pub delay: i64,
    pub warn: i64,
    pub radius: i64,
    pub style: i64,
    pub column: i64,
    pub base_x: i64,
    pub fall_t: i64,
    pub shard_t: i64,
    pub shard_x: i64,
    pub shard_dx: i64,
    pub shard_y: i64,
    pub shard_vy: i64,
    pub _rng: SimRng,
}

impl Drop {
    pub const SUB: i64 = SimConfig::SUB;
    pub const RADIUS: i64 = 10 * Self::SUB;
    pub const WARN: i64 = 45;
    pub const MIN_X: i64 = 50 * Self::SUB;
    pub const MAX_X: i64 = 310 * Self::SUB;
    pub const TOP: i64 = SimConfig::KILL_TOP;

    pub const SWAY: i64 = 22 * Self::SUB;
    pub const SWAY_PERIOD: i64 = 40;

    pub const SHARD_RADIUS: i64 = 6 * Self::SUB;
    pub const SHARD_START: i64 = 10 * Self::SUB;
    pub const SHARD_VX: i64 = 5 * Self::SUB;
    pub const SHARD_VY: i64 = -4 * Self::SUB;
    pub const SHARD_GRAVITY: i64 = 19;
    pub const SHARD_FLOOR: i64 = SimConfig::KILL_BOTTOM - 6 * Self::SUB;
    pub const SHARD_LIFE: i64 = 26;

    pub const FLOOR_SPIKES: i64 = 9;
    pub const FLOOR_SPIKE_W: i64 = SimConfig::WORLD_W / Self::FLOOR_SPIKES;
    pub const FLOOR_BASE: i64 = SimConfig::WORLD_H - 8 * Self::SUB;
    pub const STAKE_HEIGHT: i64 = 40 * Self::SUB;
    pub const STAKE_GROW: i64 = 8;
    pub const STAKE_SINK: i64 = 15;
    pub const STAKE_STEPS: i64 = 135;

    /// C# defaults: p_delay = 0, p_speed = 10 * SUB, p_gap = 25, p_warn = WARN,
    /// p_radius = RADIUS, p_style = Style.PLAIN, p_column = -1.
    pub fn new(
        p_delay: i64,
        p_speed: i64,
        p_gap: i64,
        p_warn: i64,
        p_radius: i64,
        p_style: i64,
        p_column: i64,
    ) -> Drop {
        Drop {
            base: Base::new("drop"),
            x: 0,
            y: Self::TOP,
            phase: Phase::WAIT,
            timer: 0,
            speed: p_speed,
            gap: p_gap,
            delay: p_delay,
            warn: p_warn,
            radius: p_radius,
            style: p_style,
            column: p_column,
            base_x: 0,
            fall_t: 0,
            shard_t: 0,
            shard_x: 0,
            shard_dx: 0,
            shard_y: 0,
            shard_vy: 0,
            _rng: SimRng::new(0),
        }
    }

    fn _next_column(&mut self) -> i64 {
        if self.column >= 0 {
            let c = self.column;
            self.column = SimConfig::WORLD_W - self.column;
            return c;
        }
        if self.style == Style::STAKE {
            return Self::FLOOR_SPIKE_W / 2
                + Self::FLOOR_SPIKE_W * (1 + self._rng.next_below(Self::FLOOR_SPIKES - 2));
        }
        if self.style == Style::WOBBLE {
            return Self::MIN_X + Self::SWAY + self._rng.next_below(Self::MAX_X - Self::MIN_X - 2 * Self::SWAY + 1);
        }
        Self::MIN_X + self._rng.next_below(Self::MAX_X - Self::MIN_X + 1)
    }

    fn _step_shards(&mut self) {
        self.shard_t -= 1;
        self.shard_dx += Self::SHARD_VX;
        self.shard_vy += Self::SHARD_GRAVITY;
        self.shard_y += self.shard_vy;
        if self.shard_y > Self::SHARD_FLOOR {
            self.shard_y = Self::SHARD_FLOOR;
            self.shard_vy = -G::absi(self.shard_vy) * 45 / 100;
        }
    }

    pub fn warning(&self) -> bool {
        self.phase == Phase::WARN
    }

    pub fn falling(&self) -> bool {
        self.phase == Phase::FALL
    }

    pub fn staked(&self) -> bool {
        self.phase == Phase::STAKE
    }

    pub fn warn_progress(&self) -> i64 {
        if self.phase != Phase::WARN {
            return 0;
        }
        SimTrig::ONE * (self.warn - self.timer) / self.warn
    }

    pub fn stake_height(&self) -> i64 {
        if self.phase != Phase::STAKE {
            return 0;
        }
        let age = Self::STAKE_STEPS - self.timer;
        if age < Self::STAKE_GROW {
            return Self::STAKE_HEIGHT * (age + 1) / Self::STAKE_GROW;
        }
        if self.timer < Self::STAKE_SINK {
            return Self::STAKE_HEIGHT * self.timer / Self::STAKE_SINK;
        }
        Self::STAKE_HEIGHT
    }

    pub fn stake_half_base(&self) -> i64 {
        Self::FLOOR_SPIKE_W / 2 + self.stake_height() / 10
    }

    fn _touches_stake(&self, sim: &GameSim) -> bool {
        let tip_y = SimConfig::KILL_BOTTOM - self.stake_height();
        let dx = G::absi(sim.state.x - self.base_x);
        let dy = sim.state.y - tip_y;
        let ex = self.stake_half_base();
        let ey = Self::FLOOR_BASE - tip_y;
        if dy >= 0 && dy <= ey && dx * ey <= ex * dy {
            return true;
        }
        let r = SimConfig::BIRD_RADIUS;
        let dot = dx * ex + dy * ey;
        let len2 = ex * ex + ey * ey;
        if dot <= 0 {
            return dx * dx + dy * dy <= r * r;
        }
        if dot >= len2 {
            return false;
        }
        let cross = dx * ey - dy * ex;
        cross * cross <= r * r * len2
    }
}

impl Hazard for Drop {
    impl_base!();

    fn setup(&mut self, _sim: &mut GameSim, rng: &mut SimRng) {
        self._rng.reseed(rng.next_u32());
        self.phase = Phase::WAIT;
        self.timer = self.delay;
        self.y = Self::TOP;
    }

    fn step(&mut self, sim: &mut GameSim) {
        if self.shard_t > 0 {
            self._step_shards();
            let sx = self.shard_x - self.shard_dx;
            let sx2 = self.shard_x + self.shard_dx;
            if ExitZone::hits_circle(sim, sx, self.shard_y, Self::SHARD_RADIUS)
                || ExitZone::hits_circle(sim, sx2, self.shard_y, Self::SHARD_RADIUS)
            {
                self.shard_t = 0;
            }
        }
        match self.phase {
            Phase::WAIT => {
                self.timer -= 1;
                if self.timer <= 0 {
                    self.phase = Phase::WARN;
                    self.timer = self.warn;
                    self.base_x = self._next_column();
                    self.x = self.base_x;
                    self.y = Self::TOP;
                    self.fall_t = 0;
                }
            }
            Phase::WARN => {
                self.timer -= 1;
                if self.timer <= 0 {
                    self.phase = Phase::FALL;
                    self.y = Self::TOP;
                }
            }
            Phase::FALL => {
                self.y += self.speed;
                self.fall_t += 1;
                if self.style == Style::WOBBLE {
                    self.x = self.base_x
                        + Self::SWAY * SimTrig::sin_t(self.fall_t * SimTrig::TURN / Self::SWAY_PERIOD) / SimTrig::ONE;
                }
                if self.style == Style::SHATTER && self.y + self.radius >= SimConfig::KILL_BOTTOM {
                    self.shard_t = Self::SHARD_LIFE;
                    self.shard_x = self.x;
                    self.shard_dx = 0;
                    self.shard_y = SimConfig::KILL_BOTTOM - Self::SHARD_START;
                    self.shard_vy = Self::SHARD_VY;
                    self.phase = Phase::WAIT;
                    self.timer = self.gap;
                } else if self.style == Style::STAKE && self.y + self.radius >= SimConfig::KILL_BOTTOM {
                    self.y = SimConfig::KILL_BOTTOM - self.radius;
                    self.phase = Phase::STAKE;
                    self.timer = Self::STAKE_STEPS;
                } else if self.y - self.radius > SimConfig::WORLD_H
                    || ExitZone::hits_circle(sim, self.x, self.y, self.radius)
                {
                    self.phase = Phase::WAIT;
                    self.timer = self.gap;
                }
            }
            Phase::STAKE => {
                self.timer -= 1;
                if self.timer <= 0 {
                    self.phase = Phase::WAIT;
                    self.timer = self.gap;
                }
            }
            _ => {}
        }
    }

    fn kills(&self, sim: &GameSim) -> bool {
        if self.phase == Phase::FALL && sim.bird_touches_circle(self.x, self.y, self.radius) {
            return true;
        }
        if self.shard_t > 0 {
            if sim.bird_touches_circle(self.shard_x - self.shard_dx, self.shard_y, Self::SHARD_RADIUS) {
                return true;
            }
            if sim.bird_touches_circle(self.shard_x + self.shard_dx, self.shard_y, Self::SHARD_RADIUS) {
                return true;
            }
        }
        self.phase == Phase::STAKE && self._touches_stake(sim)
    }

    fn warnings(&self, _sim: &GameSim, out_: &mut Vec<i64>) {
        if self.phase != Phase::WARN {
            return;
        }
        let half = self.radius + if self.style == Style::WOBBLE { Self::SWAY } else { 0 };
        let dur = (SimConfig::WORLD_H + self.radius - Self::TOP) / self.speed + 1;
        add_warning(out_, self.x - half, Self::TOP - self.radius, self.x + half, SimConfig::WORLD_H, self.timer, dur, WARN_KILL);
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(
            h,
            &[
                self.x,
                self.y,
                self.phase,
                self.timer,
                self.speed,
                self.gap,
                self.delay,
                self.warn,
                self.radius,
                self.style,
                self.column,
                self.base_x,
                self.fall_t,
                self.shard_t,
                self.shard_x,
                self.shard_dx,
                self.shard_y,
                self.shard_vy,
                self._rng.state_checksum(),
            ],
        )
    }
}
