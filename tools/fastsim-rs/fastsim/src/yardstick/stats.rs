//! Port of Yardstick/Stats.cs: the numbers of one run set: strength, tier fit and how human it plays.
//! Doubles are computed in the C# order (LINQ Sum/Average add left to right), so the numbers match.
use serde_json::{json, Map, Value};

use super::runs::Run;
use super::timing::TimingResult;

/// C# `Math.Round(x, digits)` (.NET Core: scale by 10^digits, round half to even, scale back;
/// values of 1e16 or more, NaN and infinities are returned as they are).
pub fn round(x: f64, digits: i32) -> f64 {
    const POW10: [f64; 16] = [1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15];
    if x.abs() < 1e16 {
        let p = POW10[digits as usize];
        (x * p).round_ties_even() / p
    } else {
        x
    }
}

/// A double as System.Text.Json writes it: whole numbers without ".0" (so the file text
/// matches the C# one), NaN and infinities as null (C# would throw on them).
pub fn jf(x: f64) -> Value {
    if !x.is_finite() {
        Value::Null
    } else if x.fract() == 0.0 && x.abs() < 1e15 {
        Value::from(x as i64)
    } else {
        Value::from(x)
    }
}

/// C# LINQ `Sum()` over doubles: left to right from 0.
pub fn sum(xs: &[f64]) -> f64 {
    let mut s = 0.0;
    for &x in xs {
        s += x;
    }
    s
}

/// C# LINQ `Average()` over doubles (C# throws on an empty list; callers guard it).
pub fn average(xs: &[f64]) -> f64 {
    sum(xs) / xs.len() as f64
}

pub struct Stats;

