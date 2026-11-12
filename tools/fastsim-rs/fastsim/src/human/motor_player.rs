//! Port of Human/MotorPlayer.cs: a human motor model (Isaksen et al. 2015,
//! measured on one-button flyers) on top of a planner that only predicts
//! visible motion (BlindPlanner, scrambled copies). docs/HUMAN_BOT.md.
//!
//! Hazard identity. C# keeps `HashSet<Hazard>` / `Dictionary<Hazard, long>`
//! keyed by object reference. Here a hazard is `(objects, index)`: its index in
//! `sim.room.hazards` (hazards are never removed or reordered in a room, and an
//! added one gets a new index) plus `_objects`, a counter bumped whenever C#
//! would hand the bot a whole new set of hazard objects:
//! - a room change (`room_index` changes): RoomRuntime.start clears the list
//!   and makes new hazards (`_enter_room` always follows `room_index += 1`);
//! - a revive (`state.revives` changes): the room is a clone of the entry room,
//!   so every hazard is a new object while `room_index` stays the same. As in
//!   C#, the old keys stay in `_known` / `_hidden` (they never match again, but
//!   a stale `_hidden` entry still counts until its time is up, which keeps the
//!   masked view on, exactly like the C# dictionary of dead objects);
//! - the caller swapping the sim for a copy (Yardstick/Leak.fork:
//!   `sa = sa.clone_deep()`): the state cannot show it, so the caller says so
//!   with `sims_swapped()` (thread-local: a fork runs on one thread).
use crate::bots::boss_blind::BossBlind;
use std::cell::Cell;
use std::collections::{HashMap, HashSet};
use std::fmt;
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::OnceLock;

use sim::prelude::*;
use sim::rooms::hazard::WARN_SIZE;

use crate::bots::blind_planner::{BlindPlanner, KNOW_EXITS};
use crate::dotnet_random::DotnetRandom;
use crate::human::fmt_f;

thread_local! {
    static SIM_SWAPS: Cell<u64> = const { Cell::new(0) };
}

/// Call right after a caller replaces the sim it feeds a MotorPlayer with a copy
/// (C# would give the player new hazard objects: all of them look new).
pub fn sims_swapped() {
    SIM_SWAPS.with(|c| c.set(c.get() + 1));
}

fn sim_swaps() -> u64 {
    SIM_SWAPS.with(|c| c.get())
}

/// C# record Motor.
#[derive(Clone, Copy, Debug)]
pub struct Motor {
    /// sd of each tap's timing error, ticks (early and late). The main skill knob.
    pub sigma: f64,
    /// reaction to newly appearing things, ex-Gaussian: normal part mean (ticks)
    pub react_mu: f64,
    ///   ... and its sd
    pub react_sd: f64,
    ///   ... plus an exponential tail with this mean
    pub react_tau: f64,
    /// ticks between two presses at least (7.7 taps per second -> 8)
    pub min_gap: i64,
    /// a planned tap can still be held back until this many ticks before it lands
    pub cancel: i64,
    /// a finer search (4 px x 12 speed buckets, ~3.6x slower): more careful thinking (C# default false)
    pub fine: bool,
    /// the human habits on top (preferred height, hesitation, thumb gap jitter); None = none
    pub p: Option<Persona>,
    /// search fineness (MotorTiers::LEVELS; -1 = by `fine`)
    pub level: i32,
}

/// C# record Persona: the human habits on top of the thumb (the user's ruling,
/// 2026-11-12: human behaviour, not human timing; no lapses and no mistakes on
/// purpose). All off by default.
#[derive(Clone, Copy, Debug, Default)]
pub struct Persona {
    /// preferred height: offset (px) of the height the player drifts to, drawn per run
    pub pref_sd: f64,
    /// chance a press hesitates: lands an extra exponential delay late
    pub hes_p: f64,
    ///   ... with this mean (ticks)
    pub hes_tau: f64,
    /// the thumb's fastest repeat varies: each next press needs min_gap + |N(0, this)| ticks
    pub gap_sd: f64,
}

