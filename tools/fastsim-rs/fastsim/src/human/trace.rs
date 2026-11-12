//! Port of Human/Trace.cs: what one run looked like, and the "looks human" score.
use std::fmt;

use sim::prelude::*;

use crate::bots::PlannerBot;
use crate::human::{fmt_f, fmt_p};

/// What one run looked like, for the "looks human" score: the bird's height
/// each tick, the taps and the bounces (new spikes appear at a bounce).
#[derive(Clone, Debug, Default)]
pub struct Trace {
    pub seed: i64,
    pub points: i64,
    pub ticks: i64,
    pub dead: bool,
    pub room: String,
    pub cause: String,
    pub taps: Vec<i64>,
    pub bounces: Vec<i64>,
    pub rooms: Vec<i64>,
    /// Heights as a share of the playfield, 0 = ceiling kill line, 1 = floor
    /// (flipped in reversed gravity, so 1 is always "where you fall to").
    pub h: Vec<f32>,
    /// Spike deaths: height at the last bounce, at death, and of the nearest gap ahead (px).
    pub bounce_y: i64,
    pub death_y: i64,
    pub gap_y: i64,
    pub since_bounce: i64,
}

impl Trace {
    /// Plays one run with `decide`, recording it. `cap` ticks at most (C# keep_heights default true).
    pub fn play<F: FnMut(&GameSim) -> bool>(sim: &mut GameSim, mut decide: F, cap: i64, keep_heights: bool) -> Trace {
        let mut tr = Trace {
            seed: sim.seed_value,
            bounce_y: -1,
            death_y: -1,
            gap_y: -1,
            since_bounce: -1,
            ..Default::default()
        };
        let start = sim.state.score;
        let mut n: i64 = 0;
        let top = SimConfig::KILL_TOP as f64;
        let span = (SimConfig::KILL_BOTTOM - SimConfig::KILL_TOP) as f64;
        while n < cap && !sim.is_over() {
            let t = sim.state.tick;
            let tap = decide(&*sim);
            let sc = sim.state.score;
            let ri = sim.state.room_index;
            sim.step(tap);
            if tap && sim.state.started {
                tr.taps.push(t);
            }
            if sim.state.score != sc {
                tr.bounces.push(t);
                tr.bounce_y = sim.state.y / SimConfig::SUB;
            }
            if sim.state.room_index != ri {
                tr.rooms.push(t);
            }
            if keep_heights && sim.state.started && sim.state.arrival_hold == 0 {
                let mut f = (sim.state.y as f64 - top) / span;
                if sim.room.gravity < 0 {
                    f = 1.0 - f;
                }
                tr.h.push(f as f32);
            }
            n += 1;
        }
        if sim.is_over() {
            tr.death_y = sim.state.y / SimConfig::SUB;
            let side = if sim.state.vx > 0 { 1 } else { 0 };
            tr.gap_y = PlannerBot::gap_center_y(sim.wall_mask(side)) / SimConfig::SUB;
            tr.since_bounce = if !tr.bounces.is_empty() { sim.state.tick - tr.bounces[tr.bounces.len() - 1] } else { -1 };
        }
        tr.points = sim.state.score - start;
        tr.ticks = n;
        tr.dead = sim.is_over();
        let v = sim.room.variant_id();
        tr.room = format!("{}{}", sim.room.def().id, if !v.is_empty() { format!("/{v}") } else { String::new() });
        tr.cause = if tr.dead { DeathCause::NAMES[sim.state.death_cause as usize].to_string() } else { String::new() };
        tr
    }
}

/// C# record Humanness.Report.
#[derive(Clone, Copy, Debug)]
pub struct Report {
    pub floor: f64,
    pub ceiling: f64,
    pub h_mean: f64,
    pub h_sd: f64,
    pub gap_med: f64,
    pub gap_cv: f64,
    pub fast_taps: f64,
    pub repeat: f64,
    pub react_fast: f64,
    pub react_med: f64,
    pub score: f64,
}

impl fmt::Display for Report {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "looks-human {}/100 | height mean {} sd {}, floor {}, ceiling {} | \
             tap gap med {}t cv {}, <6t {}, same-gap {} | first tap after bounce <8t {}, med {}t",
            fmt_f(self.score, 0),
            fmt_f(self.h_mean, 2),
            fmt_f(self.h_sd, 2),
            fmt_p(self.floor, 0),
            fmt_p(self.ceiling, 0),
            fmt_f(self.gap_med, 0),
            fmt_f(self.gap_cv, 2),
            fmt_p(self.fast_taps, 1),
            fmt_p(self.repeat, 0),
            fmt_p(self.react_fast, 0),
            fmt_f(self.react_med, 0)
        )
    }
}

/// The "looks human" score (0..100) of many runs, from parts that each
/// compare one habit with how people play a one-button flyer. No real
/// Flapjaw replays were on this PC, so the bands are priors from human
/// motor and reaction data (docs/HUMAN_BOT.md); swap in measured bands once
/// real replays are allowed.
pub struct Humanness;

/// Enumerable.Average over doubles: summed in order, then divided.
fn avg(xs: impl Iterator<Item = f64>) -> f64 {
    let mut s = 0.0;
    let mut n: i64 = 0;
    for x in xs {
        s += x;
        n += 1;
    }
    s / n as f64
}