impl Stats {
    /// The tier targets (medians); beast is 500 or more.
    pub const TIERS: [(&'static str, f64); 5] =
        [("beginner", 30.0), ("normal", 60.0), ("good", 120.0), ("expert", 250.0), ("beast", 500.0)];
    /// Inter-tap interval histogram bins, in ticks (upper bounds; the last is open).
    pub const INTERVAL_BINS: [i32; 12] = [4, 7, 10, 13, 16, 20, 25, 32, 40, 50, 64, i32::MAX];
    /// Reaction histogram bins, in ticks.
    pub const REACT_BINS: [i32; 11] = [3, 6, 9, 12, 15, 18, 21, 25, 30, 40, Run::REACT_WINDOW];
    /// Humans: at most 7.7 taps a second (Isaksen 2015), so taps are 8+ ticks apart.
    pub const HUMAN_MIN_INTERVAL: i32 = 8;
    /// Humans: timing error sigma 35.9-61.1 ms around the ideal tap.
    pub const HUMAN_SIGMA_LO: f64 = 2.2;
    pub const HUMAN_SIGMA_HI: f64 = 3.7;
    /// Humans: reaction to a new obstacle 288 ms on average; under ~170 ms is rare.
    #[allow(dead_code)]
    pub const HUMAN_REACT_MEAN: f64 = 17.0;
    pub const HUMAN_REACT_FAST: f64 = 10.0;

    pub fn pct(xs: &[f64], p: f64) -> f64 {
        let mut s = xs.to_vec();
        s.sort_by(|a, b| a.partial_cmp(b).unwrap());
        if s.is_empty() {
            return f64::NAN;
        }
        let at = p * (s.len() - 1) as f64;
        let lo = at.floor() as usize;
        let hi = at.ceil() as usize;
        s[lo] + (s[hi] - s[lo]) * (at - lo as f64)
    }

    fn sd(xs: &[f64]) -> f64 {
        if xs.len() < 2 {
            return f64::NAN;
        }
        let m = average(xs);
        let mut ss = 0.0;
        for &x in xs {
            ss += (x - m) * (x - m);
        }
        (ss / (xs.len() - 1) as f64).sqrt()
    }

    pub fn hist(xs: &[i32], bins: &[i32]) -> Vec<f64> {
        let mut h = vec![0.0; bins.len()];
        let mut n = 0i32;
        for &x in xs {
            let mut i = 0;
            while i < bins.len() - 1 && x > bins[i] {
                i += 1;
            }
            h[i] += 1.0;
            n += 1;
        }
        if n > 0 {
            for v in h.iter_mut() {
                *v /= n as f64;
            }
        }
        h
    }

    pub fn band_shares<'a>(runs: impl IntoIterator<Item = &'a Run>) -> Vec<f64> {
        let mut b = vec![0.0; Run::BANDS];
        for r in runs {
            for i in 0..Run::BANDS {
                b[i] += r.bands[i] as f64;
            }
        }
        let total = sum(&b);
        if total > 0.0 {
            for v in b.iter_mut() {
                *v /= total;
            }
        }
        b
    }

    /// Per-point death chance h (geometric, capped runs count as survived
    /// points), and the median it implies: ln 0.5 / ln(1 - h).
    pub fn death_rate(runs: &[Run]) -> (f64, f64) {
        let deaths = runs.iter().filter(|r| r.dead).count() as i64;
        let exposure = runs.iter().map(|r| r.points).sum::<i64>() + deaths;
        if deaths == 0 || exposure == 0 {
            return (0.0, f64::INFINITY);
        }
        let h = deaths as f64 / exposure as f64;
        (h, if h >= 1.0 { 0.0 } else { 0.5f64.ln() / (1.0 - h).ln() })
    }

    /// Kolmogorov-Smirnov distance between the scores and the geometric fit.
    /// Small (under ~0.1) means "dies at a steady rate", as human populations do.
    pub fn exp_fit(runs: &[Run], h: f64) -> f64 {
        if h <= 0.0 {
            return f64::NAN;
        }
        let mut pts: Vec<i64> = runs.iter().map(|r| r.points).collect();
        pts.sort();
        let mut d: f64 = 0.0;
        for i in 0..pts.len() {
            let model = 1.0 - (1.0 - h).powf((pts[i] + 1) as f64);
            let below = i as f64 / pts.len() as f64;
            let upto = (i + 1) as f64 / pts.len() as f64;
            d = d.max((upto - model).abs().max((model - below).abs()));
        }
        d
    }

    /// The tier a median lands in: the nearest target on a log scale
    /// (edges at the geometric middles: 42, 85, 173, 354).
    pub fn tier_of(median: f64) -> String {
        if median.is_nan() {
            return "-".to_string();
        }
        if median < Self::TIERS[0].1 / 2f64.sqrt() {
            return "below beginner".to_string();
        }
        for i in 0..Self::TIERS.len() - 1 {
            if median < (Self::TIERS[i].1 * Self::TIERS[i + 1].1).sqrt() {
                return Self::TIERS[i].0.to_string();
            }
        }
        "beast".to_string()
    }

    /// The tier a bot's name claims ("rl:good" -> good), or "".
    pub fn claimed_tier(bot: &str) -> String {
        let last = match bot.rfind(':') {
            Some(i) => &bot[i + 1..],
            None => bot,
        };
        if Self::TIERS.iter().any(|t| t.0 == last) {
            last.to_string()
        } else {
            String::new()
        }
    }

    /// Score bands for deaths per 100 points (bot-review.md): the rate rises
    /// steeply through the first rooms, then levels off.
    pub const SCORE_BANDS: [i64; 7] = [0, 10, 20, 40, 80, 160, 320];

    /// Deaths per 100 points scored inside each band: a run that ends at p
    /// spent min(p, hi) - lo points in a band it reached, and died in the
    /// band holding p. Capped runs count their points and no death.
    pub fn band_rates(runs: &[Run]) -> Value {
        let mut out_ = Vec::new();
        for i in 0..Self::SCORE_BANDS.len() {
            let lo = Self::SCORE_BANDS[i];
            let hi = if i + 1 < Self::SCORE_BANDS.len() { Self::SCORE_BANDS[i + 1] } else { i64::MAX };
            let pts: i64 = runs.iter().filter(|r| r.points > lo).map(|r| r.points.min(hi) - lo).sum();
            let deaths = runs.iter().filter(|r| r.dead && r.points >= lo && r.points < hi).count() as i32;
            let reached = runs.iter().filter(|r| r.points >= lo).count() as i32;
            out_.push(json!({
                "band": if hi == i64::MAX { format!("{}+", lo) } else { format!("{}..{}", lo, hi) },
                "reached": reached,
                "points": pts,
                "deaths": deaths,
                "per_100": if pts == 0 { Value::Null } else { jf(round(100.0 * deaths as f64 / pts as f64, 3)) },
            }));
        }
        Value::Array(out_)
    }

    /// Groups in first-appearance order (C# GroupBy), as (key, count).
    fn group_count<'a>(keys: impl Iterator<Item = &'a str>) -> Vec<(String, i32)> {
        let mut g: Vec<(String, i32)> = Vec::new();
        for k in keys {
            match g.iter_mut().find(|(x, _)| x == k) {
                Some(e) => e.1 += 1,
                None => g.push((k.to_string(), 1)),
            }
        }
        g
    }

