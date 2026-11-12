//! A sampling profiler for the bots (Bots/Prof.cs in spirit), only with
//! `--features prof`. Each thread stores the section it is in (`enter` /
//! `leave`, one relaxed store each); a sampler thread looks at every worker
//! about every 20 us and counts. Without the feature every call is empty.
pub const OTHER: u8 = 0;
pub const ARRIVAL: u8 = 1;
pub const STEP: u8 = 2;
pub const CLONE: u8 = 3;
pub const BLIND: u8 = 4;
pub const BEAM: u8 = 5;
pub const NEAR: u8 = 6;
pub const LOOK: u8 = 7;
pub const HZSTEP: u8 = 8;
pub const WALLS: u8 = 9;
pub const KILLS: u8 = 10;
pub const SPIKES: u8 = 11;
pub const KEEP: u8 = 12;
pub const N: usize = 13;
pub const NAMES: [&str; N] = [
    "other", "arrival", "step", "clone", "blind_copy", "beam", "near_death", "look", "hazard step", "walls",
    "kills+touch", "spikes", "beam keep",
];

#[cfg(feature = "prof")]
mod imp {
    use std::sync::atomic::{AtomicBool, AtomicU64, AtomicU8, Ordering};
    use std::sync::{Arc, Mutex, OnceLock};

    pub struct Shared {
        pub slots: Mutex<Vec<Arc<AtomicU8>>>,
        pub counts: Vec<AtomicU64>,
    }

    pub fn shared() -> &'static Shared {
        static S: OnceLock<Shared> = OnceLock::new();
        static STARTED: AtomicBool = AtomicBool::new(false);
        let s = S.get_or_init(|| Shared { slots: Mutex::new(Vec::new()), counts: (0..super::N).map(|_| AtomicU64::new(0)).collect() });
        if !STARTED.swap(true, Ordering::SeqCst) {
            std::thread::spawn(|| {
                let s = shared();
                loop {
                    let t0 = std::time::Instant::now();
                    while t0.elapsed().as_micros() < 20 {
                        std::hint::spin_loop();
                    }
                    let slots = s.slots.lock().unwrap();
                    for a in slots.iter() {
                        let k = a.load(Ordering::Relaxed) as usize;
                        if k != 255 {
                            s.counts[k].fetch_add(1, Ordering::Relaxed);
                        }
                    }
                }
            });
        }
        s
    }

    thread_local! {
        pub static MINE: Arc<AtomicU8> = {
            let a = Arc::new(AtomicU8::new(255));
            shared().slots.lock().unwrap().push(a.clone());
            a
        };
    }
}

/// Enters section `k`; returns the section to go back to.
#[inline(always)]
pub fn enter(_k: u8) -> u8 {
    #[cfg(feature = "prof")]
    {
        use std::sync::atomic::Ordering;
        return imp::MINE.with(|m| m.swap(_k, Ordering::Relaxed));
    }
    #[cfg(not(feature = "prof"))]
    0
}

#[inline(always)]
pub fn leave(_prev: u8) {
    #[cfg(feature = "prof")]
    {
        use std::sync::atomic::Ordering;
        imp::MINE.with(|m| m.store(_prev, Ordering::Relaxed));
    }
}

/// This thread is idle (not counted).
pub fn idle() {
    leave(255);
}

/// (name, share of samples) per section with samples.
pub fn totals() -> Vec<(&'static str, f64)> {
    #[cfg(feature = "prof")]
    {
        use std::sync::atomic::Ordering;
        let s = imp::shared();
        let c: Vec<u64> = s.counts.iter().map(|a| a.load(Ordering::Relaxed)).collect();
        let all: u64 = c.iter().sum::<u64>().max(1);
        return (0..N).filter(|&k| c[k] > 0).map(|k| (NAMES[k], c[k] as f64 / all as f64)).collect();
    }
    #[cfg(not(feature = "prof"))]
    Vec::new()
}
