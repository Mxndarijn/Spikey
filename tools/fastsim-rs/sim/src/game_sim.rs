//! Port of sim/game_sim.gd (Sim/GameSim.cs). Same names, same order of everything.
//! Loops over room.hazards use indexes and re-read the length, like GDScript's
//! array iteration, so a hazard added during a loop is visited too.
use std::sync::Arc;

use crate::arrival_check::ArrivalCheck;
use crate::arrival_memo::ArrivalMemo;
use crate::exit_planner::ExitPlanner;
use crate::fair_lanes::FairLanes;
use crate::g::G;
use crate::hazards::Hz;
use crate::rooms::room_catalog::RoomCatalog;
use crate::rooms::room_def::{Kind, RoomDef, RoomVariant, WallMode};
use crate::rooms::variant_check::VariantCheck;
use crate::rooms::variant_params::VariantParams;
use crate::rooms::room_rules::RoomRules;
use crate::rooms::room_runtime::RoomRuntime;
use crate::rooms::seasons::Seasons;
use crate::sim_config::SimConfig;
use crate::sim_math::{SimHash, SimMath};
use crate::sim_rng::SimRng;
use crate::sim_state::{DeathCause, ExitKind, SimState};

pub struct Event;

impl Event {
    pub const START: i32 = 0;
    pub const FLAP: i32 = 1;
    pub const BOUNCE: i32 = 2;
    pub const SCORE: i32 = 3;
    pub const ROOM_CHANGE: i32 = 4;
    pub const DEATH: i32 = 5;
    pub const COIN_SPAWN: i32 = 6;
    pub const COIN: i32 = 7;
    pub const EXIT_OPEN: i32 = 8;
    pub const EXIT_PREVIEW: i32 = 9;
    pub const REVIVE: i32 = 10;
    pub const BOSS_DOWN: i32 = 11;
}

/// Interns a variant id, so a sim copy shares it (`forced_variant`).
pub fn intern(s: &str) -> &'static str {
    use std::collections::HashSet;
    use std::sync::Mutex;
    static SET: Mutex<Option<HashSet<&'static str>>> = Mutex::new(None);
    if s.is_empty() {
        return "";
    }
    let mut g = SET.lock().unwrap();
    let set = g.get_or_insert_with(HashSet::new);
    if let Some(&v) = set.get(s) {
        return v;
    }
    let v: &'static str = Box::leak(s.to_string().into_boxed_str());
    set.insert(v);
    v
}

pub struct GameSim {
    pub seed_value: i64,
    pub season: i64,
    pub practice_room: i64,
    /// Bots only: the variant id to play in place of the drawn one ("" = the drawn one).
    pub forced_variant: &'static str,
    pub state: SimState,
    pub room: RoomRuntime,
    pub events: Vec<i32>,
    pub _rng: SimRng,
    pub _spine: SimRng,
    pub _checking: bool,
    /// Bots only, never in the game: a planner copy remembers arrival checks (arrival_memo.rs).
    pub memo_arrivals: bool,
    pub _arrival_unpin: bool,
    /// Tool info, not gameplay: the last portal arrival had no layout fair for every bird in the exit.
    pub _arrival_unfit: bool,
    pub _free_lo: i64,
    pub _free_hi: i64,
    /// The free run the last new wall was drawn with, for hazards that change the wall
    /// (CrowdFill): its first slot and the first and last starts it could have had
    /// (RoomRules.generate_wall_run). -1s: none.
    pub wall_run: [i64; 3],
    /// The room, the whole state and both RNGs as the bird came in, for a revive. Never changed after
    /// it is taken, so clones share it (GDScript's SimCopy copies it).
    pub _entry_room: Option<Arc<RoomRuntime>>,
    pub _entry_state: Option<SimState>,
    pub _entry_rng: SimRng,
    pub _entry_spine: SimRng,
    pub _points_override: i64,
    pub _points_also: i64,
}

impl GameSim {
    pub const BUMP_VY: i64 = -SimConfig::FLAP_VY * 6 / 5;
    pub const ARRIVAL_WALL_SPARE: i64 = 30;
    pub const PRACTICE_START_GAP: i64 = 40 * SimConfig::SUB;
    pub const ARRIVAL_HEIGHTS: [i64; 5] =
        [0, -SimConfig::EXIT_FIT, SimConfig::EXIT_FIT, -SimConfig::EXIT_FIT / 2, SimConfig::EXIT_FIT / 2];
    pub const EXIT_STEER: i64 = 3;
    pub const SPIKE_SLIDE: i64 = 10;

    /// C#'s private `GameSim()` (what clone_deep starts from).
    fn blank() -> GameSim {
        GameSim {
            seed_value: 0,
            season: Seasons::NONE,
            practice_room: -1,
            forced_variant: "",
            state: SimState::default(),
            room: RoomRuntime::default(),
            events: Vec::with_capacity(8),
            _rng: SimRng::default(),
            _spine: SimRng::default(),
            _checking: false,
            memo_arrivals: false,
            _arrival_unpin: false,
            _arrival_unfit: false,
            _free_lo: -1,
            _free_hi: -1,
            wall_run: [-1, -1, -1],
            _entry_room: None,
            _entry_state: None,
            _entry_rng: SimRng::default(),
            _entry_spine: SimRng::default(),
            _points_override: -1,
            _points_also: -1,
        }
    }

    /// `new GameSim(seed)`.
    pub fn new(p_seed: i64) -> GameSim {
        Self::with(p_seed, Seasons::NONE, -1, "")
    }

