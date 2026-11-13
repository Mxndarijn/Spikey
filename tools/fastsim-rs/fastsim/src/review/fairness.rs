//! Port of RL/Fairness.cs: `rl review fair`, is a BlindPlanner death the bot's
//! fault or the room's? (SpikeCage-coord/research/planner-review/08-fairness.md).
//! See the C# file for the judges (oracle, honest0, honestR) and the verdicts.
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::time::Instant;

use rayon::prelude::*;
use sim::prelude::*;

use super::{configure, crate_drop, culture_cmp, room_name, NL};
use crate::bots::{BlindPlanner, SurvivalSearch};
use crate::setups::Setups;
use crate::speed::Opts;
use crate::yardstick::fmt_num;

/// The room anchor a player can know: tracked from the walls it bounced off
/// and the exit it took (BlindPlanner.observe's rule), never state.anchor_y.
/// observe() once per tick, on the state before that tick's input.
/// C# `clone()` (MemberwiseClone plus a copy of `_last_drawn`) is `Clone`.
#[derive(Clone)]
pub struct AnchorTrack {
    pub anchor: i64,
    _seen_room: i64,
    _last_y: i64,
    _last_a: i64,
    _last_b: i64,
    _last_b_kind: i64,
    _last_open: bool,
    _last_drawn: [i64; 2],
}

impl AnchorTrack {
    pub fn new() -> AnchorTrack {
        AnchorTrack {
            anchor: SimConfig::BIRD_START_Y,
            _seen_room: 0,
            _last_y: 0,
            _last_a: 0,
            _last_b: 0,
            _last_b_kind: 0,
            _last_open: false,
            _last_drawn: [0; 2],
        }
    }

    fn drawn(s: &SimState, side: i64) -> i64 {
        let slots = ExitPlanner::slots(s);
        if s.exit_open && s.exit_side == side {
            return ((1i64 << SimConfig::SLOT_COUNT) - 1) & !slots;
        }
        let mut mask = if side == 0 { s.left_spikes } else { s.right_spikes };
        if s.exit_preview && s.exit_side == side {
            mask &= !slots;
        }
        mask
    }

    pub fn observe(&mut self, sim: &GameSim) {
        let s = &sim.state;
        if s.room_index != self._seen_room {
            self._seen_room = s.room_index;
            if self._last_open {
                let a = (self._last_y - self._last_a).abs() <= SimConfig::EXIT_FIT || self._last_b_kind == ExitKind::NORMAL;
                let door = if self._last_b_kind != ExitKind::NORMAL {
                    SimConfig::FORK_DOOR_Y
                } else if a {
                    self._last_a
                } else {
                    self._last_b
                };
                self.anchor = GameSim::_arrival_y(door);
            }
        } else if sim.events.contains(&Event::BOUNCE) {
            self.anchor = BlindPlanner::anchor_after(self._last_drawn[if s.vx > 0 { 0 } else { 1 }], self.anchor);
        }
        self._last_y = s.y;
        self._last_drawn[0] = Self::drawn(s, 0);
        self._last_drawn[1] = Self::drawn(s, 1);
        self._last_open = s.exit_open;
        self._last_a = s.exit_a_y;
        self._last_b = s.exit_b_y;
        self._last_b_kind = s.exit_b_kind;
    }
}

/// Off (--judgeanchor 0): honest copies keep the room's real anchor_y (the
/// judge before this fix). C# `static bool own_anchor`.
pub static OWN_ANCHOR: AtomicBool = AtomicBool::new(true);

fn own_anchor() -> bool {
    OWN_ANCHOR.load(Ordering::Relaxed)
}

pub struct Judge {
    pub react: i64,
    pub stage0: i64,
    pub viable: i64,
    pub tail: i64,
    pub gap: i64,
    pub k: i32,
    pub cands: i32,
    pub budget: i32,
    pub bpx: i64,
    pub speeds: i64,
    pub stages_used: i64,
    pub ran_out: bool,