impl Humanness {
    pub fn of(runs: &[Trace]) -> Report {
        let mut hs: Vec<f32> = Vec::new();
        let mut gaps: Vec<i64> = Vec::new();
        let mut react: Vec<i64> = Vec::new();
        let mut same: i64 = 0;
        let mut pairs: i64 = 0;
        for r in runs {
            hs.extend_from_slice(&r.h);
            for i in 1..r.taps.len() {
                let g = r.taps[i] - r.taps[i - 1];
                if g > 120 {
                    continue; // a hold, not a rhythm
                }
                gaps.push(g);
                if i > 1 {
                    pairs += 1;
                    if g == r.taps[i - 1] - r.taps[i - 2] {
                        same += 1;
                    }
                }
            }
            let mut j = 0;
            for &b in &r.bounces {
                while j < r.taps.len() && r.taps[j] <= b {
                    j += 1;
                }
                if j < r.taps.len() && r.taps[j] - b <= 90 {
                    react.push(r.taps[j] - b);
                }
            }
        }
        if hs.is_empty() {
            hs.push(0.5);
        }
        let nh = hs.len() as f64;
        let floor = hs.iter().filter(|&&x| x as f64 > 0.85).count() as f64 / nh;
        let ceil = hs.iter().filter(|&&x| (x as f64) < 0.12).count() as f64 / nh;
        // Average of floats: summed as double, returned as float.
        let mean = avg(hs.iter().map(|&x| x as f64)) as f32 as f64;
        let sd = avg(hs.iter().map(|&x| (x as f64 - mean) * (x as f64 - mean))).sqrt();
        let gmed = if !gaps.is_empty() { Humanness::med(&gaps) } else { 0.0 };
        let gmean = if !gaps.is_empty() { gaps.iter().sum::<i64>() as f64 / gaps.len() as f64 } else { 1.0 };
        let gcv = if gaps.len() > 1 {
            avg(gaps.iter().map(|&x| (x as f64 - gmean) * (x as f64 - gmean))).sqrt() / gmean
        } else {
            0.0
        };
        let fast = if !gaps.is_empty() { gaps.iter().filter(|&&x| x < 6).count() as f64 / gaps.len() as f64 } else { 0.0 };
        let rep = if pairs > 0 { same as f64 / pairs as f64 } else { 0.0 };
        let rfast = if !react.is_empty() { react.iter().filter(|&&x| x < 8).count() as f64 / react.len() as f64 } else { 0.0 };
        let rmed = if !react.is_empty() { Humanness::med(&react) } else { 0.0 };

        // Each part: 1 inside the human band, falling off linearly outside it.
        let mut s = 0.0;
        s += 20.0 * Humanness::band(floor, 0.0, 0.12, 0.35); // little time hugging the floor
        s += 10.0 * Humanness::band(ceil, 0.0, 0.06, 0.25); // or the ceiling
        s += 10.0 * Humanness::band2(mean, 0.35, 0.65, 0.2); // mostly mid screen
        s += 10.0 * Humanness::band2(sd, 0.10, 0.25, 0.08); // but not frozen at one height
        s += 10.0 * Humanness::band2(gmed, 14.0, 36.0, 10.0); // a calm tap rhythm (about 2-4 taps a second)
        s += 10.0 * Humanness::band2(gcv, 0.25, 0.75, 0.2); // neither metronome nor random
        s += 10.0 * Humanness::band(fast, 0.0, 0.02, 0.10); // almost never faster than 10 taps a second
        s += 10.0 * Humanness::band(rep, 0.0, 0.20, 0.50); // tick-exact repeats are robotic
        s += 10.0 * Humanness::band(rfast, 0.0, 0.08, 0.30); // no reaction to new spikes under ~130 ms
        Report {
            floor,
            ceiling: ceil,
            h_mean: mean,
            h_sd: sd,
            gap_med: gmed,
            gap_cv: gcv,
            fast_taps: fast,
            repeat: rep,
            react_fast: rfast,
            react_med: rmed,
            score: s,
        }
    }

    /// 1 when x <= ok, 0 when x >= bad (x >= lo assumed).
    fn band(x: f64, _lo: f64, ok: f64, bad: f64) -> f64 {
        if x <= ok {
            1.0
        } else if x >= bad {
            0.0
        } else {
            (bad - x) / (bad - ok)
        }
    }

    /// 1 inside [lo, hi], falling to 0 at `fall` outside.
    fn band2(x: f64, lo: f64, hi: f64, fall: f64) -> f64 {
        if x < lo {
            0f64.max(1.0 - (lo - x) / fall)
        } else if x > hi {
            0f64.max(1.0 - (x - hi) / fall)
        } else {
            1.0
        }
    }

    pub fn med(xs: &[i64]) -> f64 {
        let mut a = xs.to_vec();
        a.sort();
        if a.is_empty() {
            return 0.0;
        }
        let n = a.len();
        if n % 2 == 1 {
            a[n / 2] as f64
        } else {
            (a[n / 2 - 1] + a[n / 2]) as f64 / 2.0
        }
    }

    pub fn pct(xs: &[i64], p: f64) -> f64 {
        let mut a = xs.to_vec();
        a.sort();
        if a.is_empty() {
            return 0.0;
        }
        let n = a.len() as f64;
        let i = (p * (n - 1.0)).round_ties_even().clamp(0.0, n - 1.0) as usize;
        a[i] as f64
    }
}
