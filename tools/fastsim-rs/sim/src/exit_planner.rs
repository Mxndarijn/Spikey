//! Port of sim/exit_planner.gd (Sim/ExitPlanner.cs).
use crate::game_sim::GameSim;
use crate::g::G;
use crate::sim_config::SimConfig;
use crate::sim_math::SimHash;
use crate::sim_rng::SimRng;
use crate::sim_state::{ExitKind, SimState};

pub struct ExitPlanner;

impl ExitPlanner {
    pub const PLAN_SALT: i64 = 0x45584954;
    pub const FORK_APART: i64 = 3 * SimConfig::SLOT_SIZE;
    pub const MOUTH_STEP: i64 = 4 * SimConfig::SUB;

    pub fn slots(state: &SimState) -> i64 {
        let mut out_ = 0;
        let reach = SimConfig::EXIT_HALF + SimConfig::SPIKE_HALF_BASE;
        for slot in 0..SimConfig::SLOT_COUNT {
            let cy = SimConfig::slot_center_y(slot);
            if G::absi(cy - state.exit_a_y) < reach {
                out_ |= 1i64 << slot;
            }
            if state.exit_b_kind != ExitKind::NORMAL && G::absi(cy - state.exit_b_y) < reach {
                out_ |= 1i64 << slot;
            }
        }
        out_
    }

    pub fn is_fork(sim: &GameSim, at: i64) -> bool {
        if sim.is_practice() {
            return false;
        }
        if let Some(def) = sim.room.def_ {
            if def.boss {
                return true;
            }
        }
        at % SimConfig::FORK_EVERY == 0 && at % SimConfig::BOSS_EVERY != 0
    }

    pub fn plan(sim: &mut GameSim, rng: &mut SimRng, side: i64, at: i64) {
        sim.state.exit_side = side;
        let fork = Self::is_fork(sim, at);
        if fork {
            let mut top = Self::random_y(sim, rng, SimConfig::EXIT_MIN_Y, SimConfig::FORK_SPLIT_Y - SimConfig::EXIT_HALF);
            let mut bottom = Self::random_y(sim, rng, SimConfig::FORK_SPLIT_Y + SimConfig::EXIT_HALF, SimConfig::EXIT_MAX_Y);
            let calm_on_top = rng.next_below(2) == 0;
            if Self::blocked(sim, bottom) {
                bottom = Self::_free_apart(sim, bottom, top);
            }
            if Self::blocked(sim, top) {
                top = Self::_free_apart(sim, top, bottom);
            }
            sim.state.exit_a_y = top;
            sim.state.exit_b_y = bottom;
            sim.state.exit_a_kind = if calm_on_top { ExitKind::CALM } else { ExitKind::WILD };
            sim.state.exit_b_kind = if calm_on_top { ExitKind::WILD } else { ExitKind::CALM };
        } else {
            sim.state.exit_a_y = Self::random_y(sim, rng, SimConfig::EXIT_MIN_Y, SimConfig::EXIT_MAX_Y);
            sim.state.exit_a_kind = ExitKind::NORMAL;
            sim.state.exit_b_y = 0;
            sim.state.exit_b_kind = ExitKind::NORMAL;
        }
    }

    pub fn plan_room(sim: &mut GameSim, at: i64) {
        let mut rng = SimRng::new(SimHash::mix(sim.room.rng_seed, Self::PLAN_SALT));
        let s = &sim.state;
        let (k0, k1, k2, k3, k4) = (s.exit_side, s.exit_a_y, s.exit_a_kind, s.exit_b_y, s.exit_b_kind);
        sim.state.plan_at = at;
        sim.state.plan_a_y_left = 0;
        sim.state.plan_b_y_left = 0;
        sim.state.plan_a_y_right = 0;
        sim.state.plan_b_y_right = 0;
        let heading = if sim.state.vx > 0 { 1 } else { 0 };
        for side in 0..2 {
            sim._points_also = if side != heading { 1 } else { -1 };
            Self::plan(sim, &mut rng, side, at);
            sim._points_also = -1;
            let s = &mut sim.state;
            if side == 0 {
                s.plan_a_y_left = s.exit_a_y;
                s.plan_a_kind_left = s.exit_a_kind;
                s.plan_b_y_left = s.exit_b_y;
            } else {
                s.plan_a_y_right = s.exit_a_y;
                s.plan_a_kind_right = s.exit_a_kind;
                s.plan_b_y_right = s.exit_b_y;
            }
        }
        let s = &mut sim.state;
        s.exit_side = k0;
        s.exit_a_y = k1;
        s.exit_a_kind = k2;
        s.exit_b_y = k3;
        s.exit_b_kind = k4;
    }

    pub fn use_plan(sim: &mut GameSim, side: i64, at: i64) {
        if sim.state.plan_at != at {
            Self::plan_room(sim, at);
        }
        let s = &mut sim.state;
        s.exit_side = side;
        s.exit_a_y = if side == 0 { s.plan_a_y_left } else { s.plan_a_y_right };
        s.exit_a_kind = if side == 0 { s.plan_a_kind_left } else { s.plan_a_kind_right };
        s.exit_b_y = if side == 0 { s.plan_b_y_left } else { s.plan_b_y_right };
        s.exit_b_kind = Self::_other_kind(s.exit_a_kind);
    }

    pub fn planned_y(sim: &GameSim, side: i64, y: i64) -> i64 {
        let s = &sim.state;
        let a = if side == 0 { s.plan_a_y_left } else { s.plan_a_y_right };
        let kind = if side == 0 { s.plan_a_kind_left } else { s.plan_a_kind_right };
        let b = if side == 0 { s.plan_b_y_left } else { s.plan_b_y_right };
        if kind != ExitKind::NORMAL && G::absi(b - y) < G::absi(a - y) {
            return b;
        }
        a
    }

