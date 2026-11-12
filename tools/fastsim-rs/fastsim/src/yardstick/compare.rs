//! Port of Yardstick/Compare.cs: bot runs against human runs: distances between their
//! distributions and a small human-vs-bot classifier on per-run features (the Navigation
//! Turing Test idea, Devlin et al. ICML 2021). A classifier at 50% accuracy cannot
//! tell them apart; at 100% the bot is easy to spot.
use serde_json::{json, Map, Value};

use super::runs::Run;
use super::stats::{average, jf, round, sum, Stats};

pub struct Compare;

impl Compare {
    pub const MIN_TAPS: i32 = 10;

    pub const FEATURES: [&'static str; 15] = [
        "taps_per_s",
        "interval_median",
        "interval_p10",
        "interval_cv",
        "under_8",
        "band0",
        "band1",
        "band2",
        "band3",
        "band4",
        "band5",
        "band6",
        "band7",
        "react_bounce",
        "react_new",
    ];

    pub fn features(r: &Run) -> Vec<f64> {
        let ints: Vec<f64> = r.intervals.iter().map(|&x| x as f64).collect();
        let mean = if ints.is_empty() { 0.0 } else { average(&ints) };
        let sd = if ints.len() < 2 {
            0.0
        } else {
            let mut ss = 0.0;
            for &x in &ints {
                ss += (x - mean) * (x - mean);
            }
            (ss / (ints.len() - 1) as f64).sqrt()
        };
        let total = r.bands.iter().sum::<i64>().max(1) as f64;
        let mut f = vec![
            r.taps_per_s(),
            Stats::pct(&ints, 0.5),
            Stats::pct(&ints, 0.1),
            if mean > 0.0 { sd / mean } else { 0.0 },
            if ints.is_empty() {
                0.0
            } else {
                r.intervals.iter().filter(|&&i| i < Stats::HUMAN_MIN_INTERVAL).count() as f64 / ints.len() as f64
            },
        ];
        f.extend(r.bands.iter().map(|&b| b as f64 / total));
        let rbv: Vec<f64> = r.react_bounce.iter().map(|&x| x as f64).collect();
        let rnv: Vec<f64> = r.react_new.iter().map(|&x| x as f64).collect();
        let rb = Stats::pct(&rbv, 0.5);
        let rn = Stats::pct(&rnv, 0.5);
        f.push(if rb.is_nan() { Run::REACT_WINDOW as f64 } else { rb });
        f.push(if rn.is_nan() { Run::REACT_WINDOW as f64 } else { rn });
        f.into_iter().map(|x| if x.is_nan() { 0.0 } else { x }).collect()
    }

    fn tv(a: &[f64], b: &[f64]) -> f64 {
        let d: Vec<f64> = a.iter().zip(b.iter()).map(|(x, y)| (x - y).abs()).collect();
        0.5 * sum(&d)
    }

    fn ks(a: &[f64], b: &[f64]) -> f64 {
        if a.is_empty() || b.is_empty() {
            return f64::NAN;
        }
        // a.Concat(b).Distinct().OrderBy(x => x)
        let mut all: Vec<f64> = Vec::new();
        for &x in a.iter().chain(b.iter()) {
            if !all.contains(&x) {
                all.push(x);
            }
        }
        all.sort_by(|x, y| x.partial_cmp(y).unwrap());
        let mut sa = a.to_vec();
        sa.sort_by(|x, y| x.partial_cmp(y).unwrap());
        let mut sb = b.to_vec();
        sb.sort_by(|x, y| x.partial_cmp(y).unwrap());
        let mut d: f64 = 0.0;
        for &x in &all {
            let fa = Self::upper(&sa, x) as f64 / sa.len() as f64;
            let fb = Self::upper(&sb, x) as f64 / sb.len() as f64;
            d = d.max((fa - fb).abs());
        }
        d
    }

    fn upper(s: &[f64], x: f64) -> usize {
        let mut lo = 0;
        let mut hi = s.len();
        while lo < hi {
            let m = (lo + hi) / 2;
            if s[m] <= x {
                lo = m + 1;
            } else {
                hi = m;
            }
        }
        lo
    }

    /// Distances (0 = the same as the humans, 1 = nothing alike) and the classifier.
    pub fn against(bot: &[Run], human: &[Run]) -> Value {
        let ints = |rs: &[Run]| -> Vec<i32> { rs.iter().flat_map(|r| r.intervals.iter().copied()).collect() };
        let news = |rs: &[Run]| -> Vec<i32> { rs.iter().flat_map(|r| r.react_new.iter().copied()).collect() };
        let t_int = Self::tv(
            &Stats::hist(&ints(bot), &Stats::INTERVAL_BINS),
            &Stats::hist(&ints(human), &Stats::INTERVAL_BINS),
        );
        let t_band = Self::tv(&Stats::band_shares(bot), &Stats::band_shares(human));
        let t_react =
            Self::tv(&Stats::hist(&news(bot), &Stats::REACT_BINS), &Stats::hist(&news(human), &Stats::REACT_BINS));
        let tps_b: Vec<f64> = bot.iter().map(|r| r.taps_per_s()).collect();
        let tps_h: Vec<f64> = human.iter().map(|r| r.taps_per_s()).collect();
        let k_tps = Self::ks(&tps_b, &tps_h);
        let parts: Vec<f64> = [t_int, t_band, t_react, k_tps].into_iter().filter(|x| !x.is_nan()).collect();
        let mut o = json!({
            "human_runs": human.len(),
            "intervals_tv": jf(round(t_int, 4)),
            "bands_tv": jf(round(t_band, 4)),
            "react_tv": jf(round(t_react, 4)),
            "taps_per_s_ks": if k_tps.is_nan() { Value::Null } else { jf(round(k_tps, 4)) },
            "likeness": jf(round(1.0 - average(&parts), 4)),
        });
        let b: Vec<Run> = bot.iter().filter(|r| r.taps_played >= Self::MIN_TAPS).cloned().collect();
        let h: Vec<Run> = human.iter().filter(|r| r.taps_played >= Self::MIN_TAPS).cloned().collect();
        if b.len() >= 5 && h.len() >= 5 {
            o.as_object_mut().unwrap().insert("classifier".to_string(), Self::classify(&b, &h));
        }
        o
    }

