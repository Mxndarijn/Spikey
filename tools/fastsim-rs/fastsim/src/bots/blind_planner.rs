//! Port of Bots/BlindPlanner.cs. A planner that knows the rules but not the
//! hidden future. It looks ahead on a copy of the sim whose RNG (and the hidden
//! values already drawn, see `blind_copy`) are replaced by its own random
//! numbers. Beam search over tap / wait, re-planned every `replan` ticks.
//! Tool only (playtest bots). Same fields, defaults and order as C#.
use std::collections::VecDeque;

use crate::fxhash::FxMap;
use std::sync::atomic::{AtomicBool, Ordering};

use sim::prelude::*;

use crate::bots::boss_blind::BossBlind;
use crate::bots::survival_search::SurvivalSearch;

/// Measurement only: copies keep the room's true planned exits. True = the planner knows where the exits will be.
pub static KNOW_EXITS: AtomicBool = AtomicBool::new(false);
/// Boss rooms: the copy gets its own boss seed (BossBlind). False = a leak; measuring only.
/// Measurement only: the copy keeps the room's true wall seed (knows every next wall).
pub static KNOW_WALLS: AtomicBool = AtomicBool::new(false);
/// Measurement only: the copy is a plain copy (knows everything).
pub static KNOW_ALL: AtomicBool = AtomicBool::new(false);
pub static BOSS_BLIND: AtomicBool = AtomicBool::new(true);
/// A key chain's later keys (shown one at a time) are placed anew in the copy.
pub static HIDE_KEYS: AtomicBool = AtomicBool::new(true);

pub struct Reveal;
impl Reveal {
    pub const RNG: i32 = 1;
    pub const WALLSEED: i32 = 2;
    pub const SPINE: i32 = 4;
    pub const EXITS: i32 = 8;
    pub const STALAC: i32 = 16;
    pub const SALTS: i32 = 32;
    pub const PRIVRNG: i32 = 64;
    pub const BUBBLE: i32 = 128;
    pub const KEEPY: i32 = 256;
    pub const BEAM: i32 = 512;
    pub const UPDRAFT: i32 = 1024;
    pub const BOSS: i32 = 2048;
    pub const ALL: i32 = 4095;
    pub const KINDS: [(&'static str, i32); 12] = [
        ("rng", Self::RNG),
        ("wallseed", Self::WALLSEED),
        ("spine", Self::SPINE),
        ("exits", Self::EXITS),
        ("stalac", Self::STALAC),
        ("salts", Self::SALTS),
        ("privrng", Self::PRIVRNG),
        ("bubble", Self::BUBBLE),
        ("keepy", Self::KEEPY),
        ("beam", Self::BEAM),
        ("updraft", Self::UPDRAFT),
        ("boss", Self::BOSS),
    ];
}

/// (taps, cost, the sim at the line's end).
type Found = (Vec<u8>, i64, Option<Box<GameSim>>);

struct Node {
    sim: Box<GameSim>,
    parent: i32,
    tap: u8,
    cost: i64,
    /// Ticks since this line's last tap.
    since: i64,
}

pub struct BlindPlanner {
    /// Ticks looked ahead at most, and at most `past` ticks past the next bounce.
    pub horizon: i64,
    pub past: i64,
    /// Ticks between looks when the last look was calm, and when it was not.
    pub replan: i32,
    pub replan_danger: i32,
    /// Guessed futures per look, lines compared per look, and the tap timing error.
    pub copies: i32,
    pub lines: i32,
    pub wobble: i32,
    /// Lines differ when they part within this many ticks.
    pub part: i32,
    /// Cost per tick of each px away from the middle height, and per tap (px).
    pub mid_cost: i64,
    pub tap_cost: i64,
    /// Extra cost per tick while a bird `margin` px higher or lower would die (0 = not checked).
    pub margin: i64,
    pub margin_cost: i64,
    /// The margin also counts the spikes of the wall ahead, the ceiling and the floor.
    pub spike_margin: bool,
    /// Lines never tap twice within `min_gap` ticks (0 = off). `last_press`: set by the caller.
    pub min_gap: i64,
    pub last_press: i64,
    /// One-sided stalactite fangs re-aim at every bounce (0, 1 or 2; see C#).
    pub worst_fangs: i32,
    pub wall_look: bool,
    pub full_speeds: bool,
    pub aim_anchor: bool,
    pub wall_looks: i64,
    pub no_pingpong: bool,
    pub keep_plan: bool,
    pub bounce_look: bool,
    pub wide_key: bool,
    pub aim_exit: bool,
    pub kept_plans: i64,
    /// Buckets: one survivor per height (px) and speed bucket; the finer set is tried when the first finds no line.
    pub bucket_px: i64,
    pub speed_buckets: i64,
    pub fine_px: i64,
    pub fine_speeds: i64,
    /// Measuring only (Human/Atlas): bits of `Reveal` left as they truly are in the copy.
    pub reveal: i32,
    /// Boss rooms: the tell on screen is not taken in yet (set by the human layer), so a guess too.
    pub boss_unseen: bool,
    /// Measuring only: this planner's copies keep the true boss seed.
    pub boss_leak: bool,
    /// Honesty (research/planner-review/01-honesty.md): the copy's anchor_y is the planner's
    /// own, tracked from the walls it bounced off and the exit it took, never state.anchor_y.
    pub own_anchor: bool,
    pub anchor: i64,
    _seen_room: i64,
    _last_y: i64,
    /// Tests: the memory was set by hand, don't update it from this tick's events.
    pub skip_observe: bool,
    _last_open: bool,
    _last_a: i64,
    _last_b: i64,
    _last_b_kind: i64,
    _last_drawn: [i64; 2],

