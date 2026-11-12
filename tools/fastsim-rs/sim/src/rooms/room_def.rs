//! Port of sim/rooms/room_def.gd and room_variant.gd (Sim/Rooms/RoomDef.cs, RoomVariant.cs).
use crate::hazards::Hz;
use crate::rooms::room_pacing::RoomPacing;
use crate::rooms::seasons::Seasons;
use crate::sim_config::SimConfig;

/// A hazard factory (GDScript `func() -> Hazard`, C# `Func<Hazard>`).
pub type Factory = Box<dyn Fn() -> Hz + Send + Sync>;

/// `() => new Bouncer()` is `mk(|| Bouncer::new().into())`.
pub fn mk<F: Fn() -> Hz + Send + Sync + 'static>(f: F) -> Factory {
    Box::new(f)
}

/// A GENERATED variant's recipe (GDScript `func(p: VariantParams) -> void`): builds the layout
/// into the room with `p.add(sim, h)`, drawing from `sim._rng`.
pub type Recipe = Box<dyn Fn(&mut crate::game_sim::GameSim, &crate::rooms::variant_params::VariantParams) + Send + Sync>;

pub fn recipe<F: Fn(&mut crate::game_sim::GameSim, &crate::rooms::variant_params::VariantParams) + Send + Sync + 'static>(
    f: F,
) -> Recipe {
    Box::new(f)
}

/// RoomVariant.Kind.
pub struct Kind;
impl Kind {
    pub const STATIC: i64 = 0;
    pub const GENERATED: i64 = 1;
}

pub struct WallMode;
impl WallMode {
    pub const STATIC: i64 = 0;
    pub const TIDE: i64 = 1;
    pub const BLINK: i64 = 2;
}

pub struct Speed;
impl Speed {
    pub const NORMAL: i64 = 0;
    pub const FAST: i64 = 1;
    pub const SLOW: i64 = 2;
}

pub struct RoomDef {
    pub id: &'static str,
    pub group: &'static str,
    pub from_score: i64,
    pub arrival_skip: Vec<i64>,
    pub weight: i64,
    pub pace: Vec<i64>,
    pub season: i64,

    pub spikes: bool,
    pub extra_spikes: i64,
    pub gap: i64,
    pub max_spikes: i64,
    pub wall_mode: i64,
    pub squeeze: bool,
    pub inset: i64,
    pub reach: i64,

    pub gravity_sign: i64,
    pub speed: i64,
    pub bounce_coin: bool,
    pub bounce_coin_stacks: bool,
    pub boss: bool,

    pub hazards: Vec<Factory>,
    /// Each combo is a list of factories.
    pub combos: Vec<Vec<Factory>>,
    pub variants: Vec<RoomVariant>,
}

impl RoomDef {
    pub const CEILING_ARRIVAL: i64 = 170 * SimConfig::SUB;

    pub fn new(p_id: &'static str, p_group: &'static str, p_from: i64) -> RoomDef {
        RoomDef {
            id: p_id,
            group: p_group,
            from_score: p_from,
            arrival_skip: Vec::new(),
            weight: 10,
            pace: Vec::new(),
            season: Seasons::NONE,
            spikes: true,
            extra_spikes: 0,
            gap: 4,
            max_spikes: SimConfig::MAX_SPIKES,
            wall_mode: WallMode::STATIC,
            squeeze: false,
            inset: 0,
            reach: 0,
            gravity_sign: 1,
            speed: Speed::NORMAL,
            bounce_coin: true,
            bounce_coin_stacks: false,
            boss: false,
            hazards: Vec::new(),
            combos: Vec::new(),
            variants: Vec::new(),
        }
    }

    pub fn with(mut self, p_hazards: Vec<Factory>) -> RoomDef {
        self.hazards = p_hazards;
        self
    }

    pub fn weight_at(&self, score: i64) -> i64 {
        RoomPacing::weight(&self.pace, score)
    }

