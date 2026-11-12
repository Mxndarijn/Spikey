//! Port of sim/exit_zone.gd (Sim/ExitZone.cs): the mouths of a room's drawn
//! exits (a ghost or open), which hazards treat as part of the wall.
use crate::game_sim::GameSim;
use crate::g::G;
use crate::sim_config::SimConfig;
use crate::sim_state::ExitKind;

pub struct ExitZone;

impl ExitZone {
    pub const DEPTH: i64 = 3 * SimConfig::BIRD_RADIUS;
    pub const HALF: i64 = SimConfig::EXIT_HALF + SimConfig::BIRD_RADIUS;
    pub const BOXES: i64 = 2;

    pub fn count(_sim: &GameSim) -> i64 {
        Self::BOXES
    }

    #[inline]
    pub fn box_side(sim: &GameSim, _i: i64) -> i64 {
        sim.state.exit_side
    }

    #[inline]
    pub fn box_y(sim: &GameSim, i: i64) -> i64 {
        let s = &sim.state;
        if !s.exit_open && !s.exit_preview {
            return 0;
        }
        if i == 0 {
            return s.exit_a_y;
        }
        if s.exit_b_kind != ExitKind::NORMAL { s.exit_b_y } else { 0 }
    }

    pub fn left_on(sim: &GameSim, side: i64) -> i64 {
        if side == 0 {
            return sim.room.wall_left();
        }
        sim.room.wall_right() - Self::DEPTH
    }

    pub fn right_on(sim: &GameSim, side: i64) -> i64 {
        if side == 0 {
            return sim.room.wall_left() + Self::DEPTH;
        }
        sim.room.wall_right()
    }

    fn _lo(sim: &GameSim, side: i64) -> i64 {
        Self::left_on(sim, side) + if side == 1 { 1 } else { 0 }
    }

    fn _hi(sim: &GameSim, side: i64) -> i64 {
        Self::right_on(sim, side) - if side == 0 { 1 } else { 0 }
    }

    pub fn rect_in_box(sim: &GameSim, side: i64, ey: i64, x0: i64, y0: i64, x1: i64, y1: i64) -> bool {
        if G::maxi(x0, x1) < Self::_lo(sim, side) || G::mini(x0, x1) > Self::_hi(sim, side) {
            return false;
        }
        G::maxi(y0, y1) >= ey - Self::HALF && G::mini(y0, y1) <= ey + Self::HALF
    }

    pub fn circle_in_box(sim: &GameSim, side: i64, ey: i64, cx: i64, cy: i64, r: i64) -> bool {
        let nx = G::clampi(cx, Self::_lo(sim, side), Self::_hi(sim, side));
        let ny = G::clampi(cy, ey - Self::HALF, ey + Self::HALF);
        let dx = cx - nx;
        let dy = cy - ny;
        dx * dx + dy * dy <= r * r
    }

    pub fn hits_rect(sim: &GameSim, x0: i64, y0: i64, x1: i64, y1: i64) -> bool {
        for i in 0..Self::BOXES {
            let ey = Self::box_y(sim, i);
            if ey != 0 && Self::rect_in_box(sim, Self::box_side(sim, i), ey, x0, y0, x1, y1) {
                return true;
            }
        }
        false
    }

    pub fn hits_rect_on(sim: &GameSim, side: i64, x0: i64, y0: i64, x1: i64, y1: i64) -> bool {
        for i in 0..Self::BOXES {
            let ey = Self::box_y(sim, i);
            if ey != 0 && Self::box_side(sim, i) == side && Self::rect_in_box(sim, side, ey, x0, y0, x1, y1) {
                return true;
            }
        }
        false
    }

    pub fn circle_box(sim: &GameSim, cx: i64, cy: i64, r: i64) -> i64 {
        for i in 0..Self::BOXES {
            let ey = Self::box_y(sim, i);
            if ey != 0 && Self::circle_in_box(sim, Self::box_side(sim, i), ey, cx, cy, r) {
                return i;
            }
        }
        -1
    }

