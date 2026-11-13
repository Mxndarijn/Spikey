//! Port of sim/rooms/variant_params.gd: what a GENERATED room variant builds its layout from.
//! GDScript's `p.sim` and `p.rng` are the sim passed beside it and `sim._rng` (the room RNG).
use crate::prelude::*;

#[derive(Clone, Debug, Default)]
pub struct VariantParams {
    pub arriving: bool,
    pub entry_y: i64,
    pub spread: i64,
    pub score: i64,
    pub level: i64,
    pub attempt: i64,
    pub fallback: bool,
}

impl VariantParams {
    pub const MARGIN: i64 = 6 * SimConfig::SUB;

    pub fn make(sim: &GameSim) -> VariantParams {
        let arriving = sim.state.started;
        VariantParams {
            arriving,
            entry_y: FairLanes::entry_y(sim),
            spread: if arriving { SimConfig::EXIT_FIT } else { 0 },
            score: sim.state.score,
            level: sim.state.score / SimConfig::BOSS_EVERY,
            attempt: 0,
            fallback: false,
        }
    }

    /// `add(h)`: added to the room's hazards and set up from the room RNG; its index.
    pub fn add(&self, sim: &mut GameSim, mut h: Hz) -> usize {
        let i = sim.room.hazards.len();
        h.base_mut().idx = i;
        sim.room.hazards.push(h);
        sim.with_hazard_rng(i, |h, sim, rng| h.setup(sim, rng));
        i
    }

    pub fn add_all(&self, sim: &mut GameSim, factories: &[Factory]) -> Vec<usize> {
        let mut out_ = Vec::new();
        for f in factories {
            out_.push(self.add(sim, f()));
        }
        out_
    }

    /// Runs `f` on hazard `i` taken out of the room (GDScript calls the hazard's method with
    /// the sim; here the hazard is lent out so it can read the sim).
    pub fn edit(sim: &mut GameSim, i: usize, f: impl FnOnce(&mut Hz, &mut GameSim)) {
        let mut h = std::mem::replace(&mut sim.room.hazards[i], Hz::Taken);
        f(&mut h, sim);
        sim.room.hazards[i] = h;
    }

    pub fn clear_center(&self, sim: &GameSim, cy: i64, ext: i64) -> i64 {
        let (ht, hb) = (self.hold_top(sim), self.hold_bottom(sim));
        if cy - ext >= hb || cy + ext <= ht {
            return cy;
        }
        let above = ht - ext;
        let below = hb + ext;
        let fits_above = above - ext >= SimConfig::KILL_TOP;
        let fits_below = below + ext <= SimConfig::KILL_BOTTOM;
        if fits_above && (!fits_below || G::absi(above - cy) <= G::absi(below - cy)) {
            return above;
        }
        if fits_below {
            return below;
        }
        -1
    }

    pub fn bird_top(&self) -> i64 {
        GameSim::_arrival_y(self.entry_y - self.spread)
    }

    pub fn bird_bottom(&self) -> i64 {
        GameSim::_arrival_y(self.entry_y + self.spread)
    }

    pub fn hold_top(&self, sim: &GameSim) -> i64 {
        if sim.room.gravity < 0 {
            return self.bird_top() - SimConfig::BIRD_RADIUS - Self::MARGIN;
        }
        self.bird_top() - FairLanes::FIRST_HOP - SimConfig::BIRD_RADIUS - Self::MARGIN
    }

    pub fn hold_bottom(&self, sim: &GameSim) -> i64 {
        if sim.room.gravity < 0 {
            return self.bird_bottom() + FairLanes::FIRST_HOP + SimConfig::BIRD_RADIUS + Self::MARGIN;
        }
        self.bird_bottom() + SimConfig::BIRD_RADIUS + Self::MARGIN
    }
}
