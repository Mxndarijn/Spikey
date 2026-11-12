//! Port of Yardstick/Survival.cs: confidence intervals and survival curves for bot scores
//! (`fastsim yardstick stats`, docs/YARDSTICK.md "Statistics").
//!
//! A run is a score T (points) that either ended in a death or was cut by
//! the tick cap (censored). Everything here treats the cap properly:
//! Kaplan-Meier for the median and the survival curve, exact Poisson
//! intervals for deaths per 100 points, a piecewise-exponential model
//! (one death rate per score band) for a median that also works past the
//! cap, and paired comparisons between two run sets on the same seeds.
//! No sim is played: it reads yardstick JSONs or death-atlas TSVs.
//!
//! Doubles are computed in the C# operation order; `System.Random` is `DotnetRandom` with the
//! same seeds and call order, so the numbers and the text match the C# ones.
use std::cmp::Ordering;
use std::collections::HashMap;
use std::path::Path;

use serde_json::{json, Value};

use super::stats::{average, jf, round, Stats};
use super::{as_long, fmt_num, node_str};
use crate::dotnet_random::DotnetRandom;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Obs {
    pub seed: i64,
    pub points: i64,
    pub dead: bool,
}

impl Obs {
    pub fn new(seed: i64, points: i64, dead: bool) -> Obs {
        Obs { seed, points, dead }
    }
}

#[derive(Clone, Debug, Default)]
pub struct Set {
    pub name: String,
    pub source: String,
    pub runs: Vec<Obs>,
    /// True when survivors' points were not stored and were spread evenly.
    pub approx: bool,
    pub cap: i64,
}

impl Set {
    pub fn deaths(&self) -> i32 {
        self.runs.iter().filter(|r| r.dead).count() as i32
    }

    pub fn alive(&self) -> i32 {
        self.runs.iter().filter(|r| !r.dead).count() as i32
    }
}

/// Environment.NewLine, what StringBuilder.AppendLine adds.
const NL: &str = if cfg!(windows) { "\r\n" } else { "\n" };

/// .NET `double.CompareTo` (List.Sort, OrderBy): NaN below everything, -0 equal to 0.
fn dotnet_cmp(a: &f64, b: &f64) -> Ordering {
    match a.partial_cmp(b) {
        Some(o) => o,
        None => match (a.is_nan(), b.is_nan()) {
            (true, true) => Ordering::Equal,
            (true, false) => Ordering::Less,
            _ => Ordering::Greater,
        },
    }
}

/// .NET `double.ToString()` (invariant): shortest round-trip digits, scientific when the
/// decimal exponent is 15 or more or below -4 ("1E+15", "1E-05").
fn cs_double(x: f64) -> String {
    if x.is_nan() {
        return "NaN".to_string();
    }
    if x.is_infinite() {
        return if x > 0.0 { "Infinity".to_string() } else { "-Infinity".to_string() };
    }
    if x == 0.0 {
        return if x.is_sign_negative() { "-0".to_string() } else { "0".to_string() };
    }
    let sci = format!("{:e}", x);
    let (mant, ex) = sci.split_once('e').unwrap();
    let ex: i32 = ex.parse().unwrap();
    if ex >= 15 || ex < -4 {
        format!("{}E{}{:02}", mant, if ex < 0 { '-' } else { '+' }, ex.abs())
    } else {
        format!("{}", x)
    }
}

// ---------------------------------------------------------------- loading

/// One piece of the two atlas regexes: a literal or a `(\d+)` group.
enum Pat {
    Lit(&'static str),
    Num,
}

/// The first (leftmost) match of a regex made of literals and `(\d+)` groups, as its groups.
/// Every group is followed by a non-digit literal or ends the pattern, so greedy digits
/// without backtracking match what .NET's Regex matches.
fn regex_groups<'a>(s: &'a str, pat: &[Pat]) -> Option<Vec<&'a str>> {
    let b = s.as_bytes();
    for start in 0..=b.len() {
        let mut i = start;
        let mut groups: Vec<&'a str> = Vec::new();
        let mut ok = true;
        for p in pat {
            match p {
                Pat::Lit(l) => {
                    if b[i..].starts_with(l.as_bytes()) {
                        i += l.len();
                    } else {
                        ok = false;
                        break;
                    }
                }
                Pat::Num => {
                    let j = i + b[i..].iter().take_while(|c| c.is_ascii_digit()).count();
                    if j == i {
                        ok = false;
                        break;
                    }
                    groups.push(&s[i..j]);
                    i = j;
                }
            }
        }
        if ok {
            return Some(groups);
        }
    }
    None
}

/// C# `long.TryParse(s)` (NumberStyles.Integer: white space around, a leading sign).
fn try_parse_long(s: &str) -> Option<i64> {
    s.trim_matches(|c| matches!(c, '\t' | '\n' | '\x0B' | '\x0C' | '\r' | ' ')).parse::<i64>().ok()
}

/// C# `long.Parse(s)` (throws on a bad number; here a panic).
fn parse_long(s: &str) -> i64 {
    try_parse_long(s).unwrap_or_else(|| panic!("yardstick stats: '{}' is not a whole number", s))
}

