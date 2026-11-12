//! Port of Checks.Setups (CheckSearches.cs, tests/support/bot_setups.gd) and
//! Reaction.arrival (Reaction.cs, ArrivalBench.arrival): the sims the checks
//! start from. Parity records runs from each, so they must stay equal.
use sim::prelude::*;

pub struct Setups;

impl Setups {
    pub const ENTRY_YS: [i64; 3] = [140 * SimConfig::SUB, 300 * SimConfig::SUB, 480 * SimConfig::SUB];

    /// `ExitPlanner.plan(sim, sim._rng, side, at)`: the sim's own RNG.
    pub fn plan_with_own_rng(sim: &mut GameSim, side: i64, at: i64) {
        let mut rng = sim._rng;
        ExitPlanner::plan(sim, &mut rng, side, at);
        sim._rng = rng;
    }

    pub fn came_in(sim: &mut GameSim, index: i64, toward: i64, y: i64) {
        sim.state.y = y;
        sim.state.anchor_y = y;
        let skip = sim._arrival_retries(toward, index);
        for _ in 0..skip {
            sim._rng.next_u32();
        }
        sim._arrive_in(toward, index);
    }

    pub fn revived(index: i64, seed_value: i64, exit: &str, side: i64, toward: i64, y: i64) -> GameSim {
        let def = &RoomCatalog::all()[index as usize];
        let mut sim = GameSim::with(seed_value, def.season, -1, "");
        sim.step(true);
        let every = SimConfig::POINTS_PER_ROOM;
        let base_ = G::maxi(every, (def.from_score + every - 1) / every * every);
        sim.state.score = base_ + 3;
        Self::came_in(&mut sim, index, toward, y);
        match exit {
            "open" => {
                sim.state.score = base_;
                Self::plan_with_own_rng(&mut sim, side, base_);
                sim.state.exit_open = true;
            }
            "ghost" => {
                sim.state.score = base_ + every - 1;
                Self::plan_with_own_rng(&mut sim, side, base_ + every);
                sim.state.exit_preview = true;
            }
            _ => {}
        }
        sim.kill(DeathCause::FLOOR);
        sim.revive();
        sim
    }

    pub fn crawl_revived(index: i64, seed_value: i64, exit: &str, side: i64, y: i64) -> GameSim {
        let def = &RoomCatalog::all()[index as usize];
        let mut sim = GameSim::with(seed_value, def.season, -1, "");
        sim.step(true);
        // Not a fork score, so there is one exit.
        let base_ = 60;
        sim.state.score = base_ + 3;
        let y0 = sim.state.y;
        Self::came_in(&mut sim, index, seed_value % 2, y0);
        if exit == "open" {
            sim.state.score = base_;
            Self::plan_with_own_rng(&mut sim, side, base_);
            sim.state.exit_open = true;
        } else {
            sim.state.score = base_ + SimConfig::POINTS_PER_ROOM - 1;
            Self::plan_with_own_rng(&mut sim, side, base_ + SimConfig::POINTS_PER_ROOM);
            sim.state.exit_preview = true;
        }
        sim.state.exit_a_y = y;
        sim.kill(DeathCause::FLOOR);
        sim.revive();
        sim
    }

    /// C# default: variant = "classic".
    pub fn gates_revived(seed_value: i64, open: bool, side: i64, exit_y: i64, variant: &str) -> GameSim {
        let index = RoomCatalog::index_of("gates");
        let def = &RoomCatalog::all()[index as usize];
        let every = SimConfig::POINTS_PER_ROOM;
        let base_ = G::maxi(every, (def.from_score + every - 1) / every * every);
        let mut sim = GameSim::with(seed_value, def.season, -1, variant);
        sim.step(true);
        sim.state.score = if open { base_ } else { base_ + every - 1 };
        let y0 = sim.state.y;
        Self::came_in(&mut sim, index, seed_value % 2, y0);
        Self::plan_with_own_rng(&mut sim, side, if open { base_ } else { base_ + every });
        sim.state.exit_a_y = exit_y;
        sim.state.exit_open = open;
        sim.state.exit_preview = !open;
        sim.kill(DeathCause::HAZARD);
        sim.revive();
        sim
    }

    /// C# default: variant = "classic".
    pub fn practice(id: &str, seed_value: i64, variant: &str) -> GameSim {
        let index = RoomCatalog::index_of(id);
        GameSim::with(seed_value, RoomCatalog::all()[index as usize].season, index, variant)
    }

    /// C# default: variant = "classic".
    pub fn isles_revived(id: &str, seed_value: i64, exit: &str, side: i64, variant: &str) -> GameSim {
        let index = RoomCatalog::index_of(id);
        let def = &RoomCatalog::all()[index as usize];
        let mut sim = GameSim::with(seed_value, def.season, -1, variant);
        sim.step(true);
        let every = SimConfig::POINTS_PER_ROOM;
        let base_ = G::maxi(every, (def.from_score + every - 1) / every * every);
        let y0 = sim.state.y;
        if exit == "open" {
            sim.state.score = base_;
            Self::came_in(&mut sim, index, seed_value % 2, y0);
            Self::plan_with_own_rng(&mut sim, side, base_);
            sim.state.exit_open = true;
        } else {
            sim.state.score = base_ + every - 1;
            Self::came_in(&mut sim, index, seed_value % 2, y0);
            Self::plan_with_own_rng(&mut sim, side, base_ + every);
            sim.state.exit_preview = true;
        }
        sim.kill(DeathCause::HAZARD);
        sim.revive();
        sim
    }
}

/// Reaction.cs (ArrivalBench).
pub struct Reaction;

impl Reaction {
    pub const OFFSETS: [i64; 5] = [0, -65, 65, -32, 32];

    /// C# default: variant = "".
    pub fn arrival(index: i64, i: i64, variant: &str) -> GameSim {
        let def = &RoomCatalog::all()[index as usize];
        let mut sim = GameSim::new(9000 + i * 37);
        sim.forced_variant = sim::game_sim::intern(variant);
        sim.step(true);
        sim.state.score = G::maxi(def.from_score, 10) + (i % 3) * 10;
        let mut y = 130 + (i * 53) % 380;
        // A forced variant is only tried at heights the game would draw it for.
        let forced = def.variants.iter().find(|v| v.id == variant);
        for _ in 0..380 {
            if def.fits_arrival(y * SimConfig::SUB) && forced.is_none_or(|f| f.fits_arrival(y * SimConfig::SUB)) {
                break;
            }
            y = 130 + (y - 130 + 53) % 380;
        }
        sim.state.anchor_y = y * SimConfig::SUB;
        sim.state.y =
            GameSim::_arrival_y(sim.state.anchor_y + Self::OFFSETS[(i / 2 % Self::OFFSETS.len() as i64) as usize] * SimConfig::SUB);
        let side = i % 2;
        let skip = sim._arrival_retries(side, index);
        for _ in 0..skip {
            sim._rng.next_u32();
        }
        sim._arrive_in(side, index);
        sim
    }
}