    /// `new GameSim(seed, season, practice_room, variant)`.
    pub fn with(p_seed: i64, p_season: i64, p_practice_room: i64, p_variant: &str) -> GameSim {
        let mut s = Self::blank();
        s.seed_value = p_seed;
        s.season = p_season;
        s.forced_variant = intern(p_variant);
        s._spine = SimRng::new(p_seed);
        s._rng = SimRng::new(0);
        s._seed_room();
        if p_practice_room >= 0 && p_practice_room < RoomCatalog::all().len() as i64 {
            s.practice_room = p_practice_room;
            s.state.score = RoomCatalog::all()[s.practice_room as usize].from_score;
            s.state.x = Self::PRACTICE_START_GAP;
            s._enter_room(s.practice_room);
            let at = s.next_exit_score();
            ExitPlanner::plan_room(&mut s, at);
        } else {
            s._enter_room(RoomCatalog::first_index());
            let at = s.next_exit_score();
            ExitPlanner::plan_room(&mut s, at);
            s._keep_entry();
        }
        s
    }

    /// Deep copy (what SimClone.copy does in GDScript). Like the C# one, it leaves
    /// `_free_lo/_free_hi` and the points overrides at their defaults.
    pub fn clone_deep(&self) -> GameSim {
        GameSim {
            seed_value: self.seed_value,
            season: self.season,
            practice_room: self.practice_room,
            forced_variant: self.forced_variant,
            state: self.state,
            room: self.room.clone(),
            events: self.events.clone(),
            _rng: self._rng,
            _spine: self._spine,
            _arrival_unpin: self._arrival_unpin,
            _arrival_unfit: self._arrival_unfit,
            _checking: self._checking,
            memo_arrivals: self.memo_arrivals,
            _entry_room: self._entry_room.clone(),
            _entry_state: self._entry_state,
            _entry_rng: self._entry_rng,
            _entry_spine: self._entry_spine,
            _free_lo: -1,
            _free_hi: -1,
            wall_run: self.wall_run,
            _points_override: -1,
            _points_also: -1,
        }
    }

    /// `clone_deep` into an existing sim, reusing its buffers (no allocation once warm).
    pub fn copy_into(&self, c: &mut GameSim) {
        c.seed_value = self.seed_value;
        c.season = self.season;
        c.practice_room = self.practice_room;
        c.forced_variant = self.forced_variant;
        c.state = self.state;
        c.room.clone_from(&self.room);
        c.events.clone_from(&self.events);
        c._rng = self._rng;
        c._spine = self._spine;
        c._arrival_unpin = self._arrival_unpin;
        c._arrival_unfit = self._arrival_unfit;
        c._checking = self._checking;
        c.memo_arrivals = self.memo_arrivals;
        c._entry_room.clone_from(&self._entry_room);
        c._entry_state = self._entry_state;
        c._entry_rng = self._entry_rng;
        c._entry_spine = self._entry_spine;
        c._free_lo = -1;
        c._free_hi = -1;
        c.wall_run = self.wall_run;
        c._points_override = -1;
        c._points_also = -1;
    }

    #[inline]
    pub fn is_practice(&self) -> bool {
        self.practice_room >= 0
    }

    #[inline]
    /// Every warning (tell) on screen now: Hazard.warnings of each live hazard,
    /// WARN_SIZE numbers per warning, added to `out_` (cleared first).
    pub fn warnings(&self, out_: &mut Vec<i64>) {
        out_.clear();
        for h in self.room.hazards.iter() {
            if h.base().alive {
                h.warnings(self, out_);
            }
        }
    }

    pub fn is_over(&self) -> bool {
        !self.state.alive
    }

    /// Runs `f` on hazard `i` with it taken out of the room list (rooms/hazard.rs).
    #[inline]
    pub fn with_hazard<R>(&mut self, i: usize, f: impl FnOnce(&mut Hz, &mut GameSim) -> R) -> R {
        if !self.room.hazards[i].needs_room() {
            // Its code never reads room.hazards: lend the whole list out (3 words, not the hazard).
            let mut list = std::mem::take(&mut self.room.hazards);
            let r = f(&mut list[i], self);
            debug_assert!(self.room.hazards.is_empty(), "a hazard added hazards while the list was lent out");
            self.room.hazards = list;
            return r;
        }
        let mut h = std::mem::replace(&mut self.room.hazards[i], Hz::Taken);
        let r = f(&mut h, self);
        self.room.hazards[i] = h;
        r
    }

    /// `hazard.on_bounce(sim, sim._rng)` and the like: the hazard and the sim's
    /// RNG both taken out while it runs (no hazard touches `sim._rng` itself).
    #[inline]
    pub fn with_hazard_rng(&mut self, i: usize, f: impl FnOnce(&mut Hz, &mut GameSim, &mut SimRng)) {
        let mut rng = self._rng;
        self.with_hazard(i, |h, sim| f(h, sim, &mut rng));
        self._rng = rng;
    }

    pub fn step(&mut self, tap: bool) {
        self.events.clear();
        if !self.state.alive {
            return;
        }
        if self.state.arrival_hold > 0 {
            self.state.arrival_hold -= 1;
            self.state.tick += 1;
            return;
        }
        if tap {
            if !self.state.started {
                self.state.started = true;
                self.events.push(Event::START);
            }
            self.state.vy = SimConfig::FLAP_VY * self.room.gravity;
            self.state.flaps += 1;
            let mut i = 0;
            while i < self.room.hazards.len() {
                let h = &self.room.hazards[i];
                if h.alive() && h.has_on_flap() {
                    self.with_hazard(i, |h, sim| h.on_flap(sim));
                }
                i += 1;
            }
            self.events.push(Event::FLAP);
        }
        if self.state.started {
            let n = self.room.steps_this_tick();
            for _ in 0..n {
                self._substep();
                if !self.state.alive {
                    break;
                }
            }
            self.room.ticks += 1;
        }
        self.state.tick += 1;
    }