/// A yardstick JSON (`runs`: seed, points, dead) or a death atlas TSV
/// (one row per death; survivors are the seeds without a row, and their
/// points are the header's total minus the deaths' points, spread evenly).
pub fn load(path: &str) -> Result<Set, String> {
    let p = Path::new(path);
    if !p.is_file() {
        return Err(format!("no such run set: {}", path));
    }
    // File.ReadAllText: UTF-8, a byte order mark dropped.
    let bytes = std::fs::read(p).map_err(|e| format!("{}: {}", path, e))?;
    let text_owned = String::from_utf8_lossy(&bytes).into_owned();
    let text: &str = text_owned.strip_prefix('\u{FEFF}').unwrap_or(&text_owned);
    let mut set = Set {
        source: path.to_string(),
        name: p.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default(),
        ..Set::default()
    };
    if text.trim_start().starts_with('{') {
        let v: Value = match serde_json::from_str(text) {
            Ok(v) => v,
            Err(e) => panic!("yardstick stats: {} is not JSON: {}", path, e),
        };
        let o = v.as_object().unwrap_or_else(|| panic!("yardstick stats: {} is not a JSON object", path));
        let bot = match o.get("bot") {
            Some(Value::String(s)) => s.clone(),
            _ => set.name.clone(),
        };
        let suffix = match o.get("set") {
            Some(s) if !s.is_null() => format!("_{}", s.as_str().expect("a string \"set\"")),
            _ => String::new(),
        };
        set.name = bot + &suffix;
        set.cap = o.get("cap").and_then(as_long).unwrap_or(0);
        for r in o.get("runs").and_then(|r| r.as_array()).expect("a \"runs\" array") {
            set.runs.push(Obs::new(
                as_long(&r["seed"]).expect("a run's seed"),
                as_long(&r["points"]).expect("a run's points"),
                r["dead"].as_bool().expect("a run's dead"),
            ));
        }
        return Ok(set);
    }
    // Death atlas: "... seeds 1..400, cap 108000 ..." then "D deaths in P points ...; A of N alive".
    let lines: Vec<&str> = text.split('\n').map(|l| l.trim_end_matches('\r')).collect();
    let m = regex_groups(lines[0], &[Pat::Lit("seeds "), Pat::Num, Pat::Lit(".."), Pat::Num, Pat::Lit(", cap "), Pat::Num]);
    let m2 = regex_groups(text, &[Pat::Num, Pat::Lit(" deaths in "), Pat::Num, Pat::Lit(" points")]);
    let (Some(m), Some(m2)) = (m, m2) else {
        return Err(format!("{}: not a yardstick JSON or a death atlas", path));
    };
    let first = parse_long(m[0]);
    let last = parse_long(m[1]);
    set.cap = parse_long(m[2]);
    let total = parse_long(m2[1]);
    let Some(head) = lines.iter().position(|l| l.starts_with("seed\tscore")) else {
        return Err(format!("{}: no death rows", path));
    };
    let mut dead: HashMap<i64, i64> = HashMap::new();
    for l in &lines[head + 1..] {
        let c: Vec<&str> = l.split('\t').collect();
        if c.len() < 3 {
            continue;
        }
        let Some(seed) = try_parse_long(c[0]) else { continue };
        dead.insert(seed, parse_long(c[1]));
    }
    let mut alive: Vec<i64> = Vec::new();
    let mut s = first;
    while s <= last {
        match dead.get(&s) {
            Some(&p) => set.runs.push(Obs::new(s, p, true)),
            None => alive.push(s),
        }
        s += 1;
    }
    let left = total - dead.values().sum::<i64>();
    let n = alive.len() as i64;
    for (i, &a) in alive.iter().enumerate() {
        let share = left / n + if (i as i64) < left % n { 1 } else { 0 };
        set.runs.push(Obs::new(a, share, false));
    }
    set.approx = !alive.is_empty();
    Ok(set)
}

// ---------------------------------------------------------- distributions

fn ln_gamma(x: f64) -> f64 {
    // Lanczos, g = 7.
    #[allow(clippy::excessive_precision)]
    const C: [f64; 9] = [
        0.99999999999980993,
        676.5203681218851,
        -1259.1392167224028,
        771.32342877765313,
        -176.61502916214059,
        12.507343278686905,
        -0.13857109526572012,
        9.9843695780195716e-6,
        1.5056327351493116e-7,
    ];
    let pi = std::f64::consts::PI;
    if x < 0.5 {
        return (pi / (pi * x).sin()).ln() - ln_gamma(1.0 - x);
    }
    let x = x - 1.0;
    let mut a = C[0];
    let t = x + 7.5;
    for (i, c) in C.iter().enumerate().skip(1) {
        a += c / (x + i as f64);
    }
    0.5 * (2.0 * pi).ln() + (x + 0.5) * t.ln() - t + a.ln()
}

