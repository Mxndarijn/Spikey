//! Port of Measure/Tier.cs: tier verdicts from a holdout run set (docs/BOT_TESTING.md, "Report").
//!   beginner..expert: the KM median and its interval. A bot fits its tier
//!     when the median is within +-15% of the target and the whole interval
//!     lies inside the tier's band (edges: geometric middles of the targets).
//!   beast: the KM median is missing (half the runs reach the cap) or above
//!     354. Reported by its plateau rate (deaths per 100 points from 40 on).
//!   infinite: every run that can be finished is finished. Which runs can be
//!     finished comes from the fairness judge (`rl review fair`): a death it
//!     calls `bot` had an honest, visible-only line (a 1 s reaction); deaths it
//!     calls reaction, hidden or lost had none, so those runs do not count.
//!     finished share = alive at the cap / (alive + bot deaths), Wilson CI.
use std::collections::HashMap;

use serde_json::{json, Map, Value};

use super::jr;
use crate::yardstick::stats::jf;
use crate::yardstick::fmt_num;
use crate::yardstick::stats::Stats;
use crate::yardstick::survival::{self, Set};

pub struct Tier;

impl Tier {
    pub const FIT: f64 = 0.15;
    pub const FINISHABLE: [&'static str; 1] = ["bot"];

    pub fn band(tier: &str) -> (f64, f64) {
        let t = Stats::TIERS;
        let i = match t.iter().position(|x| x.0 == tier) {
            Some(i) => i,
            None => return (f64::NAN, f64::NAN),
        };
        let lo = if i == 0 { (t[0].1 * t[0].1 / 2.0).sqrt() } else { (t[i - 1].1 * t[i].1).sqrt() };
        let hi = if i == t.len() - 1 { f64::INFINITY } else { (t[i].1 * t[i + 1].1).sqrt() };
        (lo, hi)
    }

    /// Fairness file of `rl review fair`: the death rows (seed, ..., verdict).
    pub fn load_fair(path: &str) -> Result<HashMap<i64, String>, String> {
        let mut res = HashMap::new();
        let text = std::fs::read_to_string(path).map_err(|_| format!("Could not find file '{}'.", path))?;
        let lines: Vec<&str> = text.trim_start_matches('\u{feff}').lines().collect();
        let head = lines
            .iter()
            .position(|l| l.starts_with("seed\tscore\ttick\troom\tcause\tverdict"))
            .ok_or_else(|| format!("{}: no death rows of `rl review fair`", path))?;
        for line in &lines[head + 1..] {
            let c: Vec<&str> = line.split('\t').collect();
            if c.len() < 6 {
                break;
            }
            let seed: i64 = match c[0].trim().parse() {
                Ok(s) => s,
                Err(_) => break,
            };
            res.insert(seed, c[5].to_string());
        }
        Ok(res)
    }

    /// C# default: reps = 2000.
    pub fn verdict(set: &Set, claimed: &str, fair: Option<&HashMap<i64, String>>, reps: i32) -> Result<Value, String> {
        let d = survival::describe(set, reps);
        let km = d["km_median"].clone();
        let med = km["value"].as_f64().unwrap_or(f64::NAN);
        let lo = km["lo"].as_f64().unwrap_or(f64::NAN);
        let hi = km["hi"].as_f64().unwrap_or(f64::NAN);
        let mut o = Map::new();
        o.insert("runs".into(), (set.runs.len() as i64).into());
        o.insert("deaths".into(), set.deaths().into());
        o.insert("cap_ticks".into(), set.cap.into());
        o.insert("km_median".into(), km.clone());
        o.insert("per_100_plateau".into(), d["per_100_plateau"].clone());
        o.insert("alive_share".into(), d["alive_share"].clone());
        let beast_edge = Self::band("beast").0;
        let beast = med.is_nan() || med >= beast_edge;
        let tier = if beast { "beast".to_string() } else { Stats::tier_of(med) };
        o.insert("tier".into(), tier.into());
        if !claimed.is_empty() && claimed != "beast" && claimed != "infinite" {
            let (blo, bhi) = Self::band(claimed);
            let target = Stats::TIERS
                .iter()
                .find(|t| t.0 == claimed)
                .map(|t| t.1)
                .ok_or_else(|| format!("Sequence contains no matching element (no tier '{}')", claimed))?;
            let near = !med.is_nan() && (med / target - 1.0).abs() <= Self::FIT;
            let inside = !lo.is_nan() && !hi.is_nan() && lo >= blo && hi < bhi;
            o.insert("claimed".into(), claimed.into());
            o.insert("target".into(), jf(target));
            o.insert("band".into(), json!([jr(blo, 1), jr(bhi, 1)]));
            o.insert("off_target".into(), if med.is_nan() { Value::Null } else { jr(med / target - 1.0, 3) });
            o.insert("fits".into(), (near && inside).into());
            let why = if near && inside {
                "median within 15% of the target and its CI inside the band".to_string()
            } else if !near {
                format!("median {} is more than 15% from {}", fmt_num(med, "F0"), target)
            } else {
                format!(
                    "CI [{}, {}] leaves the band [{}, {})",
                    fmt_num(lo, "F0"),
                    fmt_num(hi, "F0"),
                    fmt_num(blo, "F0"),
                    fmt_num(bhi, "F0")
                )
            };
            o.insert("why".into(), why.into());
        }
        if beast || claimed == "beast" || claimed == "infinite" {
            o.insert("claimed".into(), if claimed.is_empty() { Value::Null } else { claimed.into() });
            o.insert("fits_beast".into(), (beast && (lo.is_nan() || lo >= beast_edge)).into());
            if let Some(fair) = fair {
                let alive = set.alive();
                let mut finishable_deaths = 0;
                let mut unfinishable = 0;
                let mut unjudged = 0;
                for r in set.runs.iter().filter(|r| r.dead) {
                    match fair.get(&r.seed) {
                        None => unjudged += 1,
                        Some(v) if Self::FINISHABLE.contains(&v.as_str()) => finishable_deaths += 1,
                        Some(_) => unfinishable += 1,
                    }
                }
                let n = alive + finishable_deaths;
                let (wlo, whi) = survival::wilson(alive, n);
                o.insert(
                    "finishable".into(),
                    json!({
                        "runs": n, "finished": alive,
                        "share": if n == 0 { Value::Null } else { jr(alive as f64 / n as f64, 4) },
                        "lo": jr(wlo, 4), "hi": jr(whi, 4),
                        "deaths_with_an_honest_line": finishable_deaths, "deaths_without": unfinishable,
                        "deaths_not_judged": unjudged,
                    }),
                );
                o.insert("infinite".into(), (unjudged == 0 && finishable_deaths == 0 && n > 0).into());
                o.insert(
                    "infinite_rule".into(),
                    "every run that can be finished (fairness judge: an honest line existed) reached the cap".into(),
                );
            } else {
                o.insert("infinite".into(), "needs --fair (rl review fair on the same seeds)".into());
            }
        }
        Ok(Value::Object(o))
    }
}
