//! Port of Difficulty/Score.cs: `fastsim difficulty score --in a.tsv[,b.tsv] [--out report]`,
//! one row per room and variant (docs/ROOM_DIFFICULTY.md).
//!
//! Skill (bots): an item-response fit over every bot's clears, P(clear) =
//!   1 / (1 + e^-(skill_bot - b_room)). The skill a room needs for 90% clears is
//!   b_room + ln 9, read on a tier scale through beginner = 1 and good = 3 (linear).
//!   The score is 20 x that: 20 beginner, 40 normal, 60 good; expert and beast land
//!   where their fitted skill puts them (report.json "tier_scores").
//! Analytic: a ridge fit of that skill on the exact-knowledge and reaction measures
//!   (tube, react), leave-one-out; it scores rooms the bots didn't play too.
//! Score: the mean of the two (either one alone when the other is missing).
//!
//! C# Dictionaries keep insertion order (no removals), so they are `OMap`s here; every double
//! sum runs in the C# order (Enumerable.Sum/Average over doubles is sequential).
use std::cmp::Ordering;
use std::collections::HashMap;
use std::hint::black_box;

use serde_json::{json, Map, Value};
use sim::prelude::*;

use super::cases::Cases;
use super::measures::ReactSweep;
use super::tube::cs_max;
use crate::human::fmt_f;
use crate::setups::Reaction;
use crate::speed::Opts;
use crate::yardstick::json_pretty;

/// An insertion-ordered dictionary (C# Dictionary without removals).
#[derive(Clone, Debug)]
pub struct OMap<V> {
    pub items: Vec<(String, V)>,
}

impl<V: Clone> OMap<V> {
    pub fn new() -> Self {
        OMap { items: Vec::new() }
    }
    pub fn get(&self, k: &str) -> Option<&V> {
        self.items.iter().find(|x| x.0 == k).map(|x| &x.1)
    }
    pub fn get_mut(&mut self, k: &str) -> Option<&mut V> {
        self.items.iter_mut().find(|x| x.0 == k).map(|x| &mut x.1)
    }
    pub fn contains(&self, k: &str) -> bool {
        self.get(k).is_some()
    }
    /// `d[k] = v`: an existing key keeps its place.
    pub fn set(&mut self, k: &str, v: V) {
        match self.get_mut(k) {
            Some(x) => *x = v,
            None => self.items.push((k.to_string(), v)),
        }
    }
    pub fn len(&self) -> usize {
        self.items.len()
    }
}

impl<V: Clone> Default for OMap<V> {
    fn default() -> Self {
        Self::new()
    }
}

impl OMap<f64> {
    /// `GetValueOrDefault(k)` (0) / `GetValueOrDefault(k, d)`.
    pub fn gv(&self, k: &str, d: f64) -> f64 {
        self.get(k).copied().unwrap_or(d)
    }
    /// `f[k]` (throws when missing).
    pub fn at(&self, k: &str) -> f64 {
        *self.get(k).unwrap_or_else(|| panic!("no key {}", k))
    }
}

pub struct Score;

#[derive(Clone, Debug)]
pub struct Room {
    pub label: String,
    pub id: String,
    pub variant: String,
    pub group: String,
    pub from: i64,
    pub boss: bool,
    /// tube (per entry lists)
    pub tube: Vec<Vec<f64>>,
    /// react: per entry [shown, (noway, died, fail|way0) x 4]
    pub react: Vec<Vec<i64>>,
    pub react_detail: Vec<String>,
    /// bots: bot -> (clears, plays)
    pub bots: OMap<(i32, i32)>,
    pub causes: OMap<OMap<i32>>,
    pub errors: i32,
    pub b: f64,
    pub skill: f64,
    pub analytic: f64,
    pub score: f64,
    pub f: OMap<f64>,
}

impl Room {
    fn new(label: &str, id: &str, variant: &str, group: &str, from: i64, boss: bool) -> Room {
        Room {
            label: label.to_string(),
            id: id.to_string(),
            variant: variant.to_string(),
            group: group.to_string(),
            from,
            boss,
            tube: Vec::new(),
            react: Vec::new(),
            react_detail: Vec::new(),
            bots: OMap::new(),
            causes: OMap::new(),
            errors: 0,
            b: f64::NAN,
            skill: f64::NAN,
            analytic: f64::NAN,
            score: f64::NAN,
            f: OMap::new(),
        }
    }
}

// ---- C# double helpers ---------------------------------------------------------------

/// The default double comparer (OrderBy): NaN before everything, NaN == NaN.
pub fn dcmp(a: f64, b: f64) -> Ordering {
    match (a.is_nan(), b.is_nan()) {
        (true, true) => Ordering::Equal,
        (true, false) => Ordering::Less,
        (false, true) => Ordering::Greater,
        _ => a.partial_cmp(&b).unwrap(),
    }
}

/// Enumerable.Sum over doubles: from 0, in order.
fn sum(xs: impl Iterator<Item = f64>) -> f64 {
    xs.fold(0.0, |a, x| a + x)
}

/// Enumerable.Average over doubles (throws on none).
fn average(xs: impl Iterator<Item = f64>) -> f64 {
    let mut s = 0.0;
    let mut n: i64 = 0;
    for x in xs {
        s += x;
        n += 1;
    }
    if n == 0 {
        panic!("Sequence contains no elements");
    }
    s / n as f64
}

