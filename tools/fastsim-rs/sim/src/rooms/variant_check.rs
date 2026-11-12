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
            if !Self::_holds_at(sim, GameSim::_arrival_y(sim.state.anchor_y + dy), avoid_touch, n) {
                return false;
            }
        }
        true
    }

    fn _holds_at(sim: &GameSim, hold: i64, avoid_touch: bool, steps: i64) -> bool {
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
                return false;
            }
            for h in &c.room.hazards {
                if !h.alive() {
                    continue;
                }
                if h.kills(&c) || (avoid_touch && Self::_touches(&c, h)) {
                    return false;
                }
            }
        }
        true
    }

    fn _touches(sim: &GameSim, h: &Hz) -> bool {
        match h {
            Hz::Bubble(b) => sim.bird_touches_circle(b.x, b.y, b.radius),
            _ => false,
        }
    }
}
