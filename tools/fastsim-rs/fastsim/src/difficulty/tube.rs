//! Port of Difficulty/Tube.cs. The "tube" of a room entry: every way through it, with exact
//! knowledge.
//!
//! A breadth-first search over real sim copies from the entry, one tick at a
//! time, that keeps one copy per bucket of bird state (4 px of height, 1/8 of a
//! flap of vertical speed, 40 px of x and the flight direction) instead of only
//! the best few (SurvivalSearch). Every kept copy is a node; each node records
//! which bucket its tap and its no-tap step landed in. A backward pass then
//! marks the viable nodes: those with a line that still reaches the exit (or,
//! in a boss room, the boss going down).
//!
//! From the viable nodes per tick:
//!   band:    how many px of bird heights still lead through (the free band);
//!            its minimum is the room's bottleneck.
//!   paths:   log2 of the number of viable tap sequences (bucket DAG paths), per second.
//!   window:  for a tap, the run of neighbouring ticks (no tap in between)
//!            at which the tap would still lead through: the timing precision
//!            it needs. The maximin line is the line whose tightest tap window
//!            is widest: "the most forgiving way through".
//!   choice:  ticks where the viable heights form two or more groups (over or
//!            under something), a route choice.
//! Taps follow SurvivalSearch's rule (only once the last flap has half worn off).
use std::collections::{HashMap, HashSet};
use std::hint::black_box;

use sim::prelude::*;

use super::cases::Cases;
use crate::bots::SurvivalSearch;

const DEAD: i32 = -1;
const EXIT: i32 = -2;

#[derive(Clone, Copy, Default)]
struct Node {
    /// slot of the child in the next layer (DEAD, EXIT)
    tap: i32,
    no: i32,
    /// slot of the node that made this copy in the layer before
    parent: i32,
    /// made by a tap
    by_tap: bool,
    /// height bucket
    yb: i16,
    #[allow(dead_code)]
    can_tap: bool,
}

#[derive(Clone, Debug)]
pub struct TubeResult {
    pub way: bool,
    pub ticks: i64,
    pub first_exit: i64,
    pub peak: i64,
    pub band_min: i64,
    pub band_p10: i64,
    pub band_med: i64,
    pub tight_s: f64,
    pub paths_bits: f64,
    pub bits_per_s: f64,
    pub line_window: i64,
    pub line_window_med: i64,
    pub line_taps: i64,
    pub line_tight: i64,
    pub line_s: f64,
    pub choice_s: f64,
    pub viable_frac: f64,
}

impl Default for TubeResult {
    fn default() -> Self {
        TubeResult {
            way: false,
            ticks: 0,
            first_exit: -1,
            peak: 0,
            band_min: 0,
            band_p10: 0,
            band_med: 0,
            tight_s: 0.0,
            paths_bits: 0.0,
            bits_per_s: 0.0,
            line_window: 0,
            line_window_med: 0,
            line_taps: 0,
            line_tight: 0,
            line_s: 0.0,
            choice_s: 0.0,
            viable_frac: 0.0,
        }
    }
}

#[derive(Default)]
pub struct Tube {
    /// Debug: a line per measured tick (tick, copies, viable, band px, height groups, viable y range).
    pub log: Option<fn(&str)>,
}

impl Tube {
    pub const BUCKET_H: i64 = 4 * SimConfig::SUB;
    pub const BUCKET_VY: i64 = -SimConfig::FLAP_VY / 8;
    pub const SPEEDS: i64 = 24;
    pub const BUCKET_X: i64 = 40 * SimConfig::SUB;
    /// Ticks after the entry and before the exit that the band ignores (the
    /// tube fans out from one point at the entry and funnels into the portal).
    pub const SKIP_START: i64 = 90;
    pub const SKIP_END: i64 = 40;
    /// A tap window this small or smaller counts as a precise tap (ticks).
    pub const TIGHT_WINDOW: i64 = 3;
    /// A route choice: viable heights split by at least this much (px).
    pub const SPLIT_PX: i64 = 24;
    pub const WINDOW_CAP: i64 = 30;

    pub fn new() -> Tube {
        Tube { log: None }
    }