    _own: SimRng,
    _plan: VecDeque<bool>,
    _since: i32,
    _wait: i32,
    _bounce_y: i64,
    _vx: i64,
    _found: Vec<Found>,
    /// Spare sims for the beam's copies (Rust only: copies reuse their buffers; no effect on play).
    _pool: Vec<Box<GameSim>>,
    /// The last look's first guessed-future seed and the plan it left (read by the autopsy).
    pub last_seed0: i64,
    /// The anchor the last look's copies used (-1 = the room's own).
    pub last_anchor: i64,
    pub last_plan: Vec<bool>,
    /// How the last look ended: 0 = a line for the whole look, 1 = only with fine buckets, 2 = only a shorter look, 3 = none.
    pub last_look: i32,
    /// In how many of the guessed futures the played line lived (of `copies`).
    pub last_agree: i32,
    pub looks: i64,
    pub fine_looks: i64,
    pub short_looks: i64,
    pub no_looks: i64,
    pub split_looks: i64,
}

impl BlindPlanner {
    pub fn new(seed: i64) -> BlindPlanner {
        BlindPlanner {
            horizon: 200,
            past: 110,
            replan: 4,
            replan_danger: 1,
            copies: 1,
            lines: 1,
            wobble: 0,
            part: 16,
            mid_cost: 1,
            tap_cost: 0,
            margin: 16,
            margin_cost: 2000,
            spike_margin: true,
            min_gap: 0,
            last_press: -1000,
            worst_fangs: 2,
            wall_look: true,
            full_speeds: false,
            aim_anchor: false,
            wall_looks: 0,
            no_pingpong: true,
            keep_plan: true,
            bounce_look: true,
            wide_key: false,
            aim_exit: true,
            kept_plans: 0,
            bucket_px: 8,
            speed_buckets: 6,
            fine_px: 3,
            fine_speeds: 12,
            reveal: 0,
            boss_unseen: false,
            boss_leak: false,
            own_anchor: true,
            anchor: SimConfig::BIRD_START_Y,
            _seen_room: 0,
            _last_y: 0,
            skip_observe: false,
            _last_open: false,
            _last_a: 0,
            _last_b: 0,
            _last_b_kind: 0,
            _last_drawn: [0, 0],
            _own: SimRng::new(977 * seed + 5),
            _plan: VecDeque::new(),
            _since: i32::MAX,
            _wait: 1,
            _bounce_y: -1,
            _vx: 0,
            _found: Vec::new(),
            _pool: Vec::new(),
            last_seed0: 0,
            last_anchor: -1,
            last_plan: Vec::new(),
            last_look: 0,
            last_agree: 0,
            looks: 0,
            fine_looks: 0,
            short_looks: 0,
            no_looks: 0,
            split_looks: 0,
        }
    }

    /// The taps planned for the next ticks (read only).
    pub fn plan(&self) -> &VecDeque<bool> {
        &self._plan
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

    /// GameSim._anchor_at_wall without the pull to the planned exit.
    pub fn anchor_after(mask: i64, anchor: i64) -> i64 {
        let mut best = anchor;
        let mut best_d = -1;
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
            let y = anchor.clamp(SimConfig::slot_center_y(lo), SimConfig::slot_center_y(slot));
            let d = (y - anchor).abs();
            if best_d < 0 || d < best_d {
                best = y;
                best_d = d;
            }
            slot += 1;
        }
        best
    }

