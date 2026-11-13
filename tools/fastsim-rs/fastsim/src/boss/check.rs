//! Checks.BossFair (Bots/BossFairCheck.cs), `bossfair`: every boss tell is fair with a 1 s
//! reaction (research/planner-review/07-bosses.md, `fastsim boss fair`). The honest planner
//! plays each boss room; at every new tell the bird keeps its old plan for REACT ticks, then
//! SurvivalSearch must still find a way through the told attack. A tell fails when there is no
//! way (verdict 0) or the old plan is hit by the boss within the reaction (-1). Tiers 1 and 3.
use serde_json::{json, Value};

use super::{fair_rows, BOSSES};
use crate::checks::{i, result, Check};

pub struct BossFair;

impl BossFair {
    pub const REACT: i64 = 60;
    pub const SEEDS: i64 = 20;
    pub const TIERS: [i64; 2] = [1, 3];

    /// Unfair tells allowed while their fix is in flight: (boss, tier, seed, tell kind, phase) -> owner.
    /// One entry per case, so any other unfair tell still fails. Remove an entry when its fix lands.
    pub const KNOWN: &'static [((&'static str, i64, i64, &'static str, i64), &'static str)] = &[
        // The old plan's tap at step 50 lifts the bird past the left wall's gap (slots 8-11);
        // the plan without it, or with one more early tap, gets through (tell at tick 1324).
        (
            ("boss_crusher", 1, 13, "jaw", 3),
            "boss-rhythm: pre-tell tap into a wall dead end (fair line exists, seed 13 tick 1324)",
        ),
        // The tap at step 53 holds the bird at the right wall's spike (slot 6); one more tap
        // at steps 3-18 gets through (tell at tick 743).
        (
            ("boss_watcher", 3, 1, "dart", 2),
            "boss-rhythm: pre-tell tap into a wall dead end (fair line exists, seed 1 tick 743)",
        ),
        // The tap at step 51 keeps the bird high, into the king's landing; a plan with one more
        // tap at step 6, or without the tap at 51, gets through for either landing (tick 1324).
        (
            ("boss_saw", 3, 11, "hop", 3),
            "boss-rhythm: pre-tell tap into a wall dead end (fair line exists, seed 11 tick 1324)",
        ),
        // The exit opens on the right wall 16 steps after the tell (slots 7-9); the old plan
        // (taps at 8 and 56) meets the slot-6 spike, one more tap at steps 0-21 gets through.
        (
            ("boss_crusher", 1, 12, "crate", 3),
            "wall-timing: pre-tell plan into a wall dead end (fair line exists, seed 12 tick 1734)",
        ),
        // 14-slot walls: the hop from 180 to 320 px meets the old plan (tap at step 10) during the
        // reaction; that plan plus one tap at step 6, 15, 18 or 21 gets through (tell at tick 1504).
        (
            ("boss_saw", 3, 15, "hop", 3),
            "edge-corners: pre-tell plan into the king's landing (fair line exists, seed 15 tick 1504)",
        ),
    ];

    fn known(boss: &str, tier: i64, seed: i64, kind: &str, phase: i64) -> bool {
        Self::KNOWN.iter().any(|(k, _)| k.0 == boss && k.1 == tier && k.2 == seed && k.3 == kind && k.4 == phase)
    }

    fn cases() -> Vec<(&'static str, i64, i64)> {
        let mut out_ = Vec::new();
        for b in BOSSES {
            for t in Self::TIERS {
                for s in 1..=Self::SEEDS {
                    out_.push((b, t, s));
                }
            }
        }
        out_
    }
}

impl Check for BossFair {
    fn name(&self) -> &'static str {
        "bossfair"
    }
    fn test(&self) -> &'static str {
        "tools/fastsim-rs/fastsim/src/boss/check.rs"
    }
    fn count(&self) -> usize {
        Self::cases().len()
    }

    fn run(&self, n: usize) -> Value {
        let (boss, tier, seed) = Self::cases()[n];
        let rows = fair_rows(boss, seed, tier, &[Self::REACT]);
        let mut fails = Vec::new();
        let mut tells: Vec<Value> = Vec::new();
        for r in &rows {
            let known = Self::known(boss, tier, seed, r.kind, r.phase);
            tells.push(json!([r.kind, r.phase, r.verdict, known]));
            if (r.verdict == 0 || r.verdict == -1) && !known {
                fails.push(format!(
                    "{} tier {} seed {}: {} tell (phase {}) at tick {} is unfair at R={} ({})",
                    boss,
                    tier,
                    seed,
                    r.kind,
                    r.phase,
                    r.tick,
                    Self::REACT,
                    if r.verdict == 0 { "no way through" } else { "hit during the reaction" }
                ));
            }
        }
        result(fails, json!({ "boss": boss, "tells": tells }))
    }

    fn summary(&self, results: &[Value]) -> String {
        let mut all: Vec<(i64, bool)> = Vec::new();
        for r in results {
            if let Some(a) = r["tells"].as_array() {
                for t in a {
                    all.push((i(&t[2]), t[3].as_bool().unwrap_or(false)));
                }
            }
        }
        let bad = all.iter().filter(|t| t.0 == 0 || t.0 == -1).count();
        let known = all.iter().filter(|t| (t.0 == 0 || t.0 == -1) && t.1).count();
        format!(
            "{} boss tells (3 bosses, tiers 1 and 3, seeds 1..{}), {} unfair at R={}{}",
            all.len(),
            Self::SEEDS,
            bad,
            Self::REACT,
            if known > 0 { format!(" ({} known)", known) } else { String::new() }
        )
    }
}