    _end: i64,
    _salt: i64,
    _left: i32,
    /// C# `_hist` past the caller's prefix: true states of ticks `_base + _pre + i`
    /// (C# copies the prefix list; here `hist[.._pre]` is read in place).
    _extra: Vec<GameSim>,
    _pre: usize,
    /// C# `_trk` (the known anchor after observing `_hist[i]`) past the prefix, as `_extra`.
    _trk_extra: Vec<AnchorTrack>,
    _taps: Vec<bool>,
    _base: i64,
}

struct Node {
    w: Vec<GameSim>,
    parent: i32,
    tap: u8,
    since: i64,
}

fn quick(max_level: i64, sim: &GameSim, ticks: i64) -> bool {
    let mut s = SurvivalSearch::new();
    s.max_level = max_level;
    s.run_quick(sim, ticks)
}

impl Judge {
    pub fn new() -> Judge {
        Judge {
            react: 60,
            stage0: 15,
            viable: 60,
            tail: 40,
            gap: 6,
            k: 6,
            cands: 6,
            budget: 24,
            bpx: 6,
            speeds: 6,
            stages_used: 0,
            ran_out: false,
            _end: 0,
            _salt: 0,
            _left: 0,
            _extra: Vec::new(),
            _pre: 0,
            _trk_extra: Vec::new(),
            _taps: Vec::new(),
            _base: 0,
        }
    }

    /// `hist`: true states of ticks base..start (inclusive) along the bot's run, `taps` its inputs
    /// for base..start-1. Whether a line from `start` lives to `end` (+ viability).
    #[allow(clippy::too_many_arguments)]
    pub fn honest(
        &mut self,
        hist: &[GameSim],
        trk: &[AnchorTrack],
        taps: &[bool],
        base_tick: i64,
        start: i64,
        end: i64,
        salt: i64,
        delayed: bool,
    ) -> bool {
        self._pre = ((start - base_tick + 1) as usize).min(hist.len());
        self._extra.clear();
        self._trk_extra.clear();
        self._taps = taps.iter().take((start - base_tick) as usize).copied().collect();
        self._base = base_tick;
        self._end = end;
        self._salt = salt;
        self._left = self.budget;
        self.ran_out = false;
        self.stages_used = 0;
        self.stage(hist, trk, start, delayed)
    }

    fn at<'a>(&'a self, hist: &'a [GameSim], tick: i64) -> &'a GameSim {
        let i = (tick - self._base) as usize;
        if i < self._pre {
            &hist[i]
        } else {
            &self._extra[i - self._pre]
        }
    }

    fn hist_count(&self) -> usize {
        self._pre + self._extra.len()
    }

    fn trk_at<'a>(&'a self, trk: &'a [AnchorTrack], tick: i64) -> &'a AnchorTrack {
        let i = (tick - self._base) as usize;
        if i < self._pre {
            &trk[i]
        } else {
            &self._trk_extra[i - self._pre]
        }
    }

    /// C# `_trk[^1]`.
    fn trk_last<'a>(&'a self, trk: &'a [AnchorTrack]) -> &'a AnchorTrack {
        match self._trk_extra.last() {
            Some(t) => t,
            None => &trk[self._pre - 1],
        }
    }

    fn known_anchor(&self, trk: &[AnchorTrack], tick: i64) -> i64 {
        if own_anchor() {
            self.trk_at(trk, tick).anchor
        } else {
            -1
        }
    }