impl Motor {
    pub fn new(sigma: f64, react_mu: f64, react_sd: f64, react_tau: f64, min_gap: i64, cancel: i64, fine: bool) -> Motor {
        Motor { sigma, react_mu, react_sd, react_tau, min_gap, cancel, fine, p: None, level: -1 }
    }

    /// Isaksen: reaction about 288 ms (17 ticks) to new things, at most 7.7 taps/s.
    pub fn at(sigma: f64) -> Motor {
        Motor::new(sigma, 13.0, 2.0, 4.0, 8, 5, false)
    }
}

impl fmt::Display for Motor {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "tap sd {} t, react {} t, gap {} t",
            fmt_f(self.sigma, 2),
            fmt_f(self.react_mu + self.react_tau, 0),
            self.min_gap
        )
    }
}

/// Experiments: which new things get a reaction time (spikes, hazards).
pub static MASK_SPIKES: AtomicBool = AtomicBool::new(true);
pub static MASK_HAZARDS: AtomicBool = AtomicBool::new(true);
/// Boss tells get the same reaction time as new hazards (07-bosses.md); off = the planner sees them at once.
pub static REACT_BOSS: AtomicBool = AtomicBool::new(true);
/// A new warning (Hazard.warnings) that breaks the plan in hand takes a reaction time.
pub static MASK_TELLS: AtomicBool = AtomicBool::new(true);
/// Plan reuse for every tier's planner (BlindPlanner.follow; 0 = a new look every 4 ticks).
pub static FOLLOW: AtomicI32 = AtomicI32::new(48);

/// A warning as the player tells it apart: (hazard index, its box).
type WarnKey = (usize, i64, i64, i64, i64);

/// A hazard as C# would tell it apart: (object set, index in room.hazards).
type HzKey = (u64, usize);

/// Plays like a person: the planner decides where taps should go; the thumb
/// lands each one N(0, sigma) ticks off (committed a little ahead, so early
/// taps happen too), never two presses closer than `min_gap`, and anything
/// that newly appears (the spikes put up at a bounce, a new hazard) is hidden
/// from the planner until a reaction time has passed.
pub struct MotorPlayer {
    pub planner: BlindPlanner,
    _m: Motor,
    _rng: DotnetRandom,
    /// committed presses: intended tick, landing tick
    _taps: Vec<(i64, i64)>,
    /// intended ticks of presses already made (the plan may still show them)
    _done: Vec<i64>,
    _known: HashSet<HzKey>,
    _hidden: HashMap<HzKey, i64>,
    _spikes_hidden_until: i64,
    _score: i64,
    _room: i64,
    _last_fire: i64,
    _window: i64,
    _boss_key: i64,
    _boss_hidden_until: i64,
    pub masked_ticks: i64,
    pub presses: i64,
    pub cancels: i64,
    pub delayed: i64,
    /// Debug: a line per tick (set by `human motortrace`). C# Action<string>; here the lines are kept.
    pub log: Option<Vec<String>>,
    // Hazard identity (see the top comment): the current object set and what it was seen with.
    _objects: u64,
    _objects_room: i64,
    _objects_revives: i64,
    _objects_swaps: u64,
    // Persona state.
    _p: Persona,
    _gap_need: i64,
    pub hesitations: i64,
    /// Every press made: (intended tick, landing tick) - the realised motor error.
    pub made: Vec<(i64, i64)>,
    /// The warnings on screen last tick, and the tick a new one has been taken in.
    _warned: HashSet<WarnKey>,
    _warned_now: HashSet<WarnKey>,
    _warn_buf: Vec<i64>,
    _tell_until: i64,
    pub tell_reactions: i64,
    pub tell_ticks: i64,
}