    pub fn strength(runs: &[Run]) -> Value {
        let pts: Vec<f64> = runs.iter().map(|r| r.points as f64).collect();
        let (h, exp_median) = Self::death_rate(runs);
        let deaths = runs.iter().filter(|r| r.dead).count() as i32;
        // C# Dictionary<string, long>: enumerated in insertion order.
        let mut visits: Vec<(String, i64)> = Vec::new();
        for r in runs {
            for (k, v) in &r.visits {
                match visits.iter_mut().find(|(x, _)| x == k) {
                    Some(e) => e.1 += *v as i64,
                    None => visits.push((k.clone(), *v as i64)),
                }
            }
        }
        let visits_of = |k: &str| visits.iter().find(|(x, _)| x == k).map(|e| e.1).unwrap_or(0);
        // GroupBy(room) then a stable OrderByDescending(count).
        let mut groups = Self::group_count(runs.iter().filter(|r| r.dead).map(|r| r.room.as_str()));
        let dead_in_list = groups.clone();
        groups.sort_by(|a, b| b.1.cmp(&a.1));
        let mut killers = Vec::new();
        for (room, count) in groups.iter().take(8) {
            let v = visits_of(room).max(1);
            killers.push(json!({
                "room": room,
                "deaths": count,
                "share": jf(round(*count as f64 / deaths.max(1) as f64, 4)),
                "visits": v,
                "per_visit": jf(round(*count as f64 / v as f64, 4)),
            }));
        }
        // The rooms most likely to kill per visit (seen 20+ times).
        let dead_in = |k: &str| dead_in_list.iter().find(|(x, _)| x == k).map(|e| e.1).unwrap_or(0);
        let mut often: Vec<&(String, i64)> = visits.iter().filter(|kv| kv.1 >= 20).collect();
        often.sort_by(|a, b| {
            let ra = dead_in(&a.0) as f64 / a.1 as f64;
            let rb = dead_in(&b.0) as f64 / b.1 as f64;
            rb.partial_cmp(&ra).unwrap()
        });
        let mut deadly = Vec::new();
        for kv in often.iter().take(8) {
            deadly.push(json!({
                "room": kv.0,
                "per_visit": jf(round(dead_in(&kv.0) as f64 / kv.1 as f64, 4)),
                "visits": kv.1,
            }));
        }
        let mut cause_groups = Self::group_count(runs.iter().filter(|r| r.dead).map(|r| r.cause.as_str()));
        cause_groups.sort_by(|a, b| b.1.cmp(&a.1));
        let mut causes = Map::new();
        for (cause, count) in &cause_groups {
            causes.insert(cause.to_lowercase(), jf(round(*count as f64 / deaths.max(1) as f64, 4)));
        }
        let median = Self::pct(&pts, 0.5);
        let ticks: Vec<f64> = runs.iter().map(|r| r.ticks as f64).collect();
        json!({
            "runs": runs.len(),
            "median": Self::num(median, 1),
            "p25": Self::num(Self::pct(&pts, 0.25), 1),
            "p75": Self::num(Self::pct(&pts, 0.75), 1),
            "p90": Self::num(Self::pct(&pts, 0.9), 1),
            "mean": jf(round(if pts.is_empty() { 0.0 } else { average(&pts) }, 2)),
            "deaths": deaths,
            "capped": runs.len() as i32 - deaths,
            "death_rate_per_point": jf(round(h, 6)),
            "rate_median": Self::num(exp_median, 1),
            "tier_by_median": Self::tier_of(median),
            "tier_by_rate": if exp_median.is_infinite() { "beast".to_string() } else { Self::tier_of(exp_median) },
            "exp_fit_ks": Self::num(Self::exp_fit(runs, h), 4),
            "deaths_per_100_by_band": Self::band_rates(runs),
            "mean_ticks": jf(round(if runs.is_empty() { 0.0 } else { average(&ticks) }, 0)),
            "killers": killers,
            "deadliest_per_visit": deadly,
            "causes": causes,
        })
    }

    /// C# `arr(xs, digits = 4)`.
    fn arr(xs: &[f64], digits: i32) -> Value {
        Value::Array(xs.iter().map(|&x| jf(round(x, digits))).collect())
    }

    fn arr_i(xs: &[i32]) -> Value {
        Value::Array(xs.iter().map(|&x| Value::from(if x == i32::MAX { -1 } else { x })).collect())
    }

    /// C# `num(x, digits = 3)`: null for NaN and infinities.
    pub fn num(x: f64, digits: i32) -> Value {
        if x.is_nan() || x.is_infinite() {
            Value::Null
        } else {
            jf(round(x, digits))
        }
    }

    /// `double.IsNaN(x) ? null : test`.
    fn ok(x: f64, test: bool) -> Value {
        if x.is_nan() {
            Value::Null
        } else {
            Value::Bool(test)
        }
    }

