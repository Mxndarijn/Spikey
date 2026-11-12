//! Port of Bots/SurvivalSearch.cs (tests/support/survival_search.gd). Must find
//! the same taps as the GDScript search, so the bucket keys, the order copies
//! are tried in and the order of the kept set are the same.
use std::collections::HashMap;

use sim::prelude::*;

use crate::dotnet_random::DotnetRandom;

pub struct SurvivalSearch {
    pub ticks_survived: i64,
    pub peak_width: i64,
    pub best: Option<GameSim>,
    pub best_inputs: Vec<u8>,
    pub last_rooms: Vec<i64>,
    /// Death cause name -> count, in first-seen order (C# Dictionary).
    pub last_deaths: Vec<(&'static str, i64)>,
    pub level: i64,
    pub max_level: i64,
    /// FastSim checks only (no GDScript twin): end on a random survivor instead
    /// of the best one, to play many different lines (Checks.Exits).
    pub pick: Option<DotnetRandom>,
    _bucket_h: i64,
    _bucket_vy: i64,
    _speed_buckets: i64,
    _parents: Vec<i32>,
    _taps: Vec<u8>,
}

struct Entry {
    sim: GameSim,
    node: i32,
    tap: u8,
}

impl Default for SurvivalSearch {
    fn default() -> Self {
        Self::new()
    }
}

impl SurvivalSearch {
    pub const TAP_BELOW_VY: i64 = SimConfig::FLAP_VY / 2;
    pub const LEVELS: [[i64; 3]; 3] = [
        [5 * SimConfig::SUB, -SimConfig::FLAP_VY / 2, 5],
        [3 * SimConfig::SUB, -SimConfig::FLAP_VY / 4, 16],
        [2 * SimConfig::SUB, -SimConfig::FLAP_VY / 8, 40],
    ];

    pub fn new() -> SurvivalSearch {
        SurvivalSearch {
            ticks_survived: 0,
            peak_width: 0,
            best: None,
            best_inputs: Vec::new(),
            last_rooms: Vec::new(),
            last_deaths: Vec::new(),
            level: 0,
            max_level: Self::LEVELS.len() as i64 - 1,
            pick: None,
            _bucket_h: 0,
            _bucket_vy: 0,
            _speed_buckets: 0,
            _parents: Vec::new(),
            _taps: Vec::new(),
        }
    }

    pub fn run(&mut self, sim: &GameSim, ticks: i64) -> bool {
        for i in 0..self.max_level + 1 {
            self.level = i;
            self._bucket_h = Self::LEVELS[i as usize][0];
            self._bucket_vy = Self::LEVELS[i as usize][1];
            self._speed_buckets = Self::LEVELS[i as usize][2];
            if self._run_once(sim, ticks) {
                return true;
            }
        }
        false
    }

    /// tests/support/quick_search.gd (QuickSearch.run): a coarse (fast) first
    /// pass; a line it finds is a real way through, and only when it finds
    /// none does the full search run.
    pub fn run_quick(&mut self, sim: &GameSim, ticks: i64) -> bool {
        self.level = -1;
        self._bucket_h = 10 * SimConfig::SUB;
        self._bucket_vy = -SimConfig::FLAP_VY / 2;
        self._speed_buckets = 4;
        if self._run_once(sim, ticks) {
            return true;
        }
        self.run(sim, ticks)
    }

    fn _run_once(&mut self, sim: &GameSim, ticks: i64) -> bool {
        self._parents = Vec::new();
        self._taps = Vec::new();
        let mut frontier = vec![Entry { sim: sim.clone_deep(), node: -1, tap: 0 }];
        self.ticks_survived = 0;
        self.peak_width = 1;
        self.best = None;
        self.best_inputs = Vec::new();
        // Insertion-ordered "dictionary": key -> slot in `next`.
        let mut slots: HashMap<i64, usize> = HashMap::new();
        let mut next: Vec<Entry> = Vec::new();
        // (room_kind, death_cause) of every frontier sim after its step, for the
        // report when nothing survives (C# reads the stepped frontier).
        let mut seen: Vec<(i64, i64)> = Vec::new();
        for t in 0..ticks {
            slots.clear();
            next.clear();
            seen.clear();
            for e in frontier.drain(..) {
                let mut s = e.sim;
                let grav = s.room.gravity;
                if s.state.vy * grav > Self::TAP_BELOW_VY || !s.state.started {
                    let mut c = s.clone_deep();
                    c.step(true);
                    self._keep(&mut slots, &mut next, c, e.node, 1);
                }
                if !s.state.started {
                    seen.push((s.state.room_kind, s.state.death_cause));
                    continue;
                }
                s.step(false);
                seen.push((s.state.room_kind, s.state.death_cause));
                self._keep(&mut slots, &mut next, s, e.node, 0);
            }
            if next.is_empty() {
                self.last_rooms.clear();
                self.last_deaths.clear();
                for &(room_kind, cause) in &seen {
                    if !self.last_rooms.contains(&room_kind) {
                        self.last_rooms.push(room_kind);
                    }
                    let why = DeathCause::NAMES[cause as usize];
                    match self.last_deaths.iter_mut().find(|(k, _)| *k == why) {
                        Some((_, n)) => *n += 1,
                        None => self.last_deaths.push((why, 1)),
                    }
                }
                return false;
            }
            for e in next.drain(..) {
                self._parents.push(e.node);
                self._taps.push(e.tap);
                frontier.push(Entry { sim: e.sim, node: self._parents.len() as i32 - 1, tap: 0 });
            }
            self.peak_width = G::maxi(self.peak_width, frontier.len() as i64);
            self.ticks_survived = t + 1;
        }
        let mut top = 0usize;
        if let Some(pick) = self.pick.as_mut() {
            top = pick.next(frontier.len() as i32) as usize;
        } else {
            for i in 0..frontier.len() {
                if Self::_better(&frontier[i].sim, &frontier[top].sim) {
                    top = i;
                }
            }
        }
        let node = frontier[top].node;
        self.best = Some(frontier.swap_remove(top).sim);
        self.best_inputs = self._inputs_to(node);
        self._parents = Vec::new();
        self._taps = Vec::new();
        true
    }

    fn _inputs_to(&self, node: i32) -> Vec<u8> {
        let mut out_ = Vec::new();
        let mut n = node;
        while n >= 0 {
            out_.push(self._taps[n as usize]);
            n = self._parents[n as usize];
        }
        out_.reverse();
        out_
    }

    fn _keep(&self, slots: &mut HashMap<i64, usize>, next: &mut Vec<Entry>, s: GameSim, parent: i32, tap: u8) {
        if s.is_over() {
            return;
        }
        let st = &s.state;
        let along = st.vy * s.room.gravity - SimConfig::FLAP_VY;
        let speed = G::clampi(along / self._bucket_vy, 0, self._speed_buckets - 1);
        let key = (st.y / self._bucket_h) * self._speed_buckets + speed;
        if let Some(&slot) = slots.get(&key) {
            if Self::_better(&s, &next[slot].sim) {
                next[slot] = Entry { sim: s, node: parent, tap };
            }
        } else {
            slots.insert(key, next.len());
            next.push(Entry { sim: s, node: parent, tap });
        }
    }

    pub fn _better(a: &GameSim, b: &GameSim) -> bool {
        if a.state.room_index != b.state.room_index {
            return a.state.room_index > b.state.room_index;
        }
        if a.state.score != b.state.score {
            return a.state.score > b.state.score;
        }
        a.state.coins > b.state.coins
    }
}
