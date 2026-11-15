//! Rate limits: at most `max` tries per key in a sliding window, in memory.
//! One server process serves the game (docs/SERVER_MIGRATION.md, VM size), so
//! memory is enough; a restart forgets the counts, which only ever lets a
//! little more through, never less.

use std::collections::{HashMap, VecDeque};
use std::sync::Mutex;
use std::time::{Duration, Instant};

pub struct Limiter {
    max: usize,
    window: Duration,
    hits: Mutex<HashMap<String, VecDeque<Instant>>>,
}

impl Limiter {
    pub fn new(max: usize, window: Duration) -> Limiter {
        Limiter { max, window, hits: Mutex::new(HashMap::new()) }
    }

    /// Counts a try for `key`; false when it is over the limit (not counted then).
    pub fn allow(&self, key: &str) -> bool {
        self.allow_at(key, Instant::now())
    }

    pub fn allow_at(&self, key: &str, now: Instant) -> bool {
        let mut hits = self.hits.lock().unwrap();
        if hits.len() > 100_000 {
            // Never grow without end: drop keys with nothing in the window.
            let window = self.window;
            hits.retain(|_, q| q.back().is_some_and(|t| now.duration_since(*t) < window));
        }
        let q = hits.entry(key.to_string()).or_default();
        while q.front().is_some_and(|t| now.duration_since(*t) >= self.window) {
            q.pop_front();
        }
        if q.len() >= self.max {
            return false;
        }
        q.push_back(now);
        true
    }
}

/// The server's limits.
pub struct Limits {
    /// Transfer code tries (preview and redeem) per signed-in player: 5 an hour.
    pub transfer_player: Limiter,
    /// Transfer code tries per IP address: 20 an hour.
    pub transfer_ip: Limiter,
    /// New players per IP address: 30 an hour (a school's wifi is many phones).
    pub signup_ip: Limiter,
    /// Device-key sign-ins per IP address: 60 an hour.
    pub device_ip: Limiter,
}

impl Limits {
    pub fn new() -> Limits {
        let hour = Duration::from_secs(3600);
        Limits {
            transfer_player: Limiter::new(5, hour),
            transfer_ip: Limiter::new(20, hour),
            signup_ip: Limiter::new(30, hour),
            device_ip: Limiter::new(60, hour),
        }
    }
}

impl Default for Limits {
    fn default() -> Self {
        Limits::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allows_up_to_the_limit_then_refuses() {
        let l = Limiter::new(3, Duration::from_secs(60));
        let t = Instant::now();
        assert!(l.allow_at("a", t));
        assert!(l.allow_at("a", t));
        assert!(l.allow_at("a", t));
        assert!(!l.allow_at("a", t), "the fourth try");
        assert!(l.allow_at("b", t), "another key has its own count");
    }

    #[test]
    fn tries_age_out_of_the_window() {
        let l = Limiter::new(1, Duration::from_secs(60));
        let t = Instant::now();
        assert!(l.allow_at("a", t));
        assert!(!l.allow_at("a", t + Duration::from_secs(59)));
        assert!(l.allow_at("a", t + Duration::from_secs(61)));
    }
}