    pub fn can_revive(&self) -> bool {
        !self.state.alive && !self.is_practice() && self.state.revives < SimConfig::MAX_REVIVES
    }

    pub fn revive(&mut self) -> bool {
        if !self.can_revive() {
            return false;
        }
        self.events.clear();
        let tick = self.state.tick;
        let revives = self.state.revives + 1;
        let flaps = self.state.flaps;
        self.state.assign(self._entry_state.as_ref().expect("no entry state"));
        self.state.tick = tick;
        self.state.revives = revives;
        self.state.flaps = flaps;
        self.state.started = true;
        self.state.arrival_hold = SimConfig::ARRIVAL_HOLD;
        self.room = (**self._entry_room.as_ref().expect("no entry room")).clone();
        self._rng = self._entry_rng;
        self._spine = self._entry_spine;
        self._free_lo = -1;
        self._free_hi = -1;
        self.events.push(Event::REVIVE);
        true
    }

    pub fn wall_mask(&self, side: i64) -> i64 {
        if self.state.exit_open && self.state.exit_side == side {
            let open = ((1i64 << SimConfig::SLOT_COUNT) - 1) & !ExitPlanner::slots(&self.state);
            return open;
        }
        let mut mask = self.room.wall_mask(side, if side == 0 { self.state.left_spikes } else { self.state.right_spikes });
        if self.state.exit_preview && self.state.exit_side == side {
            mask &= !ExitPlanner::slots(&self.state);
        }
        mask
    }

    pub fn wall_shift(&self, side: i64) -> i64 {
        let mut out_ = 0;
        for h in &self.room.hazards {
            if h.alive() {
                out_ += h.wall_shift(self, side);
            }
        }
        out_
    }

    pub fn exit_locked(&self) -> bool {
        for h in &self.room.hazards {
            if h.alive() && h.locks_exit(self) {
                return true;
            }
        }
        false
    }

    pub fn checksum(&self) -> i64 {
        SimHash::mix(
            SimHash::mix(self.room.checksum(self.state.checksum()), self._rng.state_checksum()),
            self._spine.state_checksum(),
        )
    }

    // --- Helpers for hazards ---

    #[inline]
    pub fn bird_touches_circle(&self, cx: i64, cy: i64, r: i64) -> bool {
        let dx = self.state.x - cx;
        let dy = self.state.y - cy;
        let reach = SimConfig::BIRD_RADIUS + r;
        dx * dx + dy * dy <= reach * reach
    }

    #[inline]
    pub fn bird_touches_rect(&self, x0: i64, y0: i64, x1: i64, y1: i64) -> bool {
        let nx = G::clampi(self.state.x, G::mini(x0, x1), G::maxi(x0, x1));
        let ny = G::clampi(self.state.y, G::mini(y0, y1), G::maxi(y0, y1));
        let dx = self.state.x - nx;
        let dy = self.state.y - ny;
        let r = SimConfig::BIRD_RADIUS;
        dx * dx + dy * dy <= r * r
    }

    pub fn bump_bird_from(&mut self, cx: i64, cy: i64) {
        self.state.vy = if self.state.y < cy { -Self::BUMP_VY } else { Self::BUMP_VY };
        if (self.state.x < cx) == (self.state.vx > 0) {
            self.state.vx = -self.state.vx;
            if self.state.vx > 0 {
                self.state.right_spikes = 0;
                self.state.right_new = 0;
            } else {
                self.state.left_spikes = 0;
                self.state.left_new = 0;
            }
        }
    }

    /// GDScript default: amount = 1.
    pub fn collect_coin(&mut self, x: i64, y: i64, amount: i64) {
        self.state.coins += amount;
        self.state.pickup_x = x;
        self.state.pickup_y = y;
        self.events.push(Event::COIN);
    }

    pub fn kill(&mut self, cause: i64) {
        self.state.alive = false;
        self.state.death_cause = cause;
        self.events.push(Event::DEATH);
    }

    // --- RoomRuntime.start / step (they need the sim and the room at once) ---

    /// RoomRuntime.start(def, index, sim, rng), with rng = sim._rng.
    pub fn room_start(&mut self, p_def: &'static RoomDef, p_index: i64) {
        let room = &mut self.room;
        room.def_ = Some(p_def);
        room.index = p_index;
        room.entry_score = self.state.score;
        room.t = 0;
        room.ticks = 0;
        room.points = 0;
        room.variant = 0;
        room.tide_left = 0;
        room.tide_right = 0;
        room.tide_salt_left = 0;
        room.tide_salt_right = 0;
        room.blink_left = 0;
        room.blink_right = 0;
        room.gravity = p_def.gravity_sign;
        room.walls = 0;
        room.hazards.clear();
        let def = p_def;
        let mut list: Vec<&'static crate::rooms::room_def::Factory> = def.hazards.iter().collect();
        let mut drawn: Vec<i64> = Vec::new();
        if self.state.started {
            drawn = def.arrival_variants(self.state.anchor_y);
        }
        if drawn.is_empty() {
            for i in 0..def.variants.len() {
                drawn.push(i as i64);
            }
        }
        if drawn.len() > 1 {
            self.room.variant = drawn[self._rng.next_below(drawn.len() as i64) as usize];
            if self.state.started && !self._arrival_unpin {
                let first = drawn[SimRng::new(self.room.rng_seed).next_below(drawn.len() as i64) as usize];
                if def.variants[first as usize].kind == Kind::GENERATED {
                    self.room.variant = first;
                }
            }
        } else if drawn.len() == 1 {
            self.room.variant = drawn[0];
        }
        if !self.forced_variant.is_empty() {
            self.room.variant = self.room._variant_index(self.forced_variant, self.room.variant);
        }
        let gen = !def.variants.is_empty() && def.variants[self.room.variant as usize].kind == Kind::GENERATED;
        if !def.variants.is_empty() {
            for f in &def.variants[self.room.variant as usize].hazards {
                list.push(f);
            }
        }
        let mut after: Vec<&'static crate::rooms::room_def::Factory> = Vec::new();
        if !def.combos.is_empty() {
            let combo = &def.combos[self._rng.next_below(def.combos.len() as i64) as usize];
            for f in combo {
                if gen {
                    after.push(f);
                } else {
                    list.push(f);
                }
            }
        }
        for f in list {
            let mut h = f();
            let i = self.room.hazards.len();
            h.base_mut().idx = i;
            self.room.hazards.push(h);
            self.with_hazard_rng(i, |h, sim, rng| h.setup(sim, rng));
        }
        if gen {
            self._generate(&def.variants[self.room.variant as usize]);
        }
        for f in after {
            let mut h = f();
            let i = self.room.hazards.len();
            h.base_mut().idx = i;
            self.room.hazards.push(h);
            self.with_hazard_rng(i, |h, sim, rng| h.setup(sim, rng));
        }
    }

