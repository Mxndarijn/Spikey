//! Port of Yardstick/Leak.cs: the leak check: does a bot use what is not on screen yet? The
//! same seed is played twice by two fresh copies of the bot. At a fork tick T (just after
//! a wall bounce, so the screens stay the same for a whole flight) the second
//! sim gets every hidden draw replaced (BlindPlanner::blind_copy: the sim's
//! RNG, the room's wall seed, the room spine and the planned exits, plus the hazards'
//! hidden salts, private RNGs and drawn-but-unshown values). Both bots have
//! seen the same screen so far, so until the first tick where something
//! visible differs between the two sims, an honest bot taps the same. A tap
//! that differs before then came from the hidden future: a leak.
//! "Visible" is everything in the sim but those hidden values (`visible`).
//! Hidden values that blind_copy does not replace are not tested.
use rayon::prelude::*;
use serde_json::{json, Value};
use sim::hazards::updraft::Gust;
use sim::prelude::*;

use super::bots::BotSpec;
use super::stats::{jf, Stats};
use crate::bots::BlindPlanner;

pub struct Leak;

/// C# record Fork(seed, at, verdict, first_diff_tap, visible_from).
#[derive(Clone, Debug)]
pub struct Fork {
    pub seed: i64,
    pub at: i64,
    pub verdict: &'static str,
    pub first_diff_tap: i64,
    pub visible_from: i64,
}

impl Fork {
    fn new(seed: i64, at: i64, verdict: &'static str, first_diff_tap: i64, visible_from: i64) -> Fork {
        Fork { seed, at, verdict, first_diff_tap, visible_from }
    }
}

/// A rayon pool of `threads` workers (C# ParallelOptions.MaxDegreeOfParallelism).
pub fn pool(threads: i32) -> rayon::ThreadPool {
    rayon::ThreadPoolBuilder::new().num_threads(threads.max(1) as usize).build().expect("thread pool")
}

impl Leak {
    pub const FORKS: [i64; 6] = [200, 700, 1500, 3000, 5000, 8000];
    pub const WINDOW: i64 = 400;

    /// The sim's checksum with the hidden values blind_copy replaces set to
    /// fixed values (keep the two lists in step).
    pub fn visible(sim: &GameSim) -> i64 {
        let mut c = sim.clone_deep();
        c.room.rng_seed = 0;
        let st0 = &mut c.state;
        st0.plan_a_y_left = 0;
        st0.plan_a_kind_left = 0;
        st0.plan_b_y_left = 0;
        st0.plan_a_y_right = 0;
        st0.plan_a_kind_right = 0;
        st0.plan_b_y_right = 0;
        let room_t = c.room.t;
        for hz in c.room.hazards.iter_mut() {
            // C# `case Boss bs` (any boss subclass) comes first.
            if let Some(bs) = hz.as_boss_mut() {
                bs.seed = 0;
                continue;
            }
            match hz {
                Hz::CrateDrop(cd) => cd.salt = 0,
                Hz::Dart(d) => d.salt = 0,
                Hz::Drop(dr) => dr._rng.reseed(0),
                Hz::Firework(fw) => fw._rng.reseed(0),
                Hz::OrchardSpawner(os) => os._rng.reseed(0),
                Hz::Bubble(b) => {
                    b.next_x = 0;
                    // A late spiky bubble's glow is under half size until 3 * WARN before it rises.
                    if b.spiked && b.wait > 3 * Bubble::WARN {
                        b.x = 0;
                    }
                }
                Hz::Stalactite(st) if st.gap_y != st.target_y => {
                    st.target_y = st.gap_y + (st.target_y - st.gap_y).signum();
                }
                Hz::KeepyBall(kb) if kb.waiting > 0 && room_t < KeepyBall::SECOND_DROP => {
                    kb.x = 0;
                }
                Hz::Beam(bm) => {
                    let mut idle: Vec<usize> = Vec::new();
                    for i in 0..bm.delays.len() {
                        if bm.base.t < bm.delays[i] {
                            idle.push(i);
                        }
                    }
                    let mut vals: Vec<i64> = idle.iter().map(|&i| bm.delays[i]).collect();
                    vals.sort();
                    for i in 0..idle.len() {
                        bm.delays[idle[i]] = vals[i];
                    }
                }
                Hz::Updraft(up)
                    if up.drift_span == 0 && up.gust != Gust::NONE && up.base.t + up.phase < Updraft::GUST_OFF =>
                {
                    up.phase = 0;
                }
                _ => {}
            }
        }
        c.room.checksum(c.state.checksum())
    }