    /// Called once per tick before the tap: what the player saw happen in the last tick.
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
            self.anchor = Self::anchor_after(self._last_drawn[if s.vx > 0 { 0 } else { 1 }], self.anchor);
        }
        self._last_y = s.y;
        self._last_drawn[0] = Self::drawn(s, 0);
        self._last_drawn[1] = Self::drawn(s, 1);
        self._last_open = s.exit_open;
        self._last_a = s.exit_a_y;
        self._last_b = s.exit_b_y;
        self._last_b_kind = s.exit_b_kind;
    }

    pub fn decide(&mut self, sim: &GameSim) -> bool {
        if !self.skip_observe {
            self.observe(sim);
        }
        if !sim.state.started {
            return true;
        }
        // The height at the last bounce: a player remembers it (stalactite gaps slide to it).
        if sim.state.vx != self._vx {
            if self._vx != 0 {
                self._bounce_y = sim.state.y;
            }
            if self._vx != 0 && self.bounce_look {
                self._since = i32::MAX;
            }
            self._vx = sim.state.vx;
        }
        if self._since >= self._wait || self._plan.is_empty() {
            let p0 = sim::prof::enter(sim::prof::LOOK);
            self.look(sim);
            self.last_plan = self._plan.iter().copied().collect();
            sim::prof::leave(p0);
        }
        self._since = self._since.wrapping_add(1);
        let tap = !self._plan.is_empty() && self._plan.pop_front().unwrap();
        // The sim ignores taps during the wait out of a portal: don't make them.
        tap && sim.state.arrival_hold == 0
    }

    fn copy(&self, sim: &GameSim, seed: i64) -> GameSim {
        let p0 = sim::prof::enter(sim::prof::BLIND);
        let c = Self::blind_copy(
            sim,
            SimRng::new(seed),
            self._bounce_y,
            self.reveal,
            if self.own_anchor { self.anchor } else { -1 },
            self.boss_unseen,
            self.boss_leak,
        );
        sim::prof::leave(p0);
        c
    }

    fn look(&mut self, sim: &GameSim) {
        let heading = if sim.state.vx > 0 { 1 } else { 0 };
        let want = self.horizon.min(sim.steps_to_wall(heading) + self.past);
        self.looks += 1;
        self.last_look = 0;
        let n = self.copies.max(1);
        let mut seeds = vec![0i64; n as usize];
        for j in 0..n as usize {
            seeds[j] = self._own.next_u32();
        }
        let to_wall = sim.steps_to_wall(heading);
        self.last_seed0 = seeds[0];
        self.last_anchor = if self.own_anchor { self.anchor } else { -1 };
        // Lines from the first guessed future (fine buckets when the coarse ones find none).
        let c0 = self.copy(sim, seeds[0]);
        self.beam(c0, want, self.bucket_px, self.speed_buckets);
        if self._found.is_empty() && self.fine_px > 0 {
            self.last_look = 1;
            self.fine_looks += 1;
            let c0 = self.copy(sim, seeds[0]);
            self.beam(c0, want, self.fine_px, self.fine_speeds);
        }
        let mut found: Option<Vec<u8>> = None;
        self.last_agree = 0;
        let trials = n * (1 + 2 * if self.wobble > 0 { 1 } else { 0 });
        if !self._found.is_empty() && trials == 1 {
            found = Some(self._found[0].0.clone());
            self.last_agree = 1;
        } else if !self._found.is_empty() {
            let mut best_cost = 0;
            let list: Vec<(Vec<u8>, i64)> = self._found.iter().map(|f| (f.0.clone(), f.1)).collect();
            for (taps, cost) in list {
                let mut ok = 0;
                for j in 0..n as usize {
                    for w in -1..=1 {
                        if w != 0 && self.wobble == 0 {
                            continue;
                        }
                        let mut c = self.copy(sim, seeds[j]);
                        if Self::lives(&mut c, &taps, w * self.wobble) {
                            ok += 1;
                        }
                    }
                }
                if found.is_none() || ok > self.last_agree || (ok == self.last_agree && cost < best_cost) {
                    found = Some(taps);
                    self.last_agree = ok;
                    best_cost = cost;
                }
            }
        }
        if found.is_none() && self.keep_plan && self._plan.len() >= 8 {
            let rest: Vec<u8> = self._plan.iter().map(|&b| b as u8).collect();
            let mut c = self.copy(sim, seeds[0]);
            if Self::lives(&mut c, &rest, 0) {
                self.kept_plans += 1;
                self.last_look = 2;
                self.short_looks += 1;
                self._wait = self.replan_danger;
                self._since = 0;
                return;
            }
        }
        if found.is_none() && self.wall_look && to_wall + 26 < want {
            for (px, sp) in [(self.bucket_px, self.speed_buckets), (self.fine_px, self.fine_speeds), (2, 40)] {
                let c0 = self.copy(sim, seeds[0]);
                self.beam(c0, to_wall + 26, px, sp);
                if self._found.is_empty() {
                    continue;
                }
                found = Some(self._found[0].0.clone());
                self.last_look = 2;
                self.wall_looks += 1;
                break;
            }
        }
        let mut t = want * 3 / 4;
        while t >= 2 && found.is_none() {
            self.last_look = 2;
            let c0 = self.copy(sim, seeds[0]);
            self.beam(c0, t, self.bucket_px, self.speed_buckets);
            if self._found.is_empty() && self.fine_px > 0 && self.keep_plan {
                let c0 = self.copy(sim, seeds[0]);
                self.beam(c0, t, self.fine_px, self.fine_speeds);
            }
            if !self._found.is_empty() {
                found = Some(self._found[0].0.clone());
            }
            t = t * 3 / 4;
        }
        if self.last_look == 2 {
            self.short_looks += 1;
        }
        if found.is_none() {
            self.last_look = 3;
            self.no_looks += 1;
        }
        let danger = self.last_look != 0 || self.last_agree < trials;
        if self.last_look == 0 && self.last_agree < trials {
            self.split_looks += 1;
        }
        self._wait = if danger { self.replan_danger } else { self.replan };
        self._plan.clear();
        if let Some(found) = found {
            for b in found {
                self._plan.push_back(b != 0);
            }
        }
        self._since = 0;
    }

    /// After a bounce in a copy: one-sided fangs aim as far out as their rule
    /// allows (within REACH of the anchor for the column met first, MAX_STEP
    /// past that for the other when `both`).
    fn fangs_out(c: &mut GameSim, both: bool) {
        let mut cols: Vec<usize> = Vec::new();
        for (i, hz) in c.room.hazards.iter().enumerate() {
            if let Hz::Stalactite(st) = hz {
                if st.fixed_lo < 0 && st.top != st.bottom {
                    cols.push(i);
                }
            }
        }
        if cols.is_empty() {
            return;
        }
        let right = c.state.vx > 0;
        let x_of = |c: &GameSim, i: usize| match &c.room.hazards[i] {
            Hz::Stalactite(st) => st.x,
            _ => unreachable!(),
        };
        cols.sort_by(|&p, &q| if right { x_of(c, p).cmp(&x_of(c, q)) } else { x_of(c, q).cmp(&x_of(c, p)) });
        let mut center = c.state.anchor_y;
        let mut spread = Stalactite::REACH;
        for (i, &idx) in cols.iter().enumerate() {
            if let Hz::Stalactite(st) = &mut c.room.hazards[idx] {
                if i == 0 || both {
                    st.target_y = if st.bottom {
                        Stalactite::GAP_MIN.max(center - spread)
                    } else {
                        Stalactite::GAP_MAX.min(center + spread)
                    };
                }
                center = st.target_y;
                spread = Stalactite::MAX_STEP;
            }
        }
    }

    /// Whether the bird lives through `taps` on `c`, with every tap `shift` ticks late (early if negative).
    pub fn lives(c: &mut GameSim, taps: &[u8], shift: i32) -> bool {
        let n = taps.len() as i32;
        for t in 0..n {
            let from = t - shift;
            c.step(from >= 0 && from < n && taps[from as usize] != 0);
            if c.is_over() {
                return false;
            }
        }
        true
    }

    /// A copy of `sim` with every hidden random value replaced by `own`'s.
    /// `bounce_y`: the bird's height at its last bounce if the player saw it (-1 = not).
    /// `own_anchor`: the planner's own room anchor, tracked from walls it saw (-1 = keep the copy's).
    /// `boss_unseen`: the boss tell on screen is not taken in yet (a guess too); `boss_leak`: keep the true boss seed.
    #[allow(clippy::too_many_arguments)]
    pub fn blind_copy(
        sim: &GameSim,
        mut own: SimRng,
        bounce_y: i64,
        reveal: i32,
        own_anchor: i64,
        boss_unseen: bool,
        boss_leak: bool,
    ) -> GameSim {
        let mut c = sim.clone_deep();
        c.memo_arrivals = true;
        if KNOW_ALL.load(Ordering::Relaxed) {
            return c;
        }
        if own_anchor >= 0 {
            c.state.anchor_y = own_anchor;
        }
        // The run's seed and the room as entered (kept for a revive, with both RNGs) hold the
        // true draws. A look never revives: the copy does not carry them.
        c.seed_value = 0;
        c._entry_room = None;
        c._entry_state = None;
        c._entry_rng = SimRng::default();
        c._entry_spine = SimRng::default();
        let true_seed = c.room.rng_seed;
        let r = |bit: i32| (reveal & bit) != 0;
        {
            let x = own.next_u32();
            if !r(Reveal::RNG) {
                c._rng = SimRng::new(x);
            }
        }
        // Seed-only generation: each wall reseeds from the room's seed, the
        // spine picks the next rooms, and the exits are planned from the room's
        // seed at room start. All three are hidden: replace them and plan again.
        {
            let x = own.next_u32();
            if !r(Reveal::WALLSEED) {
                c.room.rng_seed = x;
            }
        }
        {
            let x = own.next_u32();
            if !r(Reveal::SPINE) {
                c._spine = SimRng::new(x);
            }
        }
        if KNOW_WALLS.load(Ordering::Relaxed) {
            c.room.rng_seed = true_seed;
        }
        if c.state.plan_at != 0 && !KNOW_EXITS.load(Ordering::Relaxed) && !r(Reveal::EXITS) {
            let at = c.state.plan_at;
            ExitPlanner::plan_room(&mut c, at);
        }
        // Sliding stalactite gaps (the room's rule, which a player learns). The
        // room slides them to state.anchor_y on seed-only generation, so that is used.
        let _ = bounce_y;
        let bounce_y = c.state.anchor_y;
        if bounce_y >= 0 && !r(Reveal::STALAC) {
            let mut cols: Vec<usize> = Vec::new();
            for (i, hz) in c.room.hazards.iter().enumerate() {
                if let Hz::Stalactite(st) = hz {
                    if st.fixed_lo < 0 {
                        cols.push(i);
                    }
                }
            }
            let right = c.state.vx > 0;
            let x_of = |c: &GameSim, i: usize| match &c.room.hazards[i] {
                Hz::Stalactite(st) => st.x,
                _ => unreachable!(),
            };
            cols.sort_by(|&p, &q| if right { x_of(&c, p).cmp(&x_of(&c, q)) } else { x_of(&c, q).cmp(&x_of(&c, p)) });
            let mut center = bounce_y;
            let mut spread = Stalactite::REACH;
            for &idx in &cols {
                if let Hz::Stalactite(st) = &mut c.room.hazards[idx] {
                    if st.gap_y != st.target_y {
                        let mut lo = Stalactite::GAP_MIN.max(center - spread);
                        let mut hi = Stalactite::GAP_MAX.min(center + spread);
                        // Only the side it is seen sliding to.
                        if st.target_y > st.gap_y {
                            lo = lo.max(st.gap_y + 1);
                        } else {
                            hi = hi.min(st.gap_y - 1);
                        }
                        // A fang from one side only: the worst case (its tip as far out as it may go).
                        if lo > hi {
                            st.target_y = st.gap_y
                                + (if st.target_y > st.gap_y { 1 } else { -1 })
                                    * own.next_below(Stalactite::SLIDE * 8 + 1);
                        } else if st.bottom && !st.top {
                            st.target_y = lo;
                        } else if st.top && !st.bottom {
                            st.target_y = hi;
                        } else {
                            st.target_y = lo + own.next_below(hi - lo + 1);
                        }
                    }
                    center = st.target_y;
                    spread = Stalactite::MAX_STEP;
                }
            }
        }
        // Values the sim has already drawn but not yet shown. A value that is
        // on screen (a warning, a marked column, a moving thing) stays.
        let room_t = c.room.t;
        let boss_blind = BOSS_BLIND.load(Ordering::Relaxed);
        let hide_keys = HIDE_KEYS.load(Ordering::Relaxed);
        for hz in c.room.hazards.iter_mut() {
            let kind = match hz {
                Hz::CrateDrop(_) | Hz::Dart(_) => Reveal::SALTS,
                Hz::Drop(_) | Hz::Firework(_) | Hz::OrchardSpawner(_) => Reveal::PRIVRNG,
                Hz::Bubble(_) => Reveal::BUBBLE,
                Hz::Stalactite(_) => Reveal::STALAC,
                Hz::KeepyBall(_) => Reveal::KEEPY,
                Hz::Beam(_) => Reveal::BEAM,
                Hz::Updraft(_) => Reveal::UPDRAFT,
                Hz::BossCrusher(_) | Hz::BossSaw(_) | Hz::BossWatcher(_) => Reveal::BOSS,
                _ => 0,
            };
            if kind != 0 && r(kind) {
                continue;
            }
            if hz.as_boss().is_some() && boss_blind && !boss_leak {
                BossBlind::scramble(hz, &mut own, boss_unseen);
            }
            match hz {
                // Hash salts and private RNGs: where every later crate, dart, drop, rocket and coin goes.
                Hz::CrateDrop(cd) => cd.salt = own.next_u32(),
                Hz::Dart(d) => d.salt = own.next_u32(),
                Hz::Drop(dr) => dr._rng.reseed(own.next_u32()),
                Hz::Firework(fw) => fw._rng.reseed(own.next_u32()),
                Hz::OrchardSpawner(os) => os._rng.reseed(own.next_u32()),
                // Where the bubble comes back after its next pop.
                Hz::Bubble(b) => {
                    b.next_x = Bubble::MIN_X + own.next_below(Bubble::MAX_X - Bubble::MIN_X + 1);
                    // A late spiky bubble under the floor: its glow is under half size until 3 * WARN ticks before it rises.
                    if b.spiked && b.wait > 3 * Bubble::WARN {
                        b.x = Bubble::MIN_X + own.next_below(Bubble::MAX_X - Bubble::MIN_X + 1);
                    }
                }
                // Where a sliding gap stops: the side it slides to is visible, how far is not.
                Hz::Stalactite(st) if st.gap_y != st.target_y && (bounce_y < 0 || st.fixed_lo >= 0) => {
                    let far = own.next_below(Stalactite::REACH + Stalactite::MAX_STEP + 1);
                    let to = st.gap_y + if st.target_y > st.gap_y { far } else { -far };
                    st.target_y = G::clampi(to, Stalactite::GAP_MIN, Stalactite::GAP_MAX);
                }
                // A key chain: where each later key appears is drawn at the room's start.
                Hz::ExitKey(ek) if hide_keys && ek.mode == sim::hazards::exit_key::Mode::CHAIN => {
                    for i in ek.got + 1..ek.count {
                        ek.chain_off[i as usize] =
                            ExitKey::KEY_OFF_MIN + own.next_below(ExitKey::CHAIN_OFF_MAX - ExitKey::KEY_OFF_MIN + 1);
                        ek.chain_d[i as usize] =
                            ExitKey::CHAIN_D_MIN + own.next_below(ExitKey::CHAIN_D_MAX - ExitKey::CHAIN_D_MIN + 1);
                    }
                }
                // The second ball's column before it drops in.
                Hz::KeepyBall(kb) if kb.waiting > 0 && room_t < KeepyBall::SECOND_DROP => {
                    kb.x = KeepyBall::MIN_X + own.next_below(KeepyBall::MAX_X - KeepyBall::MIN_X + 1);
                }
                // The order rows fire in, among rows that have not warned yet.
                Hz::Beam(bm) => {
                    let t = bm.base.t;
                    let mut idle: Vec<usize> = Vec::new();
                    for i in 0..bm.delays.len() {
                        if t < bm.delays[i] {
                            idle.push(i);
                        }
                    }
                    // Sorted first, so the result does not depend on the true order.
                    let mut waits: Vec<i64> = idle.iter().map(|&i| bm.delays[i]).collect();
                    waits.sort();
                    for i in 0..idle.len() {
                        bm.delays[idle[i]] = waits[i];
                    }
                    let mut i = idle.len();
                    while i > 1 {
                        i -= 1;
                        let j = own.next_below(i as i64 + 1) as usize;
                        bm.delays.swap(idle[i], idle[j]);
                    }
                }
                // A gusty updraft's first gust: no countdown is shown.
                Hz::Updraft(up)
                    if up.drift_span == 0
                        && up.gust != sim::hazards::updraft::Gust::NONE
                        && up.base.t + up.phase < Updraft::GUST_OFF =>
                {
                    up.phase = own.next_below(Updraft::GUST_OFF - up.base.t);
                }
                _ => {}
            }
        }
        c
    }

    /// Fills `_found` with up to `lines` lines that live `ticks` ticks,
    /// cheapest first: the cheapest of each family of lines that share their first `part` ticks.
    /// With `by_band` > 0: the cheapest line per `by_band` px of end height instead.
    /// With `any`: stops at the first line found (only "is there one").
    fn beam(&mut self, root: GameSim, ticks: i64, bpx: i64, speeds: i64) {
        let p0 = sim::prof::enter(sim::prof::BEAM);
        self.beam_(root, ticks, bpx, speeds);
        sim::prof::leave(p0);
    }

    fn beam_(&mut self, root: GameSim, ticks: i64, bpx: i64, speeds: i64) {
        self._found.clear();
        let mut layer: Vec<usize> = Vec::new();
        let bh = bpx * SimConfig::SUB;
        let bvy = if self.full_speeds {
            (SimConfig::MAX_FALL_VY - SimConfig::FLAP_VY) / speeds + 1
        } else {
            -SimConfig::FLAP_VY * 2 / speeds
        };
        let mut mid = (SimConfig::KILL_TOP + SimConfig::KILL_BOTTOM) / 2;
        let exit_shown = root.state.exit_open || root.state.exit_preview;
        if self.aim_exit && exit_shown {
            mid = root.state.exit_a_y;
        } else if self.aim_anchor {
            mid = root.state.anchor_y;
        }
        let mut parents: Vec<i32> = Vec::new();
        let mut taps: Vec<u8> = Vec::new();
        let since0 = root.state.tick - self.last_press;
        let mut pool = std::mem::take(&mut self._pool);
        let mut frontier: Vec<Node> = vec![Node { sim: Box::new(root), parent: -1, tap: 0, cost: 0, since: since0 }];
        let mut slots: FxMap<i64, usize> = FxMap::default();
        let mut next: Vec<Node> = Vec::new();
        for _t in 0..ticks {
            slots.clear();
            next.clear();
            for e in frontier.drain(..) {
                let can_tap = e.sim.state.vy * e.sim.room.gravity > SurvivalSearch::TAP_BELOW_VY
                    && (self.min_gap <= 0 || e.since >= self.min_gap);
                let vx0 = e.sim.state.vx;
                let room0 = e.sim.state.room_index;
                let e_open = e.sim.state.exit_open;
                let mut wait_sim = Some(e.sim);
                let a_from: i64 = if can_tap { 1 } else { 0 };
                for a in (0..=a_from).rev() {
                    let q0 = sim::prof::enter(sim::prof::CLONE);
                    let mut s = if a == 1 {
                        let src = wait_sim.as_ref().unwrap();
                        let c = match pool.pop() {
                            Some(mut b) => {
                                src.copy_into(&mut b);
                                b
                            }
                            None => Box::new(src.clone_deep()),
                        };
                        c
                    } else {
                        wait_sim.take().unwrap()
                    };
                    sim::prof::leave(q0);
                    let q0 = sim::prof::enter(sim::prof::STEP);
                    s.step(a == 1);
                    sim::prof::leave(q0);
                    if s.is_over() {
                        pool.push(s);
                        continue;
                    }
                    // The exit opened on the wall the bird just bounced off, at a height nobody has seen.
                    if self.no_pingpong
                        && !exit_shown
                        && s.state.exit_open
                        && !e_open
                        && s.state.exit_side == (if s.state.vx > 0 { 0 } else { 1 })
                    {
                        pool.push(s);
                        continue;
                    }
                    let q2 = sim::prof::enter(sim::prof::KEEP);
                    let st = &s.state;
                    let along = st.vy * s.room.gravity - SimConfig::FLAP_VY;
                    let speed = G::clampi(along / bvy, 0, speeds - 1);
                    let mut key = (st.room_index * 1000 + st.y / bh) * speeds + speed;
                    if self.wide_key {
                        key = (key * 64 + st.x / (16 * SimConfig::SUB)) * 2 + if st.vx > 0 { 1 } else { 0 };
                    }
                    let mut cost = e.cost + G::absi(st.y - mid) / SimConfig::SUB * self.mid_cost + a * self.tap_cost;
                    let held = slots.get(&key).copied();
                    // Rust only, exact: the margin only adds cost, so a line that already costs no
                    // less than the one holding its bucket loses either way; skip its fang re-aim
                    // and near-death look (neither changes the key or the outcome).
                    if let Some(at) = held {
                        if self.margin_cost >= 0 && cost >= next[at].cost {
                            pool.push(s);
                            sim::prof::leave(q2);
                            continue;
                        }
                    }
                    sim::prof::leave(q2);
                    if self.worst_fangs > 0 && (s.state.vx != vx0 || s.state.room_index != room0) {
                        Self::fangs_out(&mut s, self.worst_fangs > 1);
                    }
                    let q1 = sim::prof::enter(sim::prof::NEAR);
                    let near = self.margin > 0 && self.near_death(&mut s);
                    sim::prof::leave(q1);
                    if near {
                        cost += self.margin_cost;
                    }
                    let q2 = sim::prof::enter(sim::prof::KEEP);
                    let since = if a == 1 { 1 } else { e.since + 1 };
                    let node = Node { sim: s, parent: e.parent, tap: a as u8, cost, since };
                    if let Some(at) = held {
                        if cost < next[at].cost {
                            let old = std::mem::replace(&mut next[at], node);
                            pool.push(old.sim);
                        } else {
                            pool.push(node.sim);
                        }
                    } else {
                        slots.insert(key, next.len());
                        next.push(node);
                    }
                    sim::prof::leave(q2);
                }
            }
            if next.is_empty() {
                self._pool = pool;
                return;
            }
            layer.push(parents.len());
            for e in next.drain(..) {
                parents.push(e.parent);
                taps.push(e.tap);
                frontier.push(Node { sim: e.sim, parent: parents.len() as i32 - 1, tap: 0, cost: e.cost, since: e.since });
            }
        }
        // The family of a line: its node `part` ticks in.
        let depth = (self.part as i64).min(ticks) - 1;
        let family_end =
            if ((depth + 1) as usize) < layer.len() { layer[(depth + 1) as usize] as i32 } else { parents.len() as i32 };
        let room = frontier.iter().map(|e| e.sim.state.room_index).max().unwrap();
        // C# Dictionary<int, Node>: values in first-insertion order.
        let mut best_at: FxMap<i32, usize> = FxMap::default();
        let mut best: Vec<usize> = Vec::new();
        for (i, e) in frontier.iter().enumerate() {
            if e.sim.state.room_index != room {
                continue;
            }
            let mut f = e.parent;
            while f >= family_end {
                f = parents[f as usize];
            }
            match best_at.get(&f) {
                Some(&slot) => {
                    if e.cost < frontier[best[slot]].cost {
                        best[slot] = i;
                    }
                }
                None => {
                    best_at.insert(f, best.len());
                    best.push(i);
                }
            }
        }
        // OrderBy is stable.
        best.sort_by_key(|&i| frontier[i].cost);
        best.truncate(self.lines.max(1) as usize);
        let heads: Vec<(i32, i64)> = best.iter().map(|&i| (frontier[i].parent, frontier[i].cost)).collect();
        let mut sims: Vec<Option<Box<GameSim>>> = frontier.into_iter().map(|e| Some(e.sim)).collect();
        for (k, &i) in best.iter().enumerate() {
            let (parent, cost) = heads[k];
            let mut out_ = Vec::new();
            // A frontier node's `parent` is its own node (as in C#).
            let mut nd = parent;
            while nd >= 0 {
                out_.push(taps[nd as usize]);
                nd = parents[nd as usize];
            }
            out_.reverse();
            self._found.push((out_, cost, sims[i].take()));
        }
        pool.extend(sims.into_iter().flatten());
        pool.truncate(4096);
        self._pool = pool;
    }

    fn near_spikes(s: &GameSim, y: i64, m: i64) -> bool {
        let st = &s.state;
        let r = SimConfig::BIRD_RADIUS;
        if y - m - r <= SimConfig::KILL_TOP || y + m + r >= SimConfig::KILL_BOTTOM {
            return true;
        }
        let side = if st.vx > 0 { 1 } else { 0 };
        let dist = (if side == 1 { s.room.wall_right() - st.x } else { st.x - s.room.wall_left() }) - r;
        if dist > s.room.max_spike_depth() {
            return false;
        }
        let mask = s.wall_mask(side);
        if mask == 0 {
            return false;
        }
        let shift = s.wall_shift(side);
        let hb = s.room.spike_half_base();
        Self::wall_hits(mask, shift, hb, y - m) || Self::wall_hits(mask, shift, hb, y + m)
    }

    /// RL/Observer.cs wall_hits.
    pub fn wall_hits(mask: i64, shift: i64, hb: i64, y: i64) -> bool {
        let r = SimConfig::BIRD_RADIUS;
        if y - r <= SimConfig::KILL_TOP || y + r >= SimConfig::KILL_BOTTOM {
            return true;
        }
        for slot in 0..SimConfig::SLOT_COUNT {
            if RoomRules::has_slot(mask, slot) && (y - SimConfig::slot_center_y(slot) - shift).abs() <= hb + r {
                return true;
            }
        }
        false
    }

    /// Whether a bird `margin` px above or below this one would be killed by a hazard now
    /// (or, with `spike_margin`, by the spikes of the wall ahead, the ceiling or the floor).
    fn near_death(&self, s: &mut GameSim) -> bool {
        let y = s.state.y;
        if self.spike_margin && Self::near_spikes(s, y, self.margin * SimConfig::SUB) {
            return true;
        }
        if s.room.hazards.is_empty() {
            return false;
        }
        let mut bad = false;
        let mut d = -1;
        while d <= 1 && !bad {
            s.state.y = y + d * self.margin * SimConfig::SUB;
            let mut h = 0;
            while h < s.room.hazards.len() && !bad {
                let hz = &s.room.hazards[h];
                if hz.alive() && hz.kills(s) {
                    bad = true;
                }
                h += 1;
            }
            d += 2;
        }
        s.state.y = y;
        bad
    }
}