    /// RoomRuntime._generate(sim, rng, v).
    fn _generate(&mut self, v: &'static RoomVariant) {
        let base_ = self.room.hazards.len();
        let mut p = VariantParams::make(self);
        let recipe = v.recipe.as_ref().expect("a GENERATED variant has a recipe");
        for k in 0..RoomVariant::GENERATE_TRIES {
            p.attempt = k;
            p.fallback = k == RoomVariant::GENERATE_TRIES - 1;
            recipe(self, &p);
            if p.fallback || VariantCheck::holds(self, v.avoid_touch, v.hold_steps) {
                return;
            }
            self.room.hazards.truncate(base_);
        }
    }

    /// RoomRuntime.step(sim).
    pub fn room_step(&mut self) {
        self.room.t += 1;
        // Index loop: a hazard may add hazards (none do in step today).
        let mut i = 0;
        while i < self.room.hazards.len() {
            if self.room.hazards[i].alive() {
                let t = self.room.t;
                self.room.hazards[i].base_mut().t = t;
                if self.room.hazards[i].has_step() {
                    self.with_hazard(i, |h, sim| h.step(sim));
                }
            }
            i += 1;
        }
    }

    // --- One step ---

    fn _substep(&mut self) {
        let p0 = crate::prof::enter(crate::prof::HZSTEP);
        self.room_step();
        crate::prof::leave(p0);
        self._move();
        let p0 = crate::prof::enter(crate::prof::SPIKES);
        self._check_spikes();
        crate::prof::leave(p0);
        if !self.state.alive {
            return;
        }
        let p0 = crate::prof::enter(crate::prof::KILLS);
        self._check_hazards();
        crate::prof::leave(p0);
        if !self.state.alive {
            return;
        }
        self._check_coin();
        let p0 = crate::prof::enter(crate::prof::WALLS);
        self._check_walls();
        crate::prof::leave(p0);
        self._check_ceiling_floor();
    }

    #[inline]
    fn _move(&mut self) {
        let g = SimConfig::GRAVITY * self.room.gravity;
        self.state.vy = G::clampi(self.state.vy + g, -SimConfig::MAX_FALL_VY, SimConfig::MAX_FALL_VY);
        self.state.x += self.state.vx;
        self.state.y += self.state.vy;
    }

    fn _check_hazards(&mut self) {
        let mut i = 0;
        while i < self.room.hazards.len() {
            let h = &self.room.hazards[i];
            if h.alive() && h.kills(self) {
                self.kill(DeathCause::HAZARD);
                return;
            }
            i += 1;
        }
        let mut i = 0;
        while i < self.room.hazards.len() {
            let h = &self.room.hazards[i];
            if h.alive() && h.has_touch() {
                self.with_hazard(i, |h, sim| h.touch(sim));
            }
            i += 1;
        }
    }

    fn _check_spikes(&mut self) {
        let r = SimConfig::BIRD_RADIUS;
        let left = self.room.wall_left();
        let right = self.room.wall_right();
        let reach = self.room.max_spike_depth();
        if self.state.x - r <= left + reach && self._hits_wall(0, left, 1) {
            self.kill(DeathCause::SPIKE_LEFT);
        } else if self.state.x + r >= right - reach && self._hits_wall(1, right, -1) {
            self.kill(DeathCause::SPIKE_RIGHT);
        }
    }

    fn _hits_wall(&self, side: i64, base_x: i64, dir: i64) -> bool {
        let mask = self.wall_mask(side);
        if mask == 0 || (self.state.vx > 0) == (side == 0) {
            return false;
        }
        let hb = self.room.spike_half_base();
        let shift = self.wall_shift(side);
        for slot in 0..SimConfig::SLOT_COUNT {
            if !RoomRules::has_slot(mask, slot) {
                continue;
            }
            // A new spike kills only once it is all the way out.
            let fresh = if side == 0 { self.state.left_new } else { self.state.right_new };
            if RoomRules::has_slot(fresh, slot) {
                let since = self.room.t - if side == 0 { self.state.left_drawn } else { self.state.right_drawn };
                if since < Self::SPIKE_SLIDE {
                    continue;
                }
            }
            let depth = self.room.slot_depth(side, slot);
            if depth <= 0 {
                continue;
            }
            let cy = SimConfig::slot_center_y(slot) + shift;
            let lo = cy - hb;
            let hi = cy + hb;
            if self.state.y < lo - SimConfig::BIRD_RADIUS || self.state.y > hi + SimConfig::BIRD_RADIUS {
                continue;
            }
            let tip_x = base_x + dir * depth;
            if SimMath::circle_hits_triangle(
                self.state.x,
                self.state.y,
                SimConfig::BIRD_RADIUS,
                base_x,
                lo,
                base_x,
                hi,
                tip_x,
                cy,
            ) {
                return true;
            }
        }
        false
    }