impl MotorPlayer {
    /// C# `new MotorPlayer(m, seed, planner = null)`.
    pub fn new(m: Motor, seed: i64, planner: Option<BlindPlanner>) -> MotorPlayer {
        let rng_seed = (seed.wrapping_mul(2246822519) as i32) ^ 0x3c6ef372;
        let planner = planner.unwrap_or_else(|| MotorPlayer::make_planner(seed, &m));
        let mut mp = MotorPlayer {
            planner,
            _m: m,
            _rng: DotnetRandom::new(rng_seed),
            _taps: Vec::new(),
            _done: Vec::new(),
            _known: HashSet::new(),
            _hidden: HashMap::new(),
            _spikes_hidden_until: -1,
            _score: -1,
            _room: -1,
            _last_fire: -100,
            _window: 1i64.max((2.5 * m.sigma).ceil() as i64),
            _boss_key: 0,
            _boss_hidden_until: -1,
            masked_ticks: 0,
            presses: 0,
            cancels: 0,
            delayed: 0,
            log: None,
            _objects: 0,
            _objects_room: i64::MIN,
            _objects_revives: i64::MIN,
            _objects_swaps: sim_swaps(),
            _p: m.p.unwrap_or_default(),
            _gap_need: -1,
            hesitations: 0,
            made: Vec::new(),
            _warned: HashSet::new(),
            _warned_now: HashSet::new(),
            _warn_buf: Vec::new(),
            _tell_until: -1,
            tell_reactions: 0,
            tell_ticks: 0,
        };
        if mp._p.pref_sd > 0.0 {
            mp.planner.mid_offset = (mp.gauss() * mp._p.pref_sd).round_ties_even() as i64;
        }
        mp
    }

    /// The planner a person with tap sd `sigma` plays with: it keeps its line
    /// clear of spikes, ceiling and floor too (a narrow gap costs more than a
    /// detour), and tries its lines with taps `wobble` ticks early and late.
    pub fn make_planner(seed: i64, m: &Motor) -> BlindPlanner {
        let mut bp = BlindPlanner::new(seed);
        if m.sigma > 0.0 {
            bp.lines = 8;
            bp.wobble = 1i32.max(m.sigma.round_ties_even() as i32);
        }
        if m.fine {
            bp.bucket_px = 4;
            bp.speed_buckets = 12;
        }
        if m.level >= 0 {
            let (px, speeds, tap_free) = MotorTiers::LEVELS[m.level as usize];
            bp.bucket_px = px;
            bp.speed_buckets = speeds;
            bp.tap_free = tap_free;
        }
        bp.follow = FOLLOW.load(Ordering::Relaxed);
        bp
    }

    fn gauss(&mut self) -> f64 {
        let u = 1.0 - self._rng.next_double();
        let v = self._rng.next_double();
        (-2.0 * u.ln()).sqrt() * (2.0 * std::f64::consts::PI * v).cos()
    }

    fn reaction(&mut self) -> i64 {
        let m = self._m;
        let r = m.react_mu + m.react_sd * self.gauss() - m.react_tau * (1.0 - self._rng.next_double()).ln();
        1i64.max(r.round_ties_even() as i64)
    }

    pub fn decide(&mut self, sim: &GameSim) -> bool {
        let r = self.decide_inner(sim);
        if self.log.is_some() && sim.state.started {
            let ps: String = self.planner.plan().iter().take(30).map(|&b| if b { '|' } else { '.' }).collect();
            let committed: Vec<String> = self._taps.iter().map(|x| format!("{}->{}", x.0, x.1)).collect();
            let line = format!(
                "t {} y {} vy {} look {} press {} committed [{}] plan {}",
                sim.state.tick,
                sim.state.y / SimConfig::SUB,
                sim.state.vy,
                self.planner.last_look,
                if r { 1 } else { 0 },
                committed.join(" "),
                ps
            );
            if let Some(log) = self.log.as_mut() {
                log.push(line);
            }
        }
        r
    }

    /// Bumps `_objects` whenever C# would now see new hazard objects (top comment).
    fn track_objects(&mut self, sim: &GameSim) {
        let s = &sim.state;
        let swaps = sim_swaps();
        if s.room_index != self._objects_room || s.revives != self._objects_revives || swaps != self._objects_swaps {
            if self._objects_room != i64::MIN {
                self._objects += 1;
            }
            self._objects_room = s.room_index;
            self._objects_revives = s.revives;
            self._objects_swaps = swaps;
        }
    }

