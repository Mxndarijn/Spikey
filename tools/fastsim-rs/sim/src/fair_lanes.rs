//! Port of sim/fair_lanes.gd (Sim/FairLanes.cs).
use crate::game_sim::GameSim;
use crate::g::G;
use crate::sim_config::SimConfig;

pub struct FairLanes;

impl FairLanes {
    pub const START_LANE_H: i64 = 100 * SimConfig::SUB;
    pub const START_LANE_BELOW: i64 = 12 * SimConfig::SUB;
    pub const START_LANE_W: i64 = 150 * SimConfig::SUB;
    pub const START_PATH: i64 = 32;
    pub const FIRST_HOP: i64 = SimConfig::FLAP_VY * SimConfig::FLAP_VY / (2 * SimConfig::GRAVITY);
    pub const ARRIVAL_PATH_TICKS: i64 = SimConfig::ARRIVAL_BLIND + 60;
    pub const ARRIVAL_PATH_MARGIN: i64 = 10 * SimConfig::SUB;
    pub const ARRIVAL_PATH_MIN: i64 = SimConfig::ARRIVAL_BLIND + 15;

    pub fn entry_y(sim: &GameSim) -> i64 {
        if sim.state.started {
            return sim.state.anchor_y;
        }
        sim.state.y - Self::FIRST_HOP / 2 * sim.room.gravity
    }

    pub fn arrival_path(sim: &GameSim) -> Vec<i64> {
        let mut out_ = Vec::with_capacity((2 * Self::ARRIVAL_PATH_TICKS) as usize);
        let g = sim.room.gravity;
        let hold = sim.state.anchor_y;
        let mut y = hold;
        let mut vy = 0;
        for k in 0..Self::ARRIVAL_PATH_TICKS {
            if (y - hold) * g > 0 && vy * g >= 0 {
                vy = SimConfig::FLAP_VY * g;
            }
            vy = G::clampi(vy + SimConfig::GRAVITY * g, -SimConfig::MAX_FALL_VY, SimConfig::MAX_FALL_VY);
            y += vy;
            out_.push(Self::arrival_x(sim, k + 1));
            out_.push(y);
        }
        out_
    }

    #[inline]
    pub fn arrival_path_hits(path: &[i64], k: i64, cx: i64, cy: i64, r: i64) -> bool {
        let dx = cx - path[(2 * k) as usize];
        let dy = cy - path[(2 * k + 1) as usize];
        let reach = SimConfig::BIRD_RADIUS + r + Self::ARRIVAL_PATH_MARGIN;
        dx * dx + dy * dy < reach * reach
    }

    pub fn arrival_x(sim: &GameSim, k: i64) -> i64 {
        let r = SimConfig::BIRD_RADIUS;
        let lo = sim.room.wall_left() + r;
        let span = sim.room.wall_right() - r - lo;
        let at = G::posmod(sim.state.x + sim.state.vx * k - lo, 2 * span);
        lo + if at <= span { at } else { 2 * span - at }
    }

    pub fn start_path(sim: &GameSim) -> Vec<i64> {
        let mut out_ = Vec::new();
        if sim.state.started {
            return out_;
        }
        let g = SimConfig::GRAVITY * sim.room.gravity;
        let mut x = sim.state.x;
        let hold = sim.state.anchor_y;
        let mut y = hold;
        let mut vy = SimConfig::FLAP_VY * sim.room.gravity;
        for _i in 0..Self::START_PATH {
            vy = G::clampi(vy + g, -SimConfig::MAX_FALL_VY, SimConfig::MAX_FALL_VY);
            x += sim.state.vx;
            y += vy;
            out_.push(x);
            out_.push(y);
        }
        out_
    }

    pub fn start_path_hits_rect(sim: &GameSim, x0: i64, y0: i64, x1: i64, y1: i64, margin: i64) -> bool {
        let path = Self::start_path(sim);
        let r = SimConfig::BIRD_RADIUS + margin;
        let mut i = 0;
        while i < path.len() {
            if path[i] + r > x0 && path[i] - r < x1 && path[i + 1] + r > y0 && path[i + 1] - r < y1 {
                return true;
            }
            i += 2;
        }
        false
    }

    pub fn blocks_start_lane(sim: &GameSim, x0: i64, y0: i64, x1: i64, y1: i64) -> bool {
        if sim.state.started {
            return false;
        }
        let w = Self::START_LANE_W;
        let top = sim.state.y - (Self::START_LANE_H - Self::START_LANE_BELOW) * sim.room.gravity;
        let bottom = sim.state.y + Self::START_LANE_BELOW * sim.room.gravity;
        let ly0 = G::mini(top, bottom);
        let ly1 = G::maxi(top, bottom);
        let lx0 = if sim.state.vx > 0 { sim.state.x } else { sim.state.x - w };
        let lx1 = if sim.state.vx > 0 { sim.state.x + w } else { sim.state.x };
        x1 > lx0 && x0 < lx1 && y1 > ly0 && y0 < ly1
    }
}