    fn _check_walls(&mut self) {
        let r = SimConfig::BIRD_RADIUS;
        let left = self.room.wall_left();
        let right = self.room.wall_right();
        if self.state.vx > 0 && self.state.x + r >= right {
            if self._take_exit(1) {
                return;
            }
            self._anchor_at_wall(1);
            self.state.x = 2 * (right - r) - self.state.x;
            self.state.vx = -SimConfig::SPEED_X;
            self.room.on_wall_bounce();
            self._bounce_score();
            self._walls_after_bounce(1);
            self._maybe_open_exit();
        } else if self.state.vx < 0 && self.state.x - r <= left {
            if self._take_exit(0) {
                return;
            }
            self._anchor_at_wall(0);
            self.state.x = 2 * (left + r) - self.state.x;
            self.state.vx = SimConfig::SPEED_X;
            self.room.on_wall_bounce();
            self._bounce_score();
            self._walls_after_bounce(0);
            self._maybe_open_exit();
        }
    }

    fn _walls_after_bounce(&mut self, side: i64) {
        if self.room.walls == 0 {
            self._new_wall(1 - side, false);
        }
        self._new_wall(side, true);
        self._boss_recheck(1 - side);
    }

    /// RoomRuntime._boss_recheck: a boss's wall rule runs on the wall ahead again.
    fn _boss_recheck(&mut self, side: i64) {
        if !self.room.def().boss {
            return;
        }
        let mut mask = if side == 0 { self.state.left_spikes } else { self.state.right_spikes };
        let mut i = 0;
        while i < self.room.hazards.len() {
            let h = &self.room.hazards[i];
            if h.alive() && h.has_adjust_wall() {
                mask = self.with_hazard(i, |h, sim| h.adjust_wall(sim, side, mask));
            }
            i += 1;
        }
        if side == 0 {
            self.state.left_spikes = mask;
        } else {
            self.state.right_spikes = mask;
        }
    }

    fn _take_exit(&mut self, side: i64) -> bool {
        if !self.state.exit_open || self.state.exit_side != side {
            return false;
        }
        if self.exit_locked() {
            return false;
        }
        let fit = SimConfig::EXIT_FIT;
        let mut kind = -1;
        let mut through = 0;
        if G::absi(self.state.y - self.state.exit_a_y) <= fit {
            kind = self.state.exit_a_kind;
            through = self.state.exit_a_y;
        } else if self.state.exit_b_kind != ExitKind::NORMAL && G::absi(self.state.y - self.state.exit_b_y) <= fit {
            kind = self.state.exit_b_kind;
            through = self.state.exit_b_y;
        }
        if kind < 0 {
            return false;
        }
        self._go_through(side, kind, through);
        true
    }

    fn _maybe_open_exit(&mut self) {
        // Nothing is due before a point is scored in the room (in Buttons a bounce scores
        // nothing, and the room starts at a multiple of POINTS_PER_ROOM).
        if self.state.exit_open || self.room.points == 0 {
            return;
        }
        if self.state.exit_preview {
            if self._exit_due(self.state.score) {
                self.state.exit_preview = false;
                self.state.exit_open = true;
                self.events.push(Event::EXIT_OPEN);
                self._boss_down();
            }
            return;
        }
        if self._exit_due(self.state.score + 1) && !self.room.def().boss {
            self.state.exit_preview = true;
            let at = self.state.score + 1;
            ExitPlanner::use_plan(self, SimConfig::EXIT_WALL, at);
            self.events.push(Event::EXIT_PREVIEW);
        } else if self._exit_due(self.state.score) {
            self.state.exit_open = true;
            let at = self.state.score;
            ExitPlanner::use_plan(self, SimConfig::EXIT_WALL, at);
            self.events.push(Event::EXIT_OPEN);
            self._boss_down();
        }
    }

    pub fn _exit_due(&self, at: i64) -> bool {
        if self.room.def().boss {
            return at == self.room.entry_score + SimConfig::BOSS_POINTS;
        }
        at % SimConfig::POINTS_PER_ROOM == 0
    }

    fn _boss_down(&mut self) {
        if !self.room.def().boss {
            return;
        }
        self.events.push(Event::BOSS_DOWN);
        if !self.is_practice() {
            let (x, y) = (self.state.x, self.state.y);
            let amount = SimConfig::BOSS_COINS[(SimConfig::boss_tier(self.room.entry_score) - 1) as usize];
            self.collect_coin(x, y, amount);
        }
    }

    pub fn next_exit_score(&self) -> i64 {
        if self.state.exit_open {
            return self.state.score;
        }
        if let Some(def) = self.room.def_ {
            if def.boss {
                return self.room.entry_score + SimConfig::BOSS_POINTS;
            }
        }
        let every = SimConfig::POINTS_PER_ROOM;
        (self.state.score / every + 1) * every
    }

    #[inline]
    pub fn points_to_exit(&self) -> i64 {
        if self._points_override >= 0 { self._points_override } else { self.next_exit_score() - self.state.score }
    }

    pub fn steps_to_exit(&self, side: i64) -> i64 {
        let r = SimConfig::BIRD_RADIUS;
        let left = self.room.wall_left() + r;
        let right = self.room.wall_right() - r;
        let heading = if self.state.vx > 0 { 1 } else { 0 };
        let ahead = if heading == 1 { right - self.state.x } else { self.state.x - left };
        let mut touch = self.points_to_exit() + 1;
        let on = if touch % 2 == 1 { heading } else { 1 - heading };
        if on != side {
            touch += 1;
        }
        G::maxi(ahead, 0) / SimConfig::SPEED_X + (touch - 1) * ((right - left) / SimConfig::SPEED_X)
    }

