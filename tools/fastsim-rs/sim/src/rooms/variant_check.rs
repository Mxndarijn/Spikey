//! Port of sim/rooms/variant_check.gd: the fairness check every GENERATED variant's layout
//! passes (a bird anywhere in the exit holding its height touches nothing deadly).
use crate::prelude::*;

pub struct VariantCheck;

impl VariantCheck {
    pub const HOLD_STEPS: i64 = SimConfig::ARRIVAL_BLIND;

    /// GD defaults: avoid_touch = false, steps = 0 (HOLD_STEPS).
    pub fn holds(sim: &GameSim, avoid_touch: bool, steps: i64) -> bool {
        if !sim.state.started {
            return true;
        }
        let n = if steps > 0 { steps } else { Self::HOLD_STEPS };
        for dy in GameSim::ARRIVAL_HEIGHTS {
            let at = GameSim::_arrival_y(sim.state.anchor_y + Self::arrival_dy(sim, dy));
            if !Self::_holds_at(sim, at, avoid_touch, n) {
                return false;
            }
        }
        true
    }

    pub fn arrival_dy(sim: &GameSim, dy: i64) -> i64 {
        let def = sim.room.def();
        if def.variants.is_empty() || def.variants[sim.room.variant as usize].arrival_spread == 0 {
            return dy;
        }
        dy * def.variants[sim.room.variant as usize].arrival_spread / SimConfig::EXIT_FIT
    }

    /// GD first_hit(sim, steps = 0): the hazard index that first hits a held-height bird,
    /// -2 the ceiling or floor, -1 none.
    pub fn first_hit(sim: &GameSim, steps: i64) -> i64 {
        if !sim.state.started {
            return -1;
        }
        let n = if steps > 0 { steps } else { Self::HOLD_STEPS };
        for dy in GameSim::ARRIVAL_HEIGHTS {
            let at = GameSim::_arrival_y(sim.state.anchor_y + Self::arrival_dy(sim, dy));
            let hit = Self::_hit_at(sim, at, false, n);
            if hit != -1 {
                return hit;
            }
        }
        -1
    }

    fn _holds_at(sim: &GameSim, hold: i64, avoid_touch: bool, steps: i64) -> bool {
        Self::_hit_at(sim, hold, avoid_touch, steps) == -1
    }

    fn _hit_at(sim: &GameSim, hold: i64, avoid_touch: bool, steps: i64) -> i64 {
        let mut c = sim.clone_deep();
        let g = c.room.gravity;
        let mut y = hold;
        let mut vy = 0;
        c.state.y = y;
        c.state.vy = 0;
        for k in 0..steps {
            c.room_step();
            if (y - hold) * g > 0 && vy * g >= 0 {
                vy = SimConfig::FLAP_VY * g;
            }
            vy = G::clampi(vy + SimConfig::GRAVITY * g, -SimConfig::MAX_FALL_VY, SimConfig::MAX_FALL_VY);
            y += vy;
            c.state.x = FairLanes::arrival_x(sim, k + 1);
            c.state.y = y;
            c.state.vy = vy;
            for i in 0..c.room.hazards.len() {
                if c.room.hazards[i].alive() && c.room.hazards[i].has_touch() {
                    c.with_hazard(i, |h, s| h.touch(s));
                }
            }
            y = c.state.y;
            vy = c.state.vy;
            let r = SimConfig::BIRD_RADIUS;
            if y - r <= SimConfig::KILL_TOP || y + r >= SimConfig::KILL_BOTTOM {
                return -2;
            }
            for (i, h) in c.room.hazards.iter().enumerate() {
                if !h.alive() {
                    continue;
                }
                if h.kills(&c) || (avoid_touch && Self::_touches(&c, h)) {
                    return i as i64;
                }
            }
        }
        -1
    }

    fn _touches(sim: &GameSim, h: &Hz) -> bool {
        match h {
            Hz::Bubble(b) => sim.bird_touches_circle(b.x, b.y, b.radius),
            _ => false,
        }
    }
}