    fn stage(&mut self, hist: &[GameSim], trk: &[AnchorTrack], s: i64, delayed: bool) -> bool {
        if s >= self._end {
            return quick(0, self.at(hist, s), self.viable);
        }
        let left = self._left;
        self._left -= 1;
        if left <= 0 {
            self.ran_out = true;
            return false;
        }
        self.stages_used += 1;
        let len = (if delayed { self.react } else { self.stage0 }).min(self._end - s);
        let info = if delayed { self._base.max(s - self.react) } else { s };
        let mut worlds = vec![self.at(hist, s).clone_deep()];
        for j in 0..self.k {
            let mut c = BlindPlanner::blind_copy(
                self.at(hist, info),
                SimRng::new(self._salt.wrapping_mul(7919).wrapping_add(s.wrapping_mul(131)) + j as i64 + 1),
                -1,
                0,
                self.known_anchor(trk, info),
                false,
                false,
            );
            let mut t = info;
            while t < s && !c.is_over() {
                c.step(self._taps[(t - self._base) as usize]);
                t += 1;
            }
            // A copy in which the bird would already be dead is not what the player sees.
            if !c.is_over() {
                worlds.push(c);
            }
        }
        let room_anchor = if own_anchor() { self.trk_at(trk, s).anchor } else { self.at(hist, s).state.anchor_y };
        let found = self.beam(worlds, len, room_anchor);
        for (line, ends) in found {
            let mut ok = true;
            let mut i = 0;
            while i < ends.len() && ok {
                if !quick(0, &ends[i], self.viable) {
                    ok = false;
                }
                i += 1;
            }
            if !ok {
                continue;
            }
            // Fly the line in the true world, keeping its states for the next stage's copies.
            let keep_h = self.hist_count();
            let keep_t = self._taps.len();
            let keep_k = self._pre + self._trk_extra.len();
            let mut cur = self.at(hist, s).clone_deep();
            for &b in &line {
                cur.step(b != 0);
                self._taps.push(b != 0);
                self._extra.push(cur.clone_deep());
                let mut tr = self.trk_last(trk).clone();
                tr.observe(&cur);
                self._trk_extra.push(tr);
            }
            if !cur.is_over() && self.stage(hist, trk, s + line.len() as i64, delayed) {
                return true;
            }
            self._extra.truncate(keep_h - self._pre);
            self._taps.truncate(keep_t);
            self._trk_extra.truncate(keep_k - self._pre);
            if self.ran_out {
                return false;
            }
        }
        false
    }

    /// Lines (common inputs) that live `ticks` in every world: up to `cands`, one per 40 px band of
    /// the true world's end height, nearest the room's anchor first. Each with its end states.
    fn beam(&self, roots: Vec<GameSim>, ticks: i64, room_anchor: i64) -> Vec<(Vec<u8>, Vec<GameSim>)> {
        let (r_open, r_preview, r_a_y, r_anchor) =
            (roots[0].state.exit_open, roots[0].state.exit_preview, roots[0].state.exit_a_y, room_anchor);
        let mut parents: Vec<i32> = Vec::new();
        let mut taps: Vec<u8> = Vec::new();
        let mut frontier = vec![Node { w: roots, parent: -1, tap: 0, since: 99 }];
        let mut slots: HashSet<i64> = HashSet::new();
        let mut next: Vec<Node> = Vec::new();
        let bh = self.bpx * SimConfig::SUB;
        let bvy = -SimConfig::FLAP_VY * 2 / self.speeds;
        for _t in 0..ticks {
            slots.clear();
            next.clear();
            for e in &frontier {
                let can_tap = e.since >= self.gap;
                let mut a: i32 = if can_tap { 1 } else { 0 };
                while a >= 0 {
                    let mut ws: Vec<GameSim> = Vec::with_capacity(e.w.len());
                    let mut dead = false;
                    let mut key: i64 = if a == 1 { 1 } else { (e.since + 1).min(self.gap) };
                    let mut i = 0;
                    while i < e.w.len() && !dead {
                        let mut s = e.w[i].clone_deep();
                        s.step(a == 1);
                        if s.is_over() {
                            dead = true;
                        }
                        let st = &s.state;
                        let along = st.vy * s.room.gravity - SimConfig::FLAP_VY;
                        let sp = G::clampi(along / bvy, 0, self.speeds - 1);
                        key = key
                            .wrapping_mul(1000003)
                            .wrapping_add((st.room_index * 1000 + st.y / bh) * self.speeds + sp);
                        ws.push(s);
                        i += 1;
                    }
                    if !dead {
                        if slots.insert(key) {
                            next.push(Node {
                                w: ws,
                                parent: e.parent,
                                tap: a as u8,
                                since: if a == 1 { 1 } else { e.since + 1 },
                            });
                        }
                    }
                    a -= 1;
                }
            }
            if next.is_empty() {
                return Vec::new();
            }
            frontier = Vec::with_capacity(next.len());
            for e in next.drain(..) {
                parents.push(e.parent);
                taps.push(e.tap);
                frontier.push(Node { w: e.w, parent: parents.len() as i32 - 1, tap: 0, since: e.since });
            }
        }
        let anchor = if r_open || r_preview { r_a_y } else { r_anchor };
        // C# Dictionary<long, Node>: values in insertion order.
        let mut seen: HashSet<i64> = HashSet::new();
        let mut best: Vec<Node> = Vec::new();
        for e in frontier {
            let band = e.w[0].state.y / (40 * SimConfig::SUB);
            if seen.insert(band) {
                best.push(e);
            }
        }
        best.sort_by_key(|e| (e.w[0].state.y - anchor).abs());
        let mut res = Vec::new();
        for e in best.into_iter().take(self.cands.max(0) as usize) {
            let mut out_: Vec<u8> = Vec::new();
            let mut nd = e.parent;
            while nd >= 0 {
                out_.push(taps[nd as usize]);
                nd = parents[nd as usize];
            }
            out_.reverse();
            res.push((out_, e.w));
        }
        res
    }
}