    fn _wall_target(&self, anchor: i64) -> i64 {
        let reach = RoomRules::gap_reach(self.room.def());
        if reach <= 0 || self.state.exit_open {
            return anchor;
        }
        // The wall drawn now is met a bounce after the wall ahead.
        if self.room.def().reach <= 0 && self.points_to_exit() - 1 > Self::EXIT_STEER {
            if self._free_lo >= 0 && reach - (self._free_hi - self._free_lo) / 2 >= SimConfig::SLOT_SIZE {
                return -1;
            }
            return anchor;
        }
        let to = ExitPlanner::planned_y(self, SimConfig::EXIT_WALL, anchor);
        anchor + G::clampi(to - anchor, -reach / 2, reach / 2)
    }

    pub fn steps_to_wall(&self, side: i64) -> i64 {
        let r = SimConfig::BIRD_RADIUS;
        let left = self.room.wall_left() + r;
        let right = self.room.wall_right() - r;
        let heading = if self.state.vx > 0 { 1 } else { 0 };
        let ahead = if heading == 1 { right - self.state.x } else { self.state.x - left };
        let mut steps = G::maxi(ahead, 0) / SimConfig::SPEED_X;
        if heading != side {
            steps += (right - left) / SimConfig::SPEED_X;
        }
        steps
    }

    pub fn _go_through(&mut self, side: i64, kind: i64, through_y: i64) {
        self.state.exit_open = false;
        self.state.route = kind;
        if kind == ExitKind::WILD {
            for _ in 0..SimConfig::WILD_COINS {
                let (x, y) = (self.state.x, self.state.y);
                self.collect_coin(x, y, 1);
            }
        }
        self.state.room_index += 1;
        let mut door = through_y;
        if kind != ExitKind::NORMAL {
            self.state.y += SimConfig::FORK_DOOR_Y - through_y;
            door = SimConfig::FORK_DOOR_Y;
        }
        self.state.y = Self::_arrival_y(self.state.y);
        self.state.anchor_y = Self::_arrival_y(door);
        let mut next = self.practice_room;
        if self.is_practice() {
        } else if self._boss_due() {
            next = RoomCatalog::pick_boss(&mut self._spine, self.state.bosses_met);
            self.state.bosses_met |= RoomCatalog::boss_bit(next);
        } else {
            next = RoomCatalog::pick_next(&mut self._spine, &mut self.state, self.room.index, self.season);
        }
        self._seed_room();
        let p0 = crate::prof::enter(crate::prof::ARRIVAL);
        let skip = if self.memo_arrivals { ArrivalMemo::retries(self, side, next) } else { self._arrival_retries(side, next) };
        crate::prof::leave(p0);
        for _ in 0..skip {
            self._rng.next_u32();
        }
        self._arrive_in(side, next);
    }

    pub fn _boss_due(&self) -> bool {
        self.state.score > 0 && self.state.score % SimConfig::BOSS_EVERY == 0 && !self.room.def().boss
    }

    #[inline]
    pub fn _arrival_y(y: i64) -> i64 {
        G::clampi(
            y,
            SimConfig::KILL_TOP + SimConfig::ARRIVAL_EDGE,
            SimConfig::KILL_BOTTOM - SimConfig::ARRIVAL_EDGE,
        )
    }

    fn _seed_room(&mut self) {
        self.room.rng_seed = self._spine.next_u32();
        self._rng.reseed(self.room.rng_seed);
    }

    pub fn _arrival_retries(&mut self, side: i64, next: i64) -> i64 {
        self._arrival_unpin = false;
        self._arrival_unfit = false;
        if self._checking || SimConfig::ARRIVAL_BLIND == 0 {
            return 0;
        }
        let mut best = 0;
        let mut best_score = -1;
        let mut best_unpin = false;
        let passes: &[bool] = if RoomCatalog::all()[next as usize].has_generated_choice() { &[false, true] } else { &[false] };
        for &unpin in passes {
            for k in 0..SimConfig::ARRIVAL_TRIES {
                let score = self._arrival_score(side, next, k, unpin);
                if score < 0 {
                    self._arrival_unpin = unpin;
                    return k;
                }
                if score > best_score {
                    best_score = score;
                    best = k;
                    best_unpin = unpin;
                }
            }
        }
        self._arrival_unpin = best_unpin;
        self._arrival_unfit = true;
        best
    }

    fn _arrival_score(&self, side: i64, next: i64, k: i64, unpin: bool) -> i64 {
        let fair = SimConfig::ARRIVAL_BLIND + SimConfig::ARRIVAL_FOLLOW;
        let mut centre = 0;
        let mut worst = fair;
        for dy in Self::ARRIVAL_HEIGHTS {
            let mut c = self.clone_deep();
            c._checking = true;
            c._arrival_unpin = unpin;
            c.state.y = Self::_arrival_y(self.state.anchor_y + dy);
            for _ in 0..k {
                c._rng.next_u32();
            }
            c._arrive_in(side, next);
            if VariantCheck::arrival_dy(&c, dy) != dy {
                c.state.y = Self::_arrival_y(self.state.anchor_y + VariantCheck::arrival_dy(&c, dy));
            }
            let lived = G::mini(ArrivalCheck::score(&mut c), fair);
            if dy == 0 {
                centre = lived;
            }
            worst = G::mini(worst, lived);
            if worst < fair {
                break;
            }
        }
        if worst >= fair {
            return -1;
        }
        centre * (fair + 1) + worst
    }