/// Enumerable.Min over doubles: NaN if any is NaN.
fn dmin(xs: impl Iterator<Item = f64>) -> f64 {
    let mut m: Option<f64> = None;
    for x in xs {
        if x.is_nan() {
            return x;
        }
        m = Some(match m {
            None => x,
            Some(v) => {
                if x < v {
                    x
                } else {
                    v
                }
            }
        });
    }
    m.expect("Sequence contains no elements")
}

/// C# `Math.Pow(x, y)`: the CRT pow (LLVM would turn a constant y = 2 into x * x).
fn pow(x: f64, y: f64) -> f64 {
    x.powf(black_box(y))
}

/// C# `Math.Round(x, 4)` (ToEven): scale, round, scale back, below 1e16.
fn round4(x: f64) -> f64 {
    if x.abs() < 1e16 {
        (x * 1e4).round_ties_even() / 1e4
    } else {
        x
    }
}

/// C# `double.Parse(s, InvariantCulture)`.
fn d_(s: &str) -> f64 {
    match s {
        "NaN" => f64::NAN,
        "Infinity" | "∞" => f64::INFINITY,
        "-Infinity" | "-∞" => f64::NEG_INFINITY,
        _ => s.trim().parse().unwrap_or_else(|_| panic!("not a number: {}", s)),
    }
}

fn nl() -> &'static str {
    if cfg!(windows) {
        "\r\n"
    } else {
        "\n"
    }
}

// tube columns (after the 4 key columns)
const WAY: usize = 0;
#[allow(dead_code)]
const TICKS: usize = 1;
#[allow(dead_code)]
const FIRST_EXIT: usize = 2;
#[allow(dead_code)]
const PEAK: usize = 3;
const BAND_MIN: usize = 4;
const BAND_P10: usize = 5;
const BAND_MED: usize = 6;
const TIGHT_S: usize = 7;
const BITS: usize = 8;
#[allow(dead_code)]
const BITS_S: usize = 9;
const WIN: usize = 10;
const WIN_MED: usize = 11;
const TAPS: usize = 12;
const TIGHT: usize = 13;
const LINE_S: usize = 14;
const CHOICE_S: usize = 15;
const VIABLE: usize = 16;
const CONFIRMED: usize = 17;
const MISSED: usize = 18;

