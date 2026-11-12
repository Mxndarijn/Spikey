//! Profiling timers (Bots/Prof.cs), only with `--features prof`: per-thread
//! nanosecond totals and counts per section. Without the feature every call is
//! empty and compiles away.
#[cfg(feature = "prof")]
use std::cell::RefCell;

pub const ARRIVAL: usize = 0;
pub const STEP: usize = 1;
pub const CLONE: usize = 2;
pub const BLIND: usize = 3;
pub const BEAM: usize = 4;
pub const NEAR: usize = 5;
pub const LOOK: usize = 6;
pub const HZSTEP: usize = 7;
pub const WALLS: usize = 8;
pub const N: usize = 9;
pub const NAMES: [&str; N] = ["arrival", "step", "clone", "blind_copy", "beam", "near_death", "look", "hazard step", "walls"];

#[cfg(feature = "prof")]
thread_local! {
    static T: RefCell<[(u64, u64); N]> = const { RefCell::new([(0, 0); N]) };
}

#[cfg(feature = "prof")]
static TOTAL: std::sync::Mutex<[(u64, u64); N]> = std::sync::Mutex::new([(0, 0); N]);

#[inline(always)]
pub fn now() -> u64 {
    #[cfg(feature = "prof")]
    {
        use std::sync::OnceLock;
        static START: OnceLock<std::time::Instant> = OnceLock::new();
        START.get_or_init(std::time::Instant::now).elapsed().as_nanos() as u64
    }
    #[cfg(not(feature = "prof"))]
    0
}

#[inline(always)]
pub fn add(_k: usize, _since: u64) {
    #[cfg(feature = "prof")]
    {
        let d = now() - _since;
        T.with(|t| {
            let mut t = t.borrow_mut();
            t[_k].0 += d;
            t[_k].1 += 1;
        });
    }
}

/// Adds this thread's timers to the process totals.
pub fn flush() {
    #[cfg(feature = "prof")]
    T.with(|t| {
        let mut t = t.borrow_mut();
        let mut all = TOTAL.lock().unwrap();
        for k in 0..N {
            all[k].0 += t[k].0;
            all[k].1 += t[k].1;
            t[k] = (0, 0);
        }
    });
}

/// (name, seconds, count) per section with a count.
pub fn totals() -> Vec<(&'static str, f64, u64)> {
    #[cfg(feature = "prof")]
    {
        let all = TOTAL.lock().unwrap();
        return (0..N).filter(|&k| all[k].1 > 0).map(|k| (NAMES[k], all[k].0 as f64 / 1e9, all[k].1)).collect();
    }
    #[cfg(not(feature = "prof"))]
    Vec::new()
}