    pub fn _arrive_in(&mut self, side: i64, next: i64) {
        let r = SimConfig::BIRD_RADIUS;
        self.state.vx = if side == 1 { SimConfig::SPEED_X } else { -SimConfig::SPEED_X };
        self.state.x = if side == 1 { r } else { SimConfig::WORLD_W - r };
        self._enter_room(next);
        self._arrive(side, Event::ROOM_CHANGE);
        let at = self.next_exit_score();
        ExitPlanner::plan_room(self, at);
        self.state.arrival_hold = if self.room.def().boss { SimConfig::BOSS_HOLD } else { 0 };
        self._arrival_unpin = false;
        self._keep_entry();
    }

    fn _keep_entry(&mut self) {
        if self.is_practice() || self._checking {
            return;
        }
        self._entry_room = Some(Arc::new(self.room.clone()));
        self._entry_state = Some(self.state);
        self._entry_rng = self._rng;
        self._entry_spine = self._spine;
    }

    fn _arrive(&mut self, side: i64, ev: i32) {
        let r = SimConfig::BIRD_RADIUS;
        if side == 1 {
            self.state.x = self.room.wall_left() + r;
            self.state.vx = SimConfig::SPEED_X;
        } else {
            self.state.x = self.room.wall_right() - r;
            self.state.vx = -SimConfig::SPEED_X;
        }
        self.state.vy = 0;
        self.state.left_spikes = 0;
        self.state.right_spikes = 0;
        self.state.left_new = 0;
        self.state.right_new = 0;
        self.events.push(ev);
        self._new_wall(side, true);
        if ev == Event::ROOM_CHANGE {
            self._keep_hold_band_open(side);
        }
        // The wall behind (the portal's), for the bird's way back: in a narrow room
        // a player still reading the room can get back to it too.
        self._new_wall(1 - side, false);
        if ev == Event::ROOM_CHANGE {
            self._keep_hold_band_open(1 - side);
        }
    }

    fn _keep_hold_band_open(&mut self, side: i64) {
        let steps = self.steps_to_wall(side);
        let mut ticks = 0;
        let mut done = 0;
        while done < steps {
            done += self.room.steps_at(ticks);
            ticks += 1;
        }
        if ticks > SimConfig::ARRIVAL_BLIND + Self::ARRIVAL_WALL_SPARE {
            return;
        }
        let g = self.room.gravity;
        let edge = SimConfig::BIRD_RADIUS + 4 * SimConfig::SUB;
        let spread = SimConfig::EXIT_FIT;
        let up = self.state.anchor_y - (FairLanes::FIRST_HOP + edge + spread) * g;
        let down = self.state.anchor_y + (edge + spread) * g;
        let top = G::mini(up, down);
        let bottom = G::maxi(up, down);
        let mut mask = if side == 1 { self.state.right_spikes } else { self.state.left_spikes };
        for slot in 0..SimConfig::SLOT_COUNT {
            let cy = SimConfig::slot_center_y(slot);
            if cy + SimConfig::SPIKE_HALF_BASE > top && cy - SimConfig::SPIKE_HALF_BASE < bottom {
                mask &= !(1i64 << slot);
            }
        }
        if side == 1 {
            self.state.right_spikes = mask;
        } else {
            self.state.left_spikes = mask;
        }
    }

    fn _new_wall(&mut self, side: i64, extras: bool) {
        // What the wall shows now: any spike it shows after that is new and slides out.
        let before = self.wall_mask(side);
        let other_drawn = self.room.walls > 0;
        if self.room.walls > 0 {
            self._rng.reseed(SimHash::mix(self.room.rng_seed, self.room.walls));
        }
        self.room.walls += 1;
        // The new free run is kept within reach of the other wall's, which the
        // bird meets first (its free part and the anchor the bird will have there).
        let mut anchor = self.state.anchor_y;
        if other_drawn {
            anchor = self._free_run_of(1 - side);
        }
        let mut reach = -1;
        let mut target = self._wall_target(anchor);
        if target < 0 {
            reach = RoomRules::gap_reach(self.room.def()) - (self._free_hi - self._free_lo) / 2;
            target = (self._free_lo + self._free_hi) / 2;
        }
        self._free_lo = -1;
        self._free_hi = -1;
        let mut bonus = self.room.spike_bonus(side);
        if self.state.route == ExitKind::WILD && self.room.walls > 2 && !self._checking {
            bonus += SimConfig::WILD_SPIKES;
        }
        let def = self.room.def();
        let wall_score = if def.bounce_points { self.state.score } else { self.room.entry_score };
        let drawn = RoomRules::generate_wall_run(&mut self._rng, wall_score, def, target, bonus, reach);
        let mut mask = drawn[0];
        self.wall_run = [drawn[1], drawn[2], drawn[3]];
        let mut i = 0;
        while i < self.room.hazards.len() {
            let h = &self.room.hazards[i];
            if h.alive() && h.has_adjust_wall() {
                mask = self.with_hazard(i, |h, sim| h.adjust_wall(sim, side, mask));
            }
            i += 1;
        }
        if side == 0 {
            self.state.left_spikes = mask;
        } else {
            self.state.right_spikes = mask;
        }
        let score = self.state.score;
        self.room.on_wall_generated(side, mask, score, &mut self._rng);
        // Blink Walls: the second pattern is new too.
        let mut shown = mask;
        if self.room.def().wall_mode == WallMode::BLINK {
            shown |= if side == 0 { self.room.blink_left } else { self.room.blink_right };
        }
        if side == 0 {
            self.state.left_new = shown & !before;
            self.state.left_drawn = self.room.t;
        } else {
            self.state.right_new = shown & !before;
            self.state.right_drawn = self.room.t;
        }
        if !extras {
            return;
        }
        let mut i = 0;
        while i < self.room.hazards.len() {
            let h = &self.room.hazards[i];
            if h.alive() && h.has_on_bounce() {
                self.with_hazard_rng(i, |h, sim, rng| h.on_bounce(sim, rng));
            }
            i += 1;
        }
        if self.room.def().bounce_coin && !self.is_practice() {
            self._spawn_coin();
        }
    }

