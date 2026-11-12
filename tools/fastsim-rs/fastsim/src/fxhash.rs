//! A small fast hasher (FxHash) for the search maps keyed by bucket number.
//! The maps only answer "which slot holds this key"; the order of everything
//! comes from Vecs, so the hasher never changes a result.
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};

#[derive(Default, Clone, Copy)]
pub struct FxHasher {
    hash: u64,
}

const K: u64 = 0x517cc1b727220a95;

impl Hasher for FxHasher {
    #[inline]
    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.hash = (self.hash.rotate_left(5) ^ b as u64).wrapping_mul(K);
        }
    }
    #[inline]
    fn write_i64(&mut self, i: i64) {
        self.hash = (self.hash.rotate_left(5) ^ i as u64).wrapping_mul(K);
    }
    #[inline]
    fn write_i32(&mut self, i: i32) {
        self.write_i64(i as i64);
    }
    #[inline]
    fn write_u64(&mut self, i: u64) {
        self.write_i64(i as i64);
    }
    #[inline]
    fn write_usize(&mut self, i: usize) {
        self.write_i64(i as i64);
    }
    #[inline]
    fn finish(&self) -> u64 {
        self.hash
    }
}

pub type FxMap<K, V> = HashMap<K, V, BuildHasherDefault<FxHasher>>;
