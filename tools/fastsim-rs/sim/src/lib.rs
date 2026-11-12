//! The deterministic Flapjaw sim in Rust: a line-by-line port of sim/ (first
//! made from the C# FastSim, removed on 2026-11-12; the "Port of X.cs" notes
//! name the C# file each one came from). Integers only. Porting rules:
//! tools/fastsim-rs/PORTING.md.
#![allow(clippy::collapsible_else_if, clippy::needless_range_loop, clippy::new_without_default)]

pub mod arrival_check;
pub mod arrival_memo;
pub mod exit_planner;
pub mod exit_zone;
pub mod fair_lanes;
pub mod g;
pub mod game_sim;
pub mod hazards;
pub mod prof;
pub mod rooms;
pub mod sim_config;
pub mod sim_math;
pub mod sim_rng;
pub mod sim_state;
pub mod sim_trig;

/// Everything a hazard or catalog file needs: `use crate::prelude::*;`.
pub mod prelude {
    pub use crate::arrival_check::ArrivalCheck;
    pub use crate::exit_planner::ExitPlanner;
    pub use crate::exit_zone::ExitZone;
    pub use crate::fair_lanes::FairLanes;
    pub use crate::g::G;
    pub use crate::game_sim::{Event, GameSim};
    pub use crate::hazards::*;
    pub use crate::impl_base;
    pub use crate::rooms::hazard::{mix_all, Base, Hazard};
    pub use crate::rooms::room_catalog::RoomCatalog;
    pub use crate::rooms::room_def::{mk, Factory, RoomDef, RoomVariant, Speed, Squeeze, WallMode};
    pub use crate::rooms::room_rules::RoomRules;
    pub use crate::rooms::room_runtime::RoomRuntime;
    pub use crate::rooms::seasons::Seasons;
    pub use crate::sim_config::SimConfig;
    pub use crate::sim_math::{SimHash, SimMath};
    pub use crate::sim_rng::SimRng;
    pub use crate::sim_state::{DeathCause, ExitKind, SimState};
    pub use crate::sim_trig::SimTrig;
}