    /// Logistic regression on standardised features, 5-fold cross-validated,
    /// classes weighted equally. Returns accuracy, AUC and the features it leans on.
    pub fn classify(bot: &[Run], human: &[Run]) -> Value {
        let xs: Vec<Vec<f64>> = bot.iter().map(Self::features).chain(human.iter().map(Self::features)).collect();
        let ys: Vec<i32> = bot.iter().map(|_| 0).chain(human.iter().map(|_| 1)).collect();
        let n = xs.len();
        let d = xs[0].len();
        let mut mean = vec![0.0; d];
        let mut sdv = vec![0.0; d];
        for j in 0..d {
            let col: Vec<f64> = xs.iter().map(|x| x[j]).collect();
            mean[j] = average(&col);
            let sq: Vec<f64> = xs.iter().map(|x| (x[j] - mean[j]) * (x[j] - mean[j])).collect();
            sdv[j] = average(&sq).sqrt();
            if sdv[j] < 1e-9 {
                sdv[j] = 1.0;
            }
        }
        let z: Vec<Vec<f64>> =
            xs.iter().map(|x| x.iter().enumerate().map(|(j, &v)| (v - mean[j]) / sdv[j]).collect()).collect();
        let mut order: Vec<usize> = (0..n).collect();
        order.sort_by_key(|&i| (i as i64 * 2654435761i64) % 1000003);
        let mut score = vec![0.0; n];
        const FOLDS: usize = 5;
        for f in 0..FOLDS {
            let train: Vec<usize> = order.iter().enumerate().filter(|(k, _)| k % FOLDS != f).map(|(_, &i)| i).collect();
            let w = Self::fit(&z, &ys, &train, d);
            for (_, &i) in order.iter().enumerate().filter(|(k, _)| k % FOLDS == f) {
                score[i] = Self::dot(&w, &z[i]);
            }
        }
        let mut _right = 0;
        let wb = 0.5 / bot.len() as f64;
        let wh = 0.5 / human.len() as f64;
        let mut acc = 0.0;
        for i in 0..n {
            if (score[i] > 0.0) == (ys[i] == 1) {
                _right += 1;
                acc += if ys[i] == 1 { wh } else { wb };
            }
        }
        let all_rows: Vec<usize> = (0..n).collect();
        let all_w = Self::fit(&z, &ys, &all_rows, d);
        let mut by: Vec<usize> = (0..d).collect();
        by.sort_by(|&a, &b| all_w[b].abs().partial_cmp(&all_w[a].abs()).unwrap());
        let mut top = Map::new();
        for &j in by.iter().take(5) {
            top.insert(Self::FEATURES[j].to_string(), jf(round(all_w[j], 3)));
        }
        json!({
            "balanced_accuracy": jf(round(acc, 4)),
            "auc": jf(round(Self::auc(&score, &ys), 4)),
            "bot_runs": bot.len(),
            "human_runs": human.len(),
            "weights": top,
            "note": "0.5 = cannot tell the bot from the humans; 1.0 = always can",
        })
    }

    fn dot(w: &[f64], x: &[f64]) -> f64 {
        let mut s = w[w.len() - 1];
        for j in 0..x.len() {
            s += w[j] * x[j];
        }
        s
    }

    fn fit(z: &[Vec<f64>], ys: &[i32], rows: &[usize], d: usize) -> Vec<f64> {
        let mut w = vec![0.0; d + 1];
        let pos = rows.iter().filter(|&&i| ys[i] == 1).count() as i32;
        let neg = rows.len() as i32 - pos;
        let wp = rows.len() as f64 / (2.0 * pos.max(1) as f64);
        let wn = rows.len() as f64 / (2.0 * neg.max(1) as f64);
        const LR: f64 = 0.1;
        const L2: f64 = 0.01;
        for _it in 0..500 {
            let mut g = vec![0.0; d + 1];
            for &i in rows {
                let p = 1.0 / (1.0 + (-Self::dot(&w, &z[i])).exp());
                let e = (p - ys[i] as f64) * (if ys[i] == 1 { wp } else { wn });
                for j in 0..d {
                    g[j] += e * z[i][j];
                }
                g[d] += e;
            }
            for j in 0..=d {
                w[j] -= LR * (g[j] / rows.len() as f64 + (if j < d { L2 * w[j] } else { 0.0 }));
            }
        }
        w
    }

    fn auc(s: &[f64], ys: &[i32]) -> f64 {
        let mut idx: Vec<usize> = (0..s.len()).collect();
        idx.sort_by(|&a, &b| s[a].partial_cmp(&s[b]).unwrap());
        let mut rank_sum = 0.0;
        let pos = ys.iter().filter(|&&y| y == 1).count() as i64;
        let neg = ys.len() as i64 - pos;
        for r in 0..idx.len() {
            if ys[idx[r]] == 1 {
                rank_sum += (r + 1) as f64;
            }
        }
        if pos == 0 || neg == 0 {
            return f64::NAN;
        }
        (rank_sum - (pos * (pos + 1)) as f64 / 2.0) / (pos * neg) as f64
    }
}
