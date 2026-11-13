//! Port of Bots/ArrivalMemo.cs. Planner copies only (`GameSim.memo_arrivals`,
//! set by BlindPlanner.blind_copy): remembers `GameSim._arrival_retries`. The
//! key is the state but for the fields the arrival never reads (x, y, vx, vy,
//! tick, flaps, coins, pickup_x, pickup_y, death_cause, revives), both RNGs,
//! the new room's seed, the free run of the last wall and the points overrides.
//! The real game never uses this. Tool only.
use std::cell::RefCell;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};

use crate::game_sim::GameSim;

pub struct ArrivalMemo;

pub static ON: AtomicBool = AtomicBool::new(true);
/// Check mode: on a hit, run the check anyway and count answers that differ.
pub static VERIFY: AtomicBool = AtomicBool::new(false);
pub static WRONG: AtomicI64 = AtomicI64::new(0);
pub static HITS: AtomicI64 = AtomicI64::new(0);
pub static MISSES: AtomicI64 = AtomicI64::new(0);

thread_local! {
    static MEMO: RefCell<HashMap<Vec<i64>, (i64, i64)>> = RefCell::new(HashMap::new());
}

impl ArrivalMemo {
    fn key(sim: &GameSim, side: i64, next: i64) -> Vec<i64> {
        let s = &sim.state;
        let b = |v: bool| v as i64;
        let mut k = Vec::with_capacity(60);
        k.extend_from_slice(&[side, next]);
        // SimState in field order, without the skipped fields.
        k.extend_from_slice(&[
            b(s.started),
            b(s.alive),
            s.score,
            s.room_index,
            s.room_kind,
            s.left_spikes,
            s.right_spikes,
            b(s.coin_active),
            s.coin_x,
            s.coin_y,
            b(s.exit_open),
            b(s.exit_preview),
            s.exit_side,
            s.exit_a_y,
            s.exit_a_kind,
            s.exit_b_y,
            s.exit_b_kind,
            s.route,
            s.bosses_met,
            s.deck_lo,
            s.deck_hi,
            s.arrival_hold,
            s.anchor_y,
            s.plan_a_y_left,
            s.plan_a_kind_left,
            s.plan_b_y_left,
            s.plan_a_y_right,
            s.plan_a_kind_right,
            s.plan_b_y_right,
            s.plan_at,
        ]);
        for r in [&sim._rng, &sim._spine] {
            k.extend_from_slice(&[r._s0, r._s1, r._s2, r._s3]);
        }
        k.extend_from_slice(&[
            sim.room.rng_seed,
            sim._free_lo,
            sim._free_hi,
            sim._points_override,
            sim._points_also,
            sim.season,
            sim.practice_room,
            sim.forced_variant.as_ptr() as i64,
            sim._checking as i64,
        ]);
        k
    }

    fn flags(sim: &GameSim) -> i64 {
        (sim._arrival_unpin as i64) | ((sim._arrival_unfit as i64) << 1) | ((sim._arrival_band as i64) << 2)
    }

    pub fn retries(sim: &mut GameSim, side: i64, next: i64) -> i64 {
        if !ON.load(Ordering::Relaxed) {
            return sim._arrival_retries(side, next);
        }
        let k = Self::key(sim, side, next);
        let got = MEMO.with(|m| m.borrow().get(&k).copied());
        // `flags`: bit 0 _arrival_unpin, bit 1 _arrival_unfit, bit 2 _arrival_band (what _arrival_retries sets).
        if let Some((skip, flags)) = got {
            if VERIFY.load(Ordering::Relaxed) {
                let s2 = sim._arrival_retries(side, next);
                if s2 != skip || Self::flags(sim) != flags {
                    WRONG.fetch_add(1, Ordering::Relaxed);
                }
            }
            HITS.fetch_add(1, Ordering::Relaxed);
            sim._arrival_unpin = flags & 1 != 0;
            sim._arrival_unfit = flags & 2 != 0;
            sim._arrival_band = flags & 4 != 0;
            return skip;
        }
        MISSES.fetch_add(1, Ordering::Relaxed);
        let skip = sim._arrival_retries(side, next);
        let wait = Self::flags(sim);
        MEMO.with(|m| {
            let mut m = m.borrow_mut();
            if m.len() > 4096 {
                m.clear();
            }
            m.insert(k, (skip, wait));
        });
        skip
    }
}
