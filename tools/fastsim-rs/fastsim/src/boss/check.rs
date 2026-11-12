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
    pub const KNOWN: [((&'static str, i64, i64, &'static str, i64), &'static str); 9] = [
        (("boss_watcher", 3, 3, "dart", 3), "room-fixes (hit during the reaction)"),
        (("boss_watcher", 3, 19, "rows", 3), "room-fixes (no way through)"),
        (("boss_crusher", 3, 1, "jaw", 2), "room-fixes (no way through)"),
        (("boss_crusher", 3, 2, "jaw", 3), "room-fixes (no way through)"),
        (("boss_saw", 1, 10, "hop", 3), "room-fixes (no way through)"),
        (("boss_saw", 3, 6, "hop", 3), "room-fixes (hit during the reaction)"),
        // Met once the planner's copies stopped reading the room's wall count (its lines changed).
        (("boss_watcher", 3, 18, "dart", 2), "room-fixes (no way through)"),
        (("boss_crusher", 3, 5, "jaw", 3), "room-fixes (no way through)"),
        (("boss_crusher", 3, 19, "jaw", 2), "room-fixes (hit during the reaction)"),
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
        "tools/fastsim/Bots/BossFairCheck.cs"
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
