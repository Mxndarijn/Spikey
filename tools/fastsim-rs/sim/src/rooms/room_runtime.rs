//! Port of sim/rooms/room_runtime.gd (Sim/Rooms/RoomRuntime.cs).
//! `start` and `step` need the sim and the room at once, so they live on
//! GameSim (`GameSim::room_start`, `GameSim::room_step`), line for line.
use crate::g::G;
use crate::hazards::{CoinPickup, Hz};
use crate::rooms::hazard::mix_all;
use crate::rooms::room_def::{RoomDef, RoomVariant, Speed, Squeeze, WallMode};
use crate::rooms::room_rules::RoomRules;
use crate::sim_config::SimConfig;
use crate::sim_math::SimHash;
use crate::sim_rng::SimRng;
use crate::sim_trig::SimTrig;

pub struct RoomRuntime {
    pub def_: Option<&'static RoomDef>,
    pub index: i64,
    pub t: i64,
    pub ticks: i64,
    pub points: i64,
    pub variant: i64,
    pub hazards: Vec<Hz>,
    pub tide_left: i64,
    pub tide_right: i64,
    pub tide_salt_left: i64,
    pub tide_salt_right: i64,
    pub blink_left: i64,
    pub blink_right: i64,
    pub gravity: i64,
    pub rng_seed: i64,
    pub walls: i64,
    pub entry_score: i64,
}

impl Clone for RoomRuntime {
    fn clone(&self) -> Self {
        let mut c = RoomRuntime { hazards: Vec::with_capacity(self.hazards.len()), ..RoomRuntime::default() };
        c.copy_fields(self);
        c.hazards.extend(self.hazards.iter().cloned());
        c
    }

    /// Reuses the hazard list's buffer (planner copies).
    fn clone_from(&mut self, src: &Self) {
        self.copy_fields(src);
        self.hazards.clone_from(&src.hazards);
    }
}

impl RoomRuntime {
    /// Every field but the hazards.
    #[inline]
    fn copy_fields(&mut self, o: &RoomRuntime) {
        self.def_ = o.def_;
        self.index = o.index;
        self.t = o.t;
        self.ticks = o.ticks;
        self.points = o.points;
        self.variant = o.variant;
        self.tide_left = o.tide_left;
        self.tide_right = o.tide_right;
        self.tide_salt_left = o.tide_salt_left;
        self.tide_salt_right = o.tide_salt_right;
        self.blink_left = o.blink_left;
        self.blink_right = o.blink_right;
        self.gravity = o.gravity;
        self.rng_seed = o.rng_seed;
        self.walls = o.walls;
        self.entry_score = o.entry_score;
    }
}

impl Default for RoomRuntime {
    fn default() -> Self {
        RoomRuntime {
            def_: None,
            index: 0,
            t: 0,
            ticks: 0,
            points: 0,
            variant: 0,
            hazards: Vec::new(),
            tide_left: 0,
            tide_right: 0,
            tide_salt_left: 0,
            tide_salt_right: 0,
            blink_left: 0,
            blink_right: 0,
            gravity: 1,
            rng_seed: 0,
            walls: 0,
            entry_score: 0,
        }
    }
}

impl RoomRuntime {
    pub const TIDE_PERIOD: i64 = 120;
    pub const INSET_SPEED: i64 = 2 * SimConfig::SUB;
    pub const BLINK_PERIOD: i64 = 60;
    pub const SQUEEZE_STEP: i64 = 6 * SimConfig::SUB;
    pub const SQUEEZE_MAX_POINTS: i64 = 10;
    pub const SQUEEZE_LEFT_STEP: i64 = 9 * SimConfig::SUB;
    pub const BREATHE_IN: i64 = 60 * SimConfig::SUB;
    pub const BREATHE_PERIOD: i64 = 360;