    fn _anchor_target(&self) -> i64 {
        if self.state.exit_open || self.points_to_exit() > Self::EXIT_STEER {
            return self.state.anchor_y;
        }
        ExitPlanner::planned_y(self, SimConfig::EXIT_WALL, self.state.anchor_y)
    }

    fn _drawn_mask(&self, side: i64) -> i64 {
        if self.state.exit_open && self.state.exit_side == side {
            return ((1i64 << SimConfig::SLOT_COUNT) - 1) & !ExitPlanner::slots(&self.state);
        }
        let mut mask = if side == 0 { self.state.left_spikes } else { self.state.right_spikes };
        if self.state.exit_preview && self.state.exit_side == side {
            mask &= !ExitPlanner::slots(&self.state);
        }
        mask
    }

    fn _anchor_at_wall(&mut self, side: i64) {
        self.state.anchor_y = self._free_run_of(side);
    }

    fn _free_run_of(&mut self, side: i64) -> i64 {
        let mask = self._drawn_mask(side);
        let target = self._anchor_target();
        let mut best = self.state.anchor_y;
        let mut best_d = -1;
        self._free_lo = -1;
        self._free_hi = -1;
        let mut slot = 0;
        while slot < SimConfig::SLOT_COUNT {
            if RoomRules::has_slot(mask, slot) {
                slot += 1;
                continue;
            }
            let lo = slot;
            while slot + 1 < SimConfig::SLOT_COUNT && !RoomRules::has_slot(mask, slot + 1) {
                slot += 1;
            }
            let top = SimConfig::slot_center_y(lo);
            let bottom = SimConfig::slot_center_y(slot);
            if self._free_lo < 0 {
                self._free_lo = top;
            }
            self._free_hi = bottom;
            let y = G::clampi(target, top, bottom);
            let d = G::absi(y - target);
            if best_d < 0 || d < best_d {
                best = y;
                best_d = d;
            }
            slot += 1;
        }
        best
    }

    fn _bounce_score(&mut self) {
        if self.state.exit_open || !self.room.def().bounce_points {
            self.events.push(Event::BOUNCE);
            return;
        }
        self._score();
    }

    /// A hazard scores a point (a Buttons press, ButtonPair): unless the exit is open, or the
    /// room's exit is already due and waits for the next wall bounce to open (_maybe_open_exit).
    /// Returns whether it scored. For hazards only.
    pub fn _score_press(&mut self) -> bool {
        if self.state.exit_open || (self.room.points > 0 && self._exit_due(self.state.score)) {
            return false;
        }
        self.state.score += 1;
        self.room.points += 1;
        self.events.push(Event::SCORE);
        true
    }

    fn _score(&mut self) {
        self.state.score += 1;
        self.room.points += 1;
        self.events.push(Event::BOUNCE);
        self.events.push(Event::SCORE);
    }

    pub fn _enter_room(&mut self, index: i64) {
        self.state.room_kind = index;
        self.room_start(&RoomCatalog::all()[index as usize], index);
    }

    fn _spawn_coin(&mut self) {
        let extra = self.state.coin_active;
        if extra && !self.room.def().bounce_coin_stacks {
            return;
        }
        let mut min_x = SimConfig::COIN_MIN_X;
        if self.room.def().wall_mode == WallMode::TIDE {
            min_x = G::maxi(min_x, self.room.max_spike_depth() + SimConfig::COIN_RADIUS);
        }
        let max_x = SimConfig::COIN_MAX_X - (min_x - SimConfig::COIN_MIN_X);
        let span_x = max_x - min_x + 1;
        let span_y = SimConfig::COIN_MAX_Y - SimConfig::COIN_MIN_Y + 1;
        let x = min_x + self._rng.next_below(span_x);
        let y = SimConfig::COIN_MIN_Y + self._rng.next_below(span_y);
        if extra {
            self.room.add_coin(x, y);
            return;
        }
        self.state.coin_active = true;
        self.state.coin_x = x;
        self.state.coin_y = y;
        self.events.push(Event::COIN_SPAWN);
    }

    fn _check_coin(&mut self) {
        if self.state.coin_active && self.bird_touches_circle(self.state.coin_x, self.state.coin_y, SimConfig::COIN_RADIUS) {
            self.state.coin_active = false;
            let (x, y) = (self.state.coin_x, self.state.coin_y);
            self.collect_coin(x, y, 1);
        }
    }

    fn _check_ceiling_floor(&mut self) {
        let r = SimConfig::BIRD_RADIUS;
        if self.state.y - r <= SimConfig::KILL_TOP {
            if !self._edge_guarded(true) {
                self.kill(DeathCause::CEILING);
            }
        } else if self.state.y + r >= SimConfig::KILL_BOTTOM {
            if !self._edge_guarded(false) {
                self.kill(DeathCause::FLOOR);
            }
        }
    }

    /// ButtonPair.guards_edge pushes the bird (GDScript changes state in it), so it runs
    /// taken out (`guards_edge_mut`); every other hazard's guards_edge is read-only.
    fn _edge_guarded(&mut self, top: bool) -> bool {
        for h in self.room.hazards.iter() {
            if h.alive() && h.guards_edge(self, top) {
                return true;
            }
        }
        false
    }
}
