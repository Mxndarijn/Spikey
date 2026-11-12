//! Port of sim/sim_rng.gd (xoshiro128** on 32-bit values in 64-bit ints).
use crate::sim_math::SimHash;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct SimRng {
    pub _s0: i64,
    pub _s1: i64,
    pub _s2: i64,
    pub _s3: i64,
}

impl SimRng {
    pub const MASK: i64 = 0xFFFFFFFF;

    pub fn new(seed_value: i64) -> SimRng {
        let mut r = SimRng::default();
        r.reseed(seed_value);
        r
    }

    pub fn reseed(&mut self, seed_value: i64) {
        let mut x = (seed_value ^ 0x9E3779B9) & Self::MASK;
        x ^= (seed_value >> 32) & Self::MASK;
        if x == 0 {
            x = 0x6D2B79F5;
        }
        x = Self::_xorshift32(x);
        self._s0 = x;
        x = Self::_xorshift32(x);
        self._s1 = x;
        x = Self::_xorshift32(x);
        self._s2 = x;
        x = Self::_xorshift32(x);
        self._s3 = x;
    }

    #[inline(always)]
    pub fn next_u32(&mut self) -> i64 {
        let result = (Self::_rotl((self._s1 * 5) & Self::MASK, 7) * 9) & Self::MASK;
        let t = (self._s1 << 9) & Self::MASK;
        self._s2 ^= self._s0;
        self._s3 ^= self._s1;
        self._s1 ^= self._s2;
        self._s0 ^= self._s3;
        self._s2 ^= t;
        self._s3 = Self::_rotl(self._s3, 11);
        result
    }

    #[inline(always)]
    pub fn next_below(&mut self, n: i64) -> i64 {
        self.next_u32() % n
    }

    pub fn state_checksum(&self) -> i64 {
        SimHash::mix(
            SimHash::mix(SimHash::mix(SimHash::mix(SimHash::SEED, self._s0), self._s1), self._s2),
            self._s3,
        )
    }

    #[inline(always)]
    fn _xorshift32(v: i64) -> i64 {
        let mut x = v;
        x ^= (x << 13) & Self::MASK;
        x ^= x >> 17;
        x ^= (x << 5) & Self::MASK;
        x
    }

    #[inline(always)]
    fn _rotl(x: i64, k: i64) -> i64 {
        ((x << k) | (x >> (32 - k))) & Self::MASK
    }
}