impl Score {
    #[allow(dead_code)]
    pub const TIERS: [&'static str; 5] = ["beginner", "normal", "good", "expert", "beast"];

    pub fn run(opts: &Opts) -> i32 {
        let files: Vec<String> =
            opts.get("in").map(|s| s.as_str()).unwrap_or("difficulty.tsv").split(',').map(|s| s.to_string()).collect();
        let mut list = Self::load(&files);
        let outp = opts.get("out").cloned().unwrap_or_else(|| "difficulty_report".to_string());
        for r in list.iter_mut() {
            Self::features(r);
        }
        let theta = Self::fit_irt(&mut list);
        for r in list.iter_mut() {
            if !r.b.is_nan() {
                r.skill = Self::tier_needed(r.b + 9f64.ln(), &theta);
            }
        }
        let (names, w, loo, corr) = Self::fit_analytic(&mut list);
        for r in list.iter_mut() {
            let parts: Vec<f64> = [r.skill * 20.0, r.analytic * 20.0].into_iter().filter(|x| !x.is_nan()).collect();
            r.score = if parts.is_empty() { f64::NAN } else { average(parts.iter().copied()).clamp(0.0, 130.0) };
        }
        let bands = Bands::suggest(&list);
        let report = Self::build(&list, &theta, &names, w.as_deref(), loo, &corr, &bands);
        let json_path = format!("{}.json", outp);
        let md_path = format!("{}.md", outp);
        std::fs::write(&json_path, json_pretty(&report)).unwrap_or_else(|e| panic!("{}: {}", json_path, e));
        let md = Self::markdown(&list, &theta, &corr, loo, &bands);
        std::fs::write(&md_path, &md).unwrap_or_else(|e| panic!("{}: {}", md_path, e));
        print!("{}", md.split("\n## Rooms").next().unwrap_or(""));
        println!("wrote {}.md and {}.json", outp, outp);
        0
    }

    /// The lines of a TSV that a measure run may still be writing.
    pub fn lines(path: &str) -> Vec<String> {
        let text = std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{}: {}", path, e));
        // StreamReader.ReadLine: \n, \r\n or \r ends a line; no empty line after the last one.
        let mut out_ = Vec::new();
        let mut cur = String::new();
        let mut chars = text.chars().peekable();
        while let Some(c) = chars.next() {
            match c {
                '\n' => out_.push(std::mem::take(&mut cur)),
                '\r' => {
                    if chars.peek() == Some(&'\n') {
                        chars.next();
                    }
                    out_.push(std::mem::take(&mut cur));
                }
                _ => cur.push(c),
            }
        }
        if !cur.is_empty() {
            out_.push(cur);
        }
        out_
    }

    fn load(files: &[String]) -> Vec<Room> {
        let mut rooms: Vec<Room> = Vec::new();
        let mut at: HashMap<String, usize> = HashMap::new();
        for t in Cases::all("*") {
            let group = if t.def.season != Seasons::NONE { "seasonal" } else { t.def.group };
            at.insert(t.label.clone(), rooms.len());
            rooms.push(Room::new(&t.label, t.def.id, t.variant, group, t.def.from_score, t.boss()));
        }
        for file in files {
            for line in Self::lines(file) {
                let f: Vec<&str> = line.split('\t').collect();
                if f.len() < 5 {
                    continue;
                }
                let Some(&ri) = at.get(f[1]) else { continue };
                let r = &mut rooms[ri];
                if f[4] == "error" {
                    r.errors += 1;
                    continue;
                }
                match f[0] {
                    "tube" => {
                        let mut x: Vec<f64> = f.iter().skip(4).take(17).map(|s| d_(s)).collect();
                        // Column 18: SurvivalSearch's verdict on a tube "no way" (1 no way either, 0 it got through).
                        let c = if f.len() > 22 { f[21] } else { "-" };
                        let way0 = x[WAY] == 0.0;
                        x.push(if way0 && c == "1" { 1.0 } else { 0.0 }); // CONFIRMED
                        x.push(if way0 && c == "0" { 1.0 } else { 0.0 }); // MISSED: the tube missed a way SurvivalSearch found
                        r.tube.push(x);
                    }
                    "react" => {
                        r.react.push(f.iter().skip(4).take(13).map(|s| s.parse::<i64>().expect("a react count")).collect());
                        r.react_detail.push(f[17].to_string());
                    }
                    "bots" => {
                        let (k, n) = r.bots.get(f[3]).copied().unwrap_or((0, 0));
                        let won: i32 = f[4].parse().expect("a clear flag");
                        r.bots.set(f[3], (k + won, n + 1));
                        if f[4] == "0" {
                            if !r.causes.contains(f[3]) {
                                r.causes.set(f[3], OMap::new());
                            }
                            let m = r.causes.get_mut(f[3]).unwrap();
                            let old = m.get(f[6]).copied().unwrap_or(0);
                            m.set(f[6], old + 1);
                        }
                    }
                    _ => {}
                }
            }
        }
        rooms
    }

    fn median(xs: impl Iterator<Item = f64>) -> f64 {
        let mut s: Vec<f64> = xs.collect();
        s.sort_by(|a, b| dcmp(*a, *b));
        if s.is_empty() {
            return f64::NAN;
        }
        if s.len() % 2 == 1 {
            s[s.len() / 2]
        } else {
            (s[s.len() / 2 - 1] + s[s.len() / 2]) / 2.0
        }
    }

    /// The per-room measures (medians over the entries), in Room.f.
    fn features(r: &mut Room) {
        let points = (if r.boss { SimConfig::BOSS_POINTS } else { SimConfig::POINTS_PER_ROOM }) as f64;
        if !r.tube.is_empty() {
            let ok: Vec<Vec<f64>> = r.tube.iter().filter(|x| x[WAY] > 0.0).cloned().collect();
            let cnt = |p: &dyn Fn(&Vec<f64>) -> bool| r.tube.iter().filter(|x| p(x)).count() as f64;
            let entries = r.tube.len() as f64;
            // An entry counts as having no way only when SurvivalSearch agrees (old files without
            // that column: the tube's word, as "unconfirmed").
            let no_way = cnt(&|x| x[WAY] == 0.0 && x[CONFIRMED] == 1.0);
            let unconf = cnt(&|x| x[WAY] == 0.0 && x[CONFIRMED] == 0.0 && x[MISSED] == 0.0);
            let missed = cnt(&|x| x[MISSED] == 1.0);
            r.f.set("entries", entries);
            r.f.set("no_way_entries", no_way);
            r.f.set("no_way_unconfirmed", unconf);
            r.f.set("tube_missed", missed);
            if !ok.is_empty() {
                let med = |c: &dyn Fn(&Vec<f64>) -> f64| Self::median(ok.iter().map(c));
                r.f.set("band_min", med(&|x| x[BAND_MIN]));
                r.f.set("band_worst", dmin(ok.iter().map(|x| x[BAND_MIN])));
                r.f.set("band_p10", med(&|x| x[BAND_P10]));
                r.f.set("band_med", med(&|x| x[BAND_MED]));
                r.f.set("tight_s", med(&|x| x[TIGHT_S]));
                r.f.set("bits_per_point", med(&|x| x[BITS] / points));
                r.f.set("window", med(&|x| x[WIN]));
                r.f.set("window_worst", dmin(ok.iter().map(|x| x[WIN])));
                r.f.set("window_med", med(&|x| x[WIN_MED]));
                r.f.set("tight_taps_per_s", med(&|x| if x[LINE_S] > 0.0 { x[TIGHT] / x[LINE_S] } else { 0.0 }));
                r.f.set("taps_per_s", med(&|x| if x[LINE_S] > 0.0 { x[TAPS] / x[LINE_S] } else { 0.0 }));
                r.f.set("choice_frac", med(&|x| if x[LINE_S] > 0.0 { x[CHOICE_S] / x[LINE_S] } else { 0.0 }));
                r.f.set("viable_frac", med(&|x| x[VIABLE]));
                r.f.set("line_s", med(&|x| x[LINE_S]));
            }
        }
        if !r.react.is_empty() {
            // Enumerable.Sum over longs, then to double.
            let shown = r.react.iter().map(|x| x[0]).sum::<i64>() as f64;
            let way0 = r.react.iter().map(|x| x[0] - x[1] - x[2]).sum::<i64>() as f64;
            r.f.set("shown", shown);
            let per = shown / G::maxi(1, r.react.len() as i64) as f64 / cs_max(1.0, r.f.gv("line_s", 16.0));
            r.f.set("shown_per_s", per);
            let doomed = if shown == 0.0 { 0.0 } else { r.react.iter().map(|x| x[1] + x[2]).sum::<i64>() as f64 / shown };
            r.f.set("doomed0", doomed);
            for j in 1..ReactSweep::REACTS.len() {
                let fail = r.react.iter().map(|x| x[3 + 3 * j]).sum::<i64>() as f64;
                r.f.set(&format!("fail{}", ReactSweep::REACTS[j]), if way0 == 0.0 { 0.0 } else { fail / way0 });
                r.f.set(&format!("fails{}", ReactSweep::REACTS[j]), fail);
            }
            r.f.set("way0", way0);
        }
        let bots = r.bots.items.clone();
        for (bot, (k, n)) in bots {
            r.f.set(&format!("clear_{}", bot), if n == 0 { f64::NAN } else { k as f64 / n as f64 });
        }
    }

    /// Item-response (Rasch) fit: b per room, skill per bot. Every room's b has a
    /// N(0, 2.5^2) prior, so a room every bot clears still gets a finite b.
    fn fit_irt(rooms: &mut [Room]) -> OMap<f64> {
        let mut bots: Vec<String> = Vec::new();
        for r in rooms.iter() {
            for (b, _) in &r.bots.items {
                if !bots.contains(b) {
                    bots.push(b.clone());
                }
            }
        }
        let mut th: OMap<f64> = OMap::new();
        for b in &bots {
            th.set(b, 0.0);
        }
        let played: Vec<usize> = (0..rooms.len()).filter(|&i| rooms[i].bots.len() > 0).collect();
        if played.is_empty() {
            return th;
        }
        for &i in &played {
            rooms[i].b = 0.0;
        }
        const PRIOR: f64 = 1.0 / (2.5 * 2.5);
        for _it in 0..300 {
            for &i in &played {
                let r = &mut rooms[i];
                let mut g = -PRIOR * r.b;
                let mut h = -PRIOR;
                for (bot, (k, n)) in &r.bots.items {
                    let p = 1.0 / (1.0 + (-(th.at(bot) - r.b)).exp());
                    g -= *k as f64 - *n as f64 * p;
                    h -= *n as f64 * p * (1.0 - p);
                }
                r.b -= g / h;
            }
            for bot in &bots {
                let mut g = 0.0;
                let mut h = -1e-3;
                for &i in &played {
                    let r = &rooms[i];
                    if let Some(&(k, n)) = r.bots.get(bot) {
                        let p = 1.0 / (1.0 + (-(th.at(bot) - r.b)).exp());
                        g += k as f64 - n as f64 * p;
                        h -= n as f64 * p * (1.0 - p);
                    }
                }
                let v = th.at(bot) - g / h;
                th.set(bot, v);
            }
        }
        th
    }

    /// Skill `x` on the tier scale, linear through beginner = 1 and good = 3 (the
    /// two tiers that differ most per room; normal lands at 2 by itself). Expert and
    /// beast clear little more than good in a single room, so they sit just above 3
    /// and are not used as anchors.
    pub fn tier_needed(x: f64, th: &OMap<f64>) -> f64 {
        let (Some(&lo), Some(&hi)) = (th.get("beginner"), th.get("good")) else { return f64::NAN };
        if hi <= lo {
            return f64::NAN;
        }
        1.0 + 2.0 * (x - lo) / (hi - lo)
    }

    /// The analytic measures used to predict the skill a room needs.
    pub const FEATURES: [&'static str; 13] = [
        "band_p10", "band_worst", "tight_s", "bits_per_point", "window", "window_worst", "tight_taps_per_s",
        "choice_frac", "viable_frac", "doomed0", "fail20", "fail40", "fail60",
    ];

    fn tr(name: &str, v: f64) -> f64 {
        match name {
            "band_p10" | "band_worst" | "bits_per_point" | "window" | "window_worst" => cs_max(1.0, v).ln(),
            _ => v,
        }
    }

    /// Ridge regression of the bot skill on the analytic measures (standardised);
    /// leave-one-out correlation; Spearman of every single measure with the skill.
    #[allow(clippy::type_complexity)]
    fn fit_analytic(rooms: &mut [Room]) -> (Vec<&'static str>, Option<Vec<f64>>, f64, OMap<f64>) {
        let names: Vec<&'static str> = Self::FEATURES.to_vec();
        let have: Vec<usize> = (0..rooms.len()).filter(|&i| names.iter().all(|n| rooms[i].f.contains(n))).collect();
        let train: Vec<usize> = have.iter().copied().filter(|&i| !rooms[i].skill.is_nan()).collect();
        let mut corr: OMap<f64> = OMap::new();
        let extra = ["band_min", "band_med", "taps_per_s", "no_way_entries"];
        for n in names.iter().copied().chain(extra) {
            let pr: Vec<usize> = train.iter().copied().filter(|&i| rooms[i].f.contains(n)).collect();
            if pr.len() > 3 {
                let a: Vec<f64> = pr.iter().map(|&i| rooms[i].f.at(n)).collect();
                let b: Vec<f64> = pr.iter().map(|&i| rooms[i].skill).collect();
                corr.set(n, spearman(&a, &b));
            }
        }
        if train.len() < names.len() + 3 {
            return (names, None, f64::NAN, corr);
        }
        let mu: Vec<f64> =
            names.iter().map(|n| average(train.iter().map(|&i| Self::tr(n, rooms[i].f.at(n))))).collect();
        let sd: Vec<f64> = names
            .iter()
            .enumerate()
            .map(|(j, n)| average(train.iter().map(|&i| pow(Self::tr(n, rooms[i].f.at(n)) - mu[j], 2.0))).sqrt() + 1e-9)
            .collect();
        let x_ = |r: &Room| -> Vec<f64> {
            names.iter().enumerate().map(|(j, n)| (Self::tr(n, r.f.at(n)) - mu[j]) / sd[j]).collect()
        };
        let solve = |rs: &[&Room]| -> Vec<f64> {
            let p = names.len() + 1;
            let mut a = vec![vec![0.0f64; p]; p];
            let mut y = vec![0.0f64; p];
            for r in rs {
                let mut x = x_(r);
                x.push(1.0);
                for ai in 0..p {
                    y[ai] += x[ai] * r.skill;
                    for c in 0..p {
                        a[ai][c] += x[ai] * x[c];
                    }
                }
            }
            for ai in 0..p - 1 {
                a[ai][ai] += 3.0; // ridge
            }
            gauss(&a, &y)
        };
        let predict = |w: &[f64], r: &Room| -> f64 {
            let mut x = x_(r);
            x.push(1.0);
            sum(x.iter().zip(w.iter()).map(|(a, c)| a * c))
        };
        let mut loo_pred: Vec<f64> = Vec::new();
        for &i in &train {
            let others: Vec<&Room> = train.iter().filter(|&&o| o != i).map(|&o| &rooms[o]).collect();
            let w = solve(&others);
            loo_pred.push(predict(&w, &rooms[i]));
        }
        let skills: Vec<f64> = train.iter().map(|&i| rooms[i].skill).collect();
        let loo = pearson(&loo_pred, &skills);
        let all_train: Vec<&Room> = train.iter().map(|&i| &rooms[i]).collect();
        let wall = solve(&all_train);
        let preds: Vec<f64> = have.iter().map(|&i| predict(&wall, &rooms[i])).collect();
        for (k, &i) in have.iter().enumerate() {
            rooms[i].analytic = preds[k];
        }
        (names, Some(wall), loo, corr)
    }

    pub fn flags(r: &Room, bands: &BandsResult) -> String {
        let mut f: Vec<&str> = Vec::new();
        if r.f.gv("no_way_entries", 0.0) > 0.0 {
            f.push("no-way");
        } else if r.f.gv("no_way_unconfirmed", 0.0) > 0.0 {
            f.push("no-way?");
        }
        // Reaction.MAX_EXTRA_PCT: at most 2% of cases may die that a quick reaction survives.
        if r.f.gv("fails20", 0.0) >= 2.0 && r.f.gv("fail20", 0.0) * 100.0 > Reaction::MAX_EXTRA_PCT as f64 {
            f.push("unfair-react");
        } else if r.f.gv("fail40", 0.0) > bands.fail40_limit {
            f.push("slow-react");
        }
        let sug = bands.category(r);
        if let Some(sug) = sug {
            if sug != r.group && Bands::ORDER.contains(&r.group.as_str()) {
                let a = Bands::ORDER.iter().position(|&x| x == r.group).unwrap();
                let b = Bands::ORDER.iter().position(|&x| x == sug).map(|x| x as i64).unwrap_or(-1);
                if b > a as i64 {
                    f.push("too-hard");
                }
                if b < a as i64 {
                    f.push("too-easy");
                }
            }
        }
        if (r.group == "bonus" || r.group == "seasonal") && r.score > bands.hi {
            f.push("too-hard");
        }
        if r.group == "boss" && r.score < bands.lo {
            f.push("too-easy");
        }
        let mut d: Vec<&str> = Vec::new();
        for x in f {
            if !d.contains(&x) {
                d.push(x);
            }
        }
        d.join(" ")
    }

    fn num(x: f64) -> Value {
        if x.is_nan() || x.is_infinite() {
            Value::Null
        } else {
            json!(round4(x))
        }
    }

    fn obj(items: impl Iterator<Item = (String, Value)>) -> Value {
        let mut m = Map::new();
        for (k, v) in items {
            m.insert(k, v);
        }
        Value::Object(m)
    }

    /// Rooms by descending score (NaN as -1), ties in list order (OrderByDescending is stable).
    fn ranked(rooms: &[Room]) -> Vec<&Room> {
        let key = |r: &Room| if r.score.is_nan() { -1.0 } else { r.score };
        let mut v: Vec<&Room> = rooms.iter().collect();
        v.sort_by(|a, b| dcmp(key(b), key(a)));
        v
    }

    /// `GroupBy(r => r.group)` over the scored rooms: groups in first-seen order.
    fn groups(rooms: &[Room]) -> Vec<(String, Vec<f64>)> {
        let mut g: Vec<(String, Vec<f64>)> = Vec::new();
        for r in rooms.iter().filter(|r| !r.score.is_nan()) {
            match g.iter_mut().find(|x| x.0 == r.group) {
                Some(x) => x.1.push(r.score),
                None => g.push((r.group.clone(), vec![r.score])),
            }
        }
        g
    }

    #[allow(clippy::too_many_arguments)]
    fn build(
        rooms: &[Room],
        theta: &OMap<f64>,
        names: &[&str],
        w: Option<&[f64]>,
        loo: f64,
        corr: &OMap<f64>,
        bands: &BandsResult,
    ) -> Value {
        let subs = Sub::all(rooms);
        let mut arr: Vec<Value> = Vec::new();
        for r in Self::ranked(rooms) {
            let ri = rooms.iter().position(|x| std::ptr::eq(x, r)).unwrap();
            let sub = Sub::of(&subs, ri);
            let mut o = Map::new();
            o.insert("label".into(), json!(r.label));
            o.insert("room".into(), json!(r.id));
            o.insert("variant".into(), json!(r.variant));
            o.insert("group".into(), json!(r.group));
            o.insert("from".into(), json!(r.from));
            o.insert("score".into(), Self::num(r.score));
            o.insert("skill".into(), Self::num(r.skill * 20.0));
            o.insert("analytic".into(), Self::num(r.analytic * 20.0));
            o.insert("b".into(), Self::num(r.b));
            o.insert("suggested".into(), bands.category(r).map(|s| json!(s)).unwrap_or(Value::Null));
            o.insert("flags".into(), json!(Self::flags(r, bands)));
            o.insert("errors".into(), json!(r.errors));
            o.insert("sub".into(), Self::obj(sub.items.iter().map(|(k, v)| (k.clone(), Self::num(*v)))));
            o.insert("f".into(), Self::obj(r.f.items.iter().map(|(k, v)| (k.clone(), Self::num(*v)))));
            o.insert("bots".into(), Self::obj(r.bots.items.iter().map(|(k, v)| (k.clone(), json!([v.0, v.1])))));
            o.insert(
                "react_fails".into(),
                Value::Array(r.react_detail.iter().filter(|d| d.as_str() != "-").take(12).map(|d| json!(d)).collect()),
            );
            arr.push(Value::Object(o));
        }
        let mut top = Map::new();
        top.insert("theta".into(), Self::obj(theta.items.iter().map(|(k, v)| (k.clone(), Self::num(*v)))));
        top.insert(
            "tier_scores".into(),
            Self::obj(theta.items.iter().map(|(k, v)| (k.clone(), Self::num(20.0 * Self::tier_needed(*v, theta))))),
        );
        top.insert(
            "weights".into(),
            match w {
                None => Value::Null,
                Some(w) => Self::obj(names.iter().enumerate().map(|(j, n)| (n.to_string(), Self::num(w[j])))),
            },
        );
        top.insert("loo_r".into(), Self::num(loo));
        top.insert("spearman".into(), Self::obj(corr.items.iter().map(|(k, v)| (k.clone(), Self::num(*v)))));
        let mut b = Map::new();
        b.insert("starter_max".into(), Self::num(bands.lo));
        b.insert("mid_max".into(), Self::num(bands.hi));
        b.insert("fail40_limit".into(), Self::num(bands.fail40_limit));
        b.insert("agree".into(), Self::num(bands.agree));
        b.insert("fit_starter_max".into(), Self::num(bands.fit_lo));
        b.insert("fit_mid_max".into(), Self::num(bands.fit_hi));
        b.insert("fit_agree".into(), Self::num(bands.fit_agree));
        top.insert("bands".into(), Value::Object(b));
        top.insert(
            "group_median".into(),
            Self::obj(Self::groups(rooms).into_iter().map(|(g, xs)| (g, Self::num(Self::median(xs.into_iter()))))),
        );
        top.insert("rooms".into(), Value::Array(arr));
        Value::Object(top)
    }

    /// `P(x, fmt)`: "-" for NaN, else x.ToString(fmt, InvariantCulture) ("F0" / "F2").
    fn p_(x: f64, d: usize) -> String {
        if x.is_nan() {
            "-".to_string()
        } else {
            fmt_f(x, d)
        }
    }

    fn markdown(rooms: &[Room], theta: &OMap<f64>, corr: &OMap<f64>, loo: f64, bands: &BandsResult) -> String {
        let n = nl();
        let mut sb = String::new();
        let mut line = |s: &str| {
            sb.push_str(s);
            sb.push_str(n);
        };
        line("# Room difficulty");
        line("");
        let mut by_skill: Vec<(String, f64)> = theta.items.clone();
        by_skill.sort_by(|a, b| dcmp(a.1, b.1));
        line(&format!(
            "Bot skills (item-response fit): {}",
            by_skill.iter().map(|(k, v)| format!("{} {}", k, fmt_f(*v, 2))).collect::<Vec<_>>().join(", ")
        ));
        let ln9 = 9f64.ln();
        line(&format!(
            "On the score scale (a room this bot clears 9 in 10 times needs at most): {}",
            by_skill
                .iter()
                .map(|(k, v)| format!("{} {}", k, fmt_f(20.0 * Self::tier_needed(*v - ln9 + ln9, theta), 0)))
                .collect::<Vec<_>>()
                .join(", ")
        ));
        line(&format!("Analytic fit, leave-one-out r with the bot skill: {}", Self::p_(loo, 2)));
        line("Spearman of each measure with the bot skill:");
        let mut cs: Vec<(String, f64)> = corr.items.clone();
        cs.sort_by(|a, b| dcmp(b.1.abs(), a.1.abs()));
        for (k, v) in &cs {
            line(&format!("  {:<18} {:>6}", k, fmt_f(*v, 2)));
        }
        line(&format!(
            "Bands: starter <= {} < mid <= {} < late; agreement with today's groups {} (best-fitting cuts {} / {} would agree {})",
            fmt_f(bands.lo, 0),
            fmt_f(bands.hi, 0),
            fmt_p_inv(bands.agree, 0),
            fmt_f(bands.fit_lo, 0),
            fmt_f(bands.fit_hi, 0),
            fmt_p_inv(bands.fit_agree, 0)
        ));
        line(&format!(
            "Median score per group: {}",
            Self::groups(rooms)
                .into_iter()
                .map(|(g, xs)| format!("{} {}", g, fmt_f(Self::median(xs.into_iter()), 0)))
                .collect::<Vec<_>>()
                .join(", ")
        ));
        line("");
        line("## Rooms");
        line("");
        line("| # | room | group | from | score | skill | analytic | space | precision | reaction | busy | beginner | normal | good | expert | beast | honest | suggested | flags |");
        line("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|");
        let subs = Sub::all(rooms);
        let mut i = 0;
        for r in Self::ranked(rooms) {
            let ri = rooms.iter().position(|x| std::ptr::eq(x, r)).unwrap();
            let sub = Sub::of(&subs, ri);
            let c = |bot: &str| -> String {
                match r.bots.get(bot) {
                    Some(&(k, n)) => format!("{}%", fmt_f(100.0 * k as f64 / n as f64, 0)),
                    None => "-".to_string(),
                }
            };
            let sv = |name: &str| Self::p_(sub.get(name).copied().unwrap_or(f64::NAN), 0);
            i += 1;
            line(&format!(
                "| {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} |",
                i,
                r.label,
                r.group,
                r.from,
                Self::p_(r.score, 0),
                Self::p_(r.skill * 20.0, 0),
                Self::p_(r.analytic * 20.0, 0),
                sv("space"),
                sv("precision"),
                sv("reaction"),
                sv("busy"),
                c("beginner"),
                c("normal"),
                c("good"),
                c("expert"),
                c("beast"),
                c("honest"),
                bands.category(r).unwrap_or("-"),
                Self::flags(r, bands)
            ));
        }
        sb
    }
}

fn gauss(a: &[Vec<f64>], y: &[f64]) -> Vec<f64> {
    let n = y.len();
    let mut m: Vec<Vec<f64>> = a.to_vec();
    let mut b: Vec<f64> = y.to_vec();
    for c in 0..n {
        let mut piv = c;
        for r in c + 1..n {
            if m[r][c].abs() > m[piv][c].abs() {
                piv = r;
            }
        }
        for k in 0..n {
            let t = m[c][k];
            m[c][k] = m[piv][k];
            m[piv][k] = t;
        }
        b.swap(c, piv);
        for r in 0..n {
            if r == c {
                continue;
            }
            let f = m[r][c] / m[c][c];
            for k in 0..n {
                m[r][k] -= f * m[c][k];
            }
            b[r] -= f * b[c];
        }
    }
    (0..n).map(|i| b[i] / m[i][i]).collect()
}

pub fn pearson(a: &[f64], b: &[f64]) -> f64 {
    let ma = average(a.iter().copied());
    let mb = average(b.iter().copied());
    let sab = sum(a.iter().zip(b.iter()).map(|(x, y)| (x - ma) * (y - mb)));
    let sa = sum(a.iter().map(|x| (x - ma) * (x - ma))).sqrt();
    let sb = sum(b.iter().map(|y| (y - mb) * (y - mb))).sqrt();
    if sa * sb == 0.0 {
        0.0
    } else {
        sab / (sa * sb)
    }
}

fn ranks(v: &[f64]) -> Vec<f64> {
    let mut idx: Vec<usize> = (0..v.len()).collect();
    idx.sort_by(|&i, &j| dcmp(v[i], v[j]));
    let mut r = vec![0.0f64; v.len()];
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

pub fn spearman(a: &[f64], b: &[f64]) -> f64 {
    pearson(&ranks(a), &ranks(b))
}

/// Sub-scores 0..100 (100 = hardest of all rooms scored), each from one family
/// of measures, as a percentile rank among the rooms.
pub struct Sub;

impl Sub {
    const PARTS: [(&'static str, &'static [(&'static str, i32)]); 4] = [
        ("space", &[("band_p10", -1), ("band_worst", -1), ("tight_s", 1)]),
        ("precision", &[("window", -1), ("window_worst", -1), ("tight_taps_per_s", 1)]),
        ("reaction", &[("fail20", 1), ("fail40", 1), ("fail60", 1), ("doomed0", 1)]),
        ("busy", &[("shown_per_s", 1), ("choice_frac", 1), ("bits_per_point", -1)]),
    ];

    /// The C# cache for one room list: per part, room index -> sub-score (rooms that have it).
    pub fn all(all: &[Room]) -> Vec<(&'static str, Vec<Option<f64>>)> {
        let mut c = Vec::new();
        for (name, parts) in Self::PARTS {
            let have: Vec<usize> =
                (0..all.len()).filter(|&i| parts.iter().all(|p| all[i].f.contains(p.0))).collect();
            let mut sum_: Vec<f64> = vec![0.0; all.len()];
            for &(feat, sign) in parts {
                let mut order = have.clone();
                order.sort_by(|&a, &b| dcmp(sign as f64 * all[a].f.at(feat), sign as f64 * all[b].f.at(feat)));
                for i in 0..order.len() {
                    sum_[order[i]] += if order.len() > 1 { i as f64 / (order.len() - 1) as f64 } else { 0.5 };
                }
            }
            let mut v: Vec<Option<f64>> = vec![None; all.len()];
            for &i in &have {
                v[i] = Some(100.0 * sum_[i] / parts.len() as f64);
            }
            c.push((name, v));
        }
        c
    }

    pub fn of(c: &[(&'static str, Vec<Option<f64>>)], ri: usize) -> OMap<f64> {
        let mut m = OMap::new();
        for (name, v) in c {
            if let Some(x) = v[ri] {
                m.set(name, x);
            }
        }
        m
    }
}

/// Category bands on the tier scale: starter up to 40 (a normal player clears it 9
/// times in 10), mid up to 60 (a good player), late above. `agree` is the share of
/// today's starter, mid and late rooms already in their band; `fit_lo`/`fit_hi` the
/// two cut points that would agree best (for the report only: when today's late rooms
/// are no harder than the mid ones, that fit is degenerate). Bonus, seasonal and boss
/// rooms are placed by the same bands but keep their group.
pub struct Bands;

#[derive(Clone, Debug, Default)]
pub struct BandsResult {
    pub lo: f64,
    pub hi: f64,
    pub agree: f64,
    pub fail40_limit: f64,
    pub fit_lo: f64,
    pub fit_hi: f64,
    pub fit_agree: f64,
}

impl BandsResult {
    pub fn category(&self, r: &Room) -> Option<&'static str> {
        if r.score.is_nan() {
            return None;
        }
        Some(if r.score <= self.lo {
            "starter"
        } else if r.score <= self.hi {
            "mid"
        } else {
            "late"
        })
    }
}

impl Bands {
    pub const ORDER: [&'static str; 3] = ["starter", "mid", "late"];

    pub fn suggest(rooms: &[Room]) -> BandsResult {
        let rs: Vec<&Room> =
            rooms.iter().filter(|r| !r.score.is_nan() && Self::ORDER.contains(&r.group.as_str())).collect();
        let mut res = BandsResult { lo: 40.0, hi: 60.0, ..BandsResult::default() };
        // The reaction limit: twice the 90th percentile of the starter rooms' fail rate at 40 ticks.
        let mut st: Vec<f64> =
            rooms.iter().filter(|r| r.group == "starter" && r.f.contains("fail40")).map(|r| r.f.at("fail40")).collect();
        st.sort_by(|a, b| dcmp(*a, *b));
        res.fail40_limit =
            if st.is_empty() { 0.05 } else { cs_max(0.02, 2.0 * st[(0.9 * (st.len() - 1) as f64) as i32 as usize]) };
        if rs.is_empty() {
            return res;
        }
        let band = |x: f64, lo: f64, hi: f64| -> &'static str {
            if x <= lo {
                "starter"
            } else if x <= hi {
                "mid"
            } else {
                "late"
            }
        };
        let mut cuts: Vec<f64> = Vec::new();
        for r in &rs {
            if !cuts.iter().any(|&c| c == r.score) {
                cuts.push(r.score);
            }
        }
        cuts.sort_by(|a, b| dcmp(*a, *b));
        let mut best: i64 = -1;
        for &lo in &cuts {
            for &hi in cuts.iter().filter(|&&h| h > lo) {
                let ok = rs.iter().filter(|r| band(r.score, lo, hi) == r.group).count() as i64;
                if ok > best {
                    best = ok;
                    res.fit_lo = lo;
                    res.fit_hi = hi;
                }
            }
        }
        res.fit_agree = best as f64 / rs.len() as f64;
        let best = rs.iter().filter(|r| band(r.score, res.lo, res.hi) == r.group).count() as i64;
        res.agree = best as f64 / rs.len() as f64;
        res
    }
}

/// C# `x.ToString("P<d>")` under InvariantGlobalization (FastSim.csproj): the invariant
/// culture's percent pattern "n %" (a space before the sign).
fn fmt_p_inv(x: f64, d: usize) -> String {
    format!("{} %", fmt_f(x * 100.0, d))
}