/// Regularized lower incomplete gamma P(a, x).
pub fn gamma_p(a: f64, x: f64) -> f64 {
    if x <= 0.0 {
        return 0.0;
    }
    if x < a + 1.0 {
        let mut sum = 1.0 / a;
        let mut term = sum;
        for n in 1..1000 {
            term *= x / (a + n as f64);
            sum += term;
            if term.abs() < sum.abs() * 1e-15 {
                break;
            }
        }
        return sum * (-x + a * x.ln() - ln_gamma(a)).exp();
    }
    // Continued fraction for Q, Lentz.
    let mut b = x + 1.0 - a;
    let mut cc = 1e300;
    let mut d = 1.0 / b;
    let mut h = d;
    for i in 1..1000 {
        let an = -(i as f64) * (i as f64 - a);
        b += 2.0;
        d = an * d + b;
        if d.abs() < 1e-300 {
            d = 1e-300;
        }
        cc = b + an / cc;
        if cc.abs() < 1e-300 {
            cc = 1e-300;
        }
        d = 1.0 / d;
        let del = d * cc;
        h *= del;
        if (del - 1.0).abs() < 1e-15 {
            break;
        }
    }
    1.0 - (-x + a * x.ln() - ln_gamma(a)).exp() * h
}

/// The x with P(a, x) = p (bisection; a > 0).
fn gamma_inv(a: f64, p: f64) -> f64 {
    let mut lo = 0.0;
    let mut hi = f64::max(10.0, a * 4.0 + 50.0);
    while gamma_p(a, hi) < p {
        hi *= 2.0;
    }
    for _ in 0..200 {
        let mid = (lo + hi) / 2.0;
        if gamma_p(a, mid) < p {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    (lo + hi) / 2.0
}

/// Exact (Garwood) 95% interval for a Poisson count d.
pub fn poisson_ci(d: i32) -> (f64, f64) {
    poisson_ci_conf(d, 0.95)
}

pub fn poisson_ci_conf(d: i32, conf: f64) -> (f64, f64) {
    let a = (1.0 - conf) / 2.0;
    let lo = if d == 0 { 0.0 } else { gamma_inv(d as f64, a) };
    let hi = gamma_inv((d + 1) as f64, 1.0 - a);
    (lo, hi)
}

/// Wilson interval for k of n (z = 1.96).
pub fn wilson(k: i32, n: i32) -> (f64, f64) {
    let z = 1.96;
    if n == 0 {
        return (f64::NAN, f64::NAN);
    }
    let nf = n as f64;
    let p = k as f64 / nf;
    let den = 1.0 + z * z / nf;
    let mid = (p + z * z / (2 * n) as f64) / den;
    let half = z * (p * (1.0 - p) / nf + z * z / (4.0 * nf * nf)).sqrt() / den;
    (f64::max(0.0, mid - half), f64::min(1.0, mid + half))
}

fn norm_cdf(z: f64) -> f64 {
    0.5 * (1.0 + erf(z / 2f64.sqrt()))
}

fn erf(x: f64) -> f64 {
    // Abramowitz-Stegun 7.1.26 is too coarse for p-values; use P(1/2, x^2).
    let v = gamma_p(0.5, x * x);
    if x < 0.0 {
        -v
    } else {
        v
    }
}

// ----------------------------------------------------------- exposure

/// Points a run tried inside [lo, hi): it scored min(T, hi) - lo of them
/// and, if it died at T inside the band, failed one more. A death at
/// exactly the band's low edge counts as one trial, not zero.
fn band(runs: &[Obs], lo: i64, hi: i64) -> (i64, i32) {
    let mut t: i64 = 0;
    let mut d: i32 = 0;
    for r in runs {
        if r.points > lo {
            t += r.points.min(hi) - lo;
        }
        if r.dead && r.points >= lo && r.points < hi {
            t += 1;
            d += 1;
        }
    }
    (t, d)
}

/// `rate(...)`: deaths per 100 points with an exact interval.
#[derive(Clone, Copy, Debug)]
pub struct Rate {
    pub rate: f64,
    pub lo: f64,
    pub hi: f64,
    pub deaths: i32,
    pub trials: i64,
}

/// Deaths per 100 points with an exact interval, inside [lo, hi) (C# defaults: 0, long.MaxValue).
pub fn rate(runs: &[Obs], lo: i64, hi: i64) -> Rate {
    let (t, d) = band(runs, lo, hi);
    if t == 0 {
        return Rate { rate: f64::NAN, lo: f64::NAN, hi: f64::NAN, deaths: d, trials: t };
    }
    let (a, b) = poisson_ci(d);
    Rate {
        rate: 100.0 * d as f64 / t as f64,
        lo: 100.0 * a / t as f64,
        hi: 100.0 * b / t as f64,
        deaths: d,
        trials: t,
    }
}

/// The "rate median" of the yardstick (ln 0.5 / ln(1 - h)) for a per-100 rate.
pub fn rate_median(per100: f64) -> f64 {
    if per100 <= 0.0 {
        f64::INFINITY
    } else {
        0.5f64.ln() / (1.0 - per100 / 100.0).ln()
    }
}

// ---------------------------------------------------------- Kaplan-Meier

#[allow(dead_code)]
#[derive(Clone, Copy, Debug)]
pub struct KmStep {
    pub t: i64,
    pub at_risk: i32,
    pub deaths: i32,
    pub s: f64,
    pub lo: f64,
    pub hi: f64,
}

/// Kaplan-Meier on points: S(t) = chance to score more than t. Steps at
/// each death score, with Greenwood variance and log-log 95% limits.
pub fn km(runs: &[Obs]) -> Vec<KmStep> {
    let mut steps = Vec::new();
    // GroupBy(points).OrderBy(key).
    let mut sorted = runs.to_vec();
    sorted.sort_by_key(|r| r.points);
    let mut n = runs.len() as i32;
    let mut s = 1.0;
    let mut gw = 0.0;
    let mut i = 0;
    while i < sorted.len() {
        let mut j = i;
        while j < sorted.len() && sorted[j].points == sorted[i].points {
            j += 1;
        }
        let g = &sorted[i..j];
        let d = g.iter().filter(|r| r.dead).count() as i32;
        if d > 0 {
            s *= 1.0 - d as f64 / n as f64;
            if n > d {
                gw += d as f64 / (n as f64 * (n - d) as f64);
            }
            let mut lo = s;
            let mut hi = s;
            if s > 0.0 && s < 1.0 {
                let se = gw.sqrt() / s.ln().abs();
                lo = s.powf((1.96 * se).exp());
                hi = s.powf((-1.96 * se).exp());
            }
            steps.push(KmStep { t: g[0].points, at_risk: n, deaths: d, s, lo, hi });
        }
        n -= g.len() as i32;
        i = j;
    }
    steps
}

/// S(t) from the steps (the last step at or below t).
pub fn at(steps: &[KmStep], t: i64, n: i32) -> KmStep {
    let mut last = KmStep { t: 0, at_risk: n, deaths: 0, s: 1.0, lo: 1.0, hi: 1.0 };
    for s in steps {
        if s.t > t {
            break;
        }
        last = *s;
    }
    last
}

/// KM median and its 95% interval (Brookmeyer-Crowley: the scores whose
/// log-log band contains 0.5). NaN when the curve never gets that low,
/// which happens when half or more of the runs reach the cap.
pub fn km_median(steps: &[KmStep]) -> (f64, f64, f64) {
    let mut med = f64::NAN;
    let mut lo = f64::NAN;
    let mut hi = f64::NAN;
    for s in steps {
        if lo.is_nan() && s.lo <= 0.5 {
            lo = s.t as f64;
        }
        if med.is_nan() && s.s <= 0.5 {
            med = s.t as f64;
        }
        if hi.is_nan() && s.hi <= 0.5 {
            hi = s.t as f64;
        }
    }
    (med, lo, hi)
}

/// Restricted mean score up to tau (area under the KM curve).
pub fn rmst(steps: &[KmStep], tau: i64) -> f64 {
    let mut area = 0.0;
    let mut s = 1.0;
    let mut prev: i64 = 0;
    for st in steps {
        if st.t >= tau {
            break;
        }
        area += s * (st.t - prev) as f64;
        prev = st.t;
        s = st.s;
    }
    area + s * (tau - prev) as f64
}

// --------------------------------------------------- piecewise exponential

/// Bands for the piecewise model: fine where the rate climbs (the first
/// rooms), coarse on the plateau; the last band runs on past the cap.
pub const PEM_BANDS: [i64; 17] = [0, 5, 10, 15, 20, 30, 40, 60, 80, 120, 160, 240, 320, 480, 640, 960, 1440];

/// The median of a model with one death chance per point in each band:
/// the first score where the chance to have survived falls to 0.5. Uses
/// every run (capped ones too) and extends the last band's rate past the
/// cap, so it gives a number even when most runs reach the cap.
pub fn pem_median(runs: &[Obs]) -> f64 {
    let mut log_s = 0.0;
    let half = 0.5f64.ln();
    for i in 0..PEM_BANDS.len() {
        let lo = PEM_BANDS[i];
        let hi = if i + 1 < PEM_BANDS.len() { PEM_BANDS[i + 1] } else { i64::MAX };
        let (t, d) = band(runs, lo, hi);
        let q = if t == 0 { 0.0 } else { d as f64 / t as f64 };
        if q <= 0.0 {
            if hi == i64::MAX {
                return f64::INFINITY;
            }
            continue;
        }
        let per = (1.0 - q).ln();
        let need = (half - log_s) / per;
        if hi == i64::MAX || need <= (hi - lo) as f64 {
            return lo as f64 + need;
        }
        log_s += per * (hi - lo) as f64;
    }
    f64::INFINITY
}

// ------------------------------------------------------------- bootstrap

/// Percentile 95% interval of `f` over `reps` resamples of the runs
/// (resampling seeds: the honest unit when seeds differ in difficulty).
/// C# defaults: reps 2000, seed 1.
pub fn boot(runs: &[Obs], f: impl Fn(&[Obs]) -> f64, reps: i32, seed: i32) -> (f64, f64) {
    let mut rng = DotnetRandom::new(seed);
    let mut vals: Vec<f64> = Vec::with_capacity(reps.max(0) as usize);
    let mut buf = vec![Obs::default(); runs.len()];
    for _ in 0..reps {
        for x in buf.iter_mut() {
            *x = runs[rng.next(runs.len() as i32) as usize];
        }
        vals.push(f(&buf));
    }
    vals.sort_by(dotnet_cmp);
    (vals[(0.025 * (reps - 1) as f64) as usize], vals[(0.975 * (reps - 1) as f64).ceil() as usize])
}

// ------------------------------------------------------------- comparison

/// Log-rank test of two run sets (chi-square, 1 df) and its p-value:
/// (chi2, p, observed_a, expected_a).
pub fn logrank(a: &[Obs], b: &[Obs]) -> (f64, f64, f64, f64) {
    // Distinct().OrderBy(t): the death scores in order, once each.
    let mut times: Vec<i64> = a.iter().chain(b.iter()).filter(|r| r.dead).map(|r| r.points).collect();
    times.sort();
    times.dedup();
    let mut o = 0.0;
    let mut e = 0.0;
    let mut v = 0.0;
    for &t in &times {
        let na = a.iter().filter(|r| r.points >= t).count() as i32;
        let nb = b.iter().filter(|r| r.points >= t).count() as i32;
        let da = a.iter().filter(|r| r.dead && r.points == t).count() as i32;
        let db = b.iter().filter(|r| r.dead && r.points == t).count() as i32;
        let n = na + nb;
        let d = da + db;
        if n < 2 {
            continue;
        }
        o += da as f64;
        e += d as f64 * na as f64 / n as f64;
        v += d as f64 * na as f64 * nb as f64 * (n - d) as f64 / (n as f64 * n as f64 * (n - 1) as f64);
    }
    let chi = if v > 0.0 { (o - e) * (o - e) / v } else { 0.0 };
    (chi, 2.0 * (1.0 - norm_cdf(chi.sqrt())), o, e)
}

/// Deaths needed in each of two sets to see a rate ratio `r` with a
/// two-sided 5% test and 80% power: 2 (1.96 + 0.84)^2 / ln(r)^2.
pub fn deaths_needed(r: f64) -> f64 {
    let z_a: f64 = 1.96;
    let z_b: f64 = 0.8416;
    2.0 * (z_a + z_b).powf(2.0) / r.ln().powf(2.0)
}

fn spearman(x: &[f64], y: &[f64]) -> f64 {
    fn rank(v: &[f64]) -> Vec<f64> {
        let mut idx: Vec<usize> = (0..v.len()).collect();
        idx.sort_by(|&i, &j| dotnet_cmp(&v[i], &v[j]));
        let mut r = vec![0.0; v.len()];
        let mut i = 0;
        while i < idx.len() {
            let mut j = i;
            while j + 1 < idx.len() && v[idx[j + 1]] == v[idx[i]] {
                j += 1;
            }
            for k in i..=j {
                r[idx[k]] = (i + j) as f64 / 2.0;
            }
            i = j + 1;
        }
        r
    }
    let rx = rank(x);
    let ry = rank(y);
    let mx = average(&rx);
    let my = average(&ry);
    let mut sxy = 0.0;
    let mut sxx = 0.0;
    let mut syy = 0.0;
    for i in 0..rx.len() {
        sxy += (rx[i] - mx) * (ry[i] - my);
        sxx += (rx[i] - mx) * (rx[i] - mx);
        syy += (ry[i] - my) * (ry[i] - my);
    }
    if sxx == 0.0 || syy == 0.0 {
        f64::NAN
    } else {
        sxy / (sxx * syy).sqrt()
    }
}

// ---------------------------------------------------------------- report

/// The plateau starts here: past the first rooms the rate stops climbing
/// (bot-review.md), so "deaths per 100 from 40 on" is a skill number that
/// does not depend on the ramp.
pub const PLATEAU: i64 = 40;
/// Scores to print the curve at. The bot cap is 216 000 ticks (60 min, about 2 400
/// points) since 2026-11-12; 30-minute sets (108 000) stop near 1 200.
pub const CURVE_AT: [i64; 11] = [10, 20, 40, 80, 160, 320, 640, 1000, 1500, 2000, 2400];

pub fn describe(set: &Set, reps: i32) -> Value {
    let runs = &set.runs;
    let n = runs.len() as i32;
    let all = rate(runs, 0, i64::MAX);
    let plat = rate(runs, PLATEAU, i64::MAX);
    let steps = km(runs);
    let (med, mlo, mhi) = km_median(&steps);
    let pem = pem_median(runs);
    let (plo, phi) = boot(runs, pem_median, reps, 1);
    let (alo, ahi) = wilson(set.alive(), n);
    let max_points = runs.iter().map(|r| r.points).max().expect("a run set without runs");
    let mut curve: Vec<Value> = Vec::new();
    for &t in &CURVE_AT {
        let s = at(&steps, t, n);
        let risk = runs.iter().filter(|r| r.points >= t).count() as i32;
        // Past the highest score anyone reached (the cap) the curve is unknown, not 0.
        let known = max_points >= t;
        curve.push(json!({
            "score": t,
            "survive": if known { R(s.s, 4) } else { Value::Null },
            "lo": if known { R(s.lo, 4) } else { Value::Null },
            "hi": if known { R(s.hi, 4) } else { Value::Null },
            "at_risk": risk,
        }));
    }
    let mut bands: Vec<Value> = Vec::new();
    let sb = Stats::SCORE_BANDS;
    for i in 0..sb.len() {
        let lo = sb[i];
        let hi = if i + 1 < sb.len() { sb[i + 1] } else { i64::MAX };
        let r = rate(runs, lo, hi);
        bands.push(json!({
            "band": if hi == i64::MAX { format!("{}+", lo) } else { format!("{}..{}", lo, hi) },
            "deaths": r.deaths,
            "points": r.trials,
            "per_100": R(r.rate, 3),
            "lo": R(r.lo, 3),
            "hi": R(r.hi, 3),
        }));
    }
    // Where(!dead).Select(points).DefaultIfEmpty(Max(points)).Min()
    let tau = runs.iter().filter(|r| !r.dead).map(|r| r.points).min().unwrap_or(max_points);
    let raw: Vec<f64> = runs.iter().map(|r| r.points as f64).collect();
    let (rlo, rhi) = boot(
        runs,
        |xs| {
            let p: Vec<f64> = xs.iter().map(|r| r.points as f64).collect();
            Stats::pct(&p, 0.5)
        },
        reps,
        2,
    );
    json!({
        "name": set.name,
        "source": set.source,
        "cap_ticks": set.cap,
        "runs": n,
        "deaths": set.deaths(),
        "alive_at_cap": set.alive(),
        "alive_share": { "p": R(set.alive() as f64 / n as f64, 4), "lo": R(alo, 4), "hi": R(ahi, 4) },
        "survivor_points_approx": set.approx,
        "per_100": { "all": R(all.rate, 4), "lo": R(all.lo, 4), "hi": R(all.hi, 4) },
        "per_100_plateau": {
            "from": PLATEAU, "rate": R(plat.rate, 4), "lo": R(plat.lo, 4), "hi": R(plat.hi, 4), "deaths": plat.deaths,
        },
        "rate_median": {
            "value": R(rate_median(all.rate), 1), "lo": R(rate_median(all.hi), 1), "hi": R(rate_median(all.lo), 1),
        },
        "raw_median": { "value": R(Stats::pct(&raw, 0.5), 1), "lo": R(rlo, 1), "hi": R(rhi, 1) },
        "km_median": { "value": R(med, 1), "lo": R(mlo, 1), "hi": R(mhi, 1) },
        "pem_median": { "value": R(pem, 1), "lo": R(plo, 1), "hi": R(phi, 1) },
        "tier_km": if med.is_nan() { "beast (half reach the cap)".to_string() } else { Stats::tier_of(med) },
        "tier_pem": if pem.is_infinite() { "beast".to_string() } else { Stats::tier_of(pem) },
        "rmst": { "tau": tau, "mean_points": R(rmst(&steps, tau), 1) },
        "survival": curve,
        "bands": bands,
        "deaths_for_10pct": jf((1.96 / 1.1f64.ln()).powf(2.0).ceil()),
    })
}

pub fn compare(a: &Set, b: &Set, _reps: i32) -> Value {
    let mut o = json!({ "a": a.name, "b": b.name });
    let m = o.as_object_mut().unwrap();
    for (key, lo) in [("all", 0i64), ("plateau", PLATEAU)] {
        let ra = rate(&a.runs, lo, i64::MAX);
        let rb = rate(&b.runs, lo, i64::MAX);
        let ratio = ra.rate / rb.rate;
        let se = (1.0 / ra.deaths.max(1) as f64 + 1.0 / rb.deaths.max(1) as f64).sqrt();
        let z = ratio.ln() / se;
        m.insert(
            format!("rate_ratio_{}", key),
            json!({
                "ratio": R(ratio, 3),
                "lo": R(ratio * (-1.96 * se).exp(), 3),
                "hi": R(ratio * (1.96 * se).exp(), 3),
                "z": R(z, 2),
                "p": R(2.0 * (1.0 - norm_cdf(z.abs())), 4),
            }),
        );
    }
    let lr = logrank(&a.runs, &b.runs);
    m.insert(
        "logrank".to_string(),
        json!({ "chi2": R(lr.0, 2), "p": R(lr.1, 4), "deaths_a": jf(lr.2), "expected_a": R(lr.3, 1) }),
    );
    // Paired by seed: does playing the same seeds help?
    let mut bs: HashMap<i64, Obs> = HashMap::new();
    for r in &b.runs {
        bs.entry(r.seed).or_insert(*r);
    }
    let common: Vec<(Obs, Obs)> = a.runs.iter().filter_map(|r| bs.get(&r.seed).map(|y| (*r, *y))).collect();
    if common.len() >= 10 {
        let lx: Vec<f64> = common.iter().map(|c| ((1 + c.0.points) as f64).ln()).collect();
        let ly: Vec<f64> = common.iter().map(|c| ((1 + c.1.points) as f64).ln()).collect();
        let rho = spearman(&lx, &ly);
        let both = common.iter().filter(|c| c.0.dead && c.1.dead).count() as i32;
        let only_a = common.iter().filter(|c| c.0.dead && !c.1.dead).count() as i32;
        let only_b = common.iter().filter(|c| !c.0.dead && c.1.dead).count() as i32;
        let a_longer = common.iter().filter(|c| c.0.points > c.1.points).count() as i32;
        let b_longer = common.iter().filter(|c| c.1.points > c.0.points).count() as i32;
        m.insert(
            "paired".to_string(),
            json!({
                "seeds": common.len(),
                "spearman_log_points": R(rho, 3),
                "variance_saved_by_pairing": R(if rho.is_nan() { 0.0 } else { f64::max(0.0, rho) }, 3),
                "a_scores_more": a_longer,
                "b_scores_more": b_longer,
                "sign_test_p": R(sign_p(a_longer, b_longer), 4),
                "capped_only_a_alive": only_b, "capped_only_b_alive": only_a, "both_dead": both,
            }),
        );
    }
    let (kma, _, _) = km_median(&km(&a.runs));
    let (kmb, _, _) = km_median(&km(&b.runs));
    m.insert("km_median".to_string(), json!({ "a": R(kma, 1), "b": R(kmb, 1) }));
    // Pocock bound for 5 equally spaced looks: stop early only if |z| > 2.41.
    // C# `(double)node` throws on a null z (no deaths in a set); so does this.
    let zall = m["rate_ratio_all"]["z"].as_f64().expect("rate_ratio_all.z is null");
    m.insert(
        "sequential".to_string(),
        json!({
            "rule": "look after every fifth of the planned deaths; stop when |z| > 2.41 (Pocock, 5 looks, 5% overall)",
            "stop_now": zall.abs() > 2.41,
        }),
    );
    o
}

fn sign_p(a: i32, b: i32) -> f64 {
    let n = a + b;
    if n == 0 {
        return 1.0;
    }
    let k = a.min(b);
    let mut p = 0.0;
    for i in 0..=k {
        p += (ln_choose(n, i) - n as f64 * 2f64.ln()).exp();
    }
    f64::min(1.0, 2.0 * p)
}

fn ln_choose(n: i32, k: i32) -> f64 {
    ln_gamma((n + 1) as f64) - ln_gamma((k + 1) as f64) - ln_gamma((n - k + 1) as f64)
}

/// C# `R(x, d)`: null for NaN and infinities, else `Math.Round(x, d)` as a JSON number
/// (a negative zero stays "-0", as System.Text.Json writes it).
#[allow(non_snake_case)]
fn R(x: f64, d: i32) -> Value {
    if x.is_nan() || x.is_infinite() {
        return Value::Null;
    }
    let v = round(x, d);
    if v == 0.0 && v.is_sign_negative() {
        Value::from(v)
    } else {
        jf(v)
    }
}

// ------------------------------------------------------------------- text

/// C# `F(n, fmt)`: "-" for null, else `((double)n).ToString(fmt, InvariantCulture)`.
#[allow(non_snake_case)]
fn F(n: &Value, fmt: &str) -> String {
    match n.as_f64() {
        None => "-".to_string(),
        Some(x) => fmt_num(x, fmt),
    }
}

fn ci(o: &Value, v: &str, fmt: &str) -> String {
    format!("{} [{}, {}]", F(&o[v], fmt), F(&o["lo"], fmt), F(&o["hi"], fmt))
}

pub fn text(d: &Value) -> String {
    let mut sb = String::new();
    sb.push_str(&format!(
        "{} (cap {} ticks): {} runs, {} deaths, {} alive at the cap ({}){}",
        node_str(&d["name"]),
        node_str(&d["cap_ticks"]),
        node_str(&d["runs"]),
        node_str(&d["deaths"]),
        node_str(&d["alive_at_cap"]),
        ci(&d["alive_share"], "p", "0.###"),
        if d["survivor_points_approx"].as_bool().expect("survivor_points_approx") {
            "  [survivors' points spread evenly: atlas file]"
        } else {
            ""
        }
    ));
    sb.push_str(NL);
    sb.push_str(&format!(
        "  deaths/100 pt      {}   from {}: {} ({} deaths)",
        ci(&d["per_100"], "all", "0.###"),
        PLATEAU,
        ci(&d["per_100_plateau"], "rate", "0.###"),
        node_str(&d["per_100_plateau"]["deaths"])
    ));
    sb.push_str(NL);
    sb.push_str(&format!(
        "  median: raw {}  KM {}  piecewise {}  rate {}",
        ci(&d["raw_median"], "value", "0.#"),
        ci(&d["km_median"], "value", "0.#"),
        ci(&d["pem_median"], "value", "0.#"),
        ci(&d["rate_median"], "value", "0.#")
    ));
    sb.push_str(NL);
    sb.push_str(&format!(
        "  tier: KM {}, piecewise {}; mean score up to {}: {}",
        node_str(&d["tier_km"]),
        node_str(&d["tier_pem"]),
        node_str(&d["rmst"]["tau"]),
        F(&d["rmst"]["mean_points"], "0.#")
    ));
    sb.push_str(NL);
    sb.push_str("  survive past");
    for s in d["survival"].as_array().expect("survival") {
        sb.push_str(&format!(
            "  {}: {} [{},{}]",
            node_str(&s["score"]),
            F(&s["survive"], "0.00"),
            F(&s["lo"], "0.00"),
            F(&s["hi"], "0.00")
        ));
    }
    sb.push_str(NL);
    sb.push_str("  deaths/100 by band");
    for b in d["bands"].as_array().expect("bands") {
        sb.push_str(&format!(
            "  {}: {} [{},{}]",
            node_str(&b["band"]),
            F(&b["per_100"], "0.###"),
            F(&b["lo"], "0.###"),
            F(&b["hi"], "0.###")
        ));
    }
    sb.push_str(NL);
    sb
}

pub fn text_compare(c: &Value) -> String {
    let mut sb = String::new();
    sb.push_str(&format!("{} vs {}:", node_str(&c["a"]), node_str(&c["b"])));
    sb.push_str(NL);
    for k in ["all", "plateau"] {
        let r = &c[format!("rate_ratio_{}", k).as_str()];
        sb.push_str(&format!(
            "  rate ratio ({:<7}) {} [{}, {}]  z {}  p {}",
            k,
            F(&r["ratio"], "0.###"),
            F(&r["lo"], "0.###"),
            F(&r["hi"], "0.###"),
            F(&r["z"], "0.00"),
            F(&r["p"], "0.####")
        ));
        sb.push_str(NL);
    }
    sb.push_str(&format!(
        "  log-rank chi2 {}  p {};  KM medians {} vs {}",
        F(&c["logrank"]["chi2"], "0.00"),
        F(&c["logrank"]["p"], "0.####"),
        F(&c["km_median"]["a"], "0.#"),
        F(&c["km_median"]["b"], "0.#")
    ));
    sb.push_str(NL);
    let p = &c["paired"];
    if !p.is_null() {
        sb.push_str(&format!(
            "  paired on {} seeds: spearman {} (pairing helps only if this is well above 0); a scores more on {}, b on {}, sign test p {}",
            node_str(&p["seeds"]),
            F(&p["spearman_log_points"], "0.000"),
            node_str(&p["a_scores_more"]),
            node_str(&p["b_scores_more"]),
            F(&p["sign_test_p"], "0.####")
        ));
        sb.push_str(NL);
    }
    sb.push_str(&format!(
        "  sequential: {}; stop now: {}",
        node_str(&c["sequential"]["rule"]),
        node_str(&c["sequential"]["stop_now"])
    ));
    sb.push_str(NL);
    sb
}

pub fn plan_text() -> String {
    let mut sb = String::from("deaths needed in each set to see a rate ratio (two-sided 5%, 80% power):\n");
    for r in [0.95, 0.9, 0.85, 0.8, 0.7, 0.6, 0.5] {
        sb.push_str(&format!(
            "  ratio {}: {:>6} deaths each",
            fmt_num(r, "0.00"),
            cs_double(deaths_needed(r).ceil())
        ));
        sb.push_str(NL);
    }
    sb.push_str("one set's rate to +-10%: ~400 deaths; +-20%: ~100; +-30%: ~45 (1.96 / sqrt(deaths) on the log scale)");
    sb.push_str(NL);
    sb
}

// ------------------------------------------------------------- self test

/// Known values, for the yardstick check.
pub fn self_test() -> Vec<String> {
    let mut fails: Vec<String> = Vec::new();
    let mut near = |what: &str, got: f64, want: f64, tol: f64| {
        if !((got - want).abs() <= tol) {
            fails.push(format!("{}: {}, want {}", what, cs_double(got), cs_double(want)));
        }
    };
    let (lo, hi) = poisson_ci(21);
    near("poisson lo(21)", lo, 12.999, 0.01);
    near("poisson hi(21)", hi, 32.101, 0.01);
    near("poisson hi(0)", poisson_ci(0).1, 3.689, 0.01);
    // Hand case: deaths at 3, 5, 8, 12, capped at 5 and 10 (a cap tied with a death leaves after it).
    let runs = vec![
        Obs::new(1, 3, true),
        Obs::new(2, 5, false),
        Obs::new(3, 5, true),
        Obs::new(4, 8, true),
        Obs::new(5, 10, false),
        Obs::new(6, 12, true),
    ];
    let steps = km(&runs);
    // S(3) = 5/6, S(5) = 5/6 * 4/5 = 2/3, S(8) = 2/3 * 2/3 = 4/9, S(12) = 0.
    near("km S(5)", at(&steps, 5, 6).s, 2.0 / 3.0, 1e-9);
    near("km S(8)", at(&steps, 8, 6).s, 4.0 / 9.0, 1e-9);
    near("km median", km_median(&steps).0, 8.0, 0.0);
    // A constant rate q per point gives a piecewise median of ln 0.5 / ln(1 - q).
    let mut rng = DotnetRandom::new(5);
    let mut geo: Vec<Obs> = Vec::new();
    for i in 0..4000 {
        let mut p: i64 = 0;
        while rng.next_double() > 0.01 {
            p += 1;
        }
        geo.push(Obs::new(i, p, true));
    }
    near("pem median of geometric(0.01)", pem_median(&geo), rate_median(1.0), 6.0);
    near("km median of geometric(0.01)", km_median(&km(&geo)).0, rate_median(1.0), 6.0);
    near("deaths for ratio 0.8", deaths_needed(0.8), 315.0, 2.0);
    let same = logrank(&geo[..2000], &geo[2000..]);
    if same.1 < 0.001 {
        fails.push(format!("log-rank calls two halves of one set different (p {})", cs_double(same.1)));
    }
    fails
}