    /// One fork: "same" (no tap differs before the screen does), "leak",
    /// "nondeterministic" (the two runs differ before the fork), or "dead"
    /// (the run ended before T).
    pub fn fork(bot: &BotSpec, seed: i64, at_: i64) -> Fork {
        let mut at = at_;
        let mut a = (bot.make)(seed);
        let mut b = (bot.make)(seed);
        let mut sa = GameSim::new(seed);
        let mut sb = GameSim::new(seed);
        // Fork right after a bounce at or past `at`: the next wall is drawn at
        // the next bounce, so the screens then stay the same for a whole flight.
        let mut bounced = false;
        while sa.state.tick < at || !bounced {
            if sa.state.tick >= at + 300 {
                break;
            }
            if sa.is_over() || sb.is_over() {
                return Fork::new(seed, at, "dead", -1, -1);
            }
            let ta = a(&sa);
            let tb = b(&sb);
            if ta != tb {
                return Fork::new(seed, at, "nondeterministic", sa.state.tick, -1);
            }
            sa.step(ta);
            sb.step(tb);
            bounced = sa.state.tick > at && sa.events.contains(&Event::BOUNCE);
        }
        if sa.is_over() || !bounced {
            return Fork::new(seed, at, "dead", -1, -1);
        }
        at = sa.state.tick;
        // Both sims are swapped for copies, so a bot that remembers hazards by
        // object sees new objects in both runs alike; only B's hidden draws change.
        let mut sa = sa.clone_deep();
        let mut sb = BlindPlanner::blind_copy(&sb, SimRng::new(seed * 7919 + at), -1, 0);
        // A MotorPlayer keys hazards by (object set, index): tell it both sims are new objects.
        crate::human::sims_swapped();
        let mut visible_from: i64 = -1;
        let mut first_diff: i64 = -1;
        while sa.state.tick < at + Self::WINDOW && !sa.is_over() && !sb.is_over() {
            let t = sa.state.tick;
            if visible_from < 0 && Self::visible(&sa) != Self::visible(&sb) {
                visible_from = t;
            }
            let ta = a(&sa);
            let tb = b(&sb);
            if ta != tb && first_diff < 0 {
                first_diff = t;
            }
            if visible_from >= 0 {
                break;
            }
            sa.step(ta);
            sb.step(tb);
        }
        let leak = first_diff >= 0 && (visible_from < 0 || first_diff < visible_from);
        Fork::new(seed, at, if leak { "leak" } else { "same" }, first_diff, visible_from)
    }

    pub fn check(bot: &BotSpec, seeds: i32, threads: i32) -> Value {
        let jobs: Vec<(i64, i64)> =
            (1..=seeds as i64).flat_map(|s| Self::FORKS.iter().map(move |&t| (s, t))).collect();
        let res: Vec<Fork> = pool(threads).install(|| jobs.par_iter().map(|&(s, t)| Self::fork(bot, s, t)).collect());
        let leaks = res.iter().filter(|f| f.verdict == "leak").count() as i32;
        let tested = res.iter().filter(|f| f.verdict == "leak" || f.verdict == "same").count() as i32;
        let nondet = res.iter().filter(|f| f.verdict == "nondeterministic").count() as i32;
        let ex = res.iter().find(|f| f.verdict == "leak");
        let verdict = if nondet > 0 {
            "nondeterministic"
        } else if tested == 0 {
            "untested"
        } else if leaks > 0 {
            "yes"
        } else {
            "no"
        };
        let same: Vec<f64> = res
            .iter()
            .filter(|f| f.verdict == "leak" || f.verdict == "same")
            .map(|f| ((if f.visible_from < 0 { f.at + Self::WINDOW } else { f.visible_from }) - f.at) as f64)
            .collect();
        let mut o = json!({
            "leaks": verdict,
            "forks_tested": tested,
            "forks_leaking": leaks,
            "nondeterministic": nondet,
            // How long the screens stayed the same after the forks: the test only sees leaks inside that time.
            // (Not rounded, as in C#; null when nothing was tested, where C# would fail to write NaN.)
            "same_screen_ticks_median": jf(Stats::pct(&same, 0.5)),
            "how": "same seed twice, every hidden draw replaced at the fork; a tap differing before anything visible differs is a leak",
        });
        if let Some(ex) = ex {
            let tail = if ex.visible_from < 0 {
                "nothing visible differed yet".to_string()
            } else {
                format!("the screen differed only from tick {}", ex.visible_from)
            };
            o.as_object_mut().unwrap().insert(
                "example".to_string(),
                Value::from(format!(
                    "seed {}, fork at tick {}: taps differ at tick {}, {}",
                    ex.seed, ex.at, ex.first_diff_tap, tail
                )),
            );
        }
        o
    }
}