/// Ticks until the bird, flying on (x does not depend on taps), first overlaps column `c`'s
/// crate in x (its kill range: crate edges +- the bird radius). 999 = not within 400 ticks.
pub fn crate_entry(sim: &GameSim, cd: &CrateDrop, c: i64) -> i64 {
    let r = SimConfig::BIRD_RADIUS;
    let lo = cd.col_left(c) - r;
    let hi = cd.col_left(c) + cd.crate_w + r;
    let (mut x, mut vx) = (sim.state.x, sim.state.vx);
    let (left, right) = (sim.room.wall_left(), sim.room.wall_right());
    for t in 0..400 {
        if x >= lo && x <= hi {
            return t;
        }
        x += vx;
        if vx > 0 && x + r >= right {
            x = 2 * (right - r) - x;
            vx = -vx;
        } else if vx < 0 && x - r <= left {
            x = 2 * (left + r) - x;
            vx = -vx;
        }
    }
    999
}

#[allow(dead_code)]
pub struct Death {
    pub seed: i64,
    pub score: i64,
    pub tick: i64,
    pub room: String,
    pub cause: String,
    pub verdict: String,
    pub oracle: i64,
    pub honest0: i64,
    pub honest_r: i64,
    pub undecided: bool,
    pub since_bounce: i64,
    pub since_entry: i64,
    pub x: i64,
    pub y: i64,
    pub crate_shown: i64,
    pub crate_e: i64,
    pub secs: f64,
}

/// One seed's share of C#'s concurrent collections (merged in seed order).
struct SeedOut {
    cfg: String,
    rooms: Vec<(String, i64)>,
    marks: Vec<(String, i64)>,
    points: i64,
    alive: bool,
    death: Option<Death>,
}

fn add(v: &mut Vec<(String, i64)>, k: String) {
    match v.iter_mut().find(|e| e.0 == k) {
        Some(e) => e.1 += 1,
        None => v.push((k, 1)),
    }
}

fn last(step: i64, back: i64, died: i64, base_tick: i64, saves: &mut dyn FnMut(i64) -> bool) -> i64 {
    let mut b = step;
    while b <= back && died - b >= base_tick {
        if saves(b) {
            return b;
        }
        b += step;
    }
    -1
}

