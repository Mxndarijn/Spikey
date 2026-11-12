//! GDScript's integer helpers, with the exact same edge cases (Sim/G.cs).

pub struct G;

impl G {
    #[inline(always)]
    pub fn mini(a: i64, b: i64) -> i64 {
        if a < b { a } else { b }
    }
    #[inline(always)]
    pub fn maxi(a: i64, b: i64) -> i64 {
        if a > b { a } else { b }
    }
    #[inline(always)]
    pub fn absi(a: i64) -> i64 {
        if a < 0 { a.wrapping_neg() } else { a }
    }
    #[inline(always)]
    pub fn signi(a: i64) -> i64 {
        if a > 0 { 1 } else if a < 0 { -1 } else { 0 }
    }
    /// Godot's CLAMP: below min gives min, else above max gives max.
    #[inline(always)]
    pub fn clampi(v: i64, lo: i64, hi: i64) -> i64 {
        if v < lo { lo } else if v > hi { hi } else { v }
    }
    #[inline(always)]
    pub fn posmod(a: i64, b: i64) -> i64 {
        let mut v = a.wrapping_rem(b);
        if (v < 0 && b > 0) || (v > 0 && b < 0) {
            v += b;
        }
        v
    }
    /// int(bool).
    #[inline(always)]
    pub fn b(b: bool) -> i64 {
        b as i64
    }
}