    fn decide_inner(&mut self, sim: &GameSim) -> bool {
        self.track_objects(sim);
        let s = &sim.state;
        if !s.started {
            self._score = s.score;
            self._room = s.room_index;
            for i in 0..sim.room.hazards.len() {
                self._known.insert((self._objects, i));
            }
            return true;
        }
        let t = s.tick;
        self.notice(sim, t);
        let masked_view;
        let view: &GameSim = if t < self._spikes_hidden_until || !self._hidden.is_empty() {
            masked_view = self.masked(sim, t);
            self.masked_ticks += 1;
            &masked_view
        } else {
            sim
        };
        self.planner.boss_unseen = t < self._boss_hidden_until;
        // Reacting to a tell: the old plan is played on while it lasts (never an empty thumb).
        let reacting = t < self._tell_until && !self.planner.plan().is_empty();
        if reacting {
            self.tell_ticks += 1;
        }
        self.planner.frozen = reacting;
        self.planner.min_gap = if self._m.min_gap > 1 { self._m.min_gap } else { 0 };
        self.planner.last_press = self._last_fire;
        let now = self.planner.decide(view);
        // Where the planner wants taps from now to `_window` ticks on.
        let mut want: Vec<i64> = Vec::new();
        if now {
            want.push(t);
        }
        if self._window > 0 {
            let mut u = t + 1;
            for &b in self.planner.plan().iter() {
                if u > t + self._window {
                    break;
                }
                if b {
                    want.push(u);
                }
                u += 1;
            }
        }
        // Hold back presses the plan dropped, while there is still time.
        let mut i = self._taps.len() as i64 - 1;
        while i >= 0 {
            let (w, f) = self._taps[i as usize];
            if w <= t + self._window && f - t > self._m.cancel && !want.iter().any(|&x| (x - w).abs() <= 4) {
                self._taps.remove(i as usize);
                self.cancels += 1;
            }
            i -= 1;
        }
        // Commit new presses (each one lands with its own timing error).
        for &w in &want {
            if self._taps.iter().any(|x| (x.0 - w).abs() <= 4) || self._done.iter().any(|&d| (d - w).abs() <= 4) {
                continue;
            }
            let mut e = self.gauss() * self._m.sigma;
            if self._p.hes_p > 0.0 && self._rng.next_double() < self._p.hes_p {
                e -= self._p.hes_tau * (1.0 - self._rng.next_double()).ln();
                self.hesitations += 1;
            }
            let f = w + e.round_ties_even() as i64;
            self._taps.push((w, f.max(t)));
        }
        // Press now?
        let mut due: i64 = -1;
        for i in 0..self._taps.len() {
            if self._taps[i].1 <= t && (due < 0 || self._taps[i].1 < self._taps[due as usize].1) {
                due = i as i64;
            }
        }
        if due < 0 {
            return false;
        }
        if t - self._last_fire < self._m.min_gap.max(self._gap_need) {
            self.delayed += 1;
            return false; // the thumb is still on its way back: the press lands a little later
        }
        let due = due as usize;
        self.made.push(self._taps[due]);
        self._done.push(self._taps[due].0);
        self._done.retain(|&d| d >= t - 16);
        self._taps.remove(due);
        self._last_fire = t;
        if self._p.gap_sd > 0.0 {
            self._gap_need = self._m.min_gap + (self.gauss().abs() * self._p.gap_sd).round_ties_even() as i64;
        }
        self.presses += 1;
        true
    }