    pub fn reserved(sim: &GameSim, side: i64, y: i64) -> bool {
        let s = &sim.state;
        let reach = SimConfig::EXIT_HALF + SimConfig::SPIKE_HALF_BASE;
        let a = if side == 0 { s.plan_a_y_left } else { s.plan_a_y_right };
        let kind = if side == 0 { s.plan_a_kind_left } else { s.plan_a_kind_right };
        let b = if side == 0 { s.plan_b_y_left } else { s.plan_b_y_right };
        if G::absi(y - a) < reach {
            return true;
        }
        kind != ExitKind::NORMAL && G::absi(y - b) < reach
    }

    fn _nearest_free(sim: &mut GameSim, first: i64, last: i64, fallback: i64) -> i64 {
        let c0 = SimConfig::slot_center_y(0);
        let lo = (SimConfig::EXIT_MIN_Y - c0 + SimConfig::SLOT_SIZE - 1) / SimConfig::SLOT_SIZE;
        let hi = (SimConfig::EXIT_MAX_Y - c0) / SimConfig::SLOT_SIZE;
        let mut best = fallback;
        let mut best_d = -1;
        for slot in lo..hi + 1 {
            if Self::blocked(sim, SimConfig::slot_center_y(slot)) {
                continue;
            }
            let near = G::clampi(slot, first, last);
            let d = G::absi(slot - near);
            if best_d < 0 || d < best_d {
                best = near;
                best_d = d;
            }
        }
        best
    }

    fn _free_apart(sim: &mut GameSim, y: i64, other: i64) -> i64 {
        let c0 = SimConfig::slot_center_y(0);
        let lo = (SimConfig::EXIT_MIN_Y - c0 + SimConfig::SLOT_SIZE - 1) / SimConfig::SLOT_SIZE;
        let hi = (SimConfig::EXIT_MAX_Y - c0) / SimConfig::SLOT_SIZE;
        let mut best = y;
        let mut best_d = -1;
        for slot in lo..hi + 1 {
            let cy = SimConfig::slot_center_y(slot);
            if G::absi(cy - other) < Self::FORK_APART || Self::blocked(sim, cy) {
                continue;
            }
            let d = G::absi(cy - y);
            if best_d < 0 || d < best_d {
                best = cy;
                best_d = d;
            }
        }
        best
    }

    fn _other_kind(kind: i64) -> i64 {
        if kind == ExitKind::CALM {
            return ExitKind::WILD;
        }
        if kind == ExitKind::WILD {
            return ExitKind::CALM;
        }
        ExitKind::NORMAL
    }

    pub fn random_y(sim: &mut GameSim, rng: &mut SimRng, lo: i64, hi: i64) -> i64 {
        let c0 = SimConfig::slot_center_y(0);
        let first = (lo - c0 + SimConfig::SLOT_SIZE - 1) / SimConfig::SLOT_SIZE;
        let last = (hi - c0) / SimConfig::SLOT_SIZE;
        let mut open = [0i64; SimConfig::SLOT_COUNT as usize + 2];
        let mut n = 0usize;
        for slot in first..last + 1 {
            if !Self::blocked(sim, SimConfig::slot_center_y(slot)) {
                open[n] = slot;
                n += 1;
            }
        }
        if n == 0 {
            let mut any = first + rng.next_below(last - first + 1);
            if sim.room.def().reach > 0 {
                any = G::clampi(
                    (sim.state.anchor_y - c0 + SimConfig::SLOT_SIZE / 2) / SimConfig::SLOT_SIZE,
                    first,
                    last,
                );
            } else {
                any = Self::_nearest_free(sim, first, last, any);
            }
            return SimConfig::slot_center_y(any);
        }
        SimConfig::slot_center_y(open[rng.next_below(n as i64) as usize])
    }

    pub fn blocked(sim: &mut GameSim, y: i64) -> bool {
        if Self::_blocked_now(sim, y) {
            return true;
        }
        if sim._points_also < 0 {
            return false;
        }
        let keep = sim._points_override;
        sim._points_override = sim._points_also;
        let out_ = Self::_blocked_now(sim, y);
        sim._points_override = keep;
        out_
    }

    fn _blocked_now(sim: &mut GameSim, y: i64) -> bool {
        if sim.room.def().reach > 0 && G::absi(y - sim.state.anchor_y) > sim.room.def().reach {
            return true;
        }
        let side = sim.state.exit_side;
        for h in &sim.room.hazards {
            if h.alive() && h.blocks_exit(sim, side, y) {
                return true;
            }
        }
        Self::in_mouth(sim, side, y)
    }

    pub fn in_mouth(sim: &mut GameSim, side: i64, y: i64) -> bool {
        let r = SimConfig::BIRD_RADIUS;
        let keep_x = sim.state.x;
        let keep_y = sim.state.y;
        let wall = if side == 0 { sim.room.wall_left() + r } else { sim.room.wall_right() - r };
        let dir = if side == 0 { 1 } else { -1 };
        let mut out_ = false;
        for dx in [0, r / 2, r - 1] {
            let mut dy = -SimConfig::EXIT_HALF;
            while dy <= SimConfig::EXIT_HALF && !out_ {
                sim.state.x = wall + dir * dx;
                sim.state.y = y + dy;
                for h in &sim.room.hazards {
                    if h.alive() && h.kills(sim) {
                        out_ = true;
                        break;
                    }
                }
                dy += Self::MOUTH_STEP;
            }
            if out_ {
                break;
            }
        }
        sim.state.x = keep_x;
        sim.state.y = keep_y;
        out_
    }
}