    /// How the runs play, compared with what is known about humans.
    pub fn human(runs: &[Run], timing: Option<&TimingResult>) -> Value {
        let tps: Vec<f64> = runs.iter().filter(|r| r.taps_played > 1).map(|r| r.taps_per_s()).collect();
        let ints: Vec<i32> = runs.iter().flat_map(|r| r.intervals.iter().copied()).collect();
        let ints_d: Vec<f64> = ints.iter().map(|&x| x as f64).collect();
        let rb: Vec<f64> = runs.iter().flat_map(|r| r.react_bounce.iter().map(|&x| x as f64)).collect();
        let rn: Vec<f64> = runs.iter().flat_map(|r| r.react_new.iter().map(|&x| x as f64)).collect();
        let under = if ints.is_empty() {
            f64::NAN
        } else {
            ints.iter().filter(|&&i| i < Self::HUMAN_MIN_INTERVAL).count() as f64 / ints.len() as f64
        };
        let err_sd = match timing {
            None => f64::NAN,
            Some(t) => Self::sd(&t.errors),
        };
        let react = Self::pct(&rn, 0.5);
        let held: i64 = runs.iter().map(|r| r.taps_held as i64).sum();
        let played: i64 = runs.iter().map(|r| r.taps_played as i64).sum();
        let shares = Self::band_shares(runs);
        let rb_i: Vec<i32> = rb.iter().map(|&x| x as i32).collect();
        let rn_i: Vec<i32> = rn.iter().map(|&x| x as i32).collect();
        let portal = if held + played == 0 { f64::NAN } else { held as f64 / (held + played) as f64 };
        let under_10 = if rn.is_empty() {
            f64::NAN
        } else {
            rn.iter().filter(|&&x| x < Self::HUMAN_REACT_FAST).count() as f64 / rn.len() as f64
        };
        let mut o = json!({
            "taps_ignored_in_portal_wait": Self::num(portal, 4),
            "taps_per_s": {
                "median": Self::num(Self::pct(&tps, 0.5), 3),
                "p10": Self::num(Self::pct(&tps, 0.1), 3),
                "p90": Self::num(Self::pct(&tps, 0.9), 3),
            },
            "interval": {
                "median": Self::num(Self::pct(&ints_d, 0.5), 3),
                "p10": Self::num(Self::pct(&ints_d, 0.1), 3),
                "under_8_ticks": Self::num(under, 4),
                "bins": Self::arr_i(&Self::INTERVAL_BINS),
                "hist": Self::arr(&Self::hist(&ints, &Self::INTERVAL_BINS), 4),
            },
            "height_bands": Self::arr(&shares, 4),
            "bottom_quarter": Self::num(sum(&Self::band_shares(runs)[Run::BANDS * 3 / 4..]), 4),
            "react_bounce": {
                "median": Self::num(Self::pct(&rb, 0.5), 3),
                "p10": Self::num(Self::pct(&rb, 0.1), 3),
                "n": rb.len(),
                "bins": Self::arr_i(&Self::REACT_BINS),
                "hist": Self::arr(&Self::hist(&rb_i, &Self::REACT_BINS), 4),
            },
            "react_new": {
                "median": Self::num(react, 3),
                "p10": Self::num(Self::pct(&rn, 0.1), 3),
                "n": rn.len(),
                "under_10_ticks": Self::num(under_10, 4),
                "bins": Self::arr_i(&Self::REACT_BINS),
                "hist": Self::arr(&Self::hist(&rn_i, &Self::REACT_BINS), 4),
            },
        });
        let m = o.as_object_mut().unwrap();
        if let Some(t) = timing {
            let abs: Vec<f64> = t.errors.iter().map(|x| x.abs()).collect();
            let widths: Vec<f64> = t.widths.iter().map(|&x| x as f64).collect();
            let mean = if t.errors.is_empty() { f64::NAN } else { average(&t.errors) };
            m.insert(
                "timing".to_string(),
                json!({
                    "taps_judged": t.taps_judged,
                    "critical": t.critical,
                    "error_mean": Self::num(mean, 3),
                    "error_sd": Self::num(err_sd, 3),
                    "error_abs_median": Self::num(Self::pct(&abs, 0.5), 3),
                    "window_median": Self::num(Self::pct(&widths, 0.5), 3),
                }),
            );
        }
        // Against the published human numbers (no human runs of this game yet).
        m.insert(
            "reference".to_string(),
            json!({
                "source": "Isaksen et al. FDG 2015: <= 7.7 taps/s, timing sigma 36-61 ms (2.2-3.7 ticks), reaction ~288 ms (17 ticks)",
                "intervals_ok": Self::ok(under, under <= 0.02),
                "timing_ok": Self::ok(err_sd, err_sd >= Self::HUMAN_SIGMA_LO / 1.5 && err_sd <= Self::HUMAN_SIGMA_HI * 1.5),
                "reaction_ok": Self::ok(react, react >= Self::HUMAN_REACT_FAST),
            }),
        );
        o
    }
}