    /// Starts a reaction time for everything that appeared since the last tick.
    fn notice(&mut self, sim: &GameSim, t: i64) {
        let s = &sim.state;
        let react = self._m.react_mu >= 0.0;
        let new_room = s.room_index != self._room;
        if new_room {
            // A new room: it shows during the arrival hold, so it is seen by the time the bird moves.
            self._room = s.room_index;
            self._tell_until = -1;
            self._known.clear();
            self._hidden.clear();
            for i in 0..sim.room.hazards.len() {
                self._known.insert((self._objects, i));
            }
            self._spikes_hidden_until = -1;
        } else if s.score != self._score {
            // new spikes on the wall ahead
            self._spikes_hidden_until =
                if MASK_SPIKES.load(Ordering::Relaxed) && react { t + self.reaction() } else { -1 };
        }
        self._score = s.score;
        for h in &sim.room.hazards {
            if h.as_boss().is_some() {
                let key = BossBlind::tell_key(h);
                if key != self._boss_key && REACT_BOSS.load(Ordering::Relaxed) && react {
                    self._boss_hidden_until = t + self.reaction();
                }
                self._boss_key = key;
            }
        }
        let mask_hazards = MASK_HAZARDS.load(Ordering::Relaxed);
        for (i, h) in sim.room.hazards.iter().enumerate() {
            let key = (self._objects, i);
            if h.alive() && self._known.insert(key) && mask_hazards && react {
                let r = self.reaction();
                self._hidden.insert(key, t + r);
            }
        }
        self._hidden.retain(|_, v| *v > t);
        // New warnings (tells). One that the plan in hand lives through needs no
        // change of plan; one that kills it is acted on a reaction time later.
        self._warned_now.clear();
        let mut fresh = false;
        for (i, h) in sim.room.hazards.iter().enumerate() {
            if !h.alive() {
                continue;
            }
            self._warn_buf.clear();
            h.warnings(sim, &mut self._warn_buf);
            let mut k = 0;
            while k + WARN_SIZE <= self._warn_buf.len() {
                let b = &self._warn_buf;
                let key = (i, b[k], b[k + 1], b[k + 2], b[k + 3]);
                self._warned_now.insert(key);
                if !self._warned.contains(&key) {
                    fresh = true;
                }
                k += WARN_SIZE;
            }
        }
        std::mem::swap(&mut self._warned, &mut self._warned_now);
        // Only a plan that was whole before the warning showed: a planner already
        // in trouble (no full line at its last look) keeps looking every tick.
        if fresh
            && !new_room
            && MASK_TELLS.load(Ordering::Relaxed)
            && react
            && t >= self._tell_until
            && self.planner.last_look == 0
            && !self.planner.plan().is_empty()
            && !self.planner.plan_lives(sim)
        {
            self._tell_until = t + self.reaction();
            self.tell_reactions += 1;
        }
    }

    /// The sim as the player has taken it in: new spikes not yet seen are not
    /// there, nor are hazards that appeared less than a reaction time ago.
    fn masked(&self, sim: &GameSim, t: i64) -> GameSim {
        let mut c = sim.clone_deep();
        if t < self._spikes_hidden_until {
            if c.state.vx > 0 {
                c.state.right_spikes = 0;
            } else {
                c.state.left_spikes = 0;
            }
        }
        if !self._hidden.is_empty() {
            for i in (0..c.room.hazards.len()).rev() {
                if self._hidden.contains_key(&(self._objects, i)) {
                    // kept in the list: other hazards may link to it
                    c.room.hazards[i].base_mut().alive = false;
                }
            }
        }
        c
    }
}

/// The tiers: tap timing sd (the main knob) and the reaction to new things
/// per tier, fitted on the rate median (docs/HUMAN_BOT.md). Expert reacts faster
/// than the measured human ~17 ticks (about 6), beast not at all; both think with
/// the finer search. Beast has no human limit but the 8-tick thumb gap (which costs
/// nothing once the planner plans with it).
pub struct MotorTiers;