    pub fn run(&self, start: &GameSim, cap: i64) -> TubeResult {
        let room = start.state.room_index;
        let mut layers: Vec<Vec<Node>> = Vec::new();
        let mut frontier: Vec<GameSim> = vec![start.clone_deep()];
        let first = Node { parent: -1, yb: (start.state.y / Self::BUCKET_H) as i16, ..Node::default() };
        let mut cur: Vec<Node> = vec![first];
        let mut res = TubeResult::default();
        let mut slots: HashMap<i64, i32> = HashMap::new();
        let mut next: Vec<GameSim> = Vec::new();
        let mut next_nodes: Vec<Node> = Vec::new();
        let mut t: i64 = 0;
        while t < cap && !frontier.is_empty() {
            slots.clear();
            next.clear();
            next_nodes.clear();
            let mut nodes = cur.clone();
            for (k, mut s) in frontier.drain(..).enumerate() {
                let can = s.state.vy * s.room.gravity > SurvivalSearch::TAP_BELOW_VY || !s.state.started;
                nodes[k].can_tap = can;
                nodes[k].tap = DEAD;
                nodes[k].no = DEAD;
                if can {
                    let mut c = s.clone_deep();
                    c.step(true);
                    nodes[k].tap = Self::keep(&mut slots, &mut next, &mut next_nodes, c, k as i32, true, room);
                    if nodes[k].tap == EXIT && res.first_exit < 0 {
                        res.first_exit = t + 1;
                    }
                }
                if !s.state.started {
                    continue;
                }
                s.step(false);
                nodes[k].no = Self::keep(&mut slots, &mut next, &mut next_nodes, s, k as i32, false, room);
                if nodes[k].no == EXIT && res.first_exit < 0 {
                    res.first_exit = t + 1;
                }
            }
            layers.push(nodes);
            frontier = std::mem::take(&mut next);
            cur = next_nodes.clone();
            res.peak = G::maxi(res.peak, frontier.len() as i64);
            t += 1;
        }
        // The last layer: still in the room at the cap, not a way through.
        let mut last = cur.clone();
        for n in last.iter_mut() {
            n.tap = DEAD;
            n.no = DEAD;
        }
        layers.push(last);
        res.ticks = t;
        Self::analyse(&layers, &mut res, self.log, start.state.arrival_hold);
        res
    }

    fn key(s: &GameSim) -> i64 {
        let st = &s.state;
        let along = st.vy * s.room.gravity - SimConfig::FLAP_VY;
        let speed = G::clampi(along / Self::BUCKET_VY, 0, Self::SPEEDS - 1);
        let mut k = st.y / Self::BUCKET_H;
        k = k * Self::SPEEDS + speed;
        k = k * 64 + G::clampi(st.x / Self::BUCKET_X, 0, 63);
        k = k * 2 + if st.vx > 0 { 1 } else { 0 };
        k = k * 2 + if s.room.gravity > 0 { 1 } else { 0 };
        k
    }

    #[allow(clippy::too_many_arguments)]
    fn keep(
        slots: &mut HashMap<i64, i32>,
        next: &mut Vec<GameSim>,
        nodes: &mut Vec<Node>,
        s: GameSim,
        parent: i32,
        tap: bool,
        room: i64,
    ) -> i32 {
        if s.is_over() {
            return DEAD;
        }
        if Cases::cleared(&s, room) {
            return EXIT;
        }
        let k = Self::key(&s);
        let n = Node { parent, by_tap: tap, yb: (s.state.y / Self::BUCKET_H) as i16, ..Node::default() };
        if let Some(&slot) = slots.get(&k) {
            if SurvivalSearch::_better(&s, &next[slot as usize]) {
                next[slot as usize] = s;
                nodes[slot as usize] = n;
            }
            return slot;
        }
        slots.insert(k, next.len() as i32);
        next.push(s);
        nodes.push(n);
        next.len() as i32 - 1
    }

