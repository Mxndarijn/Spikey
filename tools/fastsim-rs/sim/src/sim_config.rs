//! Port of sim/sim_config.gd (Sim/SimConfig.cs).
use crate::g::G;

pub struct SimConfig;

impl SimConfig {
    pub const GAMEPLAY_VERSION: i64 = 23;
    pub const MAX_REVIVES: i64 = 1;
    pub const TICKS_PER_SECOND: i64 = 60;
    pub const WARN_TICKS: i64 = 2 * Self::TICKS_PER_SECOND;
    pub const SUB: i64 = 64;
    pub const WORLD_W: i64 = 360 * Self::SUB;
    pub const WORLD_H: i64 = 640 * Self::SUB;
    pub const BIRD_RADIUS: i64 = 14 * Self::SUB;
    pub const BIRD_START_X: i64 = 180 * Self::SUB;
    pub const BIRD_START_Y: i64 = 300 * Self::SUB;
    pub const SPEED_X: i64 = 4 * Self::SUB;
    pub const GRAVITY: i64 = 13;
    pub const FLAP_VY: i64 = -5 * Self::SUB;
    pub const MAX_FALL_VY: i64 = 12 * Self::SUB;
    pub const KILL_TOP: i64 = 34 * Self::SUB;
    pub const KILL_BOTTOM: i64 = 606 * Self::SUB;
    pub const SLOT_TOP: i64 = 33 * Self::SUB;
    pub const SLOT_SIZE: i64 = 41 * Self::SUB;
    pub const SLOT_COUNT: i64 = 14;
    pub const SPIKE_DEPTH: i64 = 26 * Self::SUB;
    pub const SPIKE_HALF_BASE: i64 = 15 * Self::SUB;
    pub const POINTS_PER_ROOM: i64 = 10;
    pub const BASE_SPIKES: i64 = 2;
    pub const POINTS_PER_EXTRA_SPIKE: i64 = 6;
    pub const MAX_SPIKES: i64 = 8;
    pub const COIN_RADIUS: i64 = 12 * Self::SUB;
    pub const COIN_MIN_X: i64 = 80 * Self::SUB;
    pub const COIN_MAX_X: i64 = 280 * Self::SUB;
    pub const COIN_MIN_Y: i64 = 90 * Self::SUB;
    pub const COIN_MAX_Y: i64 = 550 * Self::SUB;
    pub const EXIT_WALL: i64 = 1;
    pub const EXIT_HALF: i64 = 48 * Self::SUB;
    pub const EXIT_FIT: i64 = 2 * Self::SLOT_SIZE - Self::SPIKE_HALF_BASE;
    pub const EXIT_MIN_Y: i64 = 110 * Self::SUB;
    pub const EXIT_MAX_Y: i64 = 530 * Self::SUB;
    pub const FORK_SPLIT_Y: i64 = 320 * Self::SUB;
    pub const FORK_EVERY: i64 = 50;
    pub const FORK_DOOR_Y: i64 = Self::FORK_SPLIT_Y;
    pub const WILD_COINS: i64 = 5;
    pub const WILD_SPIKES: i64 = 3;
    pub const BOSS_EVERY: i64 = 100;
    pub const BOSS_POINTS: i64 = 20;
    pub const BOSS_HOLD: i64 = 90;
    pub const BOSS_COINS: [i64; 3] = [15, 20, 25];
    pub const ARRIVAL_HOLD: i64 = 60;
    pub const ARRIVAL_BLIND: i64 = 60;
    pub const ARRIVAL_FOLLOW: i64 = 120;
    pub const ARRIVAL_TRIES: i64 = 16;
    pub const ARRIVAL_EDGE: i64 = 84 * Self::SUB;
    pub const MAX_TICKS: i64 = 60 * 60 * 60 * 4;

    pub fn boss_tier(entry_score: i64) -> i64 {
        G::clampi(entry_score / Self::BOSS_EVERY, 1, Self::BOSS_COINS.len() as i64)
    }

    #[inline(always)]
    pub fn slot_center_y(slot: i64) -> i64 {
        Self::SLOT_TOP + slot * Self::SLOT_SIZE + Self::SLOT_SIZE / 2
    }
}
