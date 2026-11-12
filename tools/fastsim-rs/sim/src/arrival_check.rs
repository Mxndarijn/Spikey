//! Port of sim/arrival_check.gd (Sim/ArrivalCheck.cs).
use crate::game_sim::GameSim;
use crate::rooms::room_rules::RoomRules;
use crate::sim_config::SimConfig;

pub struct ArrivalCheck;

impl ArrivalCheck {
    const OFFSETS: [i64; 3] = [0, -24 * SimConfig::SUB, 24 * SimConfig::SUB];
    const HOLD_SHIFTS: [i64; 3] = [0, -60 * SimConfig::SUB, 60 * SimConfig::SUB];

    pub fn score(sim: &mut GameSim) -> i64 {
        let y0 = sim.state.y;
        let mut n = 0;
        while n < SimConfig::ARRIVAL_BLIND {
            let tap = Self::_toward(sim, y0);
            sim.step(tap);
            if sim.is_over() {
                return n;
            }
            n += 1;
        }
        let mut best = 0;
        let mut second = 0;
        for kind in 0..2 {
            for i in 0..3 {
                let mut c = sim.clone_deep();
                let lived = Self::_follow(&mut c, kind, i, y0);
                if lived > best {
                    second = best;
                    best = lived;
                } else if lived > second {
                    second = lived;
                }
                if second >= SimConfig::ARRIVAL_FOLLOW {
                    return n + second;
                }
            }
        }
        n + second
    }

    fn _follow(sim: &mut GameSim, kind: i64, i: usize, y0: i64) -> i64 {
        let mut n = 0;
        while n < SimConfig::ARRIVAL_FOLLOW {
            let mut target = y0 + Self::HOLD_SHIFTS[i];
            if kind == 0 {
                target = Self::gap_target(sim) + Self::OFFSETS[i];
            }
            let tap = Self::_toward(sim, target);
            sim.step(tap);
            if sim.is_over() {
                return n;
            }
            n += 1;
        }
        n
    }

    #[inline]
    pub fn _toward(sim: &GameSim, target: i64) -> bool {
        let g = sim.room.gravity;
        (sim.state.y - target) * g > 0 && sim.state.vy * g >= 0
    }

    pub fn gap_target(sim: &GameSim) -> i64 {
        let s = &sim.state;
        let side = if s.vx > 0 { 1 } else { 0 };
        if s.exit_open && s.exit_side == side {
            return s.exit_a_y;
        }
        let mask = sim.wall_mask(side);
        let mut best_start = 0;
        let mut best_len = 0;
        let mut run_start = 0;
        let mut run_len = 0;
        for slot in 0..SimConfig::SLOT_COUNT {
            if RoomRules::has_slot(mask, slot) {
                run_len = 0;
                continue;
            }
            if run_len == 0 {
                run_start = slot;
            }
            run_len += 1;
            if run_len > best_len {
                best_len = run_len;
                best_start = run_start;
            }
        }
        if best_len == 0 {
            return s.y;
        }
        let top = SimConfig::slot_center_y(best_start);
        let mid = (top + SimConfig::slot_center_y(best_start + best_len - 1)) / 2;
        mid + sim.wall_shift(side)
    }
}