    fn analyse(layers: &[Vec<Node>], res: &mut TubeResult, log: Option<fn(&str)>, hold: i64) {
        let l_ = layers.len();
        let mut viable: Vec<Vec<bool>> = vec![Vec::new(); l_];
        let mut tap_ok: Vec<Vec<bool>> = vec![Vec::new(); l_];
        let mut no_ok: Vec<Vec<bool>> = vec![Vec::new(); l_];
        let mut fw: Vec<Vec<i32>> = vec![Vec::new(); l_];
        for t in (0..l_).rev() {
            let ns = &layers[t];
            viable[t] = vec![false; ns.len()];
            tap_ok[t] = vec![false; ns.len()];
            no_ok[t] = vec![false; ns.len()];
            fw[t] = vec![0; ns.len()];
            for k in 0..ns.len() {
                let a = ns[k].tap == EXIT || (ns[k].tap >= 0 && viable[t + 1][ns[k].tap as usize]);
                let b = ns[k].no == EXIT || (ns[k].no >= 0 && viable[t + 1][ns[k].no as usize]);
                tap_ok[t][k] = a;
                no_ok[t][k] = b;
                viable[t][k] = a || b;
                // Ticks from here on (no tap in between) at which a tap still leads through.
                fw[t][k] = if a { 1 + if b && ns[k].no >= 0 { fw[t + 1][ns[k].no as usize] } else { 0 } } else { 0 };
            }
        }
        res.way = viable[0][0];
        if !res.way {
            return;
        }

        // Forward: the earlier half of each tap window, and the viable path counts (log2).
        let mut bw: Vec<Vec<i32>> = vec![Vec::new(); l_];
        let mut logn: Vec<Vec<f64>> = layers.iter().map(|ns| vec![f64::NEG_INFINITY; ns.len()]).collect();
        logn[0][0] = 0.0;
        let mut exits = f64::NEG_INFINITY;
        for t in 0..l_ {
            let ns = &layers[t];
            bw[t] = vec![0; ns.len()];
            for k in 0..ns.len() {
                if !viable[t][k] {
                    continue;
                }
                let p = ns[k].parent;
                let chain = t > 0 && p >= 0 && !ns[k].by_tap && viable[t - 1][p as usize];
                bw[t][k] = if tap_ok[t][k] { 1 + if chain { bw[t - 1][p as usize] } else { 0 } } else { 0 };
                let me = logn[t][k];
                if me == f64::NEG_INFINITY {
                    continue;
                }
                for (child, ok) in [(ns[k].tap, tap_ok[t][k]), (ns[k].no, no_ok[t][k])] {
                    if !ok {
                        continue;
                    }
                    if child == EXIT {
                        exits = lse(exits, me);
                    } else {
                        logn[t + 1][child as usize] = lse(logn[t + 1][child as usize], me);
                    }
                }
            }
        }
        res.paths_bits = exits;

        // Backward: the maximin line (widest tightest tap window).
        let mut best: Vec<Vec<i32>> = vec![Vec::new(); l_];
        let mut pick: Vec<Vec<i8>> = vec![Vec::new(); l_]; // 1 tap, 0 no tap
        for t in (0..l_).rev() {
            let ns = &layers[t];
            best[t] = vec![0; ns.len()];
            pick[t] = vec![0; ns.len()];
            for k in 0..ns.len() {
                if !viable[t][k] {
                    continue;
                }
                let mut v_tap: i32 = -1;
                let mut v_no: i32 = -1;
                if tap_ok[t][k] {
                    let w = G::mini(Self::WINDOW_CAP, (fw[t][k] + bw[t][k] - 1) as i64) as i32;
                    let after = if ns[k].tap == EXIT { i32::MAX } else { best[t + 1][ns[k].tap as usize] };
                    v_tap = w.min(after);
                }
                if no_ok[t][k] {
                    v_no = if ns[k].no == EXIT { i32::MAX } else { best[t + 1][ns[k].no as usize] };
                }
                // Ties: hold rather than tap (fewer taps).
                if v_no >= v_tap {
                    best[t][k] = v_no;
                    pick[t][k] = 0;
                } else {
                    best[t][k] = v_tap;
                    pick[t][k] = 1;
                }
            }
        }
        let mut windows: Vec<i64> = Vec::new();
        {
            let mut k: usize = 0;
            for t in 0..l_ {
                let n = layers[t][k];
                let child;
                if pick[t][k] == 1 {
                    windows.push(G::mini(Self::WINDOW_CAP, (fw[t][k] + bw[t][k] - 1) as i64));
                    child = n.tap;
                } else {
                    child = n.no;
                }
                if child == EXIT {
                    res.line_s = (t + 1) as f64 / SimConfig::TICKS_PER_SECOND as f64;
                    break;
                }
                k = usize::try_from(child).expect("the line stays on viable nodes");
            }
        }
        // The arrival tap (before the bird moves) isn't a timed tap.
        res.line_taps = windows.len() as i64;
        res.line_window = if windows.is_empty() { Self::WINDOW_CAP } else { *windows.iter().min().unwrap() };
        res.line_window_med = if windows.is_empty() {
            Self::WINDOW_CAP
        } else {
            let mut s = windows.clone();
            s.sort();
            s[windows.len() / 2]
        };
        res.line_tight = windows.iter().filter(|&&w| w <= Self::TIGHT_WINDOW).count() as i64;
        res.bits_per_s = if res.line_s > 0.0 {
            res.paths_bits / cs_max(1.0, res.first_exit as f64 / SimConfig::TICKS_PER_SECOND as f64)
        } else {
            0.0
        };

        // Bands over the measured ticks: the end of the arrival hold + SKIP_START to the first exit - SKIP_END.
        let t0 = hold + Self::SKIP_START;
        let t1 = G::maxi(t0 + 1, (if res.first_exit < 0 { l_ as i64 } else { res.first_exit }) - Self::SKIP_END);
        let mut bands: Vec<i64> = Vec::new();
        let mut fr: f64 = 0.0;
        let mut choice: i64 = 0;
        let mut tight: i64 = 0;
        let mut ys: HashSet<i16> = HashSet::new();
        let mut t = t0 as i32 as i64;
        while t < t1 && t < l_ as i64 {
            let tu = t as usize;
            ys.clear();
            let alive = layers[tu].len();
            let mut v: usize = 0;
            for k in 0..layers[tu].len() {
                if viable[tu][k] {
                    ys.insert(layers[tu][k].yb);
                    v += 1;
                }
            }
            let band = ys.len() as i64 * Self::BUCKET_H / SimConfig::SUB;
            bands.push(band);
            if band < 60 {
                tight += 1;
            }
            fr += if alive == 0 { 0.0 } else { v as f64 / alive as f64 };
            if groups(&ys) >= 2 {
                choice += 1;
            }
            if let Some(log) = log {
                if !ys.is_empty() {
                    let lo = *ys.iter().min().unwrap() as i64;
                    let hi = *ys.iter().max().unwrap() as i64;
                    log(&format!(
                        "{}\t{}\t{}\t{}\t{}\t{}-{}",
                        t,
                        alive,
                        v,
                        band,
                        groups(&ys),
                        lo * Self::BUCKET_H / SimConfig::SUB,
                        (hi + 1) * Self::BUCKET_H / SimConfig::SUB
                    ));
                }
            }
            t += 1;
        }
        if bands.is_empty() {
            bands.push(0);
        }
        bands.sort();
        res.band_min = bands[0];
        res.band_p10 = bands[bands.len() / 10];
        res.band_med = bands[bands.len() / 2];
        res.tight_s = tight as f64 / SimConfig::TICKS_PER_SECOND as f64;
        res.choice_s = choice as f64 / SimConfig::TICKS_PER_SECOND as f64;
        res.viable_frac = fr / G::maxi(1, bands.len() as i64) as f64;
    }
}

fn groups(ys: &HashSet<i16>) -> i32 {
    if ys.is_empty() {
        return 0;
    }
    let mut s: Vec<i16> = ys.iter().copied().collect();
    s.sort();
    let mut g = 1;
    let split = Tube::SPLIT_PX * SimConfig::SUB / Tube::BUCKET_H;
    for i in 1..s.len() {
        if (s[i] - s[i - 1]) as i64 > split {
            g += 1;
        }
    }
    g
}

/// C# `Math.Max(double, double)`: NaN if either is NaN.
pub fn cs_max(a: f64, b: f64) -> f64 {
    if a.is_nan() || b.is_nan() {
        f64::NAN
    } else if a > b {
        a
    } else {
        b
    }
}

/// C# `Math.Pow(2, x)`: the CRT pow, not the exp2 LLVM would make of a constant base.
fn pow2(x: f64) -> f64 {
    black_box(2.0f64).powf(x)
}

fn lse(a: f64, b: f64) -> f64 {
    if a == f64::NEG_INFINITY {
        return b;
    }
    if b == f64::NEG_INFINITY {
        return a;
    }
    let m = cs_max(a, b);
    m + (pow2(a - m) + pow2(b - m)).log2()
}