    /// `room.def` (C#: never null once the first room started).
    #[inline(always)]
    pub fn def(&self) -> &'static RoomDef {
        self.def_.expect("room not started")
    }

    pub fn clone_deep(&self) -> RoomRuntime {
        self.clone()
    }

    #[inline]
    pub fn steps_this_tick(&self) -> i64 {
        self.steps_at(self.ticks)
    }

    #[inline]
    pub fn steps_at(&self, tick: i64) -> i64 {
        let def = self.def();
        if def.speed == Speed::FAST {
            return if tick % 4 == 0 { 2 } else { 1 };
        }
        if def.speed == Speed::SLOW {
            return if tick % 2 == 0 { 1 } else { 0 };
        }
        1
    }

    pub fn inset(&self, side: i64) -> i64 {
        let def = self.def();
        let mut out_ = G::mini(self.t * Self::INSET_SPEED, def.inset);
        if def.squeeze {
            let squeezed = G::mini(self.points, Self::SQUEEZE_MAX_POINTS);
            let mut mode = Squeeze::POINTS;
            if !def.variants.is_empty() {
                mode = self._variant().squeeze;
            }
            if mode == Squeeze::LEFT {
                if side == 0 {
                    out_ += squeezed * Self::SQUEEZE_LEFT_STEP;
                }
            } else if mode == Squeeze::BREATHE {
                out_ += SimTrig::ping_pong(self.t, Self::BREATHE_PERIOD, Self::BREATHE_IN);
            } else {
                out_ += squeezed * Self::SQUEEZE_STEP;
            }
        }
        out_
    }

    #[inline]
    pub fn _variant(&self) -> &'static RoomVariant {
        &self.def().variants[self.variant as usize]
    }

    pub fn on_wall_bounce(&mut self) {
        if !self.def().variants.is_empty() && self._variant().flip_flop {
            self.gravity = -self.gravity;
        }
    }

    pub fn _variant_index(&self, id: &str, fallback: i64) -> i64 {
        let def = self.def();
        for i in 0..def.variants.len() {
            if def.variants[i].id == id {
                return i as i64;
            }
        }
        fallback
    }

    pub fn variant_id(&self) -> &'static str {
        let def = self.def();
        if def.variants.is_empty() { "" } else { def.variants[self.variant as usize].id }
    }

    pub fn spike_depth(&self) -> i64 {
        let def = self.def();
        if def.variants.is_empty() {
            return SimConfig::SPIKE_DEPTH;
        }
        let v = &def.variants[self.variant as usize];
        SimConfig::SPIKE_DEPTH * v.spike_num / v.spike_den
    }

    pub fn spike_half_base(&self) -> i64 {
        let def = self.def();
        if def.variants.is_empty() {
            return SimConfig::SPIKE_HALF_BASE;
        }
        let v = &def.variants[self.variant as usize];
        G::mini(SimConfig::SPIKE_HALF_BASE * v.spike_num / v.spike_den, SimConfig::SLOT_SIZE / 2)
    }

    pub fn tide_max_depth(&self) -> i64 {
        if self.def().variants.is_empty() {
            return self.spike_depth() * 3 / 2;
        }
        let v = self._variant();
        self.spike_depth() * v.tide_num / v.tide_den
    }

    pub fn max_spike_depth(&self) -> i64 {
        if self.def().wall_mode == WallMode::TIDE { self.tide_max_depth() } else { self.spike_depth() }
    }

    pub fn spike_bonus(&self, side: i64) -> i64 {
        let def = self.def();
        let boss = if def.boss { SimConfig::boss_tier(self.entry_score) - 1 } else { 0 };
        if def.variants.is_empty() {
            return boss;
        }
        let v = self._variant();
        boss + v.extra_spikes + if side == 0 { v.lean } else { -v.lean }
    }

    #[inline]
    pub fn wall_left(&self) -> i64 {
        self.inset(0)
    }

    #[inline]
    pub fn wall_right(&self) -> i64 {
        SimConfig::WORLD_W - self.inset(1)
    }

    pub fn _blink_period(&self) -> i64 {
        if !self.def().variants.is_empty() && self._variant().blink_period > 0 {
            return self._variant().blink_period;
        }
        Self::BLINK_PERIOD
    }

    pub fn blink_showing_second(&self) -> bool {
        self.def().wall_mode == WallMode::BLINK && (self.t / self._blink_period()) % 2 == 1
    }

    pub fn wall_mask(&self, side: i64, base_mask: i64) -> i64 {
        if self.blink_showing_second() {
            return if side == 0 { self.blink_left } else { self.blink_right };
        }
        base_mask
    }

    pub fn slot_depth(&self, side: i64, slot: i64) -> i64 {
        if self.def().wall_mode != WallMode::TIDE {
            return self.spike_depth();
        }
        let moving = if side == 0 { self.tide_left } else { self.tide_right };
        if !RoomRules::has_slot(moving, slot) {
            return self.spike_depth();
        }
        let salt = if side == 0 { self.tide_salt_left } else { self.tide_salt_right };
        let phase = (slot * 29 + salt) % Self::TIDE_PERIOD;
        SimTrig::ping_pong(self.t + phase, Self::TIDE_PERIOD, self.tide_max_depth())
    }

    pub fn add_coin(&mut self, x: i64, y: i64) {
        let mut h: Hz = CoinPickup::new(x, y, 0).into();
        h.base_mut().t = self.t;
        h.base_mut().idx = self.hazards.len();
        self.hazards.push(h);
    }

    /// C# takes the sim for its score only.
    pub fn on_wall_generated(&mut self, side: i64, mask: i64, score: i64, rng: &mut SimRng) {
        let def = self.def();
        if def.wall_mode == WallMode::TIDE {
            let moving = rng.next_u32() & mask;
            let salt = rng.next_below(Self::TIDE_PERIOD);
            if side == 0 {
                self.tide_salt_left = salt;
                self.tide_left = moving;
            } else {
                self.tide_salt_right = salt;
                self.tide_right = moving;
            }
        } else if def.wall_mode == WallMode::BLINK {
            let mut second = RoomRules::generate_wall(rng, score, def, -1, 0, -1);
            if self._blink_period() != Self::BLINK_PERIOD {
                second &= !RoomRules::longest_gap_mask(mask);
            }
            if side == 0 {
                self.blink_left = second;
            } else {
                self.blink_right = second;
            }
        }
    }

    pub fn checksum(&self, h: i64) -> i64 {
        let mut out_ = mix_all(
            h,
            &[
                self.index,
                self.t,
                self.ticks,
                self.points,
                self.variant,
                self.tide_left,
                self.tide_right,
                self.tide_salt_left,
                self.tide_salt_right,
                self.blink_left,
                self.blink_right,
                self.gravity,
                self.rng_seed,
                self.walls,
                self.entry_score,
            ],
        );
        for hz in &self.hazards {
            out_ = SimHash::mix(out_, G::b(hz.alive()));
            out_ = hz.checksum(out_);
        }
        out_
    }
}
