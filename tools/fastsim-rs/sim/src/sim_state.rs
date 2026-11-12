//! Port of sim/sim_state.gd (Sim/SimState.cs).
use crate::g::G;
use crate::sim_config::SimConfig;
use crate::sim_math::SimHash;

pub struct DeathCause;

impl DeathCause {
    pub const NONE: i64 = 0;
    pub const CEILING: i64 = 1;
    pub const FLOOR: i64 = 2;
    pub const SPIKE_LEFT: i64 = 3;
    pub const SPIKE_RIGHT: i64 = 4;
    pub const HAZARD: i64 = 5;
    pub const NAMES: [&'static str; 6] = ["NONE", "CEILING", "FLOOR", "SPIKE_LEFT", "SPIKE_RIGHT", "HAZARD"];
}

pub struct ExitKind;

impl ExitKind {
    pub const NORMAL: i64 = 0;
    pub const CALM: i64 = 1;
    pub const WILD: i64 = 2;
}

/// Plain values only, so a copy is a `Copy` (GDScript SimState.copy / assign).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct SimState {
    pub tick: i64,
    pub started: bool,
    pub alive: bool,
    pub death_cause: i64,
    pub x: i64,
    pub y: i64,
    pub vx: i64,
    pub vy: i64,
    pub score: i64,
    pub room_index: i64,
    pub room_kind: i64,
    pub left_spikes: i64,
    pub right_spikes: i64,
    pub coin_active: bool,
    pub coin_x: i64,
    pub coin_y: i64,
    pub coins: i64,
    pub flaps: i64,
    pub exit_open: bool,
    pub exit_preview: bool,
    pub exit_side: i64,
    pub exit_a_y: i64,
    pub exit_a_kind: i64,
    pub exit_b_y: i64,
    pub exit_b_kind: i64,
    pub route: i64,
    pub bosses_met: i64,
    pub deck_lo: i64,
    pub deck_hi: i64,
    pub pickup_x: i64,
    pub pickup_y: i64,
    pub arrival_hold: i64,
    pub revives: i64,
    pub anchor_y: i64,
    pub plan_a_y_left: i64,
    pub plan_a_kind_left: i64,
    pub plan_b_y_left: i64,
    pub plan_a_y_right: i64,
    pub plan_a_kind_right: i64,
    pub plan_b_y_right: i64,
    pub plan_at: i64,
}

impl Default for SimState {
    fn default() -> Self {
        SimState {
            tick: 0,
            started: false,
            alive: true,
            death_cause: DeathCause::NONE,
            x: SimConfig::BIRD_START_X,
            y: SimConfig::BIRD_START_Y,
            vx: SimConfig::SPEED_X,
            vy: 0,
            score: 0,
            room_index: 0,
            room_kind: 0,
            left_spikes: 0,
            right_spikes: 0,
            coin_active: false,
            coin_x: 0,
            coin_y: 0,
            coins: 0,
            flaps: 0,
            exit_open: false,
            exit_preview: false,
            exit_side: 0,
            exit_a_y: 0,
            exit_a_kind: 0,
            exit_b_y: 0,
            exit_b_kind: 0,
            route: 0,
            bosses_met: 0,
            deck_lo: 0,
            deck_hi: 0,
            pickup_x: 0,
            pickup_y: 0,
            arrival_hold: 0,
            revives: 0,
            anchor_y: SimConfig::BIRD_START_Y,
            plan_a_y_left: 0,
            plan_a_kind_left: 0,
            plan_b_y_left: 0,
            plan_a_y_right: 0,
            plan_a_kind_right: 0,
            plan_b_y_right: 0,
            plan_at: 0,
        }
    }
}

impl SimState {
    pub fn copy(&self) -> SimState {
        *self
    }

    /// Every field set to `o`'s (GDScript SimState.assign).
    pub fn assign(&mut self, o: &SimState) {
        *self = *o;
    }

    pub fn checksum(&self) -> i64 {
        let mut h = SimHash::SEED;
        h = SimHash::mix(h, self.tick);
        h = SimHash::mix(h, G::b(self.started));
        h = SimHash::mix(h, G::b(self.alive));
        h = SimHash::mix(h, self.death_cause);
        h = SimHash::mix(h, self.x);
        h = SimHash::mix(h, self.y);
        h = SimHash::mix(h, self.vx);
        h = SimHash::mix(h, self.vy);
        h = SimHash::mix(h, self.score);
        h = SimHash::mix(h, self.room_index);
        h = SimHash::mix(h, self.room_kind);
        h = SimHash::mix(h, self.left_spikes);
        h = SimHash::mix(h, self.right_spikes);
        h = SimHash::mix(h, G::b(self.coin_active));
        h = SimHash::mix(h, self.coin_x);
        h = SimHash::mix(h, self.coin_y);
        h = SimHash::mix(h, self.coins);
        h = SimHash::mix(h, self.flaps);
        h = SimHash::mix(h, G::b(self.exit_open));
        h = SimHash::mix(h, self.exit_side);
        h = SimHash::mix(h, self.exit_a_y);
        h = SimHash::mix(h, self.exit_a_kind);
        h = SimHash::mix(h, self.exit_b_y);
        h = SimHash::mix(h, self.exit_b_kind);
        h = SimHash::mix(h, self.route);
        h = SimHash::mix(h, self.arrival_hold);
        h = SimHash::mix(h, G::b(self.exit_preview));
        h = SimHash::mix(h, self.revives);
        h = SimHash::mix(h, self.anchor_y);
        h = SimHash::mix(h, self.plan_a_y_left);
        h = SimHash::mix(h, self.plan_a_kind_left);
        h = SimHash::mix(h, self.plan_b_y_left);
        h = SimHash::mix(h, self.plan_a_y_right);
        h = SimHash::mix(h, self.plan_a_kind_right);
        h = SimHash::mix(h, self.plan_b_y_right);
        h = SimHash::mix(h, self.plan_at);
        h = SimHash::mix(h, self.bosses_met);
        h = SimHash::mix(h, self.deck_lo);
        h = SimHash::mix(h, self.deck_hi);
        h
    }
}
