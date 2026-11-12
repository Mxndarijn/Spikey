//! Port of Yardstick/Timing.cs: tap timing against the ideal moment (Isaksen et al., FDG 2015).
//! A press is a tap, or a burst of taps no more than PRESS_GAP ticks apart (a bot can tap
//! on many ticks in a row; a human finger makes one press). For a press at
//! tick t, move it to t+d for every d in -SHIFT..SHIFT, keep the run's other
//! taps where they were, and replay: the shifts after which the bird is still
//! alive HORIZON ticks past t+SHIFT form the press's window. The ideal moment
//! is the window's middle and the press's error is its distance from it
//! (positive = late). Only presses whose window is closed on both sides are
//! timing-critical; for the others any time nearby works. This replays the
//! real sim, but only to judge a tap already made, never to make one.
use std::collections::HashSet;

use sim::prelude::*;

use super::runs::{Run, RunInput};

/// C# Timing.Result.
#[derive(Clone, Debug, Default)]
pub struct TimingResult {
    pub taps_judged: i32,
    pub critical: i32,
    /// Press tick minus the ideal tick, for the timing-critical presses.
    pub errors: Vec<f64>,
    pub widths: Vec<i32>,
}

pub struct Timing;

impl Timing {
    pub const SHIFT: i32 = 12;
    pub const HORIZON: i64 = 40;
    pub const PRESS_GAP: i64 = 3;

    /// The presses of a run: (first tick, taps in it).
    pub fn presses(taps: &[i64]) -> Vec<(i64, Vec<i64>)> {
        let mut out_ = Vec::new();
        let mut i = 0;
        while i < taps.len() {
            let mut j = i;
            while j + 1 < taps.len() && taps[j + 1] - taps[j] <= Self::PRESS_GAP {
                j += 1;
            }
            out_.push((taps[i], taps[i..j + 1].to_vec()));
            i = j + 1;
        }
        out_
    }

    /// Judges up to `per_run` presses of the run, spread evenly over it.
    pub fn judge(r: &RunInput, played: &Run, per_run: i32) -> TimingResult {
        let shift = Self::SHIFT as i64;
        let mut res = TimingResult::default();
        let last_ok = played.ticks - shift - Self::HORIZON - 1;
        let all = Self::presses(&r.taps);
        let cand: Vec<&(i64, Vec<i64>)> = all
            .iter()
            .filter(|p| p.0 >= played.start_tick + shift && p.1[p.1.len() - 1] + shift <= last_ok)
            .collect();
        if cand.is_empty() {
            return res;
        }
        let want = (per_run as usize).min(cand.len());
        // C# .Distinct(): the indexes i * Count / want rise strictly, so nothing repeats.
        let pick: Vec<&(i64, Vec<i64>)> = (0..want).map(|i| cand[i * cand.len() / want]).collect();
        let tapset: HashSet<i64> = r.taps.iter().copied().collect();
        let mut sim = GameSim::with(r.seed, r.season, -1, "");
        for (t, press) in pick {
            let from = t - shift;
            if sim.state.tick > from {
                continue;
            }
            while sim.state.tick < from && !sim.is_over() {
                let tap = tapset.contains(&sim.state.tick);
                sim.step(tap);
            }
            if sim.is_over() {
                break;
            }
            let mine: HashSet<i64> = press.iter().copied().collect();
            let end = press[press.len() - 1] + shift + Self::HORIZON;
            let mut ok = vec![false; 2 * Self::SHIFT as usize + 1];
            for d in -shift..=shift {
                if d == 0 {
                    ok[Self::SHIFT as usize] = true;
                    continue;
                }
                let mut c = sim.clone_deep();
                while c.state.tick < end && !c.is_over() {
                    let k = c.state.tick;
                    let tap = mine.contains(&(k - d)) || (!mine.contains(&k) && tapset.contains(&k));
                    c.step(tap);
                }
                ok[(d + shift) as usize] = !c.is_over();
            }
            res.taps_judged += 1;
            let mut lo = Self::SHIFT;
            let mut hi = Self::SHIFT;
            while lo > 0 && ok[(lo - 1) as usize] {
                lo -= 1;
            }
            while hi < 2 * Self::SHIFT && ok[(hi + 1) as usize] {
                hi += 1;
            }
            if lo == 0 || hi == 2 * Self::SHIFT {
                continue;
            }
            res.critical += 1;
            res.widths.push(hi - lo + 1);
            res.errors.push(Self::SHIFT as f64 - (lo + hi) as f64 / 2.0);
        }
        res
    }
}