pub fn run(opts: &Opts, seeds: i32, cap: i64) -> i32 {
    let l = |key: &str, d: i64| -> i64 { opts.get(key).map(|v| v.parse().expect(key)).unwrap_or(d) };
    let (first, back, step) = (l("first", 0), l("back", 240), l("step", 10));
    let out_path = opts.get("out").cloned().unwrap_or_default();
    OWN_ANCHOR.store(l("judgeanchor", 1) != 0, Ordering::Relaxed);
    // --room id [--variant v]: each run starts in that room (a practice
    // start) and ends when the bird leaves it: deaths per visit, room by room.
    let only = opts.get("room").cloned().unwrap_or_default();
    let only_v = opts.get("variant").cloned().unwrap_or_else(|| "classic".to_string());
    // --boss 0|1|2 --score N: each run starts in that boss room (Watcher,
    // Crusher, Saw King) out of the boss portal at score N, as in a real run.
    let (boss, boss_score) = (l("boss", -1), l("score", SimConfig::BOSS_EVERY));
    let room_score = l("roomscore", 0);
    let start = |seed: i64| -> GameSim {
        if boss >= 0 {
            let mut g = GameSim::new(seed);
            g.state.started = true;
            g.state.score = boss_score;
            g.state.bosses_met = ((1i64 << RoomCatalog::bosses().len()) - 1) & !(1i64 << boss);
            g._go_through(1, ExitKind::NORMAL, 320 * SimConfig::SUB);
            return g;
        }
        if only.is_empty() {
            GameSim::new(seed)
        } else {
            let mut g = Setups::practice(&only, seed, &only_v);
            // --roomscore N: the practice room's walls drawn as at score N (dense walls).
            if room_score > 0 {
                g.state.score = room_score;
                g.room.entry_score = room_score;
            }
            g
        }
    };
    let make = || {
        let mut j = Judge::new();
        j.react = l("react", 60);
        j.stage0 = l("stage0", 15);
        j.viable = l("viable", 60);
        j.tail = l("tail", 40);
        j.gap = l("gap", 6);
        j.k = l("k", 6) as i32;
        j.cands = l("cands", 6) as i32;
        j.budget = l("budget", 24) as i32;
        j
    };
    let clock = Instant::now();
    let done = AtomicUsize::new(0);
    let outs: Vec<SeedOut> = (0..seeds as i64)
        .into_par_iter()
        .map(|i| {
            let t0 = Instant::now();
            let seed = first + i + 1;
            let mut sim = start(seed);
            let room0 = sim.state.room_index;
            let mut bot = BlindPlanner::new(seed);
            let cfg = configure(&mut bot, opts);
            let mut rooms: Vec<(String, i64)> = Vec::new();
            let mut marks: Vec<(String, i64)> = Vec::new();
            let mut taps: Vec<bool> = Vec::new();
            let (mut bounce_tick, mut entry_tick, mut drops, mut drop_tick) = (0i64, 0i64, -1i64, 0i64);
            let (mut ri0, mut last_e) = (-1i64, -1i64);
            while !sim.is_over()
                && (taps.len() as i64) < cap
                && (only.is_empty() && boss < 0 || sim.state.room_index == room0)
            {
                if sim.state.room_index != ri0 {
                    ri0 = sim.state.room_index;
                    add(&mut rooms, room_name(&sim));
                }
                let tap = bot.decide(&sim);
                taps.push(tap);
                let (vx, ri) = (sim.state.vx, sim.state.room_index);
                sim.step(tap);
                if sim.state.vx != vx {
                    bounce_tick = taps.len() as i64;
                }
                if sim.state.room_index != ri {
                    entry_tick = taps.len() as i64;
                }
                let cd = crate_drop(&sim);
                let dn = cd.map(|c| c.drops).unwrap_or(-1);
                if dn != drops {
                    drops = dn;
                    drop_tick = taps.len() as i64;
                    if let Some(cd) = cd {
                        if cd.col >= 0 {
                            for cc in [cd.col, cd.col_b] {
                                if cc < 0 {
                                    continue;
                                }
                                let e = crate_entry(&sim, cd, cc);
                                last_e = e;
                                let outer = cc == 0 || cc == cd.cols - 1;
                                let v = room_name(&sim);
                                add(
                                    &mut marks,
                                    format!("{}\t{}\t{}", v, if outer { "outer" } else { "inner" }, e.min(200) / 5 * 5),
                                );
                            }
                        }
                    }
                }
            }
            let points = sim.state.score;
            if !sim.is_over() {
                let n = done.fetch_add(1, Ordering::Relaxed) + 1;
                eprintln!("[{n}/{seeds}] seed {seed} alive at {}", sim.state.score);
                return SeedOut { cfg, rooms, marks, points, alive: true, death: None };
            }
            let died = taps.len() as i64;
            let room = room_name(&sim);
            let cause = DeathCause::NAMES[sim.state.death_cause as usize].to_string();
            let shown = if crate_drop(&sim).is_some() { died - drop_tick } else { -1 };
            // True states of the last back + react + 1 ticks before the death.
            let lead = back + l("react", 60) + 1;
            let base_tick = 0.max(died - lead);
            let mut c = start(seed);
            let mut track = AnchorTrack::new();
            for t in 0..base_tick {
                track.observe(&c);
                c.step(taps[t as usize]);
            }
            let mut hist: Vec<GameSim> = Vec::new();
            let mut trk: Vec<AnchorTrack> = Vec::new();
            for t in base_tick..=died {
                track.observe(&c);
                hist.push(c.clone_deep());
                trk.push(track.clone());
                if t < died {
                    c.step(taps[t as usize]);
                }
            }
            let end = died + l("tail", 40);
            let mut judge = make();
            let mut undecided = false;
            let (jt, jv) = (judge.tail, judge.viable);
            let oracle = last(step, back, died, base_tick, &mut |b| {
                SurvivalSearch::new().run_quick(&hist[(died - b - base_tick) as usize], b + jt + jv)
            });
            let rel: Vec<bool> = taps[base_tick as usize..].to_vec();
            let mut honest_r = -1;
            let mut honest0 = -1;
            if oracle >= 0 {
                honest_r = last(step, back, died, base_tick, &mut |b| {
                    let ok = judge.honest(&hist, &trk, &rel, base_tick, died - b, end, seed, true);
                    undecided |= judge.ran_out;
                    ok
                });
                if honest_r < 0 {
                    honest0 = last(step, back, died, base_tick, &mut |b| {
                        judge.honest(&hist, &trk, &rel, base_tick, died - b, end, seed, false)
                    });
                } else {
                    honest0 = honest_r;
                }
            }
            let verdict = if honest_r >= 0 {
                "bot"
            } else if honest0 >= 0 {
                "reaction"
            } else if oracle >= 0 {
                "hidden"
            } else {
                "lost"
            };
            let secs = t0.elapsed().as_secs_f64();
            let n = done.fetch_add(1, Ordering::Relaxed) + 1;
            eprintln!(
                "[{n}/{seeds}] seed {seed} {room} {cause} {verdict} o{oracle} h0 {honest0} hR {honest_r}{} {}s",
                if undecided { " (budget)" } else { "" },
                fmt_num(secs, "F0")
            );
            let death = Death {
                seed,
                score: sim.state.score,
                tick: died,
                room,
                cause,
                verdict: verdict.to_string(),
                oracle,
                honest0,
                honest_r,
                undecided,
                since_bounce: died - bounce_tick,
                since_entry: died - entry_tick,
                x: sim.state.x / SimConfig::SUB,
                y: sim.state.y / SimConfig::SUB,
                crate_shown: shown,
                crate_e: if shown >= 0 { last_e } else { -1 },
                secs,
            };
            SeedOut { cfg, rooms, marks, points, alive: false, death: Some(death) }
        })
        .collect();
    let setup = outs.first().map(|o| o.cfg.clone()).unwrap_or_default();
    let points: i64 = outs.iter().map(|o| o.points).sum();
    let alive = outs.iter().filter(|o| o.alive).count();
    let mut rooms: HashMap<String, i64> = HashMap::new();
    let mut marks: HashMap<String, i64> = HashMap::new();
    let mut ds: Vec<&Death> = Vec::new();
    for o in &outs {
        for (k, v) in &o.rooms {
            *rooms.entry(k.clone()).or_insert(0) += v;
        }
        for (k, v) in &o.marks {
            *marks.entry(k.clone()).or_insert(0) += v;
        }
        if let Some(d) = &o.death {
            ds.push(d);
        }
    }
    ds.sort_by_key(|d| d.seed);
    let j = make();
    let mut sb = String::new();
    let mut line = |s: String| {
        sb.push_str(&s);
        sb.push_str(NL);
    };
    line(format!(
        "fairness of BlindPlanner deaths [{setup}], seeds {}..{}, cap {cap}, gameplay {}",
        first + 1,
        first + seeds as i64,
        SimConfig::GAMEPLAY_VERSION
    ));
    line(format!(
        "judges: back {back} step {step}, react {}, stage0 {}, copies {}, cands {}, budget {}, viable {}, tail {}, tap gap {}",
        j.react, j.stage0, j.k, j.cands, j.budget, j.viable, j.tail, j.gap
    ));
    line(format!(
        "{} deaths in {points} points = {} per 100; {alive} of {seeds} alive at the cap; {} s",
        ds.len(),
        fmt_num(100.0 * ds.len() as f64 / points.max(1) as f64, "F3"),
        fmt_num(clock.elapsed().as_secs_f64(), "F0")
    ));
    // GroupBy (first-seen order) then a stable OrderByDescending(count).
    let mut verdicts: Vec<(String, usize)> = Vec::new();
    for d in &ds {
        match verdicts.iter_mut().find(|g| g.0 == d.verdict) {
            Some(g) => g.1 += 1,
            None => verdicts.push((d.verdict.clone(), 1)),
        }
    }
    verdicts.sort_by(|a, b| b.1.cmp(&a.1));
    line(format!(
        "verdicts: {}",
        verdicts.iter().map(|(k, n)| format!("{k} {n}")).collect::<Vec<_>>().join(", ")
    ));
    line("rooms\tvariant\tentered\tdeaths\tbot\treaction\thidden\tlost".to_string());
    let mut rs: Vec<(&String, &i64)> = rooms.iter().collect();
    let dcount = |k: &str| ds.iter().filter(|d| d.room == k).count();
    rs.sort_by(|a, b| dcount(b.0).cmp(&dcount(a.0)).then_with(|| culture_cmp(a.0, b.0)));
    for (k, v) in rs {
        let g: Vec<&&Death> = ds.iter().filter(|d| &d.room == k).collect();
        let n = |v: &str| g.iter().filter(|d| d.verdict == v).count();
        line(format!(
            "room\t{k}\t{v}\t{}\t{}\t{}\t{}\t{}",
            g.len(),
            n("bot"),
            n("reaction"),
            n("hidden"),
            n("lost")
        ));
    }
    line(
        "seed\tscore\ttick\troom\tcause\tverdict\toracle\thonest0\thonestR\tundecided\tsince_bounce\tsince_entry\tx\ty\tcrate_shown\tsecs"
            .to_string(),
    );
    for d in &ds {
        line(format!(
            "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
            d.seed,
            d.score,
            d.tick,
            d.room,
            d.cause,
            d.verdict,
            d.oracle,
            d.honest0,
            d.honest_r,
            if d.undecided { 1 } else { 0 },
            d.since_bounce,
            d.since_entry,
            d.x,
            d.y,
            d.crate_shown,
            fmt_num(d.secs, "F0")
        ));
    }
    line("crate marks: variant, column, ticks from the mark until the bird enters the column's kill range (5-tick bins), count".to_string());
    let mut ms: Vec<(&String, &i64)> = marks.iter().collect();
    ms.sort_by(|a, b| culture_cmp(a.0, b.0));
    for (k, v) in ms {
        line(format!("mark\t{k}\t{v}"));
    }
    if !out_path.is_empty() {
        std::fs::write(&out_path, &sb).expect("--out");
    }
    print!("{sb}");
    0
}