impl MotorTiers {
    /// (tier, (sigma, react, fine)), in C# dictionary order.
    pub const TIER: [(&'static str, (f64, f64, bool)); 5] = [
        ("beginner", (1.4, 13.0, false)),
        ("normal", (0.6, 13.0, false)),
        ("good", (0.0, 8.0, false)),
        ("expert", (0.2, 2.0, true)),
        ("beast", (0.0, -100.0, true)),
    ];

    /// The tiers when the planner knows the planned exit mouths (BlindPlanner.know_exits):
    /// hazards bounce off them from room start, so a hidden-exit copy mispredicts them.
    /// Seeds 1..100, full cap: rate medians 33 / 59 / 119 / 257 / 724.
    pub const TIER_KNOWN_EXITS: [(&'static str, (f64, f64, bool)); 5] = [
        ("beginner", (1.4, 13.0, false)),
        ("normal", (0.6, 13.0, false)),
        ("good", (0.3, 13.0, false)),
        ("expert", (0.0, 8.0, false)),
        ("beast", (0.0, -100.0, true)),
    ];

    pub fn sigma(tier: &str) -> f64 {
        MotorTiers::find(&MotorTiers::TIER, tier).0
    }

    fn find(table: &[(&'static str, (f64, f64, bool)); 5], tier: &str) -> (f64, f64, bool) {
        match table.iter().find(|x| x.0 == tier) {
            Some(x) => x.1,
            None => panic!("unknown tier '{tier}'"),
        }
    }

    /// `of` with the table picked by `known_exits` (C# reads BlindPlanner.know_exits).
    pub fn of_table(tier: &str, known_exits: bool) -> Motor {
        let (sg, re, fine) =
            MotorTiers::find(if known_exits { &MotorTiers::TIER_KNOWN_EXITS } else { &MotorTiers::TIER }, tier);
        let mut m = Motor::at(sg);
        m.react_mu = re;
        m.react_tau = if re < 0.0 { 0.0 } else { 4.0 };
        m.fine = fine;
        m
    }

    pub fn of(tier: &str) -> Motor {
        let known = KNOW_EXITS.load(Ordering::Relaxed);
        if !known {
            if let Some(&(react, level)) = MotorTiers::calibrated().get(tier) {
                return MotorTiers::shared(react, level);
            }
        }
        MotorTiers::of_table(tier, known)
    }

    // ---------------------------------------------------- calibrated tiers

    /// The human rules every calibrated tier shares (C# MotorTiers.SHARED_SIGMA / SHARED).
    pub const SHARED_SIGMA: f64 = 0.4;
    pub const SHARED: Persona = Persona { pref_sd: 20.0, hes_p: 0.03, hes_tau: 4.0, gap_sd: 1.5 };

    /// Search fineness, coarse to fine: (bucket px, speed buckets, free tap timing).
    pub const LEVELS: [(i64, i64, bool); 6] =
        [(16, 3, false), (12, 4, false), (8, 6, false), (6, 8, false), (4, 12, false), (4, 12, true)];
    pub const DEFAULT_LEVEL: i32 = 2;

    /// A tier at these knobs: `react` the mean reaction to new things (ticks, ex-Gaussian with
    /// sd 2 and a tail of 4), `level` the search fineness (LEVELS).
    pub fn shared(react: f64, level: i32) -> Motor {
        assert!(level >= 0 && (level as usize) < MotorTiers::LEVELS.len(), "search level {level}: 0..5");
        let mut m = Motor::new(MotorTiers::SHARED_SIGMA, (react - 4.0).max(0.0), 2.0, 4.0, 8, 5, false);
        m.p = Some(MotorTiers::SHARED);
        m.level = level;
        m
    }

    /// The fitted knobs per tier: tools/fastsim/Human/tiers.json (the same file C# reads,
    /// written by tools/calibrate_tiers.ps1). Empty when there is no file.
    pub fn calibrated() -> &'static HashMap<String, (f64, i32)> {
        static CAL: OnceLock<HashMap<String, (f64, i32)>> = OnceLock::new();
        CAL.get_or_init(|| {
            let mut res = HashMap::new();
            let Ok(exe) = std::env::current_exe() else { return res };
            let mut d = exe.parent().map(|p| p.to_path_buf());
            while let Some(dir) = d {
                let f = dir.join("tools").join("fastsim").join("Human").join("tiers.json");
                if f.exists() {
                    if let Ok(text) = std::fs::read_to_string(&f) {
                        if let Ok(j) = serde_json::from_str::<serde_json::Value>(text.trim_start_matches('\u{feff}')) {
                            if let Some(t) = j["tiers"].as_object() {
                                for (k, v) in t {
                                    if let (Some(r), Some(l)) = (v["react"].as_f64(), v["level"].as_i64()) {
                                        res.insert(k.clone(), (r, l as i32));
                                    }
                                }
                            }
                        }
                    }
                    break;
                }
                d = dir.parent().map(|p| p.to_path_buf());
            }
            res
        })
    }
}
