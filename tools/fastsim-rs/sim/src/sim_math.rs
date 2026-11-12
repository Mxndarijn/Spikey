//! Port of sim/sim_math.gd, and SimHash (sim/sim_hash.gd).
pub struct SimMath;

impl SimMath {
    #[inline(always)]
    pub fn cross(ax: i64, ay: i64, bx: i64, by: i64, px: i64, py: i64) -> i64 {
        (bx - ax) * (py - ay) - (by - ay) * (px - ax)
    }

    #[allow(clippy::too_many_arguments)]
    pub fn point_in_triangle(px: i64, py: i64, ax: i64, ay: i64, bx: i64, by: i64, cx: i64, cy: i64) -> bool {
        let d1 = Self::cross(ax, ay, bx, by, px, py);
        let d2 = Self::cross(bx, by, cx, cy, px, py);
        let d3 = Self::cross(cx, cy, ax, ay, px, py);
        let has_neg = d1 < 0 || d2 < 0 || d3 < 0;
        let has_pos = d1 > 0 || d2 > 0 || d3 > 0;
        !(has_neg && has_pos)
    }

    pub fn circle_hits_segment(px: i64, py: i64, r: i64, ax: i64, ay: i64, bx: i64, by: i64) -> bool {
        let dx = bx - ax;
        let dy = by - ay;
        let fx = px - ax;
        let fy = py - ay;
        let len2 = dx * dx + dy * dy;
        let t = fx * dx + fy * dy;
        let r2 = r * r;
        if len2 == 0 || t <= 0 {
            return fx * fx + fy * fy <= r2;
        }
        if t >= len2 {
            let gx = px - bx;
            let gy = py - by;
            return gx * gx + gy * gy <= r2;
        }
        let c = dx * fy - dy * fx;
        c * c <= r2 * len2
    }

    #[allow(clippy::too_many_arguments)]
    pub fn circle_hits_triangle(px: i64, py: i64, r: i64, ax: i64, ay: i64, bx: i64, by: i64, cx: i64, cy: i64) -> bool {
        if Self::point_in_triangle(px, py, ax, ay, bx, by, cx, cy) {
            return true;
        }
        Self::circle_hits_segment(px, py, r, ax, ay, bx, by)
            || Self::circle_hits_segment(px, py, r, bx, by, cx, cy)
            || Self::circle_hits_segment(px, py, r, cx, cy, ax, ay)
    }
}

pub struct SimHash;

impl SimHash {
    pub const SEED: i64 = 0x811C9DC5;
    pub const PRIME: i64 = 16777619;
    pub const MASK: i64 = 0xFFFFFFFF;

    #[inline(always)]
    pub fn mix(h: i64, value: i64) -> i64 {
        ((h ^ (value & Self::MASK)).wrapping_mul(Self::PRIME)) & Self::MASK
    }
}