    pub fn fits_arrival(&self, y: i64) -> bool {
        let mut i = 0;
        while i < self.arrival_skip.len() {
            if y >= self.arrival_skip[i] && y < self.arrival_skip[i + 1] {
                return false;
            }
            i += 2;
        }
        self.variants.is_empty() || !self.arrival_variants(y).is_empty()
    }

    pub fn arrival_variants(&self, y: i64) -> Vec<i64> {
        let mut out_ = Vec::new();
        for i in 0..self.variants.len() {
            if self.variants[i].fits_arrival(y) {
                out_.push(i as i64);
            }
        }
        out_
    }

    pub fn skips_heights(&self) -> bool {
        if !self.arrival_skip.is_empty() {
            return true;
        }
        for v in &self.variants {
            if !v.arrival_skip.is_empty() {
                return true;
            }
        }
        false
    }
}

pub struct Squeeze;
impl Squeeze {
    pub const POINTS: i64 = 0;
    pub const LEFT: i64 = 1;
    pub const BREATHE: i64 = 2;
}

pub struct RoomVariant {
    pub id: &'static str,
    pub kind: i64,
    pub recipe: Option<Recipe>,
    pub avoid_touch: bool,
    pub hold_steps: i64,
    pub arrival_spread: i64,
    pub spike_num: i64,
    pub spike_den: i64,
    pub extra_spikes: i64,
    pub hazards: Vec<Factory>,
    pub arrival_skip: Vec<i64>,
    pub lean: i64,
    pub squeeze: i64,
    pub blink_period: i64,
    pub flip_flop: bool,
}

impl RoomVariant {
    pub fn new(p_id: &'static str) -> RoomVariant {
        RoomVariant {
            id: p_id,
            kind: Kind::STATIC,
            recipe: None,
            avoid_touch: false,
            hold_steps: 0,
            arrival_spread: 0,
            spike_num: 1,
            spike_den: 1,
            extra_spikes: 0,
            hazards: Vec::new(),
            arrival_skip: Vec::new(),
            lean: 0,
            squeeze: Squeeze::POINTS,
            blink_period: 0,
            flip_flop: false,
        }
    }

    pub fn sized(mut self, num: i64, den: i64, p_extra_spikes: i64) -> RoomVariant {
        self.spike_num = num;
        self.spike_den = den;
        self.extra_spikes = p_extra_spikes;
        self
    }

    pub fn with(mut self, p_hazards: Vec<Factory>) -> RoomVariant {
        self.hazards = p_hazards;
        self
    }

    pub const GENERATE_TRIES: i64 = 8;

    /// GD defaults: p_avoid_touch = false, p_hold_steps = 0.
    pub fn generated(mut self, p_recipe: Recipe, p_avoid_touch: bool, p_hold_steps: i64) -> RoomVariant {
        self.kind = Kind::GENERATED;
        self.recipe = Some(p_recipe);
        self.avoid_touch = p_avoid_touch;
        self.hold_steps = p_hold_steps;
        self
    }

    pub fn checked_within(mut self, p_spread: i64) -> RoomVariant {
        self.arrival_spread = p_spread;
        self
    }

    pub fn skipping(mut self, p_ranges: Vec<i64>) -> RoomVariant {
        self.arrival_skip = p_ranges;
        self
    }

    pub fn leaning(mut self, p_lean: i64) -> RoomVariant {
        self.lean = p_lean;
        self
    }

    pub fn squeezing(mut self, p_mode: i64) -> RoomVariant {
        self.squeeze = p_mode;
        self
    }

    pub fn blinking(mut self, p_period: i64) -> RoomVariant {
        self.blink_period = p_period;
        self
    }

    pub fn flipping(mut self) -> RoomVariant {
        self.flip_flop = true;
        self
    }

    pub fn fits_arrival(&self, y: i64) -> bool {
        let mut i = 0;
        while i < self.arrival_skip.len() {
            if y >= self.arrival_skip[i] && y < self.arrival_skip[i + 1] {
                return false;
            }
            i += 2;
        }
        true
    }
}