    pub fn hits_circle(sim: &GameSim, cx: i64, cy: i64, r: i64) -> bool {
        Self::circle_box(sim, cx, cy, r) >= 0
    }

    pub fn clear_y(sim: &GameSim, side: i64, y: i64, half: i64, lo: i64, hi: i64) -> i64 {
        let reach = Self::HALF + half + 1;
        let mut first = -1;
        for i in 0..Self::BOXES {
            let ey = Self::box_y(sim, i);
            if ey != 0 && Self::_on(sim, i, side) && G::absi(y - ey) < reach {
                first = i;
                break;
            }
        }
        if first < 0 {
            return y;
        }
        let dir = if y < Self::box_y(sim, first) { -1 } else { 1 };
        let mut out_ = Self::_push_y(sim, side, y, reach, dir);
        if out_ < lo || out_ > hi {
            out_ = Self::_push_y(sim, side, y, reach, -dir);
        }
        out_
    }

    fn _push_y(sim: &GameSim, side: i64, y: i64, reach: i64, dir: i64) -> i64 {
        let mut out_ = y;
        for _k in 0..Self::BOXES {
            let mut moved = false;
            for i in 0..Self::BOXES {
                let ey = Self::box_y(sim, i);
                if ey != 0 && Self::_on(sim, i, side) && G::absi(out_ - ey) < reach {
                    out_ = ey + dir * reach;
                    moved = true;
                }
            }
            if !moved {
                break;
            }
        }
        out_
    }

    #[allow(clippy::too_many_arguments)]
    pub fn stop_y(sim: &GameSim, side: i64, from: i64, to: i64, half: i64, lo: i64, hi: i64) -> i64 {
        let reach = Self::HALF + half + 1;
        if Self::clear_y(sim, side, from, half, lo, hi) != from {
            return Self::clear_y(sim, side, to, half, lo, hi);
        }
        if to == from {
            return to;
        }
        Self::_push_y(sim, side, to, reach, if to > from { -1 } else { 1 })
    }

    fn _on(sim: &GameSim, i: i64, side: i64) -> bool {
        side < 0 || Self::box_side(sim, i) == side
    }

    pub fn push_x(sim: &GameSim, x: i64, y: i64, r: i64) -> i64 {
        let i = Self::circle_box(sim, x, y, r);
        if i < 0 {
            return x;
        }
        if Self::box_side(sim, i) == 0 {
            return Self::right_on(sim, 0) + r + 1;
        }
        Self::left_on(sim, 1) - r - 1
    }

    /// [x, y, vx, vy] after the bounce, or None (GDScript: an empty array).
    pub fn bounce(sim: &GameSim, x: i64, y: i64, vx: i64, vy: i64, r: i64) -> Option<[i64; 4]> {
        let i = Self::circle_box(sim, x, y, r);
        if i < 0 {
            return None;
        }
        let ey = Self::box_y(sim, i);
        let prev_y = y - vy;
        let (mut nx, mut ny, mut nvx, mut nvy) = (x, y, vx, vy);
        if prev_y + r < ey - Self::HALF {
            let top = ey - Self::HALF - r - 1;
            ny = 2 * top - y;
            nvy = -G::absi(vy);
        } else if prev_y - r > ey + Self::HALF {
            let bottom = ey + Self::HALF + r + 1;
            ny = 2 * bottom - y;
            nvy = G::absi(vy);
        } else if Self::box_side(sim, i) == 0 {
            let edge = Self::right_on(sim, 0) + r + 1;
            nx = 2 * edge - x;
            nvx = G::absi(vx);
        } else {
            let edge = Self::left_on(sim, 1) - r - 1;
            nx = 2 * edge - x;
            nvx = -G::absi(vx);
        }
        Some([nx, ny, nvx, nvy])
    }
}
